import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabledNames = movementCatalog
      .where((m) => m.enabled)
      .map((m) => m.name)
      .toList(growable: false);

  test('every enabled movement has a positive locked code and duration', () {
    for (final name in enabledNames) {
      expect(positiveLockedCodeForMovement(name), isNotNull, reason: name);
      expect(
        positiveSuccessCodes.contains(positiveLockedCodeForMovement(name)),
        isTrue,
      );
      expect(recommendedDurationForMovement(name), greaterThan(0));
    }
  });

  test('exactly one coaching profile exists per enabled movement', () {
    expect(movementCoachingProfiles.keys.toSet(), equals(enabledNames.toSet()));
    for (final name in enabledNames) {
      expect(
        movementCoachingProfiles.keys.where((k) => k == name).length,
        1,
        reason: name,
      );
    }
  });

  test('no coaching profile exists outside enabled catalog', () {
    expect(
      movementCoachingProfiles.keys.toSet().difference(enabledNames.toSet()),
      isEmpty,
    );
  });

  test('every profile field is nonempty', () {
    for (final entry in movementCoachingProfiles.entries) {
      final profile = entry.value;
      expect(profile.confirmedStrengthMessage, isNotEmpty, reason: entry.key);
      expect(profile.formStrengthMessage, isNotEmpty, reason: entry.key);
      expect(profile.cleanSessionMessage, isNotEmpty, reason: entry.key);
      expect(
        profile.successfulRecommendationReason,
        isNotEmpty,
        reason: entry.key,
      );
      expect(
        profile.lowDataRecommendationReason,
        isNotEmpty,
        reason: entry.key,
      );
      expect(
        profile.unconfirmedRecommendationReason,
        isNotEmpty,
        reason: entry.key,
      );
      expect(profile.holdTargetInstruction, isNotEmpty, reason: entry.key);
    }
  });

  test('confirmed strength messages are distinct across enabled movements', () {
    final messages = enabledNames
        .map(confirmedStrengthMessageFor)
        .toList(growable: false);
    expect(messages.toSet().length, enabledNames.length);
  });

  test(
    'low-data recommendation reasons are distinct across enabled movements',
    () {
      final reasons = enabledNames
          .map(
            (name) => lowDataRecommendationReasonFor(name, TrainingProp.bottle),
          )
          .toList(growable: false);
      expect(reasons.toSet().length, enabledNames.length);
    },
  );

  test(
    'unconfirmed recommendation reasons are distinct across enabled movements',
    () {
      final reasons = enabledNames
          .map(
            (name) =>
                unconfirmedRecommendationReasonFor(name, TrainingProp.bottle),
          )
          .toList(growable: false);
      expect(reasons.toSet().length, enabledNames.length);
    },
  );

  test('hold target instructions are distinct across enabled movements', () {
    final instructions = enabledNames
        .map((name) => holdTargetInstructionFor(name, TrainingProp.bottle))
        .toList(growable: false);
    expect(instructions.toSet().length, enabledNames.length);
  });
  test('focus copy covers representative Phase B technique codes', () {
    expect(
      focusCopyForCode(
        'overhand_grip_required',
        prop: TrainingProp.bottle,
        fallbackMessage: 'fallback',
      ),
      'Rotate your wrist into an overhand grip',
    );
    expect(
      focusCopyForCode(
        'shaker_not_horizontal',
        prop: TrainingProp.bottleAndShaker,
        fallbackMessage: 'fallback',
      ),
      'Hold the cocktail shaker horizontally',
    );
    expect(
      focusCopyForCode(
        'prop_not_positioned_on_target',
        prop: TrainingProp.shaker,
        fallbackMessage: 'fallback',
      ),
      'Align the cocktail shaker over the stall point',
    );
    expect(
      focusCopyForCode(
        'bottles_not_one_per_palm',
        prop: TrainingProp.bottle,
        fallbackMessage: 'fallback',
      ),
      'Position one bottle directly above each palm',
    );
  });

  test('confirmed strength helpers are deterministic', () {
    expect(
      confirmedStrengthCodeFor('normal_grip_locked'),
      'normal_grip_confirmed',
    );
    expect(
      confirmedStrengthMessageFor('Normal Grip'),
      'Secure overhand neck grip maintained',
    );
    expect(
      formStrengthMessageFor('Elbow Stall'),
      'Correct elbow stall position detected',
    );
  });

  test('successful recommendations are movement-specific', () {
    expect(
      successfulRecommendationReasonFor('Normal Grip'),
      contains('overhand neck'),
    );
    expect(
      successfulRecommendationReasonFor('Hand Stall'),
      contains('open-palm'),
    );
    expect(
      successfulRecommendationReasonFor('Shoulder Stall'),
      contains('shoulder'),
    );
    expect(
      successfulRecommendationReasonFor('Double Hand Stall'),
      contains('dual-palm'),
    );
    expect(
      successfulRecommendationReasonFor('Bottle in a tin'),
      contains('bottle-on-shaker'),
    );
  });

  test('low-data and unconfirmed recommendations are movement-specific', () {
    expect(
      lowDataRecommendationReasonFor('Normal Grip', TrainingProp.bottle),
      contains('overhand neck grip'),
    );
    expect(
      unconfirmedRecommendationReasonFor('Normal Grip', TrainingProp.bottle),
      contains('overhand neck grip'),
    );

    final handStallUnconfirmed = unconfirmedRecommendationReasonFor(
      'Hand Stall',
      TrainingProp.shaker,
    );
    expect(handStallUnconfirmed.toLowerCase(), contains('open palm'));
    expect(handStallUnconfirmed.toLowerCase(), contains('cocktail shaker'));
    expect(handStallUnconfirmed.toLowerCase(), isNot(contains('bottle')));

    expect(
      unconfirmedRecommendationReasonFor(
        'One Finger Stall',
        TrainingProp.bottle,
      ),
      contains('index fingertip'),
    );
    expect(
      unconfirmedRecommendationReasonFor(
        'Double Hand Stall',
        TrainingProp.bottle,
      ).toLowerCase(),
      contains('both'),
    );
    expect(
      unconfirmedRecommendationReasonFor(
        'Bottle in a tin',
        TrainingProp.bottleAndShaker,
      ).toLowerCase(),
      contains('horizontal shaker'),
    );
  });
  test('hold target label derives duration only from holdTargetMs', () {
    final withTarget = formatHoldTargetLabel(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      holdTargetMs: 2500,
    );
    expect(withTarget, contains('2.5 seconds'));
    expect(withTarget, contains('overhand neck grip'));

    final withoutTarget = formatHoldTargetLabel(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      holdTargetMs: 0,
    );
    expect(withoutTarget, isNot(contains('seconds')));
    expect(withoutTarget, contains('overhand neck grip'));
  });

  test('prop-aware hold target uses selected prop label', () {
    final bottle = formatHoldTargetLabel(
      movement: 'Hand Stall',
      prop: TrainingProp.bottle,
      holdTargetMs: 0,
    );
    final shaker = formatHoldTargetLabel(
      movement: 'Hand Stall',
      prop: TrainingProp.shaker,
      holdTargetMs: 0,
    );
    expect(bottle.toLowerCase(), contains('bottle'));
    expect(shaker.toLowerCase(), contains('cocktail shaker'));
    expect(shaker.toLowerCase(), isNot(contains('bottle')));
  });

  test('bottle-only and bottle-or-shaker movements keep config entries', () {
    expect(positiveLockedCodeForMovement('Normal Grip'), 'normal_grip_locked');
    expect(positiveLockedCodeForMovement('Hand Stall'), 'hand_stall_locked');
    expect(
      positiveLockedCodeForMovement('Double Hand Stall'),
      'double_hand_stall_locked',
    );
    expect(
      positiveLockedCodeForMovement('Bottle in a tin'),
      'bottle_in_tin_locked',
    );
  });

  test('unknown movement uses neutral legacy fallbacks', () {
    expect(positiveLockedCodeForMovement('Coming Soon Stall'), isNull);
    expect(recommendedDurationForMovement('Coming Soon Stall'), 180);
    expect(movementCoachingProfileFor('Coming Soon Stall'), isNull);
    expect(
      confirmedStrengthMessageFor('Coming Soon Stall'),
      'Coming Soon Stall confirmed',
    );
    expect(
      formStrengthMessageFor('Coming Soon Stall'),
      'Correct Coming Soon Stall form detected',
    );
    expect(
      cleanSessionMessageFor('Coming Soon Stall'),
      'No recurring technique issue met the session threshold.',
    );
    expect(
      successfulRecommendationReasonFor('Coming Soon Stall'),
      'Practice Coming Soon Stall again to reinforce a confirmed hold.',
    );
    expect(
      lowDataRecommendationReasonFor('Coming Soon Stall', TrainingProp.bottle),
      'Practice Coming Soon Stall again to gather technique feedback.',
    );
    expect(
      unconfirmedRecommendationReasonFor(
        'Coming Soon Stall',
        TrainingProp.bottle,
      ),
      'Practice Coming Soon Stall again and complete one confirmed hold.',
    );
    expect(
      holdTargetInstructionFor('Coming Soon Stall', TrainingProp.bottle),
      'Complete one confirmed hold',
    );
  });
}
