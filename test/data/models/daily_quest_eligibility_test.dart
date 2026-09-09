import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_eligibility.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

DailyQuestUnlockPool _pool({
  int movementIdentityCount = 1,
  int shakerVariantCount = 0,
  int comboVariantCount = 0,
  int distinctPropCount = 1,
  int nonBottleVariantCount = 0,
  int easyOptionCount = 1,
  int mediumOptionCount = 0,
  int hardOptionCount = 0,
}) {
  return DailyQuestUnlockPool(
    movementIdentityCount: movementIdentityCount,
    shakerVariantCount: shakerVariantCount,
    comboVariantCount: comboVariantCount,
    distinctPropCount: distinctPropCount,
    nonBottleVariantCount: nonBottleVariantCount,
    easyOptionCount: easyOptionCount,
    mediumOptionCount: mediumOptionCount,
    hardOptionCount: hardOptionCount,
  );
}

bool _eligible(String id, DailyQuestUnlockPool pool) {
  return isEligibleForDailyQuestGeneration(questById(id)!, pool);
}

void main() {
  group('DailyQuestUnlockPool.fromPersonalLevel', () {
    test(
      'Level 1 has one Easy bottle option and no locked-content inventory',
      () {
        final pool = DailyQuestUnlockPool.fromPersonalLevel(1);
        expect(pool.movementIdentityCount, 1);
        expect(pool.easyOptionCount, 1);
        expect(pool.mediumOptionCount, 0);
        expect(pool.hardOptionCount, 0);
        expect(pool.shakerVariantCount, 0);
        expect(pool.comboVariantCount, 0);
        expect(pool.distinctPropCount, 1);
        expect(pool.nonBottleVariantCount, 0);
      },
    );

    test('counts practice variants, not only movement identities', () {
      final atSix = DailyQuestUnlockPool.fromPersonalLevel(6);
      final atSeven = DailyQuestUnlockPool.fromPersonalLevel(7);
      expect(atSix.mediumOptionCount, 1);
      expect(atSix.shakerVariantCount, 0);
      expect(atSeven.mediumOptionCount, 2);
      expect(atSeven.shakerVariantCount, 1);
      expect(atSeven.movementIdentityCount, atSix.movementIdentityCount);
    });

    test(
      'derives inventory from the personal catalog, not assignment grants',
      () {
        final expected = allPersonallyLevelUnlockedVariants(9);
        final pool = DailyQuestUnlockPool.fromVariants(expected);
        expect(
          DailyQuestUnlockPool.fromPersonalLevel(9).shakerVariantCount,
          pool.shakerVariantCount,
        );
        expect(
          expected.where(
            (variant) => variant.trainingProp == TrainingProp.shaker,
          ),
          hasLength(2),
        );
      },
    );
  });

  group('isEligibleForDailyQuestGeneration', () {
    test(
      'generic session, duration, and score quests stay eligible at Level 1',
      () {
        final pool = DailyQuestUnlockPool.fromPersonalLevel(1);
        for (final id in [
          'session_count_1',
          'duration_10min',
          'score_70',
          'session_count_3',
          'duration_20min',
          'score_85',
          'sessions_above_70_x2',
          'session_count_5',
          'duration_30min',
          'score_95',
        ]) {
          expect(_eligible(id, pool), isTrue, reason: id);
        }
      },
    );

    test(
      'Practice 2 Different Movements needs at least 3 unlocked identities',
      () {
        expect(
          _eligible('two_movements', _pool(movementIdentityCount: 2)),
          isFalse,
        );
        expect(
          _eligible('two_movements', _pool(movementIdentityCount: 3)),
          isTrue,
        );
      },
    );

    test(
      'Practice 3 Different Movements needs at least 5 unlocked identities',
      () {
        expect(
          _eligible('three_movements', _pool(movementIdentityCount: 4)),
          isFalse,
        );
        expect(
          _eligible('three_movements', _pool(movementIdentityCount: 5)),
          isTrue,
        );
      },
    );

    test('Easy-difficulty quest stays available when Easy content exists', () {
      expect(
        _eligible('practice_easy_movement', _pool(easyOptionCount: 1)),
        isTrue,
      );
      expect(
        _eligible('practice_easy_movement', _pool(easyOptionCount: 0)),
        isFalse,
      );
    });

    test(
      'Medium-difficulty quest needs at least 2 Medium practice options',
      () {
        expect(
          _eligible('practice_medium_movement', _pool(mediumOptionCount: 1)),
          isFalse,
        );
        expect(
          _eligible('practice_medium_movement', _pool(mediumOptionCount: 2)),
          isTrue,
        );
      },
    );

    test('Hard-difficulty quest needs at least 2 Hard practice options', () {
      expect(
        _eligible('practice_hard_movement', _pool(hardOptionCount: 1)),
        isFalse,
      );
      expect(
        _eligible('practice_hard_movement', _pool(hardOptionCount: 2)),
        isTrue,
      );
    });

    test(
      'Shaker quest needs at least 2 personally unlocked Shaker variants',
      () {
        expect(_eligible('use_shaker', _pool(shakerVariantCount: 1)), isFalse);
        expect(_eligible('use_shaker', _pool(shakerVariantCount: 2)), isTrue);
      },
    );

    test('2 Different Props requires two usable prop families with choice', () {
      expect(
        _eligible(
          'distinct_props_2',
          _pool(
            distinctPropCount: 2,
            nonBottleVariantCount: 1,
            shakerVariantCount: 1,
          ),
        ),
        isFalse,
      );
      expect(
        _eligible(
          'distinct_props_2',
          _pool(
            distinctPropCount: 2,
            nonBottleVariantCount: 2,
            shakerVariantCount: 2,
          ),
        ),
        isTrue,
      );
      expect(
        _eligible(
          'distinct_props_2',
          _pool(
            distinctPropCount: 2,
            nonBottleVariantCount: 2,
            shakerVariantCount: 1,
            comboVariantCount: 1,
          ),
        ),
        isTrue,
      );
    });

    test('legacy combo quest needs multiple combo-capable options', () {
      expect(
        _eligible(
          'use_bottle_and_shaker_combo',
          _pool(comboVariantCount: 1, distinctPropCount: 3),
        ),
        isFalse,
      );
      expect(
        _eligible(
          'use_bottle_and_shaker_combo',
          _pool(comboVariantCount: 2, distinctPropCount: 3),
        ),
        isTrue,
      );
    });
  });

  group('legacy combo quest remains evaluable', () {
    test('questById still resolves use_bottle_and_shaker_combo', () {
      final quest = questById('use_bottle_and_shaker_combo');
      expect(quest, isNotNull);
      expect(quest!.id, 'use_bottle_and_shaker_combo');
      expect(quest.tier, QuestTier.hard);
      expect(quest.xp, 20);
    });

    test('a combo-prop session still completes the persisted quest', () {
      final quest = questById('use_bottle_and_shaker_combo')!;
      final incomplete = quest.evaluate(const [
        Session(
          userId: 'u1',
          movementName: 'Hand Stall',
          difficulty: 'Medium',
          durationSeconds: 60,
          propType: TrainingProp.shaker,
        ),
      ]);
      expect(incomplete.completed, isFalse);

      final complete = quest.evaluate(const [
        Session(
          userId: 'u1',
          movementName: 'Bottle in a tin',
          difficulty: 'Hard',
          durationSeconds: 60,
          propType: TrainingProp.bottleAndShaker,
        ),
      ]);
      expect(complete.completed, isTrue);
      expect(complete.target, 1);
    });
  });
}
