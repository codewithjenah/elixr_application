"""Missing-landmark frames must be UNCERTAIN, never a technique fail."""

from __future__ import annotations

import pytest

from assessment.feedback_codes import (
    FeedbackCategory,
    FeedbackCode,
    category_for,
    criterion_for,
)
from assessment.rule_engine import evaluate_movement
from assessment.rules import arm_stall, bottle_in_a_tin, elbow_stall, shoulder_stall
from assessment.rules.common_checks import check_bottle_visible, check_hands_visible
from assessment.rubric import RubricCriterion
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _bottle(cx: int = 320, cy: int = 240) -> BottleDetection:
    return BottleDetection(
        x1=cx - 20, y1=cy - 40, x2=cx + 20, y2=cy + 40, confidence=0.9
    )


def _open_palm(x: float = 0.5, y: float = 0.5) -> HandLandmarks:
    return HandLandmarks(
        points={
            0: Point2D(x, y + 0.04),
            9: Point2D(x, y - 0.04),
        },
        handedness="Right",
    )


def _hands() -> HandsResult:
    return HandsResult(hands=[_open_palm()])


def _tin_shaker() -> BottleDetection:
    return BottleDetection(x1=220, y1=300, x2=420, y2=350, confidence=0.9)


def _tin_bottle() -> BottleDetection:
    return BottleDetection(x1=300, y1=202, x2=340, y2=302, confidence=0.9)


def _assert_uncertain(result, *, code: FeedbackCode) -> None:
    assert result.posture_status == "unknown"
    assert result.feedback_code == code.value
    assert result.criterion_results is None
    assert category_for(result.feedback_code) in {
        FeedbackCategory.VISIBILITY,
        FeedbackCategory.ENVIRONMENT,
    }
    assert criterion_for(result.feedback_code) is None


@pytest.mark.parametrize(
    "movement,kwargs,expected_code",
    [
        ("Normal Grip", {"bottle": _bottle(), "hands": None}, FeedbackCode.HAND_NOT_VISIBLE),
        (
            "Bartender's Grip",
            {"bottle": _bottle(), "hands": None},
            FeedbackCode.HAND_NOT_VISIBLE,
        ),
        ("Reverse Grip", {"bottle": _bottle(), "hands": None}, FeedbackCode.HAND_NOT_VISIBLE),
        ("Claw Grip", {"bottle": _bottle(), "hands": None}, FeedbackCode.HAND_NOT_VISIBLE),
        (
            "Hand Stall",
            {"bottle": _bottle(), "hands": None},
            FeedbackCode.HAND_NOT_FULLY_VISIBLE,
        ),
        (
            "One Finger Stall",
            {"bottle": _bottle(), "hands": None},
            FeedbackCode.INDEX_FINGER_NOT_VISIBLE,
        ),
        (
            "Forearm Stall",
            {"bottle": _bottle(), "hands": _hands(), "pose": None},
            FeedbackCode.POSE_ARM_NOT_VISIBLE,
        ),
        (
            "Elbow Stall",
            {"bottle": _bottle(), "hands": _hands(), "pose": None},
            FeedbackCode.POSE_ARM_NOT_VISIBLE,
        ),
        (
            "Reverse Forearm Stall",
            {"bottle": _bottle(), "hands": _hands(), "pose": None},
            FeedbackCode.POSE_ARM_NOT_VISIBLE,
        ),
        (
            "Shoulder Stall",
            {"bottle": _bottle(), "hands": _hands(), "pose": None},
            FeedbackCode.SHOULDERS_NOT_VISIBLE,
        ),
        (
            "Double Hand Stall",
            {
                "bottle": None,
                "hands": None,
                "bottles": [_bottle(200, 240), _bottle(440, 240)],
            },
            FeedbackCode.BOTH_HANDS_NOT_VISIBLE,
        ),
        (
            "Bottle in a tin",
            {
                "bottle": None,
                "hands": None,
                "bottles": [_tin_bottle()],
                "shakers": [_tin_shaker()],
            },
            FeedbackCode.HAND_NOT_VISIBLE,
        ),
    ],
)
def test_scored_movements_missing_required_landmarks_are_unknown(
    movement, kwargs, expected_code
):
    result, _, _ = evaluate_movement(
        movement,
        kwargs.get("bottle"),
        kwargs.get("pose"),
        kwargs.get("hands"),
        None,
        bottles=kwargs.get("bottles"),
        shakers=kwargs.get("shakers"),
    )
    _assert_uncertain(result, code=expected_code)


def test_shared_visibility_helpers_omit_criterion_results():
    bottle = check_bottle_visible(None)
    hands = check_hands_visible(None)
    assert bottle is not None and hands is not None
    _assert_uncertain(bottle, code=FeedbackCode.PROP_NOT_DETECTED)
    _assert_uncertain(hands, code=FeedbackCode.HAND_NOT_VISIBLE)


def test_forearm_and_elbow_without_pose_are_not_technique_fails():
    bottle = _bottle()
    hands = _hands()
    forearm, _, _ = arm_stall.evaluate(bottle, None, hands, None)
    elbow, _, _ = elbow_stall.evaluate(bottle, None, hands, None)
    _assert_uncertain(forearm, code=FeedbackCode.POSE_ARM_NOT_VISIBLE)
    _assert_uncertain(elbow, code=FeedbackCode.POSE_ARM_NOT_VISIBLE)
    assert forearm.feedback_code != FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    assert "Move back" in forearm.feedback
    assert "elbow" in forearm.feedback.lower()
    assert "Move back" in elbow.feedback
    assert "elbow" in elbow.feedback.lower()


def test_shoulder_missing_pose_copy_is_visibility_not_technique():
    result, _, _ = shoulder_stall.evaluate(_bottle(), None, _hands(), None)
    _assert_uncertain(result, code=FeedbackCode.SHOULDERS_NOT_VISIBLE)
    assert result.feedback == "Move back so your shoulder is visible."
    assert "stall" not in result.feedback.lower()


def test_bottle_in_a_tin_no_usable_hands_is_visibility_unknown():
    result, _, _ = bottle_in_a_tin.evaluate(
        _tin_bottle(), _tin_shaker(), None, None, None
    )
    _assert_uncertain(result, code=FeedbackCode.HAND_NOT_VISIBLE)
    assert result.feedback == "Keep your supporting hand visible."


def test_bottle_in_a_tin_far_visible_hand_is_wrong_support():
    far_hand = HandsResult(hands=[_open_palm(0.05, 0.05)])
    result, _, _ = bottle_in_a_tin.evaluate(
        _tin_bottle(), _tin_shaker(), None, far_hand, None
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.HAND_NOT_SUPPORTING_SHAKER.value
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE
    assert criterion_for(result.feedback_code) == RubricCriterion.PROP_POSITIONING
    assert result.criterion_results is not None
    assert result.feedback == "Support the shaker with your hand."
