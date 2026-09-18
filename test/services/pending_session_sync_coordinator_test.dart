import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/services/pending_session_store.dart';
import 'package:elixr_application/services/pending_session_sync_coordinator.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

PendingSession _pending() => PendingSession(
  sessionId: 'stable-session-id',
  userId: 'trainee-a',
  displayName: 'Trainee A',
  movementName: 'Hand Stall',
  difficulty: 'Easy',
  prop: TrainingProp.bottle,
  rubric: const RubricAssessment(
    technique: 2,
    stability: 2,
    completion: 2,
    propPositioning: 2,
  ),
  durationSeconds: 30,
  improvements: const [
    PracticeFeedback(
      bottleDetected: false,
      movement: 'Hand Stall',
      feedback: 'Keep steady.',
      feedbackType: 'technique',
      postureStatus: 'unknown',
    ),
  ],
  completedAt: DateTime.utc(2026, 9, 18),
);

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('elixr-sync-test-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'successful authoritative replay dequeues the same reserved ID',
    () async {
      String? savedId;
      final service = SessionService(
        saveCompletedSessionAtomicOverride:
            ({required sessionId, required session, required feedbacks}) async {
              savedId = sessionId;
            },
      );
      final store = PendingSessionStore(directory: directory);
      final pending = _pending();
      final coordinator = PendingSessionSyncCoordinator(
        store: store,
        sessionService: service,
      )..setActiveTrainee('trainee-a');
      await Future<void>.delayed(Duration.zero);
      await store.enqueue(pending);

      expect(await coordinator.syncSession(pending), isTrue);
      expect(savedId, pending.sessionId);
      expect(await store.listForUser('trainee-a'), isEmpty);
    },
  );

  test(
    'remote failure stays queued and another account cannot replay it',
    () async {
      final service = SessionService(
        saveCompletedSessionAtomicOverride:
            ({required sessionId, required session, required feedbacks}) async {
              throw StateError('offline');
            },
      );
      final store = PendingSessionStore(directory: directory);
      final pending = _pending();
      await store.enqueue(pending);
      final coordinator = PendingSessionSyncCoordinator(
        store: store,
        sessionService: service,
      )..setActiveTrainee('trainee-b');

      expect(await coordinator.syncSession(pending), isFalse);
      expect(await store.listForUser('trainee-a'), hasLength(1));
    },
  );

  test('repeated triggers use one remote save flight', () async {
    final completion = Completer<void>();
    var calls = 0;
    final service = SessionService(
      saveCompletedSessionAtomicOverride:
          ({required sessionId, required session, required feedbacks}) async {
            calls++;
            await completion.future;
          },
    );
    final store = PendingSessionStore(directory: directory);
    final pending = _pending();
    final coordinator = PendingSessionSyncCoordinator(
      store: store,
      sessionService: service,
    )..setActiveTrainee('trainee-a');
    await Future<void>.delayed(Duration.zero);
    await store.enqueue(pending);

    final first = coordinator.syncSession(pending);
    final second = coordinator.syncSession(pending);
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    completion.complete();
    expect(await first, isTrue);
  });
}
