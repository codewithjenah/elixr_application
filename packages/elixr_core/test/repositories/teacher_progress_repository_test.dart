import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

PublicProfileSession makeSession(String id, String date) =>
    PublicProfileSession(
      sessionId: id,
      userId: 'trainee',
      movementName: 'Hand Stall',
      difficulty: 'Easy',
      legacyScore: 80,
      durationSeconds: 60,
      propType: TrainingProp.bottle,
      createdAt: date,
    );

void main() {
  test('page-size contract is bounded from one to fifty', () {
    expect(TeacherProgressRepository.defaultPageSize, 20);
    for (final value in [1, 50]) {
      expect(
        () => TeacherProgressRepository.validatePageSize(value),
        returnsNormally,
      );
    }
    for (final value in [0, -1, 51]) {
      expect(
        () => TeacherProgressRepository.validatePageSize(value),
        throwsArgumentError,
      );
    }
  });

  test(
    'in-memory repository orders sessions and returns opaque cursor pages',
    () async {
      final repo = InMemoryTeacherProgressRepository()
        ..sessions['trainee'] = [
          makeSession('old', '2026-08-01T00:00:00Z'),
          makeSession('new', '2026-08-03T00:00:00Z'),
          makeSession('middle', '2026-08-02T00:00:00Z'),
        ];
      final first = await repo.fetchSessionsPage(
        traineeId: 'trainee',
        pageSize: 2,
      );
      expect(first.sessions.map((s) => s.sessionId), ['new', 'middle']);
      expect(first.hasMore, isTrue);
      final second = await repo.fetchSessionsPage(
        traineeId: 'trainee',
        startAfter: first.nextCursor,
      );
      expect(second.sessions.single.sessionId, 'old');
      expect(second.hasMore, isFalse);
      expect(second.nextCursor, isNull);
      await expectLater(
        repo.fetchSessionsPage(
          traineeId: 'other',
          startAfter: first.nextCursor,
        ),
        throwsArgumentError,
      );
      await repo.dispose();
    },
  );

  test('summary stream emits current and later values', () async {
    final repo = InMemoryTeacherProgressRepository();
    final values = <PublicProfileSummary?>[];
    final sub = repo.watchSummary('trainee').listen(values.add);
    await pumpEventQueue();
    repo.setSummary(
      'trainee',
      const PublicProfileSummary(
        totalDurationSeconds: 60,
        completedMovementNames: [],
      ),
    );
    await pumpEventQueue();
    expect(values, hasLength(2));
    await sub.cancel();
    await repo.dispose();
  });
}
