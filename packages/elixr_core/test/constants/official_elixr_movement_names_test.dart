import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official identities are exactly the 12 catalog names', () {
    expect(
      officialElixrMovementNames,
      unorderedEquals(const [
        'Normal Grip',
        "Bartender's Grip",
        'Reverse Grip',
        'Claw Grip',
        'Hand Stall',
        'One Finger Stall',
        'Forearm Stall',
        'Elbow Stall',
        'Reverse Forearm Stall',
        'Shoulder Stall',
        'Double Hand Stall',
        'Bottle in a tin',
      ]),
    );
    expect(officialElixrMovementNames, equals(coachingMovementNames));
  });

  test(
    'predicate accepts official names and rejects aliases and custom names',
    () {
      expect(isOfficialElixrMovementName('Hand Stall'), isTrue);
      expect(isOfficialElixrMovementName("Bartender's Grip"), isTrue);
      expect(isOfficialElixrMovementName('Bottle in a tin'), isTrue);

      expect(isOfficialElixrMovementName('Free Practice'), isFalse);
      expect(isOfficialElixrMovementName('Arm Stall'), isFalse);
      expect(isOfficialElixrMovementName('Upper Forearm Stall'), isFalse);
      expect(isOfficialElixrMovementName('Wrist Stall'), isFalse);
      expect(isOfficialElixrMovementName('Basic Flip'), isFalse);
      expect(isOfficialElixrMovementName('hand stall'), isFalse);
      expect(isOfficialElixrMovementName(''), isFalse);
    },
  );
}
