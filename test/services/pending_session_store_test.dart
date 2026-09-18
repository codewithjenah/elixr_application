import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/services/pending_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

PendingSession _session(
  String id, {
  String userId = 'trainee-a',
  bool evidence = false,
}) => PendingSession(
  sessionId: id,
  userId: userId,
  displayName: 'Trainee A',
  movementName: 'Arm Stall',
  difficulty: 'Easy',
  prop: TrainingProp.bottle,
  rubric: const RubricAssessment(
    technique: 2,
    stability: 2,
    completion: 2,
    propPositioning: 2,
  ),
  durationSeconds: 42,
  improvements: const [
    PracticeFeedback(
      bottleDetected: false,
      movement: 'Arm Stall',
      feedback: 'Keep your elbow steady.',
      feedbackType: 'technique',
      postureStatus: 'unknown',
    ),
  ],
  completedAt: DateTime.utc(2026, 9, 18, 12),
  evidenceFileName: evidence ? '$id.jpg' : null,
  evidenceSizeBytes: evidence ? 1024 : null,
);

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('elixr-outbox-test-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'starts empty and survives a store restart with completion time',
    () async {
      final store = PendingSessionStore(directory: directory);
      expect(await store.listForUser('trainee-a'), isEmpty);

      final pending = _session('session-1');
      await store.enqueue(pending);

      final reloaded = await PendingSessionStore(
        directory: directory,
      ).listForUser('trainee-a');
      expect(reloaded, hasLength(1));
      expect(reloaded.single.sessionId, 'session-1');
      expect(reloaded.single.completedAt.toUtc(), pending.completedAt.toUtc());
    },
  );

  test(
    'identical enqueue is idempotent but a conflicting ID is rejected',
    () async {
      final store = PendingSessionStore(directory: directory);
      await store.enqueue(_session('session-1'));
      await store.enqueue(_session('session-1'));
      expect(await store.listForUser('trainee-a'), hasLength(1));

      await expectLater(
        store.enqueue(_session('session-1', userId: 'trainee-b')),
        completes,
      );
      await expectLater(
        store.enqueue(
          PendingSession(
            sessionId: 'session-1',
            userId: 'trainee-a',
            displayName: 'Changed',
            movementName: 'Arm Stall',
            difficulty: 'Easy',
            prop: TrainingProp.bottle,
            rubric: const RubricAssessment(
              technique: 2,
              stability: 2,
              completion: 2,
              propPositioning: 2,
            ),
            durationSeconds: 42,
            improvements: const [],
            completedAt: DateTime.utc(2026, 9, 18, 12),
          ),
        ),
        throwsA(isA<PendingSessionConflictException>()),
      );
    },
  );

  test(
    'account queues and temporary evidence remain isolated and purgeable',
    () async {
      final store = PendingSessionStore(directory: directory);
      final withEvidence = _session('session-a', evidence: true);
      await store.enqueue(withEvidence, evidenceBytes: Uint8List(1024));
      await store.enqueue(_session('session-b', userId: 'trainee-b'));

      expect(
        await (await store.evidenceFileFor(withEvidence)).exists(),
        isTrue,
      );
      await store.purgeUser('trainee-a');
      expect(await store.listForUser('trainee-a'), isEmpty);
      expect(await store.listForUser('trainee-b'), hasLength(1));
      expect(
        await (await store.evidenceFileFor(withEvidence)).exists(),
        isFalse,
      );
    },
  );
}
