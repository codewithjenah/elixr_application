import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

enum MessageSearchState { idle, waiting, loading, ready, empty, error }

enum MessagePaneState { empty, loading, ready, error }

class MessagesController extends ChangeNotifier {
  MessagesController({
    required this.repository,
    required this.currentUser,
    this.searchDebounce = const Duration(milliseconds: 350),
  });

  final ChatRepository repository;
  final ChatUser currentUser;
  final Duration searchDebounce;

  List<ChatConversation> inbox = const [];
  List<ChatUser> searchResults = const [];
  List<ChatMessage> messages = const [];
  ChatUser? selectedUser;
  ChatConversation? selectedConversation;
  ChatBlockState blockState = const ChatBlockState.none();
  MessageSearchState searchState = MessageSearchState.idle;
  MessagePaneState messageState = MessagePaneState.empty;
  Object? inboxError;
  Object? messageError;
  Object? searchError;
  Object? paginationError;
  bool loadingOlder = false;
  bool hasOlder = false;
  String? alertMessage;

  StreamSubscription<List<ChatConversation>>? _inboxSubscription;
  StreamSubscription<ChatMessagePage>? _messageSubscription;
  StreamSubscription<ChatBlockState>? _blockSubscription;
  String? _subscribedConversationId;
  ChatMessageCursor? _messageCursor;
  bool _hasLoadedOlder = false;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  bool _disposed = false;

  String? get conversationId {
    final other = selectedUser;
    if (other == null) return null;
    return ChatRepository.conversationIdFor(currentUser.id, other.id);
  }

  void start({ChatUser? initialUser}) {
    _inboxSubscription?.cancel();
    _inboxSubscription = repository
        .watchInbox(currentUser.id)
        .listen(
          _onInbox,
          onError: (Object error) {
            inboxError = error;
            _notify();
          },
        );
    if (initialUser != null && initialUser.id != currentUser.id) {
      unawaited(openUser(initialUser));
    }
  }

  void _onInbox(List<ChatConversation> value) {
    final previousUnread = inbox.fold<int>(
      0,
      (total, item) => total + item.unreadFor(currentUser.id),
    );
    final nextUnread = value.fold<int>(
      0,
      (total, item) => total + item.unreadFor(currentUser.id),
    );
    inbox = value;
    inboxError = null;

    final id = conversationId;
    if (id != null) {
      final matching = value.where((item) => item.id == id).firstOrNull;
      if (matching != null) {
        final isNewlyCreated = selectedConversation == null;
        selectedConversation = matching;
        selectedUser =
            matching.otherParticipant(currentUser.id) ?? selectedUser;
        if (isNewlyCreated || _subscribedConversationId != matching.id) {
          unawaited(_subscribeToMessages(matching.id));
        }
        if (matching.unreadFor(currentUser.id) > 0) {
          unawaited(
            repository.markRead(
              conversationId: matching.id,
              currentUserId: currentUser.id,
            ),
          );
        }
      }
    }
    if (nextUnread > previousUnread && selectedUser == null) {
      alertMessage = 'You have a new message.';
    }
    _notify();
  }

  void dismissAlert() {
    alertMessage = null;
    _notify();
  }

  void updateSearch(String query) {
    _searchTimer?.cancel();
    final trimmed = query.trim();
    final generation = ++_searchGeneration;
    searchError = null;
    if (trimmed.isEmpty) {
      searchResults = const [];
      searchState = MessageSearchState.idle;
      _notify();
      return;
    }
    if (trimmed.length < 2) {
      searchResults = const [];
      searchState = MessageSearchState.waiting;
      _notify();
      return;
    }
    searchState = MessageSearchState.loading;
    _notify();
    _searchTimer = Timer(searchDebounce, () async {
      try {
        final result = await repository.searchUsers(trimmed);
        if (!_currentSearch(generation)) return;
        searchResults = result
            .where((user) => user.id != currentUser.id)
            .toList();
        searchState = searchResults.isEmpty
            ? MessageSearchState.empty
            : MessageSearchState.ready;
      } catch (error) {
        if (!_currentSearch(generation)) return;
        searchError = error;
        searchState = MessageSearchState.error;
      }
      _notify();
    });
  }

