"""Central registry of stable feedback codes and categories.

Movement rules must import [FeedbackCode] values. Categories are derived only
via [category_for] — rules must not hand-pair code/category strings.

Rubric criterion membership is derived via [criterion_for]. Visibility and
environment codes map to None so readiness/camera failures never reduce the
trainee's rubric score.
"""

from __future__ import annotations

from enum import Enum
from typing import Optional

from assessment.rubric import RubricCriterion
from assessment.rules.base import CriterionCheck


class FeedbackCategory(str, Enum):
    TECHNIQUE = "technique"
    VISIBILITY = "visibility"
    ENVIRONMENT = "environment"
    SYSTEM = "system"


class FeedbackCode(str, Enum):
    """Stable technique / visibility / environment identity for coaching.

    Phase A (Hand Stall + shared) values are preserved. Phase B adds codes for
    every enabled scored-practice movement. Prefer prop-neutral shared codes
    when the semantic meaning is identical across Bottle and Cocktail Shaker.
    """

    # --- Shared visibility / environment ---
    PROP_NOT_DETECTED = "prop_not_detected"
    HAND_NOT_VISIBLE = "hand_not_visible"
    HAND_NOT_FULLY_VISIBLE = "hand_not_fully_visible"
    INDEX_FINGER_NOT_VISIBLE = "index_finger_not_visible"
    THENAR_NOT_VISIBLE = "thenar_not_visible"
    POSE_ARM_NOT_VISIBLE = "pose_arm_not_visible"
    SHOULDERS_NOT_VISIBLE = "shoulders_not_visible"
    BOTH_BOTTLES_NOT_VISIBLE = "both_bottles_not_visible"
    NEED_TWO_BOTTLES = "need_two_bottles"
    BOTH_HANDS_NOT_VISIBLE = "both_hands_not_visible"
    BOTH_PROPS_NOT_DETECTED = "both_props_not_detected"
    BOTTLE_NOT_DETECTED = "bottle_not_detected"
    SHAKER_NOT_DETECTED = "shaker_not_detected"
    HAND_NOT_SUPPORTING_SHAKER = "hand_not_supporting_shaker"

    # --- Shared technique ---
    PALM_NOT_OPEN = "palm_not_open"
    BOTH_PALMS_NOT_OPEN = "both_palms_not_open"
    PROP_NOT_UPRIGHT = "prop_not_upright"
    PROP_BASE_NOT_ON_PALM = "prop_base_not_on_palm"
    PROP_NOT_ABOVE_PALM = "prop_not_above_palm"
    PROP_NOT_STEADY = "prop_not_steady"
    PROP_NOT_POSITIONED_ON_TARGET = "prop_not_positioned_on_target"
    HAND_BOTTLE_TOO_FAR = "hand_bottle_too_far"
    PINCH_FINGERS_NOT_VISIBLE = "pinch_fingers_not_visible"
    PINCH_NOT_CLOSED = "pinch_not_closed"
    PROP_NOT_IN_PINCH = "prop_not_in_pinch"

    # --- Normal Grip ---
    HAND_NOT_AT_NECK = "hand_not_at_neck"
    OVERHAND_GRIP_REQUIRED = "overhand_grip_required"
    INSUFFICIENT_NECK_FINGER_WRAP = "insufficient_neck_finger_wrap"
    NORMAL_GRIP_NOT_SECURE = "normal_grip_not_secure"
    NORMAL_NOT_TOP_DOWN = "normal_not_top_down"
    NORMAL_THUMB_PINKY_ORIENTATION = "normal_thumb_pinky_orientation"
    NORMAL_GRIP_LOCKED = "normal_grip_locked"

    # --- Bartender's Grip ---
    BARTENDER_GRIP_POSITION = "bartender_grip_position"
    BARTENDER_PINCH_REQUIRED = "bartender_pinch_required"
    BARTENDER_HAND_ORIENTATION = "bartender_hand_orientation"
    BARTENDER_PALM_TOO_LOW = "bartender_palm_too_low"
    BARTENDER_INDEX_EXTENSION = "bartender_index_extension"
    BARTENDER_WRAP_FINGERS = "bartender_wrap_fingers"
    BARTENDER_GRIP_LOCKED = "bartender_grip_locked"

    # --- Reverse Grip ---
    UNDERHAND_GRIP_REQUIRED = "underhand_grip_required"
    REVERSE_PINKY_THUMB_ORIENTATION = "reverse_pinky_thumb_orientation"
    REVERSE_GRIP_LOCKED = "reverse_grip_locked"

    # --- Claw Grip ---
    CLAW_WRIST_ABOVE_NECK = "claw_wrist_above_neck"
    CLAW_REACH_FROM_ABOVE = "claw_reach_from_above"
    CLAW_FINGERS_NOT_CURLED = "claw_fingers_not_curled"
    CLAW_NOT_PINCH_GRIP = "claw_not_pinch_grip"
    CLAW_NOT_SIDE_OVERHAND = "claw_not_side_overhand"
    CLAW_NOT_REVERSE_HOLD = "claw_not_reverse_hold"
    CLAW_PALM_OVER_MOUTH = "claw_palm_over_mouth"
    CLAW_THUMB_SUPPORT = "claw_thumb_support"
    CLAW_MORE_FINGERS_CURLED = "claw_more_fingers_curled"
    CLAW_GRIP_LOCKED = "claw_grip_locked"

    # --- Hand Stall (Phase A) ---
    HAND_STALL_LOCKED = "hand_stall_locked"

    # --- One Finger Stall ---
    INDEX_FINGER_NOT_EXTENDED = "index_finger_not_extended"
    INDEX_FINGER_NOT_HORIZONTAL = "index_finger_not_horizontal"
    OTHER_FINGERS_NOT_CURLED = "other_fingers_not_curled"
    PROP_BASE_NOT_ON_INDEX = "prop_base_not_on_index"
    PROP_NOT_CENTERED_ON_INDEX = "prop_not_centered_on_index"
    PROP_BASE_NOT_ON_THENAR = "prop_base_not_on_thenar"
    PROP_NOT_CENTERED_ON_THENAR = "prop_not_centered_on_thenar"
    ONE_FINGER_STALL_LOCKED = "one_finger_stall_locked"

    # --- Forearm / Elbow stalls ---
    FOREARM_STALL_LOCKED = "forearm_stall_locked"
    ELBOW_STALL_LOCKED = "elbow_stall_locked"

    # --- Reverse Forearm Stall ---
    PROP_TOO_NEAR_ELBOW = "prop_too_near_elbow"
    PROP_TOO_NEAR_MID_FOREARM = "prop_too_near_mid_forearm"
    PROP_NOT_ON_REVERSE_FOREARM = "prop_not_on_reverse_forearm"
    REVERSE_FOREARM_STALL_LOCKED = "reverse_forearm_stall_locked"

    # --- Shoulder Stall ---
    PROP_BELOW_SHOULDER = "prop_below_shoulder"
    PROP_NOT_ON_SHOULDER = "prop_not_on_shoulder"
    SHOULDER_STALL_LOCKED = "shoulder_stall_locked"

    # --- Double Hand Stall ---
    BOTH_PALMS_HEIGHT_MISMATCH = "both_palms_height_mismatch"
    BOTTLES_NOT_ONE_PER_PALM = "bottles_not_one_per_palm"
    BOTH_PROPS_NOT_STEADY = "both_props_not_steady"
    DOUBLE_HAND_STALL_LOCKED = "double_hand_stall_locked"

    # --- Bottle in a tin ---
    SHAKER_NOT_HORIZONTAL = "shaker_not_horizontal"
    BOTTLE_NOT_CENTERED_ON_SHAKER = "bottle_not_centered_on_shaker"
    BOTTLE_NOT_ON_SHAKER = "bottle_not_on_shaker"
    BOTTLE_IN_TIN_LOCKED = "bottle_in_tin_locked"


