from typing import Callable, Optional

from config import (
    GRIP_ANGLE_MAX,
    GRIP_ANGLE_MIN,
    MOVEMENT_CONFIG,
    REVERSE_GRIP_ANGLE_MAX,
    REVERSE_GRIP_ANGLE_MIN,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_grip_angle,
    check_shoulder_alignment,
    check_stance_stability,
    dominant_elbow,
    dominant_wrist,
    forearm_midpoint,
)
from vision.types import HandsResult, Point2D, PoseLandmarks


def _movement_requires_hands(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    if cfg is None:
        return True
    return bool(cfg.get("requires_hands", True))


def _check_hands_visible(hands: Optional[HandsResult]) -> Optional[RuleResult]:
    if hands is None or not hands.hands:
        return RuleResult(
            feedback="Hand not detected. Keep your hand in frame.",
            feedback_type="warning",
            posture_status="unknown",
        )
    return None


def _check_pose_point_visible(
    pose: Optional[PoseLandmarks],
    get_point: Callable[[PoseLandmarks], Optional[Point2D]],
    *,
    warning_message: str,
) -> Optional[RuleResult]:
    if pose is None:
        return RuleResult(
            feedback="Body not detected. Step back so your upper body is visible.",
            feedback_type="warning",
            posture_status="unknown",
        )
    if get_point(pose) is None:
        return RuleResult(
            feedback=warning_message,
            feedback_type="warning",
            posture_status="unknown",
        )
    return None


def _good_posture(message: str) -> RuleResult:
    return RuleResult(
        feedback=message,
        feedback_type="positive",
        posture_status="stable",
    )


_POSTURE_SUCCESS: dict[str, str] = {
    "Normal Grip": "Solid posture for normal grip practice.",
    "Bartender's Grip": "Good posture for bartender's grip practice.",
    "Reverse Grip": "Correct underhand posture for reverse grip.",
    "Hand Stall": "Hand position looks steady. Enable bottle detection for stall scoring.",
    "Arm Stall": "Arm position looks steady. Enable bottle detection for stall scoring.",
    "Elbow Stall": "Elbow position looks steady. Enable bottle detection for stall scoring.",
    "Clip": "Stable posture for clip practice.",
    "Tap": "Stable posture for tap practice.",
    "Basket": "Stable posture for basket practice.",
    "Switching": "Stable posture for switching practice.",
    "Front Flip": "Stable posture for front flip practice.",
    "Side Flip": "Stable posture for side flip practice.",
    "Quick Chest Pass": "Stable posture for chest pass practice.",
    "Staggered Switch": "Stable posture for staggered switch practice.",
    "Elbow Tap": "Stable posture for elbow tap practice.",
}


def evaluate_posture_only(
    movement: str,
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    shoulder_check = check_shoulder_alignment(pose)
    if shoulder_check:
        return shoulder_check, prev_hip_center, None

    stance_check, hip_center = check_stance_stability(pose, prev_hip_center)

    if _movement_requires_hands(movement):
        hands_check = _check_hands_visible(hands)
        if hands_check:
            return hands_check, hip_center, None

    if movement == "Normal Grip":
        grip = check_grip_angle(
            pose,
            min_angle=GRIP_ANGLE_MIN,
            max_angle=GRIP_ANGLE_MAX,
            success_message=_POSTURE_SUCCESS["Normal Grip"],
            fail_message="Adjust wrist angle for a standard overhand grip.",
        )
        if grip.feedback_type != "positive":
            return grip, hip_center, None
    elif movement == "Reverse Grip":
        grip = check_grip_angle(
            pose,
            min_angle=REVERSE_GRIP_ANGLE_MIN,
            max_angle=REVERSE_GRIP_ANGLE_MAX,
            success_message=_POSTURE_SUCCESS["Reverse Grip"],
            fail_message="Rotate wrist for an underhand reverse grip.",
        )
        if grip.feedback_type != "positive":
            return grip, hip_center, None
    elif movement == "Hand Stall":
        limb_check = _check_pose_point_visible(
            pose,
            dominant_wrist,
            warning_message="Wrist not visible. Show your hand to the camera.",
        )
        if limb_check:
            return limb_check, hip_center, None
    elif movement == "Arm Stall":
        limb_check = _check_pose_point_visible(
            pose,
            forearm_midpoint,
            warning_message="Forearm not visible. Extend your arm into frame.",
        )
        if limb_check:
            return limb_check, hip_center, None
    elif movement == "Elbow Stall":
        limb_check = _check_pose_point_visible(
            pose,
            dominant_elbow,
            warning_message="Elbow not visible. Bend your arm into frame.",
        )
        if limb_check:
            return limb_check, hip_center, None

    if stance_check:
        return stance_check, hip_center, None

    message = _POSTURE_SUCCESS.get(
        movement,
        "Good posture. Enable bottle detection for full movement scoring.",
    )
    return _good_posture(message), hip_center, None
