from typing import Optional

from config import MOVEMENT_CONFIG
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import check_hands_visible, visible_palm_centers
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
    "Hand Stall": "Hand looks steady. Enable bottle detection for stall scoring.",
    "Arm Stall": "Arm looks steady. Enable bottle detection for stall scoring.",
    "Elbow Stall": "Elbow looks steady. Enable bottle detection for stall scoring.",
    "Upper Forearm Stall": (
        "Arm looks ready for an upper-forearm stall. "
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
}


def evaluate_posture_only(
    movement: str,
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    if movement == "Double Hand Stall":
        palms = visible_palm_centers(hands)
        if len(palms) < 2:
            return (
                RuleResult(
                    feedback="Keep both hands visible for the double hand stall.",
                    feedback_type="warning",
                    posture_status="unknown",
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

    message = _POSTURE_SUCCESS.get(
        movement,
        "Hand looks ready. Enable bottle detection for full movement scoring.",
    )
    return (
        RuleResult(feedback=message, feedback_type="positive", posture_status="stable"),
        prev_hip_center,
        None,
    )