  bool _currentSearch(int generation) =>
      !_disposed && generation == _searchGeneration;

  Future<void> openConversation(ChatConversation conversation) async {
    final other = conversation.otherParticipant(currentUser.id);
    if (other == null) return;
    selectedConversation = conversation;
    await openUser(other);
  }

  Future<void> openUser(ChatUser user) async {
    if (user.id == currentUser.id) return;
    selectedUser = user;
    selectedConversation = inbox
        .where(
          (item) =>
              item.id ==
              ChatRepository.conversationIdFor(currentUser.id, user.id),
        )
        .firstOrNull;
    messages = const [];
    _messageCursor = null;
    _hasLoadedOlder = false;
    hasOlder = false;
    paginationError = null;
    messageError = null;
    messageState = selectedConversation == null
        ? MessagePaneState.empty
        : MessagePaneState.loading;
    _notify();

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    _subscribedConversationId = null;
    await _blockSubscription?.cancel();
    final id = conversationId!;
    if (selectedConversation != null) {
      await _subscribeToMessages(id);
    }
    _blockSubscription = repository
        .watchBlockState(currentUserId: currentUser.id, otherUserId: user.id)
        .listen(
          (state) {
            blockState = state;
            _notify();
          },
          onError: (_) {
            blockState = const ChatBlockState.none();
            _notify();
          },
        );
    final conversation = selectedConversation;
    if (conversation != null) {
      unawaited(
        repository.markRead(
          conversationId: conversation.id,
          currentUserId: currentUser.id,
        ),
      );
    }
  }

  Future<void> _subscribeToMessages(String id) async {
    if (_disposed || _subscribedConversationId == id) return;
    await _messageSubscription?.cancel();
    if (_disposed || conversationId != id) return;
    _subscribedConversationId = id;
    _messageSubscription = repository
        .watchMessages(conversationId: id)
        .listen(
          (page) {
            final liveIds = page.messages.map((message) => message.id).toSet();
            final optimistic = messages.where(
              (message) =>
                  message.deliveryState == ChatDeliveryState.error ||
                  (message.deliveryState == ChatDeliveryState.sending &&
                      !page.messages.any(
                        (saved) =>
                            saved.senderId == message.senderId &&
                            saved.body == message.body &&
                            saved.createdAt
                                    .difference(message.createdAt)
                                    .abs() <
                                const Duration(seconds: 30),
                      )),
            );
            final retainedOlder = _hasLoadedOlder
                ? messages.where(
                    (message) =>
                        message.deliveryState == ChatDeliveryState.sent &&
                        !liveIds.contains(message.id),
                  )
                : const <ChatMessage>[];
            messages = _deduplicate([
              ...page.messages,
              ...retainedOlder,
              ...optimistic,
            ]);
            if (!_hasLoadedOlder) {
              _messageCursor = page.nextCursor;
              hasOlder = page.hasMore;
            }
            messageState = messages.isEmpty
                ? MessagePaneState.empty
                : MessagePaneState.ready;
            messageError = null;
            _notify();
          },
          onError: (Object error) {
            _subscribedConversationId = null;
            messageError = error;
            messageState = MessagePaneState.error;
            _notify();
          },
        );
  }

