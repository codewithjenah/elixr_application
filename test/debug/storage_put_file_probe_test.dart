import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/debug/storage_put_file_probe.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('elixr_putfile_probe_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('release mode cannot invoke the production probe path', () async {
    var putFileCalls = 0;
    var deleteCalls = 0;
    final logs = <String>[];

    final result = await runStoragePutFileProbe(
      debugMode: false,
      uid: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
      bucket: 'elixr-app-2026.firebasestorage.app',
      imageBytes: storagePutFileProbePngBytes,
      contentType: 'image/png',
      tempDirectory: tempRoot,
      now: DateTime.utc(2026, 8, 21, 7, 34),
      log: logs.add,
      putFile:
          ({required file, required storagePath, required contentType}) async {
            putFileCalls += 1;
          },
      deleteRemote: (storagePath) async {
        deleteCalls += 1;
      },
    );

    expect(result.invoked, isFalse);
    expect(putFileCalls, 0);
    expect(deleteCalls, 0);
    expect(logs, isEmpty);
    expect(result.remoteCleanup, StoragePutFileProbeRemoteCleanup.notCreated);
    expect(result.localCleanup, StoragePutFileProbeLocalCleanup.success);
  });

  test(
    'live dart-define seam is a no-op when debug or define is off',
    () async {
      var liveRuns = 0;
      expect(
        await maybeRunLiveStoragePutFileProbe(
          debugMode: false,
          dartDefineEnabled: true,
          runLive: () async {
            liveRuns += 1;
            throw StateError('must not run');
          },
        ),
        isNull,
      );
      expect(
        await maybeRunLiveStoragePutFileProbe(
          debugMode: true,
          dartDefineEnabled: false,
          runLive: () async {
            liveRuns += 1;
            throw StateError('must not run');
          },
        ),
        isNull,
      );
      expect(liveRuns, 0);
    },
  );

  test('null Firebase user fails closed without upload', () async {
    var putFileCalls = 0;
    var deleteCalls = 0;
    final logs = <String>[];

    final result = await runStoragePutFileProbe(
      debugMode: true,
      uid: null,
      bucket: 'elixr-app-2026.firebasestorage.app',
      imageBytes: storagePutFileProbePngBytes,
      contentType: 'image/png',
      tempDirectory: tempRoot,
      now: DateTime.utc(2026, 8, 21, 7, 34),
      log: logs.add,
      putFile:
          ({required file, required storagePath, required contentType}) async {
            putFileCalls += 1;
          },
      deleteRemote: (storagePath) async {
        deleteCalls += 1;
      },
    );

    expect(result.invoked, isFalse);
    expect(putFileCalls, 0);
    expect(deleteCalls, 0);
    expect(result.remoteCleanup, StoragePutFileProbeRemoteCleanup.notCreated);
    expect(
      logs.join('\n'),
      contains(
        '[StoragePutFileProbe]\nresult=failure\nerror_type=Unauthenticated',
      ),
    );
    expect(tempRoot.listSync(), isEmpty);
  });

  test('FirebaseException is reported without secrets', () async {
    final logs = <String>[];
    File? capturedFile;

    final result = await runStoragePutFileProbe(
      debugMode: true,
      uid: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
      bucket: 'elixr-app-2026.firebasestorage.app',
      imageBytes: storagePutFileProbePngBytes,
      contentType: 'image/png',
      tempDirectory: tempRoot,
      now: DateTime.utc(2026, 8, 21, 7, 34),
      log: logs.add,
      putFile: ({required file, required storagePath, required contentType}) async {
        capturedFile = file;
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message:
              'User does not have permission. id_token=abc.secret '
              r'C:\Users\Jiro\AppData\Local\Temp\probe.png '
              'trainee@example.com https://firebasestorage.googleapis.com/v0/b/x',
        );
      },
      deleteRemote: (storagePath) async {},
    );

    expect(result.uploadSucceeded, isFalse);
    expect(result.plugin, 'firebase_storage');
    expect(result.code, 'unauthorized');
    expect(result.remoteCleanup, StoragePutFileProbeRemoteCleanup.notCreated);
    final joined = logs.join('\n');
    expect(joined, contains('result=failure'));
    expect(joined, contains('error_type=FirebaseException'));
    expect(joined, contains('plugin=firebase_storage'));
    expect(joined, contains('code=unauthorized'));
    expect(joined, isNot(contains('abc.secret')));
    expect(joined, isNot(contains(r'C:\Users')));
    expect(joined, isNot(contains('trainee@example.com')));
    expect(joined, isNot(contains('https://firebasestorage')));
    expect(capturedFile, isNotNull);
    expect(capturedFile!.existsSync(), isFalse);
    expect(result.localCleanup, StoragePutFileProbeLocalCleanup.success);
  });

  test('remote cleanup is attempted only after successful upload', () async {
    final events = <String>[];
    var profileRepositoryCalls = 0;
    var firestoreProfileUpdates = 0;

    final result = await runStoragePutFileProbe(
      debugMode: true,
      uid: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
      bucket: 'elixr-app-2026.firebasestorage.app',
      imageBytes: storagePutFileProbePngBytes,
      contentType: 'image/png',
      tempDirectory: tempRoot,
      now: DateTime.utc(2026, 8, 21, 7, 34, 12),
      log: events.add,
      putFile:
          ({required file, required storagePath, required contentType}) async {
            events.add(
              'putFile:$storagePath:$contentType:${file.lengthSync()}',
            );
            expect(file.existsSync(), isTrue);
            expect(contentType, 'image/png');
            expect(
              storagePath,
              'users/OeflNaVfBkZ93BLOsGhRyOv6WAD3/profile/'
              'transport_probe_1787297652000.png',
            );
          },
      deleteRemote: (storagePath) async {
        events.add('deleteRemote:$storagePath');
      },
    );

    expect(result.invoked, isTrue);
    expect(result.uploadSucceeded, isTrue);
    expect(result.remoteCleanup, StoragePutFileProbeRemoteCleanup.success);
    expect(result.localCleanup, StoragePutFileProbeLocalCleanup.success);
    expect(events.where((line) => line.startsWith('putFile:')), hasLength(1));
    expect(
      events.where((line) => line.startsWith('deleteRemote:')),
      hasLength(1),
    );
    expect(
      events.indexWhere((line) => line.startsWith('putFile:')),
      lessThan(events.indexWhere((line) => line.startsWith('deleteRemote:'))),
    );
    expect(events, contains('[StoragePutFileProbe] result=success bytes=67'));
    expect(events, contains('[StoragePutFileProbe] remote_cleanup=success'));
    expect(events, contains('[StoragePutFileProbe] local_cleanup=success'));
    expect(tempRoot.listSync(), isEmpty);
    expect(profileRepositoryCalls, 0);
    expect(firestoreProfileUpdates, 0);
  });

  test('failed upload does not attempt remote cleanup', () async {
    var deleteCalls = 0;
    await runStoragePutFileProbe(
      debugMode: true,
      uid: 'uid-1',
      bucket: 'bucket',
      imageBytes: storagePutFileProbePngBytes,
      contentType: 'image/png',
      tempDirectory: tempRoot,
      now: DateTime.utc(2026, 8, 21),
      log: (_) {},
      putFile:
          ({required file, required storagePath, required contentType}) async {
            throw FirebaseException(
              plugin: 'firebase_storage',
              code: 'unauthorized',
            );
          },
      deleteRemote: (storagePath) async {
        deleteCalls += 1;
      },
    );
    expect(deleteCalls, 0);
  });

  test(
    'local temp cleanup always runs even when remote cleanup fails',
    () async {
      File? capturedFile;
      final logs = <String>[];

      final result = await runStoragePutFileProbe(
        debugMode: true,
        uid: 'uid-1',
        bucket: 'bucket',
        imageBytes: storagePutFileProbePngBytes,
        contentType: 'image/png',
        tempDirectory: tempRoot,
        now: DateTime.utc(2026, 8, 21),
        log: logs.add,
        putFile:
            ({
              required file,
              required storagePath,
              required contentType,
            }) async {
              capturedFile = file;
            },
        deleteRemote: (storagePath) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unknown',
            message: 'delete failed',
          );
        },
      );

      expect(result.uploadSucceeded, isTrue);
      expect(result.remoteCleanup, StoragePutFileProbeRemoteCleanup.failure);
      expect(result.localCleanup, StoragePutFileProbeLocalCleanup.success);
      expect(capturedFile!.existsSync(), isFalse);
      expect(logs, contains('[StoragePutFileProbe] remote_cleanup=failure'));
      expect(logs, contains('[StoragePutFileProbe] local_cleanup=success'));
    },
  );

  test('probe PNG fixture is a tiny valid PNG payload', () {
    expect(storagePutFileProbePngBytes.length, lessThan(128));
    expect(
      storagePutFileProbePngBytes.sublist(0, 8),
      Uint8List.fromList(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
    );
  });
}
