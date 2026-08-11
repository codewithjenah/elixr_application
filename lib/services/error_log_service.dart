import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Appends uncaught/Flutter errors to rotating local log files.
///
/// Log directory: `<application support>/logs/`.
/// Files: `error_log_YYYY-MM-DD.txt`, then `error_log_YYYY-MM-DD_2.txt`, …
/// when the active file reaches [maxFileBytes].
///
/// Write failures are swallowed so logging never crashes the app.
class ErrorLogService {
  ErrorLogService({
    Directory? logsDirectory,
    DateTime Function()? clock,
    this.maxFileBytes = defaultMaxFileBytes,
  }) : _logsDirectoryOverride = logsDirectory,
       _clock = clock ?? DateTime.now;

  static const int defaultMaxFileBytes = 5 * 1024 * 1024;

  final Directory? _logsDirectoryOverride;
  final DateTime Function() _clock;
  final int maxFileBytes;

  Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {
    try {
      final logsDir = await _resolveLogsDirectory();
      final now = _clock().toUtc();
      final date = _formatDate(now);
      final file = await _resolveWriteTarget(logsDir, date);
      final entry = _formatEntry(
        timestamp: now,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (_) {
      // Best-effort logging must never crash the app.
    }
  }

  Future<Directory> _resolveLogsDirectory() async {
    final override = _logsDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }

    final support = await getApplicationSupportDirectory();
    final logs = Directory('${support.path}${Platform.pathSeparator}logs');
    if (!await logs.exists()) {
      await logs.create(recursive: true);
    }
    return logs;
  }

  Future<File> _resolveWriteTarget(Directory logsDir, String date) async {
    var index = 1;
    while (true) {
      final file = _fileForIndex(logsDir, date, index);
      if (!await file.exists()) {
        return file;
      }
      final length = await file.length();
      if (length < maxFileBytes) {
        return file;
      }
      index++;
    }
  }

  File _fileForIndex(Directory logsDir, String date, int index) {
    final name = index <= 1
        ? 'error_log_$date.txt'
        : 'error_log_${date}_$index.txt';
    return File('${logsDir.path}${Platform.pathSeparator}$name');
  }

  String _formatDate(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatEntry({
    required DateTime timestamp,
    required String? context,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final label = (context == null || context.isEmpty) ? 'error' : context;
    final stamp = timestamp.toIso8601String();
    return '==== $stamp | $label ====\n'
        'Error: $error\n'
        'StackTrace:\n'
        '$stackTrace\n\n';
  }
}
