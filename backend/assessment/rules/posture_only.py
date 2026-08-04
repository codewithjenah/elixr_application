from typing import Optional

from config import MOVEMENT_CONFIG
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_hands_visible,
    is_open_palm,
    usable_hands_with_palms,
)
from vision.types import HandsResult, Point2D, PoseLandmarks


def _movement_requires_hands(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    if cfg is None:
        return True
    return bool(cfg.get("requires_hands", True))


_POSTURE_SUCCESS: dict[str, str] = {
    "Normal Grip": "Hand looks ready for normal grip. Enable bottle detection for scoring.",
    "Bartender's Grip": "Hand looks ready for bartender's grip. Enable bottle detection for scoring.",
    "Reverse Grip": "Hand looks ready for reverse grip. Enable bottle detection for scoring.",
    "Claw Grip": (
        "Hand looks ready for a claw grip. "
        "Enable bottle detection for complete scoring."
    ),
    "Hand Stall": "Hand looks steady. Enable bottle detection for stall scoring.",
    "One Finger Stall": (
        "Index finger looks ready for a one finger stall. "
        "Enable bottle detection for complete scoring."
    ),
    "Forearm Stall": "Forearm looks steady. Enable bottle detection for stall scoring.",
    "Elbow Stall": "Elbow looks steady. Enable bottle detection for stall scoring.",
    "Reverse Forearm Stall": (
        "Arm looks ready for a reverse forearm stall. "
        "Enable bottle detection for complete scoring."
    ),
    # Legacy movement names for historical sessions and backward compatibility.
    "Arm Stall": "Forearm looks steady. Enable bottle detection for stall scoring.",
    "Upper Forearm Stall": (
        "Arm looks ready for a reverse forearm stall. "
        "Enable bottle detection for complete scoring."
    ),
    "Shoulder Stall": (
        "Shoulders look ready for a shoulder stall. "
        "Enable bottle detection for complete scoring."
    ),
    "Double Hand Stall": (
        "Both hands look ready for a double hand stall. "
        "Enable bottle detection for complete scoring."
    ),
    "Bottle in a tin": (
        "Hand looks ready to support the shaker. "
        "Enable prop detection for complete scoring."
    ),
}


def evaluate_posture_only(
    movement: str,
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    *,
    prop_label: str = "Bottle",
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    if movement == "Double Hand Stall":
        usable = usable_hands_with_palms(hands)
        if len(usable) < 2:
            return (
                RuleResult(
                    feedback="Keep both hands fully visible.",
                    feedback_type="warning",
                    posture_status="unknown",
                ),
                prev_hip_center,
                None,
            )
        ordered = sorted(usable, key=lambda item: item[1].x)
        left_hand, _ = ordered[0]
        right_hand, _ = ordered[-1]
        if not is_open_palm(left_hand) or not is_open_palm(right_hand):
            return (
                RuleResult(
                    feedback="Open both palms and extend your fingers.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                None,
            )
        return (
            RuleResult(
                feedback=_POSTURE_SUCCESS["Double Hand Stall"],
                feedback_type="positive",
                posture_status="stable",
            ),
            prev_hip_center,
            None,
        )

    if _movement_requires_hands(movement):
        hands_check = check_hands_visible(hands)
        if hands_check:
            return hands_check, prev_hip_center, None

    if prop_label.strip().lower() == "bottle":
        message = _POSTURE_SUCCESS.get(
            movement,
            "Hand looks ready. Enable bottle detection for full movement scoring.",
        )
    elif movement in {
        "Hand Stall",
        "One Finger Stall",
        "Forearm Stall",
        "Arm Stall",
        "Elbow Stall",
    }:
        message = (
            "Posture looks ready. Enable prop detection for stall scoring."
        )
    else:
        message = "Posture looks ready. Enable prop detection for full scoring."
    return (
        RuleResult(feedback=message, feedback_type="positive", posture_status="stable"),
        prev_hip_center,
        None,
    )
