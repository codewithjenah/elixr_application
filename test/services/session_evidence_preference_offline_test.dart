import 'dart:async';
import 'dart:io';

import 'package:elixr_application/services/session_evidence_preference_store.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SessionEvidencePreferenceStore> createStore() async {
    final directory = await Directory.systemTemp.createTemp('elixr_evidence_');
    addTearDown(() => directory.delete(recursive: true));
    return SessionEvidencePreferenceStore(
      file: File('${directory.path}${Platform.pathSeparator}preferences.json'),
    );
  }

  test(
    'first choice persists locally without waiting for unavailable Firebase',
    () async {
      final store = await createStore();
      final neverCompletes = Completer<void>();
      final service = SessionService(
        evidencePreferenceStore: store,
        evidencePreferenceRemoteWriter: ({required userId, required enabled}) =>
            neverCompletes.future,
      );

      await service.setSessionEvidenceEnabled(
        userId: 'trainee-a',
        enabled: true,
      );

      expect(await store.read('trainee-a'), isTrue);
      expect(await service.sessionEvidenceEnabled('trainee-a'), isTrue);
    },
  );

  test(
    'a later best-effort sync projects the locally durable choice',
    () async {
      final store = await createStore();
      final writes = <({String userId, bool enabled})>[];
      final service = SessionService(
        evidencePreferenceStore: store,
        evidencePreferenceRemoteWriter:
            ({required userId, required enabled}) async {
              writes.add((userId: userId, enabled: enabled));
            },
      );
      await store.write('trainee-a', true);

      await service.syncSessionEvidencePreference('trainee-a');
      await pumpEventQueue();

      expect(writes, contains((userId: 'trainee-a', enabled: true)));
    },
  );

  test('a newer opt-out is sent after an in-flight older opt-in', () async {
    final store = await createStore();
    final firstWrite = Completer<void>();
    final optInStarted = Completer<void>();
    final writes = <bool>[];
    final service = SessionService(
      evidencePreferenceStore: store,
      evidencePreferenceRemoteWriter:
          ({required userId, required enabled}) async {
            writes.add(enabled);
            if (enabled) {
              optInStarted.complete();
              await firstWrite.future;
            }
          },
    );

    await service.setSessionEvidenceEnabled(userId: 'trainee-a', enabled: true);
    await optInStarted.future;
    await service.setSessionEvidenceEnabled(
      userId: 'trainee-a',
      enabled: false,
    );
    firstWrite.complete();
    await pumpEventQueue();

    expect(writes, [true, false]);
    expect(await store.read('trainee-a'), isFalse);
  });

  test(
    'a temporary remote preference write failure retries the durable choice',
    () async {
      final store = await createStore();
      final retried = Completer<void>();
      var attempts = 0;
      final service = SessionService(
        evidencePreferenceStore: store,
        evidencePreferenceRetryDelay: (_) => Duration.zero,
        evidencePreferenceRemoteWriter:
            ({required userId, required enabled}) async {
              attempts++;
              if (attempts == 1) throw StateError('temporary network failure');
              retried.complete();
            },
      );
      addTearDown(service.dispose);

      await service.setSessionEvidenceEnabled(
        userId: 'trainee-a',
        enabled: true,
      );
      await retried.future;

      expect(attempts, 2);
      expect(await store.read('trainee-a'), isTrue);
    },
  );

  test(
    'a late old remote write reprojects the latest local decision',
    () async {
      final store = await createStore();
      final oldOptIn = Completer<void>();
      final oldOptInStarted = Completer<void>();
      final writes = <bool>[];
      final service = SessionService(
        evidencePreferenceStore: store,
        evidencePreferenceWriteTimeout: const Duration(milliseconds: 1),
        evidencePreferenceRetryDelay: (_) => const Duration(days: 1),
        evidencePreferenceRemoteWriter:
            ({required userId, required enabled}) async {
              writes.add(enabled);
              if (enabled && writes.where((value) => value).length == 1) {
                oldOptInStarted.complete();
                await oldOptIn.future;
              }
            },
      );
      addTearDown(service.dispose);

      await service.setSessionEvidenceEnabled(
        userId: 'trainee-a',
        enabled: true,
      );
      await oldOptInStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.setSessionEvidenceEnabled(
        userId: 'trainee-a',
        enabled: false,
      );
      await pumpEventQueue();
      oldOptIn.complete();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(writes, [true, false, false]);
      expect(await store.read('trainee-a'), isFalse);
    },
  );

  test('false consent remains local and is never converted to true', () async {
    final store = await createStore();
    final service = SessionService(
      evidencePreferenceStore: store,
      evidencePreferenceRemoteWriter:
          ({required userId, required enabled}) async {},
    );

    await service.setSessionEvidenceEnabled(
      userId: 'trainee-a',
      enabled: false,
    );

    expect(await service.sessionEvidenceEnabled('trainee-a'), isFalse);
    await service.purgeLocalSessionEvidencePreference('trainee-a');
    expect(await store.read('trainee-a'), isNull);
  });
}
