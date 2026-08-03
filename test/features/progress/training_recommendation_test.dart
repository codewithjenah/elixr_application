import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'user-1';

Session _session({
  required String movementName,
  int score = 70,
  String? createdAt,
  String difficulty = 'Easy',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    score: score,
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
          score: 80,
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

    test('one high-scoring session does not mark a movement mastered', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          score: 90,
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
      expect(mastery.recentAverageScore, 90);
    });

    test('three recent scores of at least 85 mark a movement mastered', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          score: 85,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Normal Grip',
          score: 88,
          createdAt: _iso(2026, 1, 2),
        ),
        _session(
          movementName: 'Normal Grip',
          score: 90,
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
      expect(mastery.status, MovementMasteryStatus.mastered);
    });

    test('recent average uses no more than five sessions', () {
      final sessions = <Session>[
        for (var i = 1; i <= 7; i++)
          _session(
            movementName: 'Normal Grip',
            score: i == 7 ? 100 : 50,
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
      expect(mastery.recentAverageScore, 60);
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
            score: 90,
            createdAt: _iso(2026, 1, i),
          ),
        for (var i = 1; i <= 3; i++)
          _session(
            movementName: 'Mastered B',
            score: 90,
            createdAt: _iso(2026, 2, i),
          ),
        _session(
          movementName: 'Weak Move',
          score: 64,
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
        'Your recent average of 64 is your lowest current mastery score.',
      );
    });

    test('oldest practice date resolves equal-score ties', () {
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
          score: 60,
          createdAt: _iso(2026, 1, 10),
        ),
        _session(
          movementName: 'Move B',
          score: 60,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Move C',
          score: 60,
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
        _session(movementName: 'Normal Grip', score: 70, createdAt: null),
        _session(
          movementName: 'Normal Grip',
          score: 75,
          createdAt: 'not-a-date',
        ),
        _session(
          movementName: 'Normal Grip',
          score: 80,
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
      expect(mastery.recentAverageScore, isNotNull);
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
              score: 90,
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
            score: 55,
            createdAt: _iso(2026, 1, 3),
          ),
          _session(
            movementName: 'Normal Grip',
            score: 80,
            createdAt: _iso(2026, 1, 1),
          ),
          _session(
            movementName: "Bartender's Grip",
            score: 72,
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
          ordered.masteries.map((m) => m.recentAverageScore),
          reversed.masteries.map((m) => m.recentAverageScore),
        );
      },
    );

    test('scores outside 0–100 are clamped safely', () {
      final sessions = [
        _session(
          movementName: 'Normal Grip',
          score: 150,
          createdAt: _iso(2026, 1, 1),
        ),
        _session(
          movementName: 'Normal Grip',
          score: -20,
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
      expect(mastery.bestScore, 100);
      expect(mastery.recentAverageScore, 50);
      expect(mastery.lifetimeAverageScore, 50);
    });
  });
}
