import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every enabled movement has a positive locked code and duration', () {
    final enabled = movementCatalog.where((m) => m.enabled);
    for (final movement in enabled) {
      expect(
        positiveLockedCodeForMovement(movement.name),
        isNotNull,
        reason: movement.name,
      );
      expect(
        positiveSuccessCodes.contains(
          positiveLockedCodeForMovement(movement.name),
        ),
        isTrue,
      );
      expect(recommendedDurationForMovement(movement.name), greaterThan(0));
    }
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
    expect(confirmedStrengthMessageFor('Normal Grip'), 'Normal Grip confirmed');
    expect(
      formStrengthMessageFor('Elbow Stall'),
      'Correct Elbow Stall form detected',
    );
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

  test('unknown movement uses duration default without positive code', () {
    expect(positiveLockedCodeForMovement('Coming Soon Stall'), isNull);
    expect(recommendedDurationForMovement('Coming Soon Stall'), 180);
    expect(
      formStrengthMessageFor('Coming Soon Stall'),
      'Correct Coming Soon Stall form detected',
    );
  });
}
