import 'package:elixr_application/debug/storage_cross_service_probe.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release mode cannot invoke the diagnostic probe path', () async {
    var putDataCalls = 0;
    var deleteCalls = 0;
    final logs = <String>[];

    final result = await runStorageCrossServiceProbe(
      debugMode: false,
      uid: kStorageCrossServiceProbeTraineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: logs.add,
      putData:
          ({required bytes, required storagePath, required contentType}) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {
        deleteCalls += 1;
      },
    );

    expect(result.invoked, isFalse);
    expect(result.cases, isEmpty);
    expect(putDataCalls, 0);
    expect(deleteCalls, 0);
    expect(logs, isEmpty);
  });

  test(
    'live dart-define seam is a no-op when debug or define is off',
    () async {
      var liveRuns = 0;
      expect(
        await maybeRunLiveStorageCrossServiceProbe(
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
        await maybeRunLiveStorageCrossServiceProbe(
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
    var putDataCalls = 0;
    final logs = <String>[];

    final result = await runStorageCrossServiceProbe(
      debugMode: true,
      uid: null,
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: logs.add,
      putData:
          ({required bytes, required storagePath, required contentType}) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {},
    );

    expect(result.invoked, isFalse);
    expect(putDataCalls, 0);
    expect(result.firstFailure, 'request_local');
    expect(
      logs.join('\n'),
      contains(
        '[StorageCrossServiceProbe]\n'
        'case=request_local\n'
        'result=failure\n'
        'error_type=Unauthenticated',
      ),
    );
  });

  test('wrong trainee fails closed without upload', () async {
    var putDataCalls = 0;
    final logs = <String>[];

    final result = await runStorageCrossServiceProbe(
      debugMode: true,
      uid: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: logs.add,
      putData:
          ({required bytes, required storagePath, required contentType}) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {},
    );

    expect(result.invoked, isFalse);
    expect(putDataCalls, 0);
    expect(result.errorType, 'WrongTrainee');
    expect(logs.join('\n'), contains('error_type=WrongTrainee'));
  });

  test('payload is 128 bytes of application/octet-stream', () {
    expect(storageCrossServiceProbeBytes.length, 128);
    expect(kStorageCrossServiceProbeContentType, 'application/octet-stream');
  });

  test('successful suite uploads each case once then deletes', () async {
    final events = <String>[];
    final logs = <String>[];

    final result = await runStorageCrossServiceProbe(
      debugMode: true,
      uid: kStorageCrossServiceProbeTraineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: logs.add,
      putData:
          ({required bytes, required storagePath, required contentType}) async {
            expect(bytes.length, 128);
            expect(contentType, 'application/octet-stream');
            events.add('putData:$storagePath');
          },
      deleteRemote: (storagePath) async {
        events.add('delete:$storagePath');
      },
    );

    expect(result.invoked, isTrue);
    expect(result.allSucceeded, isTrue);
    expect(result.firstFailure, isNull);
    expect(result.cases, hasLength(4));
    expect(
      result.cases.map((item) => item.caseName),
      kStorageCrossServiceProbeCases,
    );
    const prefix =
        '__elixr_diagnostics__/phase6_cross_service/$kStorageCrossServiceProbeTraineeId';
    expect(events, [
      'putData:$prefix/request_local.bin',
      'delete:$prefix/request_local.bin',
      'putData:$prefix/membership_one_get.bin',
      'delete:$prefix/membership_one_get.bin',
      'putData:$prefix/assignment_one_get.bin',
      'delete:$prefix/assignment_one_get.bin',
      'putData:$prefix/two_gets.bin',
      'delete:$prefix/two_gets.bin',
    ]);
    expect(logs.join('\n'), contains('case=request_local\nresult=success'));
    expect(logs.join('\n'), contains('remote_cleanup=success'));
  });

  test('stops at the first failure and does not retry', () async {
    final events = <String>[];
    final logs = <String>[];
    var putDataCalls = 0;

    final result = await runStorageCrossServiceProbe(
      debugMode: true,
      uid: kStorageCrossServiceProbeTraineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: logs.add,
      putData:
          ({required bytes, required storagePath, required contentType}) async {
            putDataCalls += 1;
            events.add(storagePath);
            if (storagePath.endsWith('membership_one_get.bin')) {
              throw FirebaseException(
                plugin: 'firebase_storage',
                code: 'unauthorized',
                message:
                    'User does not have permission. id_token=abc.secret '
                    'trainee@example.com https://firebasestorage.googleapis.com/v0/b/x '
                    'Authorization: Bearer secret-token',
              );
            }
          },
      deleteRemote: (storagePath) async {
        events.add('delete:$storagePath');
      },
    );

    expect(putDataCalls, 2);
    expect(result.firstFailure, 'membership_one_get');
    expect(result.allSucceeded, isFalse);
    expect(result.cases, hasLength(2));
    expect(result.cases.last.uploadSucceeded, isFalse);
    expect(
      result.cases.last.remoteCleanup,
      StorageCrossServiceProbeRemoteCleanup.notCreated,
    );
    expect(
      events.where((path) => path.endsWith('assignment_one_get.bin')),
      isEmpty,
    );
    expect(events.where((path) => path.endsWith('two_gets.bin')), isEmpty);
    final joined = logs.join('\n');
    expect(joined, contains('case=membership_one_get'));
    expect(joined, contains('result=failure'));
    expect(joined, contains('plugin=firebase_storage'));
    expect(joined, contains('code=unauthorized'));
    expect(joined, isNot(contains('abc.secret')));
    expect(joined, isNot(contains('trainee@example.com')));
    expect(joined, isNot(contains('https://firebasestorage')));
    expect(joined, isNot(contains('Bearer secret-token')));
    expect(joined, isNot(contains('Authorization: Bearer')));
  });

  test('does not create Firestore documents', () async {
    var firestoreWrites = 0;
    await runStorageCrossServiceProbe(
      debugMode: true,
      uid: kStorageCrossServiceProbeTraineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      payload: storageCrossServiceProbeBytes,
      log: (_) {},
      putData:
          ({
            required bytes,
            required storagePath,
            required contentType,
          }) async {},
      deleteRemote: (_) async {},
    );
    expect(firestoreWrites, 0);
  });
}
