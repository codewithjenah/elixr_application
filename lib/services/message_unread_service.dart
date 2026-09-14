import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

class IncomingMessageEvent {
  const IncomingMessageEvent({required this.id, required this.senderName});

  final String id;
  final String senderName;
}

/// Keeps the app-wide unread message total in sync with the current inbox.
class MessageUnreadService extends ChangeNotifier {
  MessageUnreadService({required this.repository});

  final ChatRepository repository;

  StreamSubscription<List<ChatConversation>>? _subscription;
  String? _userId;
  int _unreadCount = 0;
  bool _disposed = false;
  int _generation = 0;
  bool _receivedInitialSnapshot = false;
  Map<String, _ConversationSnapshot> _conversationSnapshots = const {};
  IncomingMessageEvent? _latestIncomingMessage;

  int get unreadCount => _unreadCount;
  IncomingMessageEvent? get latestIncomingMessage => _latestIncomingMessage;

  void setUser(String? userId) {
    final normalized = userId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_userId == next) return;
    _userId = next;
    final generation = ++_generation;
    final oldSubscription = _subscription;
    _subscription = null;
    _receivedInitialSnapshot = false;
    _conversationSnapshots = const {};
    _latestIncomingMessage = null;
    _setUnreadCount(0);
    unawaited(_restart(next, generation, oldSubscription));
  }

  Future<void> _restart(
    String? userId,
    int generation,
    StreamSubscription<List<ChatConversation>>? oldSubscription,
  ) async {
    try {
      await oldSubscription?.cancel();
    } catch (error, stackTrace) {
      debugPrint('Failed to cancel the previous inbox listener: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (_disposed || generation != _generation || _userId != userId) return;
    if (userId == null) return;
    _subscription = repository
        .watchInbox(userId)
        .listen(
          (conversations) {
            if (_disposed || _userId != userId) return;
            _observeIncomingMessages(userId, conversations);
            final total = conversations.fold<int>(
              0,
              (sum, conversation) => sum + conversation.unreadFor(userId),
            );
            _setUnreadCount(total);
          },
          onError: (_) {
            if (!_disposed && _userId == userId) _setUnreadCount(0);
          },
        );
  }

  void _observeIncomingMessages(
    String userId,
    List<ChatConversation> conversations,
  ) {
    final next = <String, _ConversationSnapshot>{
      for (final conversation in conversations)
        conversation.id: _ConversationSnapshot(
          lastMessageId: conversation.lastMessageId,
          unreadCount: conversation.unreadFor(userId),
        ),
    };
    if (!_receivedInitialSnapshot) {
      _receivedInitialSnapshot = true;
      _conversationSnapshots = next;
      return;
    }

    for (final conversation in conversations) {
      final previous = _conversationSnapshots[conversation.id];
      final lastMessageId = conversation.lastMessageId;
      final senderId = conversation.lastMessageSenderId;
      if (lastMessageId != null &&
          lastMessageId != previous?.lastMessageId &&
          conversation.unreadFor(userId) > (previous?.unreadCount ?? 0) &&
          senderId != null &&
          senderId != userId) {
        final sender = conversation.otherParticipant(userId);
        _latestIncomingMessage = IncomingMessageEvent(
          id: '${conversation.id}:$lastMessageId',
          senderName: sender?.displayName ?? 'someone',
        );
        break;
      }
    }
    _conversationSnapshots = next;
  }

  void _setUnreadCount(int value) {
    if (_disposed || _unreadCount == value) return;
    _unreadCount = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class _ConversationSnapshot {
  const _ConversationSnapshot({
    required this.lastMessageId,
    required this.unreadCount,
  });

  final String? lastMessageId;
  final int unreadCount;
}
