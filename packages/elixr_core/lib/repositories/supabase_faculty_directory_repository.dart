import 'dart:async';

import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/chat_user.dart';
import 'faculty_directory_repository.dart';

/// Verified-Teacher faculty directory. Profiles are private rows, so the
/// directory is served by a Teacher-only RPC and refreshed while listened.
class SupabaseFacultyDirectoryRepository implements FacultyDirectoryRepository {
  SupabaseFacultyDirectoryRepository({
    SupabaseClient? client,
    this.refreshInterval = const Duration(minutes: 1),
  }) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  final Duration refreshInterval;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  @override
  Stream<List<ChatUser>> watchTeachers() {
    late StreamController<List<ChatUser>> controller;
    Timer? timer;
    var active = true;

    Future<void> load() async {
      try {
        final result = await _client.rpc<dynamic>('list_faculty_directory');
        if (!active || controller.isClosed) return;
        controller.add([
          for (final row in rowsFrom(result))
            ?ChatUser.tryFromMap(row, id: row['id'] as String?),
        ]);
      } catch (error, stackTrace) {
        if (active && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<List<ChatUser>>(
      onListen: () {
        unawaited(load());
        timer = Timer.periodic(refreshInterval, (_) => unawaited(load()));
      },
      onCancel: () {
        active = false;
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }
}
