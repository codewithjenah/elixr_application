import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

/// Keeps the app-wide unread message total in sync with the current inbox.
class MessageUnreadService extends ChangeNotifier {
  MessageUnreadService({required this.repository});

  final ChatRepository repository;

  StreamSubscription<List<ChatConversation>>? _subscription;
  String? _userId;
  int _unreadCount = 0;
  bool _disposed = false;
  int _generation = 0;

  int get unreadCount => _unreadCount;

  void setUser(String? userId) {
    final normalized = userId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_userId == next) return;
    _userId = next;
    final generation = ++_generation;
    final oldSubscription = _subscription;
    _subscription = null;
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
