import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'user-1';

/// Distributes a 0..12 total across the four criteria (each 0..3).
RubricAssessment _rubric(int total) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = total.clamp(0, 12);
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    final value = remaining >= 3 ? 3 : remaining;
    scores[i] = value;
    remaining -= value;
  }
  return RubricAssessment(
    technique: scores[0],
    stability: scores[1],
    completion: scores[2],
    propPositioning: scores[3],
  );
}

/// Assessment V2 fixture.
Session _session({
  required String movementName,
  int rubricTotal = 8,
  String? createdAt,
  String difficulty = 'Easy',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    rubric: _rubric(rubricTotal),
    assessmentVersion: 2,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

/// Legacy Assessment V1 fixture (0..100 percentage).
Session _legacySession({
  required String movementName,
  int legacyScore = 80,
  String? createdAt,
  String difficulty = 'Easy',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    legacyScore: legacyScore,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

String _iso(int year, int month, int day, {int hour = 12}) {
  return DateTime(year, month, day, hour).toUtc().toIso8601String();
}

void main() {
  group('buildTrainingRecommendation', () {
    test('no sessions recommends the first enabled Easy movement', () {
      final result = buildTrainingRecommendation(
        sessions: const [],
        movements: movementCatalog,
      );

      expect(result.recommended.movement.name, 'Normal Grip');
      expect(result.recommended.movement.difficulty, 'Easy');
      expect(result.reason, 'You have not practiced this movement yet.');
    });

    test('an unpracticed movement is prioritized', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 10,
          createdAt: _iso(2026, 1, 1),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      expect(result.recommended.movement.name, "Bartender's Grip");
      expect(result.reason, 'You have not practiced this movement yet.');
    });

    test('one proficient session does not mark a movement mastered', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 11,
          createdAt: _iso(2026, 1, 1),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.status, MovementMasteryStatus.improving);
      expect(mastery.recentAverageRubric, 11);
      expect(mastery.recentPerformanceLevel, PerformanceLevel.proficient);
    });

    test('three proficient rubric totals mark a movement mastered', () {
      final sessions = [
        for (var i = 1; i <= 3; i++)
          _session(
            movementName: 'Normal Grip',
            rubricTotal: 9 + i,
            createdAt: _iso(2026, 1, i),
          ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.status, MovementMasteryStatus.mastered);
      expect(mastery.bestRubricTotal, 12);
    });

    test('mastery tiers follow rubric performance levels', () {
      const movements = <Movement>[
        Movement(
          name: 'Competent Move',
          difficulty: 'Easy',
          description: 'A',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Beginning Move',
          difficulty: 'Easy',
          description: 'B',
          requiresHandsDetection: true,
          enabled: true,
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: [
          for (var i = 1; i <= 3; i++)
            _session(
              movementName: 'Competent Move',
              rubricTotal: 8,
              createdAt: _iso(2026, 1, i),
            ),
          for (var i = 1; i <= 3; i++)
            _session(
              movementName: 'Beginning Move',
              rubricTotal: 3,
              createdAt: _iso(2026, 2, i),
            ),
        ],
        movements: movements,
      );

      final competent = result.masteries.firstWhere(
        (m) => m.movement.name == 'Competent Move',
      );
      final beginning = result.masteries.firstWhere(
        (m) => m.movement.name == 'Beginning Move',
      );
      expect(competent.status, MovementMasteryStatus.improving);
      expect(beginning.status, MovementMasteryStatus.learning);
      expect(result.recommended.movement.name, 'Beginning Move');
    });

    test('recent average uses no more than five sessions', () {
      final sessions = <Session>[
        for (var i = 1; i <= 7; i++)
          _session(
            movementName: 'Normal Grip',
            rubricTotal: i == 7 ? 12 : 6,
            createdAt: _iso(2026, 1, i),
          ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      // Last five totals: 6, 6, 6, 6, 12.
      expect(mastery.recentAverageRubric, closeTo(36 / 5, 0.0001));
      expect(mastery.rubricSessionCount, 7);
    });

    test('legacy sessions are excluded from rubric aggregates', () {
      final sessions = [
        for (var i = 1; i <= 3; i++)
          _legacySession(
            movementName: 'Normal Grip',
            legacyScore: 90,
            createdAt: _iso(2026, 1, i),
          ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.completedSessions, 3);
      expect(mastery.rubricSessionCount, 0);
      expect(mastery.recentAverageRubric, isNull);
      expect(mastery.lifetimeAverageRubric, isNull);
      expect(mastery.bestRubricTotal, isNull);
      // Practiced, but a legacy percentage is not rubric evidence of mastery.
      expect(mastery.status, MovementMasteryStatus.learning);
    });

    test('mixed cohorts average only the rubric sessions', () {
      final sessions = [
        _legacySession(
          movementName: 'Normal Grip',
          legacyScore: 100,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 6,
          createdAt: _iso(2026, 1, 2),
        ),
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 8,
          createdAt: _iso(2026, 1, 3),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.completedSessions, 3);
      expect(mastery.rubricSessionCount, 2);
      expect(mastery.recentAverageRubric, 7);
      expect(mastery.bestRubricTotal, 8);
    });

    test('the weakest non-mastered movement is recommended', () {
      const movements = <Movement>[
        Movement(
          name: 'Mastered A',
          difficulty: 'Easy',
          description: 'A',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Mastered B',
          difficulty: 'Easy',
          description: 'B',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Weak Move',
          difficulty: 'Easy',
          description: 'C',
          requiresHandsDetection: true,
          enabled: true,
        ),
      ];

      final sessions = [
        for (var i = 1; i <= 3; i++)
          _session(
            movementName: 'Mastered A',
            rubricTotal: 11,
            createdAt: _iso(2026, 1, i),
          ),
        for (var i = 1; i <= 3; i++)
          _session(
            movementName: 'Mastered B',
            rubricTotal: 11,
            createdAt: _iso(2026, 2, i),
          ),
        _session(
          movementName: 'Weak Move',
          rubricTotal: 6,
          createdAt: _iso(2026, 3, 1),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movements,
      );

      expect(result.recommended.movement.name, 'Weak Move');
      expect(
        result.reason,
        'Your recent rubric average of 6 / 12 is your lowest current mastery '
        'result.',
      );
    });

    test('oldest practice date resolves equal-total ties', () {
      const movements = <Movement>[
        Movement(
          name: 'Move A',
          difficulty: 'Easy',
          description: 'A',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Move B',
          difficulty: 'Easy',
          description: 'B',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Move C',
          difficulty: 'Easy',
          description: 'C',
          requiresHandsDetection: true,
          enabled: true,
        ),
      ];

      final sessions = [
        _session(
          movementName: 'Move A',
          rubricTotal: 6,
          createdAt: _iso(2026, 1, 10),
        ),
        _session(
          movementName: 'Move B',
          rubricTotal: 6,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Move C',
          rubricTotal: 6,
          createdAt: _iso(2026, 1, 5),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movements,
      );

      expect(result.recommended.movement.name, 'Move B');
    });

    test('malformed and null dates do not throw', () {
      final sessions = [
        _session(movementName: 'Normal Grip', rubricTotal: 8, createdAt: null),
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 9,
          createdAt: 'not-a-date',
        ),
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 10,
          createdAt: _iso(2026, 2, 1),
        ),
      ];

      expect(
        () => buildTrainingRecommendation(
          sessions: sessions,
          movements: movementCatalog,
        ),
        returnsNormally,
      );

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );
      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.completedSessions, 3);
      expect(mastery.recentAverageRubric, isNotNull);
    });

    test('disabled movements are excluded', () {
      const movements = <Movement>[
        Movement(
          name: 'Enabled Move',
          difficulty: 'Easy',
          description: 'Enabled',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Disabled Move',
          difficulty: 'Easy',
          description: 'Disabled',
          requiresHandsDetection: true,
          enabled: false,
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: const [],
        movements: movements,
      );

      expect(result.masteries, hasLength(1));
      expect(result.masteries.single.movement.name, 'Enabled Move');
      expect(result.recommended.movement.name, 'Enabled Move');
    });

    test('all-mastered users receive a maintenance recommendation', () {
      final sessions = <Session>[];
      for (final movement in movementCatalog.where((m) => m.enabled)) {
        for (var i = 1; i <= 3; i++) {
          sessions.add(
            _session(
              movementName: movement.name,
              rubricTotal: 11,
              createdAt: _iso(2026, 1, i + movementCatalog.indexOf(movement)),
            ),
          );
        }
      }

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      expect(
        result.masteries.every(
          (m) => m.status == MovementMasteryStatus.mastered,
        ),
        isTrue,
      );
      expect(
        result.reason,
        'All movements are mastered. Revisit this movement to maintain your skill.',
      );
    });

    test(
      'output remains deterministic when input sessions are in a different order',
      () {
        final sessions = [
          _session(
            movementName: 'Reverse Grip',
            rubricTotal: 5,
            createdAt: _iso(2026, 1, 3),
          ),
          _session(
            movementName: 'Normal Grip',
            rubricTotal: 10,
            createdAt: _iso(2026, 1, 1),
          ),
          _session(
            movementName: "Bartender's Grip",
            rubricTotal: 8,
            createdAt: _iso(2026, 1, 2),
          ),
        ];
        final shuffled = [sessions[2], sessions[0], sessions[1]];

        final ordered = buildTrainingRecommendation(
          sessions: sessions,
          movements: movementCatalog,
        );
        final reversed = buildTrainingRecommendation(
          sessions: shuffled,
          movements: movementCatalog,
        );

        expect(
          ordered.recommended.movement.name,
          reversed.recommended.movement.name,
        );
        expect(ordered.reason, reversed.reason);
        expect(
          ordered.masteries.map((m) => m.recentAverageRubric),
          reversed.masteries.map((m) => m.recentAverageRubric),
        );
      },
    );

    test('rubric aggregates stay inside 0..12', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 12,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Normal Grip',
          rubricTotal: 0,
          createdAt: _iso(2026, 1, 2),
        ),
      ];

      final result = buildTrainingRecommendation(
        sessions: sessions,
        movements: movementCatalog,
      );

      final mastery = result.masteries.firstWhere(
        (m) => m.movement.name == 'Normal Grip',
      );
      expect(mastery.bestRubricTotal, 12);
      expect(mastery.recentAverageRubric, 6);
      expect(mastery.lifetimeAverageRubric, 6);
      expect(mastery.recentAverageRubric, inInclusiveRange(0, 12));
    });
  });
}
