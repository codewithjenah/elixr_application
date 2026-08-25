import 'dart:async';

import '../models/chat_user.dart';
import '../models/user.dart';
import 'faculty_directory_repository.dart';

class InMemoryFacultyDirectoryRepository implements FacultyDirectoryRepository {
  final Map<String, ChatUser> _users = {};
  final Map<String, String?> _lifecycle = {};
  StreamController<List<ChatUser>>? _controller;

  void seed(ChatUser user, {String? lifecycleState = 'active'}) {
    _users[user.id] = user;
    _lifecycle[user.id] = lifecycleState;
    _emit();
  }

  void remove(String id) {
    _users.remove(id);
    _lifecycle.remove(id);
    _emit();
  }

  void dispose() {
    _controller?.close();
    _controller = null;
  }

  @override
  Stream<List<ChatUser>> watchTeachers() {
    final existing = _controller;
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<ChatUser>> controller;
    controller = StreamController<List<ChatUser>>.broadcast(
      onListen: () => controller.add(_activeTeachers()),
    );
    _controller = controller;
    return controller.stream;
  }

  List<ChatUser> _activeTeachers() {
    return [
      for (final user in _users.values)
        if (user.role == User.roleTeacher &&
            (_lifecycle[user.id] == null || _lifecycle[user.id] == 'active'))
          user,
    ];
  }

  void _emit() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(_activeTeachers());
  }
}
