import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Account-scoped, local read state for teacher activity. This intentionally
/// stays off Firestore because reading an activity is a personal UI choice.
abstract interface class ActivityReadStore {
  Future<Map<String, DateTime>> load(String teacherId);

  Future<void> save(String teacherId, Map<String, DateTime> readAtById);
}

class FileActivityReadStore implements ActivityReadStore {
  FileActivityReadStore({File? file}) : _fileOverride = file;

  static const _fileName = 'teacher_activity_read_state.json';

  final File? _fileOverride;

  @override
  Future<Map<String, DateTime>> load(String teacherId) async {
    final all = await _readAll();
    final account = all[teacherId];
    if (account is! Map) return <String, DateTime>{};

    final result = <String, DateTime>{};
    for (final entry in account.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final id = (entry.key as String).trim();
      final parsed = DateTime.tryParse(entry.value as String)?.toUtc();
      if (id.isNotEmpty && parsed != null) result[id] = parsed;
    }
    return result;
  }

  @override
  Future<void> save(String teacherId, Map<String, DateTime> readAtById) async {
    final all = await _readAll();
    all[teacherId] = {
      for (final entry in readAtById.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    };
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all), flush: true);
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return <String, dynamic>{};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<File> _file() async =>
      _fileOverride ??
      File(
        '${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}$_fileName',
      );
}

class InMemoryActivityReadStore implements ActivityReadStore {
  final Map<String, Map<String, DateTime>> _accounts = {};
  Object? nextLoadError;
  Object? nextSaveError;

  @override
  Future<Map<String, DateTime>> load(String teacherId) async {
    final error = nextLoadError;
    nextLoadError = null;
    if (error != null) throw error;
    return Map<String, DateTime>.from(_accounts[teacherId] ?? const {});
  }

  @override
  Future<void> save(String teacherId, Map<String, DateTime> readAtById) async {
    final error = nextSaveError;
    nextSaveError = null;
    if (error != null) throw error;
    _accounts[teacherId] = Map<String, DateTime>.from(readAtById);
  }
}