# Single source of truth: every registered code maps to exactly one category.
_CODE_CATEGORIES: dict[FeedbackCode, FeedbackCategory] = {
    # Shared visibility / environment
    FeedbackCode.PROP_NOT_DETECTED: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.HAND_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.HAND_NOT_FULLY_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.INDEX_FINGER_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.THENAR_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.POSE_ARM_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.SHOULDERS_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.NEED_TWO_BOTTLES: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.BOTH_HANDS_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.BOTH_PROPS_NOT_DETECTED: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.BOTTLE_NOT_DETECTED: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.SHAKER_NOT_DETECTED: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.HAND_NOT_SUPPORTING_SHAKER: FeedbackCategory.TECHNIQUE,
    # Shared technique
    FeedbackCode.PALM_NOT_OPEN: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTH_PALMS_NOT_OPEN: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_UPRIGHT: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_BASE_NOT_ON_PALM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_ABOVE_PALM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_STEADY: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET: FeedbackCategory.TECHNIQUE,
    FeedbackCode.HAND_BOTTLE_TOO_FAR: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PINCH_FINGERS_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.PINCH_NOT_CLOSED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_IN_PINCH: FeedbackCategory.TECHNIQUE,
    # Normal Grip
    FeedbackCode.HAND_NOT_AT_NECK: FeedbackCategory.TECHNIQUE,
    FeedbackCode.OVERHAND_GRIP_REQUIRED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP: FeedbackCategory.TECHNIQUE,
    FeedbackCode.NORMAL_GRIP_NOT_SECURE: FeedbackCategory.TECHNIQUE,
    FeedbackCode.NORMAL_NOT_TOP_DOWN: FeedbackCategory.TECHNIQUE,
    FeedbackCode.NORMAL_THUMB_PINKY_ORIENTATION: FeedbackCategory.TECHNIQUE,
    FeedbackCode.NORMAL_GRIP_LOCKED: FeedbackCategory.TECHNIQUE,
    # Bartender's Grip
    FeedbackCode.BARTENDER_GRIP_POSITION: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_PINCH_REQUIRED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_HAND_ORIENTATION: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_PALM_TOO_LOW: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_INDEX_EXTENSION: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_WRAP_FINGERS: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BARTENDER_GRIP_LOCKED: FeedbackCategory.TECHNIQUE,
    # Reverse Grip
    FeedbackCode.UNDERHAND_GRIP_REQUIRED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.REVERSE_PINKY_THUMB_ORIENTATION: FeedbackCategory.TECHNIQUE,
    FeedbackCode.REVERSE_GRIP_LOCKED: FeedbackCategory.TECHNIQUE,
    # Claw Grip
    FeedbackCode.CLAW_WRIST_ABOVE_NECK: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_REACH_FROM_ABOVE: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_FINGERS_NOT_CURLED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_NOT_PINCH_GRIP: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_NOT_SIDE_OVERHAND: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_NOT_REVERSE_HOLD: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_PALM_OVER_MOUTH: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_THUMB_SUPPORT: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_MORE_FINGERS_CURLED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.CLAW_GRIP_LOCKED: FeedbackCategory.TECHNIQUE,
    # Hand Stall
    FeedbackCode.HAND_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # One Finger Stall
    FeedbackCode.INDEX_FINGER_NOT_EXTENDED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.INDEX_FINGER_NOT_HORIZONTAL: FeedbackCategory.TECHNIQUE,
    FeedbackCode.OTHER_FINGERS_NOT_CURLED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_BASE_NOT_ON_INDEX: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_CENTERED_ON_INDEX: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_BASE_NOT_ON_THENAR: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_CENTERED_ON_THENAR: FeedbackCategory.TECHNIQUE,
    FeedbackCode.ONE_FINGER_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # Forearm / Elbow
    FeedbackCode.FOREARM_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    FeedbackCode.ELBOW_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # Reverse Forearm
    FeedbackCode.PROP_TOO_NEAR_ELBOW: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_TOO_NEAR_MID_FOREARM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.REVERSE_FOREARM_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # Shoulder
    FeedbackCode.PROP_BELOW_SHOULDER: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_ON_SHOULDER: FeedbackCategory.TECHNIQUE,
    FeedbackCode.SHOULDER_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # Double Hand Stall
    FeedbackCode.BOTH_PALMS_HEIGHT_MISMATCH: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTTLES_NOT_ONE_PER_PALM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTH_PROPS_NOT_STEADY: FeedbackCategory.TECHNIQUE,
    FeedbackCode.DOUBLE_HAND_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
    # Bottle in a tin
    FeedbackCode.SHAKER_NOT_HORIZONTAL: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTTLE_NOT_CENTERED_ON_SHAKER: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTTLE_NOT_ON_SHAKER: FeedbackCategory.TECHNIQUE,
    FeedbackCode.BOTTLE_IN_TIN_LOCKED: FeedbackCategory.TECHNIQUE,
}

