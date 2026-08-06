/// Observability-only display copy for guided-practice calibration checks.
///
/// Titles and instructions must describe visibility conditions the backend
/// actually evaluates — never technique (upright bottle, open palm, etc.).
library;

/// Resolved display strings for a single readiness check item.
class ReadinessDisplayInfo {
  const ReadinessDisplayInfo({required this.title, required this.instruction});

  /// Short label shown as the checklist item title.
  final String title;

  /// One-line guidance shown as the subtitle / body under the title.
  final String instruction;
}

/// Resolve display strings for a readiness check [code].
///
/// Known codes use hard-coded observability copy. Unknown codes use a safe
/// fallback that does not repeat the same [backendMessage] as both title and
/// instruction.
ReadinessDisplayInfo resolveReadinessDisplay(
  String code, {
  String? backendMessage,
}) {
  final known = switch (code) {
    'camera_frame' => const ReadinessDisplayInfo(
      title: 'Camera',
      instruction: 'Live camera frame received.',
    ),
    'prop_detected' => const ReadinessDisplayInfo(
      title: 'Selected Prop',
      instruction: 'Keep the selected prop fully inside the frame.',
    ),
    'bottle_detected' => const ReadinessDisplayInfo(
      title: 'Bottle',
      instruction: 'Keep the bottle fully inside the frame.',
    ),
    'shaker_detected' => const ReadinessDisplayInfo(
      title: 'Cocktail Shaker',
      instruction: 'Keep the cocktail shaker fully inside the frame.',
    ),
    'prop_count_two' => const ReadinessDisplayInfo(
      title: 'Two Bottles',
      instruction: 'Keep two bottles fully inside the frame.',
    ),
    'grip_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Grip Hand',
      instruction: 'Keep the full gripping hand visible.',
    ),
    'palm_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Hand Center',
      instruction: 'Keep the center of your hand visible.',
    ),
    'index_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Index Finger',
      instruction: 'Keep the index-finger tracking points visible.',
    ),
    'two_hands_visible' => const ReadinessDisplayInfo(
      title: 'Both Hands',
      instruction: 'Keep both hands fully inside the frame.',
    ),
    'supporting_hand_visible' => const ReadinessDisplayInfo(
      title: 'Supporting Hand',
      instruction: 'Keep a supporting hand visible in the frame.',
    ),
    'pose_forearm_or_hand' => const ReadinessDisplayInfo(
      title: 'Arm or Hand',
      instruction: 'Keep a forearm or hand tracking points visible.',
    ),
    'pose_upper_forearm' => const ReadinessDisplayInfo(
      title: 'Upper Arm',
      instruction: 'Keep upper-arm pose landmarks visible in the frame.',
    ),
    'pose_shoulder' => const ReadinessDisplayInfo(
      title: 'Shoulder',
      instruction: 'Keep a shoulder landmark visible in the frame.',
    ),
    'upper_body_visible' => const ReadinessDisplayInfo(
      title: 'Upper Body',
      instruction: 'Keep both shoulders and at least one complete arm visible.',
    ),
    _ => null,
  };
  if (known != null) return known;

  final trimmed = backendMessage?.trim();
  final hasMessage = trimmed != null && trimmed.isNotEmpty;
  final title = _humanizeCode(code);
  if (!hasMessage || trimmed == title) {
    return ReadinessDisplayInfo(
      title: title,
      instruction: 'Follow the on-screen guidance.',
    );
  }
  return ReadinessDisplayInfo(title: title, instruction: trimmed);
}

String _humanizeCode(String code) {
  if (code.isEmpty) return 'Setup check';
  final words = code.split(RegExp(r'[_\s]+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return 'Setup check';
  return words
      .map(
        (w) =>
            '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}',
      )
      .join(' ');
}
