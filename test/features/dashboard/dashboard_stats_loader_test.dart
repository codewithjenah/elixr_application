import 'dart:async';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/repositories/progress_repository.dart';
import 'package:elixr_application/data/repositories/session_repository.dart';
import 'package:elixr_application/features/dashboard/dashboard_stats_loader.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

Session _session({
  String userId = 'user-a',
  String movementName = 'Normal Grip',
}) {
  return Session(
    userId: userId,
    movementName: movementName,
    difficulty: 'Easy',
    rubric: const RubricAssessment(
      technique: 2,
      stability: 2,
      completion: 2,
      propPositioning: 2,
    ),
    assessmentVersion: 2,
    durationSeconds: 60,
    createdAt: '2026-09-10T04:00:00.000Z',
  );
}

TrainingRecommendation _recommend(List<Session> sessions) {
  return buildTrainingRecommendation(
    sessions: sessions,
    movements: movementCatalog,
  );
}

void main() {
  group('DashboardStatsLoader', () {
    test('keeps previous same-user values when a refresh fails', () async {
      final sessions = _FakeSessionRepository([_session()]);
      final loader = DashboardStatsLoader(
        sessionRepository: sessions,
        buildRecommendation: _recommend,
      );

      await loader.load('user-a');
      expect(loader.stats?.totalSessions, 1);
      expect(loader.sessions, hasLength(1));
      expect(loader.loadError, isNull);
      expect(loader.loading, isFalse);

      sessions.error = StateError('unavailable');
      await loader.load('user-a');

      expect(loader.stats?.totalSessions, 1);
      expect(loader.sessions, hasLength(1));
      expect(loader.trainingRecommendation, isNotNull);
      expect(loader.loadedUserId, 'user-a');
      expect(loader.loadError, isNotNull);
      expect(loader.showFullPageError, isFalse);
      expect(loader.showInlineError, isTrue);
      expect(loader.loading, isFalse);
    });

    test('first-load failure has no cached dashboard data', () async {
      final loader = DashboardStatsLoader(
        sessionRepository: _FakeSessionRepository(const [])
          ..error = StateError('unavailable'),
        buildRecommendation: _recommend,
      );

      await loader.load('user-a');

      expect(loader.stats, isNull);
      expect(loader.sessions, isEmpty);
      expect(loader.trainingRecommendation, isNull);
      expect(loader.loadedUserId, isNull);
      expect(loader.showFullPageError, isTrue);
      expect(loader.requestedUserId, 'user-a');
      expect(loader.loading, isFalse);
    });

    test('successful retry replaces stale same-user values', () async {
      final sessions = _FakeSessionRepository([_session()]);
      final loader = DashboardStatsLoader(
        sessionRepository: sessions,
        buildRecommendation: _recommend,
      );

      await loader.load('user-a');
      sessions.error = StateError('unavailable');
      await loader.load('user-a');
      expect(loader.stats?.totalSessions, 1);

      sessions.error = null;
      sessions.sessions = [_session(), _session(movementName: 'Stall')];
      await loader.load('user-a');

      expect(loader.stats?.totalSessions, 2);
      expect(loader.sessions, hasLength(2));
      expect(loader.loadError, isNull);
    });

    test(
      'clears previous user data as soon as another user starts loading',
      () async {
        final sessions = _FakeSessionRepository([_session()]);
        final loader = DashboardStatsLoader(
          sessionRepository: sessions,
          buildRecommendation: _recommend,
        );

        await loader.load('user-a');
        expect(loader.stats?.totalSessions, 1);

        final blocked = Completer<List<Session>>();
        sessions.completer = blocked;
        sessions.sessions = [_session(userId: 'user-b', movementName: 'Stall')];

        final pending = loader.load('user-b');
        expect(loader.loading, isTrue);
        expect(loader.stats, isNull);
        expect(loader.sessions, isEmpty);
        expect(loader.loadedUserId, isNull);
        expect(loader.trainingRecommendation, isNull);
        expect(loader.hasDataFor('user-a'), isFalse);
        expect(loader.hasDataFor('user-b'), isFalse);

        blocked.complete(sessions.sessions);
        await pending;

        expect(loader.loadedUserId, 'user-b');
        expect(loader.stats?.totalSessions, 1);
        expect(loader.sessions.single.userId, 'user-b');
      },
    );

    test('ignores a late previous-user response after a newer load', () async {
      final sessions = _FakeSessionRepository([_session()]);
      final loader = DashboardStatsLoader(
        sessionRepository: sessions,
        buildRecommendation: _recommend,
      );

      final firstSessions = Completer<List<Session>>();
      sessions.completer = firstSessions;
      final first = loader.load('user-a');

      sessions.completer = null;
      sessions.sessions = [_session(userId: 'user-b', movementName: 'Stall')];
      await loader.load('user-b');
      expect(loader.loadedUserId, 'user-b');

      firstSessions.complete([_session(), _session(), _session()]);
      await first;

      expect(loader.loadedUserId, 'user-b');
      expect(loader.stats?.totalSessions, 1);
      expect(loader.sessions.single.userId, 'user-b');
    });

    test(
      'does not blank already-loaded same-user data while refreshing',
      () async {
        final sessions = _FakeSessionRepository([_session()]);
        final loader = DashboardStatsLoader(
          sessionRepository: sessions,
          buildRecommendation: _recommend,
        );

        await loader.load('user-a');
        final refreshSessions = Completer<List<Session>>();
        sessions.completer = refreshSessions;
        final refresh = loader.load('user-a');

        expect(loader.loading, isFalse);
        expect(loader.stats?.totalSessions, 1);
        expect(loader.sessions, hasLength(1));

        refreshSessions.complete([_session(), _session(movementName: 'Stall')]);
        await refresh;
        expect(loader.stats?.totalSessions, 2);
      },
    );

    test('derives ProgressStats from the loaded session snapshot', () async {
      final sessions = [
        _session(movementName: 'Normal Grip'),
        _session(movementName: 'Normal Grip'),
        _session(movementName: 'Stall'),
      ];
      final loader = DashboardStatsLoader(
        sessionRepository: _FakeSessionRepository(sessions),
        buildRecommendation: _recommend,
      );

      await loader.load('user-a');
      final expected = ProgressStats.fromSessions(sessions);
      expect(loader.stats?.totalSessions, expected.totalSessions);
      expect(loader.stats?.mostPracticedMovement, 'Normal Grip');
      expect(loader.stats?.rubricSessionCount, 3);
    });
  });
}

class _FakeSessionRepository extends SessionRepository {
  _FakeSessionRepository(this.sessions);

  List<Session> sessions;
  Object? error;
  Completer<List<Session>>? completer;

  @override
  Future<List<Session>> getSessionsForUser(String userId) async {
    if (completer != null) return completer!.future;
    if (error != null) throw error!;
    return sessions;
  }
}
