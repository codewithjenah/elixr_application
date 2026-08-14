/// Movement names that may be attached to a coaching recommendation.
///
/// This intentionally contains only the cross-client identity, not the
/// Windows catalogue's hardware and presentation metadata.
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

bool isRecognizedCoachingMovement(String value) =>
    coachingMovementNames.contains(value);
