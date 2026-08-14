/// Shared movement-name → image asset mapping for movement UI.
///
/// Historical movement names without an entry intentionally use the generic
/// fallback supplied by `MovementImage`.
abstract final class MovementVisuals {
  static const Map<String, String> assetPaths = {
    'Normal Grip': 'assets/movements_icon/normal_grip.png',
    "Bartender's Grip": 'assets/movements_icon/bartender_grip.png',
    'Reverse Grip': 'assets/movements_icon/reverse_grip.png',
    'Claw Grip': 'assets/movements_icon/claw_grip.png',
    'Hand Stall': 'assets/movements_icon/hand_stall.png',
    'One Finger Stall': 'assets/movements_icon/one_finger_stall.png',
    'Forearm Stall': 'assets/movements_icon/forearm_stall.png',
    'Elbow Stall': 'assets/movements_icon/elbow_stall.png',
    'Reverse Forearm Stall': 'assets/movements_icon/reverse_forearm_stall.png',
    'Shoulder Stall': 'assets/movements_icon/shoulder_stall.png',
    'Double Hand Stall': 'assets/movements_icon/double_hand_stall.png',
    'Bottle in a tin': 'assets/movements_icon/bottle_in_a_tin.png',
  };

  static String? assetPathFor(String movementName) => assetPaths[movementName];
}
