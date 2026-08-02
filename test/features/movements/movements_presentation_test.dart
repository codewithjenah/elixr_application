import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/constants/movement_visuals.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeMovementsSummary', () {
    test('returns empty-friendly values when there are no sessions', () {
      final summary = computeMovementsSummary(const {});

      expect(summary.practicedCount, 0);
      expect(summary.totalMovements, movementCatalog.length);
      expect(summary.totalSessions, 0);
      expect(summary.overallAverage, isNull);
    });

    test('counts practiced movements and weighted average by sessions', () {
      final summary = computeMovementsSummary({
        'Normal Grip': (count: 2, avgScore: 80),
        'Hand Stall': (count: 1, avgScore: 90),
        'Shoulder Stall': (count: 3, avgScore: 70),
      });

      // Weighted: (80*2 + 90*1 + 70*3) / 6 = 460 / 6
      expect(summary.practicedCount, 3);
      expect(summary.totalSessions, 6);
      expect(summary.overallAverage, closeTo(460 / 6, 0.001));
    });

    test('ignores catalog movements with zero sessions', () {
      final summary = computeMovementsSummary({
        'Normal Grip': (count: 0, avgScore: 0),
        'Forearm Stall': (count: 4, avgScore: 55),
      });

      expect(summary.practicedCount, 1);
      expect(summary.totalSessions, 4);
      expect(summary.overallAverage, 55);
    });
  });

  group('movement catalog', () {
    test('contains exactly one enabled Claw Grip on Easy', () {
      final claw = movementCatalog.where((m) => m.name == 'Claw Grip').toList();
      expect(claw.length, 1);
      expect(claw.first.enabled, isTrue);
      expect(claw.first.difficulty, 'Easy');
      expect(claw.first.requiresHandsDetection, isTrue);
    });

    test('Easy movements include Claw Grip', () {
      final easy = movementsByDifficulty('Easy');
      expect(easy.any((m) => m.name == 'Claw Grip'), isTrue);
    });

    test('contains exactly one enabled One Finger Stall on Medium', () {
      final oneFinger = movementCatalog
          .where((m) => m.name == 'One Finger Stall')
          .toList();
      expect(oneFinger.length, 1);
      expect(oneFinger.first.enabled, isTrue);
      expect(oneFinger.first.difficulty, 'Medium');
      expect(oneFinger.first.requiresHandsDetection, isTrue);
    });

    test('Medium movements include One Finger Stall', () {
      final medium = movementsByDifficulty('Medium');
      expect(medium.any((m) => m.name == 'One Finger Stall'), isTrue);
    });

    test('catalog contains eleven movements', () {
      expect(movementCatalog.length, 11);
    });

    test('Claw Grip has a dedicated emoji mapping', () {
      expect(MovementVisuals.emojiFor('Claw Grip'), '🦅');
      expect(MovementVisuals.emojiFor('Claw Grip'), isNot('🍾'));
    });

    test('One Finger Stall has a dedicated emoji mapping', () {
      expect(MovementVisuals.emojiFor('One Finger Stall'), '☝️');
      expect(MovementVisuals.emojiFor('One Finger Stall'), isNot('🍾'));
    });
  });

  group('difficulty helpers', () {
    test('maps difficulty accents and section titles', () {
      expect(difficultyAccentColor('Easy'), AppColors.success);
      expect(difficultyAccentColor('Medium'), AppColors.warning);
      expect(difficultyAccentColor('Hard'), AppColors.error);
      expect(difficultySectionTitle('Easy'), 'Easy — Foundations');
      expect(difficultySectionTitle('Medium'), 'Medium — Balance and control');
      expect(difficultySectionTitle('Hard'), 'Hard — Advanced stability');
    });
  });
}
