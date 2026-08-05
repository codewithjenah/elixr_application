"""Central registry of stable feedback codes and categories.

Movement rules must import [FeedbackCode] values. Categories are derived only
via [category_for] — rules must not hand-pair code/category strings.
"""

from __future__ import annotations

from enum import Enum


class FeedbackCategory(str, Enum):
    TECHNIQUE = "technique"
    VISIBILITY = "visibility"
    ENVIRONMENT = "environment"
    SYSTEM = "system"


class FeedbackCode(str, Enum):
    """Phase A: shared checks + Hand Stall only.

    Hand Stall technique codes are prop-neutral (bottle or shaker).
    """

    PROP_NOT_DETECTED = "prop_not_detected"
    HAND_NOT_VISIBLE = "hand_not_visible"
    HAND_NOT_FULLY_VISIBLE = "hand_not_fully_visible"
    PALM_NOT_OPEN = "palm_not_open"
    PROP_NOT_UPRIGHT = "prop_not_upright"
    PROP_BASE_NOT_ON_PALM = "prop_base_not_on_palm"
    PROP_NOT_ABOVE_PALM = "prop_not_above_palm"
    PROP_NOT_STEADY = "prop_not_steady"
    HAND_STALL_LOCKED = "hand_stall_locked"


# Single source of truth: every registered code maps to exactly one category.
_CODE_CATEGORIES: dict[FeedbackCode, FeedbackCategory] = {
    FeedbackCode.PROP_NOT_DETECTED: FeedbackCategory.ENVIRONMENT,
    FeedbackCode.HAND_NOT_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.HAND_NOT_FULLY_VISIBLE: FeedbackCategory.VISIBILITY,
    FeedbackCode.PALM_NOT_OPEN: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_UPRIGHT: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_BASE_NOT_ON_PALM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_ABOVE_PALM: FeedbackCategory.TECHNIQUE,
    FeedbackCode.PROP_NOT_STEADY: FeedbackCategory.TECHNIQUE,
    FeedbackCode.HAND_STALL_LOCKED: FeedbackCategory.TECHNIQUE,
}


def _validate_registry() -> None:
    values = [code.value for code in FeedbackCode]
    if len(values) != len(set(values)):
        raise RuntimeError("Duplicate FeedbackCode values in registry")
    for code in FeedbackCode:
        if code not in _CODE_CATEGORIES:
            raise RuntimeError(f"FeedbackCode {code!r} missing category mapping")
    if len(_CODE_CATEGORIES) != len(FeedbackCode):
        raise RuntimeError("Orphan category mappings for unknown FeedbackCode values")


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