# Rubric criterion membership. None = visibility/environment — never scored.
# Locked codes map to TECHNIQUE as a registry default; RubricTracker treats
# locked frames as satisfying technique + stability + prop_positioning.
_CODE_CRITERIA: dict[FeedbackCode, Optional[RubricCriterion]] = {
    # Visibility / environment — no rubric impact
    FeedbackCode.PROP_NOT_DETECTED: None,
    FeedbackCode.HAND_NOT_VISIBLE: None,
    FeedbackCode.HAND_NOT_FULLY_VISIBLE: None,
    FeedbackCode.INDEX_FINGER_NOT_VISIBLE: None,
    FeedbackCode.THENAR_NOT_VISIBLE: None,
    FeedbackCode.POSE_ARM_NOT_VISIBLE: None,
    FeedbackCode.SHOULDERS_NOT_VISIBLE: None,
    FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE: None,
    FeedbackCode.NEED_TWO_BOTTLES: None,
    FeedbackCode.BOTH_HANDS_NOT_VISIBLE: None,
    FeedbackCode.BOTH_PROPS_NOT_DETECTED: None,
    FeedbackCode.BOTTLE_NOT_DETECTED: None,
    FeedbackCode.SHAKER_NOT_DETECTED: None,
    FeedbackCode.PINCH_FINGERS_NOT_VISIBLE: None,
    # Technique
    FeedbackCode.PALM_NOT_OPEN: RubricCriterion.TECHNIQUE,
    FeedbackCode.BOTH_PALMS_NOT_OPEN: RubricCriterion.TECHNIQUE,
    FeedbackCode.PROP_NOT_UPRIGHT: RubricCriterion.TECHNIQUE,
    FeedbackCode.SHAKER_NOT_HORIZONTAL: RubricCriterion.TECHNIQUE,
    FeedbackCode.OVERHAND_GRIP_REQUIRED: RubricCriterion.TECHNIQUE,
    FeedbackCode.UNDERHAND_GRIP_REQUIRED: RubricCriterion.TECHNIQUE,
    FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP: RubricCriterion.TECHNIQUE,
    FeedbackCode.NORMAL_GRIP_NOT_SECURE: RubricCriterion.TECHNIQUE,
    FeedbackCode.NORMAL_THUMB_PINKY_ORIENTATION: RubricCriterion.TECHNIQUE,
    FeedbackCode.REVERSE_PINKY_THUMB_ORIENTATION: RubricCriterion.TECHNIQUE,
    FeedbackCode.BARTENDER_PINCH_REQUIRED: RubricCriterion.TECHNIQUE,
    FeedbackCode.BARTENDER_HAND_ORIENTATION: RubricCriterion.TECHNIQUE,
    FeedbackCode.BARTENDER_INDEX_EXTENSION: RubricCriterion.TECHNIQUE,
    FeedbackCode.BARTENDER_WRAP_FINGERS: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_FINGERS_NOT_CURLED: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_NOT_PINCH_GRIP: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_NOT_SIDE_OVERHAND: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_NOT_REVERSE_HOLD: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_THUMB_SUPPORT: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_MORE_FINGERS_CURLED: RubricCriterion.TECHNIQUE,
    FeedbackCode.INDEX_FINGER_NOT_EXTENDED: RubricCriterion.TECHNIQUE,
    FeedbackCode.INDEX_FINGER_NOT_HORIZONTAL: RubricCriterion.TECHNIQUE,
    FeedbackCode.OTHER_FINGERS_NOT_CURLED: RubricCriterion.TECHNIQUE,
    FeedbackCode.PINCH_NOT_CLOSED: RubricCriterion.TECHNIQUE,
    FeedbackCode.BOTH_PALMS_HEIGHT_MISMATCH: RubricCriterion.TECHNIQUE,
    # Prop positioning
    FeedbackCode.PROP_BASE_NOT_ON_PALM: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_ABOVE_PALM: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_BASE_NOT_ON_INDEX: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_CENTERED_ON_INDEX: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_BASE_NOT_ON_THENAR: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_CENTERED_ON_THENAR: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.HAND_BOTTLE_TOO_FAR: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.HAND_NOT_AT_NECK: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.NORMAL_NOT_TOP_DOWN: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.BARTENDER_GRIP_POSITION: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.BARTENDER_PALM_TOO_LOW: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.CLAW_WRIST_ABOVE_NECK: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.CLAW_REACH_FROM_ABOVE: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.CLAW_PALM_OVER_MOUTH: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_TOO_NEAR_ELBOW: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_TOO_NEAR_MID_FOREARM: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_BELOW_SHOULDER: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_ON_SHOULDER: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.BOTTLE_NOT_CENTERED_ON_SHAKER: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.BOTTLE_NOT_ON_SHAKER: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.HAND_NOT_SUPPORTING_SHAKER: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.BOTTLES_NOT_ONE_PER_PALM: RubricCriterion.PROP_POSITIONING,
    FeedbackCode.PROP_NOT_IN_PINCH: RubricCriterion.PROP_POSITIONING,
    # Stability
    FeedbackCode.PROP_NOT_STEADY: RubricCriterion.STABILITY,
    FeedbackCode.BOTH_PROPS_NOT_STEADY: RubricCriterion.STABILITY,
    # Locked success codes (registry default; tracker expands to three criteria)
    FeedbackCode.NORMAL_GRIP_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.BARTENDER_GRIP_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.REVERSE_GRIP_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.CLAW_GRIP_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.HAND_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.ONE_FINGER_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.FOREARM_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.ELBOW_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.REVERSE_FOREARM_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.SHOULDER_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.DOUBLE_HAND_STALL_LOCKED: RubricCriterion.TECHNIQUE,
    FeedbackCode.BOTTLE_IN_TIN_LOCKED: RubricCriterion.TECHNIQUE,
}

