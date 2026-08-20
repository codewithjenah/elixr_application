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
