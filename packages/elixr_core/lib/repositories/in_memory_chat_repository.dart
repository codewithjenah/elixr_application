import 'dart:async';

import '../models/chat_conversation.dart';
import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';
import 'chat_repository.dart';

class InMemoryChatRepository implements ChatRepository {
  final List<ChatUser> users = [];
  final Map<String, ChatConversation> conversations = {};
  final Map<String, List<ChatMessage>> messages = {};
  final Set<String> blocks = {};

  final _inboxChanges = StreamController<void>.broadcast();
  final _messageChanges = StreamController<String>.broadcast();
  final _blockChanges = StreamController<void>.broadcast();
  int _nextMessageId = 0;

  String _blockKey(String blocker, String blocked) => '$blocker::$blocked';

  @override
  Future<List<ChatUser>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      throw const ChatException(ChatError.invalidQuery);
    }
    return users
        .where((user) {
          return user.displayName
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .any((token) => token.startsWith(normalized));
        })
        .take(20)
        .toList(growable: false);
  }

  @override
  Stream<List<ChatConversation>> watchInbox(String currentUserId) async* {
    List<ChatConversation> current() {
      final result =
          conversations.values
              .where(
                (item) =>
                    item.participants.containsKey(currentUserId) &&
                    !item.isClearedFor(currentUserId),
              )
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    }

    yield current();
    await for (final _ in _inboxChanges.stream) {
      yield current();
    }
  }

  @override
  Stream<ChatMessagePage> watchMessages({
    required String conversationId,
    int pageSize = ChatRepository.defaultMessagePageSize,
  }) async* {
    ChatMessagePage current() => _page(conversationId, 0, pageSize);
    yield current();
    await for (final changedId in _messageChanges.stream) {
      if (changedId == conversationId) yield current();
    }
  }

  @override
  Future<ChatMessagePage> fetchOlderMessages({
    required String conversationId,
    required ChatMessageCursor startAfter,
    int pageSize = ChatRepository.defaultMessagePageSize,
  }) async {
    if (startAfter is! _MemoryChatCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    return _page(conversationId, startAfter.offset, pageSize);
  }

  ChatMessagePage _page(String conversationId, int offset, int pageSize) {
    final all = [...messages[conversationId] ?? const <ChatMessage>[]]
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      });
    final page = all.skip(offset).take(pageSize).toList(growable: false);
    final next = offset + page.length;
    return ChatMessagePage(
      messages: page,
      hasMore: next < all.length,
      nextCursor: next < all.length ? _MemoryChatCursor(next) : null,
    );
  }

  @override
  Future<ChatMessage> sendMessage({
    required ChatUser sender,
    required ChatUser recipient,
    required String body,
  }) async {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    if (blocks.contains(_blockKey(sender.id, recipient.id)) ||
        blocks.contains(_blockKey(recipient.id, sender.id))) {
      throw const ChatException(ChatError.blocked);
    }
    final id = ChatRepository.conversationIdFor(sender.id, recipient.id);
    final now = DateTime.now().toUtc();
    final message = ChatMessage(
      id: 'message_${++_nextMessageId}',
      conversationId: id,
      senderId: sender.id,
      body: body.trim(),
      createdAt: now,
    );
    messages.putIfAbsent(id, () => []).add(message);
    final existing = conversations[id];
    final unread = {...?existing?.unreadCounts};
    unread[sender.id] = 0;
    unread[recipient.id] = (unread[recipient.id] ?? 0) + 1;
    conversations[id] = ChatConversation(
      id: id,
      participants: {sender.id: sender, recipient.id: recipient},
      lastMessageId: message.id,
      lastMessageBody: message.body,
      lastMessageSenderId: sender.id,
      lastMessageAt: now,
      updatedAt: now,
      unreadCounts: unread,
      readAt: {...?existing?.readAt, sender.id: now},
      clearedAt: existing?.clearedAt ?? const {},
      status: existing?.status ?? 'active',
    );
    _messageChanges.add(id);
    _inboxChanges.add(null);
    return message;
  }

  @override
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
    required String body,
  }) async {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    final list = messages[conversationId];
    final index = list?.indexWhere((item) => item.id == messageId) ?? -1;
    if (index < 0) throw const ChatException(ChatError.notFound);
    final old = list![index];
    if (old.senderId != currentUserId || old.isDeleted) {
      throw const ChatException(ChatError.permissionDenied);
    }
    final edited = ChatMessage(
      id: old.id,
      conversationId: old.conversationId,
      senderId: old.senderId,
      body: body.trim(),
      createdAt: old.createdAt,
      editedAt: DateTime.now().toUtc(),
      legacyMovementName: old.legacyMovementName,
      isMigratedCoaching: old.isMigratedCoaching,
    );
    list[index] = edited;
    _replaceSummaryIfLatest(conversationId, messageId, body.trim());
    _messageChanges.add(conversationId);
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
  }) async {
    final list = messages[conversationId];
    final index = list?.indexWhere((item) => item.id == messageId) ?? -1;
    if (index < 0) throw const ChatException(ChatError.notFound);
    final old = list![index];
    if (old.senderId != currentUserId || old.isDeleted) {
      throw const ChatException(ChatError.permissionDenied);
    }
    list[index] = ChatMessage(
      id: old.id,
      conversationId: old.conversationId,
      senderId: old.senderId,
      createdAt: old.createdAt,
      deletedAt: DateTime.now().toUtc(),
      legacyMovementName: old.legacyMovementName,
      isMigratedCoaching: old.isMigratedCoaching,
    );
    _replaceSummaryIfLatest(conversationId, messageId, 'Message deleted');
    _messageChanges.add(conversationId);
  }

  void _replaceSummaryIfLatest(
    String conversationId,
    String messageId,
    String body,
  ) {
    final old = conversations[conversationId];
    if (old == null || old.lastMessageId != messageId) return;
    conversations[conversationId] = ChatConversation(
      id: old.id,
      participants: old.participants,
      lastMessageId: old.lastMessageId,
      lastMessageBody: body,
      lastMessageSenderId: old.lastMessageSenderId,
      lastMessageAt: old.lastMessageAt,
      updatedAt: old.updatedAt,
      unreadCounts: old.unreadCounts,
      readAt: old.readAt,
      clearedAt: old.clearedAt,
      status: old.status,
    );
    _inboxChanges.add(null);
  }

  @override
  Future<void> markRead({
    required String conversationId,
    required String currentUserId,
  }) async {
    final old = conversations[conversationId];
    if (old == null) return;
    conversations[conversationId] = ChatConversation(
      id: old.id,
      participants: old.participants,
      lastMessageId: old.lastMessageId,
      lastMessageBody: old.lastMessageBody,
      lastMessageSenderId: old.lastMessageSenderId,
      lastMessageAt: old.lastMessageAt,
      updatedAt: old.updatedAt,
      unreadCounts: {...old.unreadCounts, currentUserId: 0},
      readAt: {...old.readAt, currentUserId: DateTime.now().toUtc()},
      clearedAt: old.clearedAt,
      status: old.status,
    );
    _inboxChanges.add(null);
  }

  @override
  Future<void> markUnread({
    required String conversationId,
    required String currentUserId,
  }) async {
    final old = conversations[conversationId];
    if (old == null || !old.participants.containsKey(currentUserId)) return;
    conversations[conversationId] = ChatConversation(
      id: old.id,
      participants: old.participants,
      lastMessageId: old.lastMessageId,
      lastMessageBody: old.lastMessageBody,
      lastMessageSenderId: old.lastMessageSenderId,
      lastMessageAt: old.lastMessageAt,
      updatedAt: old.updatedAt,
      unreadCounts: {...old.unreadCounts, currentUserId: 1},
      readAt: old.readAt,
      clearedAt: old.clearedAt,
      status: old.status,
    );
    _inboxChanges.add(null);
  }

  @override
  Future<void> clearConversation({
    required String conversationId,
    required String currentUserId,
  }) async {
    final old = conversations[conversationId];
    if (old == null || !old.participants.containsKey(currentUserId)) return;
    final now = DateTime.now().toUtc();
    conversations[conversationId] = ChatConversation(
      id: old.id,
      participants: old.participants,
      lastMessageId: old.lastMessageId,
      lastMessageBody: old.lastMessageBody,
      lastMessageSenderId: old.lastMessageSenderId,
      lastMessageAt: old.lastMessageAt,
      updatedAt: old.updatedAt,
      unreadCounts: {...old.unreadCounts, currentUserId: 0},
      readAt: {...old.readAt, currentUserId: now},
      clearedAt: {...old.clearedAt, currentUserId: now},
      status: old.status,
    );
    _inboxChanges.add(null);
  }

  @override
  Stream<ChatBlockState> watchBlockState({
    required String currentUserId,
    required String otherUserId,
  }) async* {
    ChatBlockState current() => ChatBlockState(
      blockedByMe: blocks.contains(_blockKey(currentUserId, otherUserId)),
      blockedByOther: blocks.contains(_blockKey(otherUserId, currentUserId)),
    );
    yield current();
    await for (final _ in _blockChanges.stream) {
      yield current();
    }
  }

  @override
  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    blocks.add(_blockKey(currentUserId, blockedUserId));
    _blockChanges.add(null);
  }

  @override
  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    blocks.remove(_blockKey(currentUserId, blockedUserId));
    _blockChanges.add(null);
  }

  Future<void> dispose() async {
    await _inboxChanges.close();
    await _messageChanges.close();
    await _blockChanges.close();
  }
}

class _MemoryChatCursor extends ChatMessageCursor {
  const _MemoryChatCursor(this.offset);
  final int offset;
}