_LOCKED_CODES: frozenset[FeedbackCode] = frozenset(
    code for code in FeedbackCode if code.value.endswith("_locked")
)


def _validate_registry() -> None:
    values = [code.value for code in FeedbackCode]
    if len(values) != len(set(values)):
        raise RuntimeError("Duplicate FeedbackCode values in registry")
    for code in FeedbackCode:
        if code not in _CODE_CATEGORIES:
            raise RuntimeError(f"FeedbackCode {code!r} missing category mapping")
        if code not in _CODE_CRITERIA:
            raise RuntimeError(f"FeedbackCode {code!r} missing criterion mapping")
    if len(_CODE_CATEGORIES) != len(FeedbackCode):
        raise RuntimeError("Orphan category mappings for unknown FeedbackCode values")
    if len(_CODE_CRITERIA) != len(FeedbackCode):
        raise RuntimeError("Orphan criterion mappings for unknown FeedbackCode values")


_validate_registry()


def category_for(code: str | FeedbackCode | None) -> FeedbackCategory | None:
    """Return the registry category for a code, or None if missing/unknown."""
    if code is None:
        return None
    if isinstance(code, FeedbackCode):
        return _CODE_CATEGORIES.get(code)
    try:
        feedback_code = FeedbackCode(code)
    except ValueError:
        return None
    return _CODE_CATEGORIES.get(feedback_code)


