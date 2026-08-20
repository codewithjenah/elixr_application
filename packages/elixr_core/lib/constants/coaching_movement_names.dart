/// Official ELIXR movement identities.
///
/// This is the shared cross-client identity set, not the Windows catalogue's
/// hardware and presentation metadata. Flutter `movementCatalog` (enabled
/// entries) remains the product catalog authority; CI parity tests require
/// that set, this set, and `test/fixtures/enabled_scored_movements.json` to
/// stay identical. Legacy aliases and Free Practice are intentionally absent.
const coachingMovementNames = <String>{
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
};

/// Official ELIXR catalog names eligible for new saved sessions and global XP.
const officialElixrMovementNames = coachingMovementNames;

bool isRecognizedCoachingMovement(String value) =>
    coachingMovementNames.contains(value);

/// Whether [name] is one of the 12 official ELIXR catalog identities.
///
/// Backend-recognized aliases such as `Arm Stall` are not official.
bool isOfficialElixrMovementName(String name) =>
    officialElixrMovementNames.contains(name);

/// Stable Firestore identity for one official ELIXR catalog movement.
class OfficialElixrMovementIdentity {
  const OfficialElixrMovementIdentity({
    required this.catalogName,
    required this.movementId,
    required this.revisionId,
  });

  final String catalogName;
  final String movementId;
  final String revisionId;
}

const officialElixrMovementIdentities = <OfficialElixrMovementIdentity>[
  OfficialElixrMovementIdentity(
    catalogName: 'Normal Grip',
    movementId: 'official_normal_grip',
    revisionId: 'official_normal_grip_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: "Bartender's Grip",
    movementId: 'official_bartenders_grip',
    revisionId: 'official_bartenders_grip_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Reverse Grip',
    movementId: 'official_reverse_grip',
    revisionId: 'official_reverse_grip_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Claw Grip',
    movementId: 'official_claw_grip',
    revisionId: 'official_claw_grip_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Hand Stall',
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'One Finger Stall',
    movementId: 'official_one_finger_stall',
    revisionId: 'official_one_finger_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Forearm Stall',
    movementId: 'official_forearm_stall',
    revisionId: 'official_forearm_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Elbow Stall',
    movementId: 'official_elbow_stall',
    revisionId: 'official_elbow_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Reverse Forearm Stall',
    movementId: 'official_reverse_forearm_stall',
    revisionId: 'official_reverse_forearm_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Shoulder Stall',
    movementId: 'official_shoulder_stall',
    revisionId: 'official_shoulder_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Double Hand Stall',
    movementId: 'official_double_hand_stall',
    revisionId: 'official_double_hand_stall_v1',
  ),
  OfficialElixrMovementIdentity(
    catalogName: 'Bottle in a tin',
    movementId: 'official_bottle_in_a_tin',
    revisionId: 'official_bottle_in_a_tin_v1',
  ),
];

final Map<String, OfficialElixrMovementIdentity>
_officialElixrIdentityByCatalogName = {
  for (final identity in officialElixrMovementIdentities)
    identity.catalogName: identity,
};

final Map<String, OfficialElixrMovementIdentity>
_officialElixrIdentityByMovementId = {
  for (final identity in officialElixrMovementIdentities)
    identity.movementId: identity,
};

/// Explicit catalog mapping. Does not slug arbitrary movement names.
OfficialElixrMovementIdentity? officialElixrIdentityForName(String name) {
  return _officialElixrIdentityByCatalogName[name];
}

OfficialElixrMovementIdentity? officialElixrIdentityForMovementId(
  String movementId,
) {
  return _officialElixrIdentityByMovementId[movementId];
}
