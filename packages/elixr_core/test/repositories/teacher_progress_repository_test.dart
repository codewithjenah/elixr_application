import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

PublicProfileSession makeSession(String id, String? date) =>
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

class _Cursor extends TeacherProgressCursor {
  const _Cursor(this.offset);

  final int offset;
}

class _PagedOnlyRepository extends TeacherProgressRepository {
  _PagedOnlyRepository(this.items);

  final List<PublicProfileSession> items;
  int pageCalls = 0;

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) =>
      const Stream<PublicProfileSummary?>.empty();

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) async {
    TeacherProgressRepository.validatePageSize(pageSize);
    pageCalls++;
    final sorted = List<PublicProfileSession>.from(items)
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final offset = startAfter is _Cursor ? startAfter.offset : 0;
    final page = sorted.skip(offset).take(pageSize).toList(growable: false);
    final next = offset + page.length;
    return TeacherProgressPage(
      sessions: page,
      hasMore: next < sorted.length,
      nextCursor: next < sorted.length ? _Cursor(next) : null,
    );
  }
}

Map<String, dynamic> _firestoreSession({
  required String id,
  required DateTime createdAt,
  bool valid = true,
}) => {
  'session_id': id,
  'user_id': 'trainee',
  if (valid) 'movement_name': 'Hand Stall',
  'difficulty': 'Easy',
  'score': 80,
  'duration_seconds': 60,
  'prop_type': 'bottle',
  'created_at': Timestamp.fromDate(createdAt),
};

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

  test('range reads use an inclusive start and exclusive end', () async {
    final repo = InMemoryTeacherProgressRepository()
      ..sessions['trainee'] = [
        makeSession('before', '2026-08-01T23:59:59Z'),
        makeSession('at-start', '2026-08-02T00:00:00Z'),
        makeSession('inside', '2026-08-02T12:00:00Z'),
        makeSession('at-end', '2026-08-03T00:00:00Z'),
        makeSession('missing-date', null),
      ];

    final result = await repo.fetchSessionsInRange(
      traineeId: 'trainee',
      startUtc: DateTime.utc(2026, 8, 2),
      endUtc: DateTime.utc(2026, 8, 3),
    );
    expect(result.map((session) => session.sessionId), ['inside', 'at-start']);
    await repo.dispose();
  });

  test(
    'default range implementation paginates beyond fifty sessions',
    () async {
      final items = [
        for (var index = 0; index < 55; index++)
          makeSession(
            'session-$index',
            DateTime.utc(2026, 8, 2, 0, index).toIso8601String(),
          ),
      ];
      final repo = _PagedOnlyRepository(items);

      final result = await repo.fetchSessionsInRange(
        traineeId: 'trainee',
        startUtc: DateTime.utc(2026, 8, 2),
        endUtc: DateTime.utc(2026, 8, 3),
      );

      expect(result, hasLength(55));
      expect(repo.pageCalls, 2);
    },
  );

  test(
    'Firebase range query bounds timestamps and skips malformed projections',
    () async {
      final firestore = FakeFirebaseFirestore();
      final sessions = firestore
          .collection(FirestoreCollections.publicProfiles)
          .doc('trainee')
          .collection('sessions');
      final start = DateTime.utc(2026, 8, 2);
      final end = DateTime.utc(2026, 8, 3);
      await Future.wait([
        sessions
            .doc('at-start')
            .set(_firestoreSession(id: 'at-start', createdAt: start)),
        sessions
            .doc('at-end')
            .set(_firestoreSession(id: 'at-end', createdAt: end)),
        sessions
            .doc('inside')
            .set(
              _firestoreSession(
                id: 'inside',
                createdAt: DateTime.utc(2026, 8, 2, 12),
              ),
            ),
        sessions
            .doc('malformed')
            .set(
              _firestoreSession(
                id: 'malformed',
                createdAt: DateTime.utc(2026, 8, 2, 13),
                valid: false,
              ),
            ),
      ]);

      final repository = FirebaseTeacherProgressRepository(
        firestore: firestore,
      );
      final result = await repository.fetchSessionsInRange(
        traineeId: 'trainee',
        startUtc: start,
        endUtc: end,
      );

      expect(result, hasLength(2));
      expect(result.map((session) => session.sessionId), contains('at-start'));
      expect(result.map((session) => session.sessionId), contains('inside'));
      expect(
        result.map((session) => session.sessionId),
        isNot(contains('at-end')),
      );
      expect(
        result.map((session) => session.sessionId),
        isNot(contains('malformed')),
      );
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