def criterion_for(code: str | FeedbackCode | None) -> Optional[RubricCriterion]:
    """Return the rubric criterion for a code, or None if unscored/unknown."""
    if code is None:
        return None
    if isinstance(code, FeedbackCode):
        return _CODE_CRITERIA.get(code)
    try:
        feedback_code = FeedbackCode(code)
    except ValueError:
        return None
    return _CODE_CRITERIA.get(feedback_code)


def is_locked_code(code: str | FeedbackCode | None) -> bool:
    """True when the code is a movement-locked success identity."""
    if code is None:
        return False
    if isinstance(code, FeedbackCode):
        return code in _LOCKED_CODES
    try:
        return FeedbackCode(code) in _LOCKED_CODES
    except ValueError:
        return False


def is_registered(code: str | FeedbackCode | None) -> bool:
    if code is None:
        return False
    if isinstance(code, FeedbackCode):
        return code in _CODE_CATEGORIES
    try:
        return FeedbackCode(code) in _CODE_CATEGORIES
    except ValueError:
        return False


def registered_codes() -> tuple[FeedbackCode, ...]:
    return tuple(FeedbackCode)


def evaluable_criterion_results(
    *,
    technique_fail: str | None = None,
    positioning_fail: str | None = None,
    stability_fail: str | None = None,
    locked_code: str,
    technique_observed: bool = True,
    positioning_observed: bool = True,
    stability_observed: bool = True,
) -> dict[str, CriterionCheck]:
    """Build a per-criterion map for a frame that could be evaluated.

    A ``None`` fail code means that criterion passed. Set ``*_observed=False``
    when that criterion genuinely could not be checked on this frame.
    """

    def _entry(observed: bool, fail: str | None) -> CriterionCheck | None:
        if not observed:
            return None
        if fail is None:
            return CriterionCheck(
                observed=True,
                satisfied=True,
                reason_code=locked_code,
            )
        return CriterionCheck(
            observed=True,
            satisfied=False,
            reason_code=fail,
        )

    results: dict[str, CriterionCheck] = {}
    technique = _entry(technique_observed, technique_fail)
    if technique is not None:
        results[RubricCriterion.TECHNIQUE.value] = technique
    stability = _entry(stability_observed, stability_fail)
    if stability is not None:
        results[RubricCriterion.STABILITY.value] = stability
    positioning = _entry(positioning_observed, positioning_fail)
    if positioning is not None:
        results[RubricCriterion.PROP_POSITIONING.value] = positioning
    return results
