from typing import Callable, Optional

from config import MOVEMENT_CONFIG
from assessment.rules import (
    arm_stall,
    bartenders_grip,
    claw_grip,
    coming_soon,
    double_hand_stall,
    elbow_stall,
    hand_stall,
    normal_grip,
    one_finger_stall,
    reverse_grip,
    shoulder_stall,
    upper_forearm_stall,
)
from assessment.rules.base import RuleResult
from assessment.rules.posture_only import evaluate_posture_only
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks

EvaluateFn = Callable[..., tuple[RuleResult, Optional[Point2D], Optional[dict]]]

_RULES: dict[str, EvaluateFn] = {
    "Normal Grip": normal_grip.evaluate,
    "Bartender's Grip": bartenders_grip.evaluate,
    "Reverse Grip": reverse_grip.evaluate,
    "Claw Grip": claw_grip.evaluate,
    "Hand Stall": hand_stall.evaluate,
    "One Finger Stall": one_finger_stall.evaluate,
    "Forearm Stall": arm_stall.evaluate,
    "Elbow Stall": elbow_stall.evaluate,
    "Reverse Forearm Stall": upper_forearm_stall.evaluate,
    # Legacy movement names for historical sessions and backward compatibility.
    "Arm Stall": arm_stall.evaluate,
    "Upper Forearm Stall": upper_forearm_stall.evaluate,
    "Shoulder Stall": shoulder_stall.evaluate,
    "Double Hand Stall": double_hand_stall.evaluate,
}
_PROP_AWARE_MOVEMENTS = {
    "Hand Stall",
    "One Finger Stall",
    "Forearm Stall",
    "Elbow Stall",
    "Arm Stall",
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


def movement_is_internal(movement: str) -> bool:
    """True for registered modes that must not appear in the user catalog."""
    cfg = MOVEMENT_CONFIG.get(movement)
    return cfg is not None and bool(cfg.get("internal", False))


def movement_is_prop_detection_only(movement: str) -> bool:
    """True when the session should run camera + prop detect without scoring."""
    cfg = MOVEMENT_CONFIG.get(movement)
    return cfg is not None and bool(cfg.get("prop_detection_only", False))


def movement_is_easy(movement: str) -> bool:
    cfg = MOVEMENT_CONFIG.get(movement)
    return cfg is not None and cfg.get("difficulty") == "Easy"


def is_known_movement(movement: str) -> bool:
    """Return True when ``movement`` is registered in MOVEMENT_CONFIG."""
    return movement in MOVEMENT_CONFIG


def validate_movement_name(movement: str) -> str | None:
    """Validate a movement name against the public registry.

    Returns an error code, or ``None`` when valid. Unknown names must not be
    silently routed to the ``coming_soon`` evaluator for protocol v1 commands.
    """
    if not isinstance(movement, str) or not movement.strip():
        return "invalid_movement"
    if movement not in MOVEMENT_CONFIG:
        return "invalid_movement"
    return None


def configured_difficulty(movement: str) -> str | None:
    """Return the authoritative difficulty for a known movement, else None."""
    cfg = MOVEMENT_CONFIG.get(movement)
    if cfg is None:
        return None
    difficulty = cfg.get("difficulty")
    return str(difficulty) if difficulty is not None else None


def validate_movement_difficulty(
    movement: str,
    difficulty: str,
) -> tuple[str | None, str | None]:
    """Validate movement + difficulty for protocol v1.

    Returns ``(authoritative_difficulty, error_code)``.
    On success ``error_code`` is ``None`` and difficulty is the configured value.
    """
    movement_error = validate_movement_name(movement)
    if movement_error is not None:
        return None, movement_error

    expected = configured_difficulty(movement)
    if expected is None:
        return None, "invalid_movement"
    if difficulty != expected:
        return expected, "difficulty_mismatch"
    return expected, None


def evaluate_movement(
    movement: str,
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    bottle_detection_enabled: bool = True,
    bottles: Optional[list[BottleDetection]] = None,
    prop_type: str = "bottle",
    prop_label: str | None = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    resolved_prop_label = prop_label or (
        "Cocktail Shaker" if prop_type == "shaker" else "Bottle"
    )

    if not bottle_detection_enabled and bottle is None:
        return evaluate_posture_only(
            movement,
            pose,
            hands,
            prev_hip_center,
            prop_label=resolved_prop_label,
        )

    # Double Hand Stall scores two bottles; keep other movements on primary bottle.
    if movement == "Double Hand Stall":
        bottle_list = (
            list(bottles)
            if bottles is not None
            else ([bottle] if bottle is not None else [])
        )
        return double_hand_stall.evaluate(
            bottle,
            pose,
            hands,
            prev_hip_center,
            movement_state,
            bottles=bottle_list,
        )

    if movement in _RULES:
        evaluate = _RULES[movement]
        if movement in _PROP_AWARE_MOVEMENTS:
            return evaluate(
                bottle,
                pose,
                hands,
                prev_hip_center,
                movement_state,
                prop_label=resolved_prop_label,
            )
        return evaluate(bottle, pose, hands, prev_hip_center, movement_state)
    return coming_soon.evaluate(bottle, pose, hands, prev_hip_center, movement_state)
