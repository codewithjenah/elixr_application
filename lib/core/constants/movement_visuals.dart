/// Shared movement-name → emoji mapping for History, Movements, and Dashboard.
///
/// Includes legacy movement names that may still appear on historical sessions.
abstract final class MovementVisuals {
  static const Map<String, String> emojis = {
    'Normal Grip': '🍾',
    "Bartender's Grip": '🤏',
    'Reverse Grip': '🖐️',
    'Hand Stall': '✋',
    'Arm Stall': '💪',
    'Elbow Stall': '🦾',
    'Upper Forearm Stall': '🆙',
    'Shoulder Stall': '🧍',
    'Double Hand Stall': '🙌',
    // Legacy movements kept only for historical session display.
    'Hand-to-Hand Bottle Exchange': '🔄',
    'Tap': '🥂',
    'Basket': '🧺',
  };

  static String emojiFor(String movementName) => emojis[movementName] ?? '🍾';
}
