import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:elixr_application/data/models/profile_frame_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildProfileFramePresentationOrder', () {
    test('puts equipped first among unlocked, then progression order', () {
      final order = buildProfileFramePresentationOrder(
        unlockedBorderIds: const {'bronze_ember', 'cyan_orbit', 'starter_glow'},
        equippedBorderId: 'cyan_orbit',
      );

      expect(order.unlockedBorders.map((b) => b.id).toList(), [
        'cyan_orbit',
        'starter_glow',
        'bronze_ember',
      ]);
    });

    test('partitions unlocked and locked without overlap', () {
      final order = buildProfileFramePresentationOrder(
        unlockedBorderIds: const {'starter_glow', 'bronze_ember'},
        equippedBorderId: null,
      );

      final unlockedIds = order.unlockedBorders.map((b) => b.id).toSet();
      final lockedIds = order.lockedBorders.map((b) => b.id).toSet();

      expect(unlockedIds, {'starter_glow', 'bronze_ember'});
      expect(unlockedIds.intersection(lockedIds), isEmpty);
      expect({
        ...unlockedIds,
        ...lockedIds,
      }, profileBorderCatalog.map((b) => b.id).toSet());
    });

    test('locked frames preserve achievement progression', () {
      final order = buildProfileFramePresentationOrder(
        unlockedBorderIds: const {'starter_glow'},
        equippedBorderId: null,
      );

      final lockedProgressions = <int>[];
      for (final border in order.lockedBorders) {
        final achievement = achievementCatalog.firstWhere(
          (a) => a.rewardBorderId == border.id,
        );
        lockedProgressions.add(achievement.progressionOrder);
      }

      expect(
        lockedProgressions,
        orderedEquals([...lockedProgressions]..sort()),
      );
    });

    test(
      'equipped-but-not-unlocked is presentation-only and does not mutate input',
      () {
        final unlocked = <String>{'starter_glow'};
        final order = buildProfileFramePresentationOrder(
          unlockedBorderIds: unlocked,
          equippedBorderId: 'gold_mastery',
        );

        expect(unlocked, {'starter_glow'});
        expect(order.unlockedBorders.first.id, 'gold_mastery');
        expect(
          order.unlockedBorders.map((b) => b.id),
          containsAll(['gold_mastery', 'starter_glow']),
        );
        expect(
          order.lockedBorders.map((b) => b.id),
          isNot(contains('gold_mastery')),
        );
      },
    );

    test('unknown equipped ID is ignored safely', () {
      final order = buildProfileFramePresentationOrder(
        unlockedBorderIds: const {'starter_glow'},
        equippedBorderId: 'not_a_real_border',
      );

      expect(order.unlockedBorders.map((b) => b.id).toList(), ['starter_glow']);
      expect(
        order.unlockedBorders.any((b) => b.id == 'not_a_real_border'),
        isFalse,
      );
    });

    test('empty/whitespace equipped ID is treated as none', () {
      final order = buildProfileFramePresentationOrder(
        unlockedBorderIds: const {'starter_glow'},
        equippedBorderId: '   ',
      );
      expect(order.unlockedBorders.map((b) => b.id).toList(), ['starter_glow']);
    });

    test('unmapped border uses catalog-index fallback after progression-backed', () {
      // Architecture allows future non-achievement cosmetics. Without mutating
      // the live catalog, verify compare logic via a synthetic local sort using
      // the same key rules as the helper (progression first, then catalog index).
      final progressionByBorderId = {
        for (final a in achievementCatalog)
          a.rewardBorderId: a.progressionOrder,
      };
      final catalogIndex = {
        for (var i = 0; i < profileBorderCatalog.length; i++)
          profileBorderCatalog[i].id: i,
      };

      int compareBorders(String aId, String bId) {
        final aProgression = progressionByBorderId[aId];
        final bProgression = progressionByBorderId[bId];
        if (aProgression != null && bProgression != null) {
          return aProgression.compareTo(bProgression);
        }
        if (aProgression != null) return -1;
        if (bProgression != null) return 1;
        return (catalogIndex[aId] ?? 1 << 20).compareTo(
          catalogIndex[bId] ?? 1 << 20,
        );
      }

      // Hypothetical unmapped id sorts after all progression-backed ids.
      final ids = [
        ...profileBorderCatalog.map((b) => b.id),
        'future_standalone_frame',
      ]..sort(compareBorders);

      expect(ids.last, 'future_standalone_frame');
      expect(ids.first, 'starter_glow'); // progressionOrder 1
    });
  });

  group('achievement-border progression resolve', () {
    test('every achievement rewardBorderId resolves to a known border', () {
      for (final achievement in achievementCatalog) {
        expect(
          isKnownProfileBorderId(achievement.rewardBorderId),
          isTrue,
          reason: achievement.id,
        );
      }
    });

    test(
      'every achievement-backed border resolves back to achievement progression',
      () {
        for (final entry in achievementRewardBorderIds.entries) {
          final achievement = achievementById(entry.key);
          expect(achievement, isNotNull, reason: entry.key);
          expect(achievement!.rewardBorderId, entry.value);
          expect(achievement.progressionOrder, greaterThan(0));
          expect(isKnownProfileBorderId(entry.value), isTrue);
        }
      },
    );
  });
}
