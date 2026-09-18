import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local mirror of the user's already-authoritative evidence choice.
///
/// It contains no image data, credentials, or tokens. It only prevents an
/// offline completion from having to wait for a profile read before deciding
/// whether a confirming frame should enter the encrypted/account-scoped local
/// outbox.
class SessionEvidencePreferenceStore {
  SessionEvidencePreferenceStore({File? file}) : _fileOverride = file;

  final File? _fileOverride;

  Future<bool?> read(String userId) async {
    try {
      final data = await _readAll();
      final value = data[userId];
      return value is bool ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, bool enabled) async {
    final data = await _readAll();
    data[userId] = enabled;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> purge(String userId) async {
    final data = await _readAll();
    if (!data.containsKey(userId)) return;
    data.remove(userId);
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
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
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}session_evidence_preferences.json',
      );
}
