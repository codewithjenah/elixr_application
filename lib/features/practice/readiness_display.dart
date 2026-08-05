/// Maps backend readiness check codes to human-readable UI strings.
///
/// Unknown codes fall back to [backendMessage] for both title and instruction.
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
/// Returns a hard-coded mapping for every known code. For unknown codes,
/// [backendMessage] is used as both [ReadinessDisplayInfo.title] and
/// [ReadinessDisplayInfo.instruction] (or a generic fallback when null).
ReadinessDisplayInfo resolveReadinessDisplay(
  String code, {
  String? backendMessage,
}) {
  return switch (code) {
    'camera_frame' => const ReadinessDisplayInfo(
      title: 'Camera Frame',
      instruction: 'Make sure your camera is on and facing you.',
    ),
    'prop_detected' => const ReadinessDisplayInfo(
      title: 'Prop Detected',
      instruction: 'Hold your prop clearly in front of the camera.',
    ),
    'bottle_detected' => const ReadinessDisplayInfo(
      title: 'Bottle Detected',
      instruction: 'Ensure the bottle is visible and upright.',
    ),
    'shaker_detected' => const ReadinessDisplayInfo(
      title: 'Shaker Detected',
      instruction: 'Ensure the shaker is clearly visible to the camera.',
    ),
    'prop_count_two' => const ReadinessDisplayInfo(
      title: 'Two Props Visible',
      instruction: 'Hold both props so the camera can see them at once.',
    ),
    'grip_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Grip Landmarks',
      instruction:
          'Show your gripping hand clearly — fingers facing the camera.',
    ),
    'palm_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Palm Landmarks',
      instruction:
          'Open your palm toward the camera so all landmarks are visible.',
    ),
    'index_landmarks_visible' => const ReadinessDisplayInfo(
      title: 'Index Finger Visible',
      instruction: 'Extend your index finger toward the camera.',
    ),
    'two_hands_visible' => const ReadinessDisplayInfo(
      title: 'Both Hands Visible',
      instruction: 'Keep both hands in the camera frame.',
    ),
    'supporting_hand_visible' => const ReadinessDisplayInfo(
      title: 'Supporting Hand',
      instruction: 'Make sure your non-dominant hand is visible.',
    ),
    'pose_forearm_or_hand' => const ReadinessDisplayInfo(
      title: 'Forearm or Hand Pose',
      instruction: 'Position your forearm or hand so the camera can track it.',
    ),
    'pose_upper_forearm' => const ReadinessDisplayInfo(
      title: 'Upper Forearm Pose',
      instruction:
          'Raise your forearm until the upper section is clearly visible.',
    ),
    'pose_shoulder' => const ReadinessDisplayInfo(
      title: 'Shoulder Visible',
      instruction: 'Step back or tilt the camera so your shoulder is in frame.',
    ),
    _ => ReadinessDisplayInfo(
      title: backendMessage ?? code,
      instruction: backendMessage ?? 'Follow the on-screen guidance.',
    ),
  };
}
