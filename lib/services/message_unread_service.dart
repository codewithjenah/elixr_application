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

  int get unreadCount => _unreadCount;

  void setUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _setUnreadCount(0);

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
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
