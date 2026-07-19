from typing import Callable, Optional

from config import MOVEMENT_CONFIG
from assessment.rules import (
    arm_stall,
    bartenders_grip,
    basket,
    coming_soon,
    elbow_stall,
    hand_stall,
    normal_grip,
    reverse_grip,
    tap,
)
from assessment.rules.base import RuleResult
from assessment.rules.posture_only import evaluate_posture_only
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks

EvaluateFn = Callable[
    [
        Optional[BottleDetection],
        Optional[PoseLandmarks],
        Optional[HandsResult],
        Optional[Point2D],
        Optional[dict],
    ],
    tuple[RuleResult, Optional[Point2D], Optional[dict]],
]

_RULES: dict[str, EvaluateFn] = {
    "Normal Grip": normal_grip.evaluate,
    "Bartender's Grip": bartenders_grip.evaluate,
    "Reverse Grip": reverse_grip.evaluate,
    "Hand Stall": hand_stall.evaluate,
    "Arm Stall": arm_stall.evaluate,
    "Elbow Stall": elbow_stall.evaluate,
    "Tap": tap.evaluate,
    "Basket": basket.evaluate,
}


def movement_requires_hands(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    if cfg is None:
        return True
    return bool(cfg.get("requires_hands", True))


def movement_requires_pose(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    if cfg is None:
        return False
    return bool(cfg.get("requires_pose", False))


def movement_is_easy(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    return cfg is not None and cfg.get("difficulty") == "Easy"


def evaluate_movement(
    movement: str,
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    bottle_detection_enabled: bool = True,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    if not bottle_detection_enabled and bottle is None:
        return evaluate_posture_only(movement, pose, hands, prev_hip_center)

    if movement in _RULES:
        return _RULES[movement](bottle, pose, hands, prev_hip_center, movement_state)
    return coming_soon.evaluate(bottle, pose, hands, prev_hip_center, movement_state)
