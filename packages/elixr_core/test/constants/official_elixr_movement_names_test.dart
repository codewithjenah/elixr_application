import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official identities are exactly the 15 catalog names', () {
    expect(
      officialElixrMovementNames,
      unorderedEquals(const [
        'Normal Grip',
        "Bartender's Grip",
        'Reverse Grip',
        'Claw Grip',
        'Body Grip',
        'Hand Stall',
        'One Finger Stall',
        'Forearm Stall',
        'Elbow Stall',
        'Wrist Stall',
        'Reverse Forearm Stall',
        'Shoulder Stall',
        'Double Hand Stall',
        'Bottle in a tin',
        'Double Forearm Stall',
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
      expect(isOfficialElixrMovementName('Wrist Stall'), isTrue);
      expect(isOfficialElixrMovementName('Body Grip'), isTrue);
      expect(isOfficialElixrMovementName('Double Forearm Stall'), isTrue);
      expect(isOfficialElixrMovementName('Basic Flip'), isFalse);
      expect(isOfficialElixrMovementName('hand stall'), isFalse);
      expect(isOfficialElixrMovementName(''), isFalse);
    },
  );

  test('official identity map is explicit, complete, and not a slugger', () {
    expect(officialElixrMovementIdentities, hasLength(15));
    expect(
      officialElixrMovementIdentities.map((identity) => identity.catalogName),
      unorderedEquals(officialElixrMovementNames),
    );
    expect(
      officialElixrIdentityForName('Hand Stall'),
      isA<OfficialElixrMovementIdentity>()
          .having((id) => id.movementId, 'movementId', 'official_hand_stall')
          .having(
            (id) => id.revisionId,
            'revisionId',
            'official_hand_stall_v1',
          ),
    );
    expect(
      officialElixrIdentityForName("Bartender's Grip")?.movementId,
      'official_bartenders_grip',
    );
    expect(
      officialElixrIdentityForName('Bottle in a tin')?.revisionId,
      'official_bottle_in_a_tin_v1',
    );
    expect(officialElixrIdentityForName('Arm Stall'), isNull);
    expect(officialElixrIdentityForName('Upper Forearm Stall'), isNull);
    expect(
      officialElixrIdentityForName('Wrist Stall')?.movementId,
      'official_wrist_stall',
    );
    expect(
      officialElixrIdentityForName('Body Grip')?.revisionId,
      'official_body_grip_v1',
    );
    expect(
      officialElixrIdentityForName('Double Forearm Stall')?.revisionId,
      'official_double_forearm_stall_v1',
    );
    expect(officialElixrIdentityForName('Free Practice'), isNull);
    expect(officialElixrIdentityForName('hand stall'), isNull);
    expect(
      officialElixrIdentityForMovementId('official_normal_grip')?.catalogName,
      'Normal Grip',
    );
  });
}