  Future<void> loadOlder() async {
    final id = conversationId;
    final cursor = _messageCursor;
    if (id == null || cursor == null || loadingOlder || !hasOlder) return;
    loadingOlder = true;
    paginationError = null;
    _notify();
    try {
      final page = await repository.fetchOlderMessages(
        conversationId: id,
        startAfter: cursor,
      );
      messages = _deduplicate([...messages, ...page.messages]);
      _hasLoadedOlder = true;
      _messageCursor = page.nextCursor;
      hasOlder = page.hasMore;
    } catch (error) {
      paginationError = error;
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  Future<bool> send(String body) async {
    final recipient = selectedUser;
    if (recipient == null || blockState.cannotSend) return false;
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      messageError = ChatException(ChatError.invalidMessage, validation);
      _notify();
      return false;
    }
    final temporary = ChatMessage(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId!,
      senderId: currentUser.id,
      body: body.trim(),
      createdAt: DateTime.now().toUtc(),
      deliveryState: ChatDeliveryState.sending,
    );
    messages = _deduplicate([temporary, ...messages]);
    messageState = MessagePaneState.ready;
    messageError = null;
    _notify();
    try {
      final saved = await repository.sendMessage(
        sender: currentUser,
        recipient: recipient,
        body: body,
      );
      messages = _deduplicate([
        saved,
        ...messages.where((item) => item.id != temporary.id),
      ]);
      _notify();
      return true;
    } catch (error) {
      messages = messages
          .map(
            (item) => item.id == temporary.id
                ? item.copyWith(deliveryState: ChatDeliveryState.error)
                : item,
          )
          .toList(growable: false);
      messageError = error;
      _notify();
      return false;
    }
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (message.deliveryState != ChatDeliveryState.error ||
        message.body == null) {
      return;
    }
    messages = messages.where((item) => item.id != message.id).toList();
    _notify();
    await send(message.body!);
  }

  Future<void> editMessage(ChatMessage message, String body) async {
    await repository.editMessage(
      conversationId: message.conversationId,
      messageId: message.id,
      currentUserId: currentUser.id,
      body: body,
    );
    final editedAt = DateTime.now().toUtc();
    messages = messages
        .map(
          (item) => item.id == message.id
              ? item.withEditedBody(body.trim(), editedAt)
              : item,
        )
        .toList(growable: false);
    _notify();
  }

  Future<void> deleteMessage(ChatMessage message) async {
    await repository.deleteMessage(
      conversationId: message.conversationId,
      messageId: message.id,
      currentUserId: currentUser.id,
    );
    final deletedAt = DateTime.now().toUtc();
    messages = messages
        .map((item) => item.id == message.id ? item.asDeleted(deletedAt) : item)
        .toList(growable: false);
    _notify();
  }

  Future<void> toggleBlock() async {
    final other = selectedUser;
    if (other == null) return;
    if (blockState.blockedByMe) {
      await repository.unblockUser(
        currentUserId: currentUser.id,
        blockedUserId: other.id,
      );
    } else {
      await repository.blockUser(
        currentUserId: currentUser.id,
        blockedUserId: other.id,
      );
    }
  }

  bool isLatestOutgoingSeen(ChatMessage message) {
    final conversation = selectedConversation;
    final other = selectedUser;
    if (conversation == null ||
        other == null ||
        message.senderId != currentUser.id) {
      return false;
    }
    final latestOutgoing = messages
        .where(
          (item) =>
              item.senderId == currentUser.id &&
              item.deliveryState == ChatDeliveryState.sent,
        )
        .firstOrNull;
    if (latestOutgoing?.id != message.id) return false;
    final seenAt = conversation.readAt[other.id];
    return seenAt != null && !seenAt.isBefore(message.createdAt);
  }

  void showInboxPane() {
    selectedUser = null;
    selectedConversation = null;
    messages = const [];
    _hasLoadedOlder = false;
    messageState = MessagePaneState.empty;
    blockState = const ChatBlockState.none();
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _subscribedConversationId = null;
    _blockSubscription?.cancel();
    _blockSubscription = null;
    _notify();
  }

  static List<ChatMessage> _deduplicate(Iterable<ChatMessage> source) {
    final ids = <String>{};
    final result = source.where((item) => ids.add(item.id)).toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      });
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchGeneration++;
    _searchTimer?.cancel();
    _inboxSubscription?.cancel();
    _messageSubscription?.cancel();
    _blockSubscription?.cancel();
    super.dispose();
  }
}
