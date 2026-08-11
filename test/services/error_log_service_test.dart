import 'dart:io';

import 'package:elixr_application/services/error_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory logsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_error_log_');
    logsDir = Directory('${tempDir.path}${Platform.pathSeparator}logs');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('logError creates logs dir and appends structured entry', () async {
    final service = ErrorLogService(
      logsDirectory: logsDir,
      clock: () => DateTime(2026, 8, 11, 10, 30),
    );

    await service.logError(
      StateError('boom'),
      StackTrace.fromString('#0 fake\n#1 frame'),
      context: 'FlutterError',
    );

    expect(await logsDir.exists(), isTrue);
    final file = File(
      '${logsDir.path}${Platform.pathSeparator}error_log_2026-08-11.txt',
    );
    expect(await file.exists(), isTrue);
    final contents = await file.readAsString();
    expect(contents, contains('2026-08-11T10:30:00.000'));
    expect(contents, contains('FlutterError'));
    expect(contents, contains('boom'));
    expect(contents, contains('#0 fake'));
  });

  test('logError rolls to sibling file when size cap is reached', () async {
    await logsDir.create(recursive: true);
    final first = File(
      '${logsDir.path}${Platform.pathSeparator}error_log_2026-08-11.txt',
    );
    await first.writeAsString('x' * 100);

    final service = ErrorLogService(
      logsDirectory: logsDir,
      clock: () => DateTime(2026, 8, 11, 12),
      maxFileBytes: 100,
    );

    await service.logError(
      Exception('overflow'),
      StackTrace.fromString('stack'),
      context: 'ZonedGuarded',
    );

    final second = File(
      '${logsDir.path}${Platform.pathSeparator}error_log_2026-08-11_2.txt',
    );
    expect(await second.exists(), isTrue);
    final rolled = await second.readAsString();
    expect(rolled, contains('overflow'));
    expect(await first.readAsString(), equals('x' * 100));
  });

  test('logError swallows write failures', () async {
    final blocked = Directory(
      '${tempDir.path}${Platform.pathSeparator}blocked_as_file',
    );
    await File(blocked.path).writeAsString('not a directory');

    final service = ErrorLogService(logsDirectory: blocked);

    await expectLater(
      service.logError(Exception('x'), StackTrace.empty),
      completes,
    );
  });
}
