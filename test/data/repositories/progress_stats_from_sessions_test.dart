import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/repositories/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Session _v2({required String movementName, required int rubricTotal}) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = rubricTotal.clamp(0, 12);
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    final value = remaining >= 3 ? 3 : remaining;
    scores[i] = value;
    remaining -= value;
  }
  return Session(
    userId: 'stats-user',
    movementName: movementName,
    difficulty: 'Easy',
    rubric: RubricAssessment(
      technique: scores[0],
      stability: scores[1],
      completion: scores[2],
      propPositioning: scores[3],
    ),
    assessmentVersion: 2,
    durationSeconds: 60,
    createdAt: '2026-09-10T04:00:00.000Z',
  );
}

Session _v1({required String movementName, required int legacyScore}) {
  return Session(
    userId: 'stats-user',
    movementName: movementName,
    difficulty: 'Easy',
    legacyScore: legacyScore,
    assessmentVersion: 1,
    durationSeconds: 60,
    createdAt: '2026-09-10T04:00:00.000Z',
  );
}

void main() {
  group('ProgressStats.fromSessions', () {
    test('uses the snapshot length as totalSessions', () {
      final stats = ProgressStats.fromSessions([
        _v2(movementName: 'Normal Grip', rubricTotal: 8),
        _v1(movementName: 'Stall', legacyScore: 70),
      ]);

      expect(stats.totalSessions, 2);
      expect(stats.sessionsByMovement, {'Normal Grip': 1, 'Stall': 1});
    });

    test('partitions Assessment V1 and V2 and never mixes scales', () {
      final stats = ProgressStats.fromSessions([
        _v2(movementName: 'Normal Grip', rubricTotal: 12),
        _v2(movementName: 'Normal Grip', rubricTotal: 6),
        _v1(movementName: 'Stall', legacyScore: 90),
        _v1(movementName: 'Stall', legacyScore: 70),
      ]);

      expect(stats.rubricSessionCount, 2);
      expect(stats.averageRubricTotal, 9);
      expect(stats.bestRubricTotal, 12);
      expect(stats.legacySessionCount, 2);
      expect(stats.averageLegacyScore, 80);
      expect(stats.bestLegacyScore, 90);
      expect(stats.preferredAverage, 9);
      expect(stats.hasRubricData, isTrue);
      expect(stats.hasLegacyOnly, isFalse);
    });

    test('keeps legacy-only averages on the 0..100 scale', () {
      final stats = ProgressStats.fromSessions([
        _v1(movementName: 'Normal Grip', legacyScore: 40),
        _v1(movementName: 'Normal Grip', legacyScore: 80),
      ]);

      expect(stats.rubricSessionCount, 0);
      expect(stats.averageRubricTotal, isNull);
      expect(stats.legacySessionCount, 2);
      expect(stats.averageLegacyScore, 60);
      expect(stats.preferredAverage, 60);
      expect(stats.hasLegacyOnly, isTrue);
    });

    test('picks the first maximum movement in snapshot order', () {
      final stats = ProgressStats.fromSessions([
        _v2(movementName: 'Stall', rubricTotal: 8),
        _v2(movementName: 'Normal Grip', rubricTotal: 8),
        _v2(movementName: 'Stall', rubricTotal: 8),
        _v2(movementName: 'Normal Grip', rubricTotal: 8),
      ]);

      expect(stats.sessionsByMovement['Stall'], 2);
      expect(stats.sessionsByMovement['Normal Grip'], 2);
      expect(stats.mostPracticedMovement, 'Stall');
    });
  });
}
