import '../../core/progression/practice_variant.dart';
import '../../core/progression/progression_catalog.dart';
import 'daily_quest.dart';
import 'training_prop.dart';

/// Personally unlocked practice inventory used only when generating a new
/// Daily Quest board.
///
/// Derived from [allPersonallyLevelUnlockedVariants] plus the official
/// movement catalog. Tutorial completion and teacher assignment grants are
/// intentionally ignored so generation cannot leak assignment-scoped access
/// or treat a tutorial-locked variant as a Daily Quest requirement.
class DailyQuestUnlockPool {
  const DailyQuestUnlockPool({
    required this.movementIdentityCount,
    required this.shakerVariantCount,
    required this.comboVariantCount,
    required this.distinctPropCount,
    required this.nonBottleVariantCount,
    required this.easyOptionCount,
    required this.mediumOptionCount,
    required this.hardOptionCount,
  });

  /// Distinct official movement names among personally unlocked variants.
  final int movementIdentityCount;

  /// Personally unlocked variants whose prop is [TrainingProp.shaker].
  final int shakerVariantCount;

  /// Personally unlocked variants whose prop is [TrainingProp.bottleAndShaker].
  final int comboVariantCount;

  /// Distinct [TrainingProp] values among personally unlocked variants.
  final int distinctPropCount;

  /// Personally unlocked variants that are not bottle-only.
  final int nonBottleVariantCount;

  /// Personally unlocked practice variants whose catalog difficulty is Easy.
  final int easyOptionCount;

  /// Personally unlocked practice variants whose catalog difficulty is Medium.
  final int mediumOptionCount;

  /// Personally unlocked practice variants whose catalog difficulty is Hard.
  final int hardOptionCount;

  /// Builds the pool from the canonical 20-level personal progression.
  ///
  /// Unknown or catalog-unresolved variants are skipped (fail closed) rather
  /// than guessed. Does not consult assignment grants.
  factory DailyQuestUnlockPool.fromPersonalLevel(int level) {
    final variants = allPersonallyLevelUnlockedVariants(level);
    return DailyQuestUnlockPool.fromVariants(variants);
  }

  factory DailyQuestUnlockPool.fromVariants(
    Iterable<PracticeVariant> variants,
  ) {
    final identities = <String>{};
    final props = <TrainingProp>{};
    var shakerVariantCount = 0;
    var comboVariantCount = 0;
    var nonBottleVariantCount = 0;
    var easyOptionCount = 0;
    var mediumOptionCount = 0;
    var hardOptionCount = 0;

    for (final variant in variants) {
      final step = resolvePracticeVariant(variant);
      if (step == null) continue;

      identities.add(step.movement.name);
      props.add(variant.trainingProp);
      switch (variant.trainingProp) {
        case TrainingProp.shaker:
          shakerVariantCount++;
          nonBottleVariantCount++;
        case TrainingProp.bottleAndShaker:
          comboVariantCount++;
          nonBottleVariantCount++;
        case TrainingProp.bottle:
          break;
      }

      switch (step.movement.difficulty.trim().toLowerCase()) {
        case 'easy':
          easyOptionCount++;
        case 'medium':
          mediumOptionCount++;
        case 'hard':
          hardOptionCount++;
      }
    }

    return DailyQuestUnlockPool(
      movementIdentityCount: identities.length,
      shakerVariantCount: shakerVariantCount,
      comboVariantCount: comboVariantCount,
      distinctPropCount: props.length,
      nonBottleVariantCount: nonBottleVariantCount,
      easyOptionCount: easyOptionCount,
      mediumOptionCount: mediumOptionCount,
      hardOptionCount: hardOptionCount,
    );
  }
}

/// Whether [quest] may enter **new** Daily Quest board generation given the
/// trainee's personally unlocked practice pool.
///
/// Generic session/duration/score quests are always eligible. Content
/// quests require enough unlocked choice that completion is not forced onto
/// a single newly unlocked movement, difficulty, or prop.
///
/// This is generation-only. [QuestDefinition.evaluate] still reads completed
/// [Session] data and must not depend on this pool.
bool isEligibleForDailyQuestGeneration(
  QuestDefinition quest,
  DailyQuestUnlockPool pool,
) {
  return switch (quest.id) {
    'two_movements' => pool.movementIdentityCount >= 3,
    'three_movements' => pool.movementIdentityCount >= 5,
    'practice_easy_movement' => pool.easyOptionCount >= 1,
    'practice_medium_movement' => pool.mediumOptionCount >= 2,
    'practice_hard_movement' => pool.hardOptionCount >= 2,
    'use_shaker' => pool.shakerVariantCount >= 2,
    'distinct_props_2' =>
      pool.distinctPropCount >= 2 && pool.nonBottleVariantCount >= 2,
    'use_bottle_and_shaker_combo' => pool.comboVariantCount >= 2,
    _ => true,
  };
}
