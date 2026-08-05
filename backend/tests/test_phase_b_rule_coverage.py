"""Phase B: every enabled movement rule return path carries a registered code."""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from assessment.feedback_codes import (
    FeedbackCategory,
    FeedbackCode,
    category_for,
    is_registered,
)
from assessment.rule_engine import evaluate_movement
from assessment.rules import (
    arm_stall,
    bartenders_grip,
    bottle_in_a_tin,
    claw_grip,
    double_hand_stall,
    elbow_stall,
    hand_stall,
    normal_grip,
    one_finger_stall,
    reverse_grip,
    shoulder_stall,
    upper_forearm_stall,
)
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks

_RULES_DIR = Path(__file__).resolve().parents[1] / "assessment" / "rules"

# Enabled Flutter catalog movements (authoritative for Phase B scope).
ENABLED_MOVEMENTS = (
    "Normal Grip",
    "Bartender's Grip",
    "Reverse Grip",
    "Claw Grip",
    "Hand Stall",
    "One Finger Stall",
    "Forearm Stall",
    "Elbow Stall",
    "Reverse Forearm Stall",
    "Shoulder Stall",
    "Double Hand Stall",
    "Bottle in a tin",
)

ENABLED_RULE_MODULES = (
    "normal_grip.py",
    "bartenders_grip.py",
    "reverse_grip.py",
    "claw_grip.py",
    "hand_stall.py",
    "one_finger_stall.py",
    "arm_stall.py",
    "elbow_stall.py",
    "upper_forearm_stall.py",
    "shoulder_stall.py",
    "double_hand_stall.py",
    "bottle_in_a_tin.py",
    "common_checks.py",
)

POSITIVE_LOCKED_BY_MOVEMENT = {
    "Normal Grip": FeedbackCode.NORMAL_GRIP_LOCKED,
    "Bartender's Grip": FeedbackCode.BARTENDER_GRIP_LOCKED,
    "Reverse Grip": FeedbackCode.REVERSE_GRIP_LOCKED,
    "Claw Grip": FeedbackCode.CLAW_GRIP_LOCKED,
    "Hand Stall": FeedbackCode.HAND_STALL_LOCKED,
    "One Finger Stall": FeedbackCode.ONE_FINGER_STALL_LOCKED,
    "Forearm Stall": FeedbackCode.FOREARM_STALL_LOCKED,
    "Elbow Stall": FeedbackCode.ELBOW_STALL_LOCKED,
    "Reverse Forearm Stall": FeedbackCode.REVERSE_FOREARM_STALL_LOCKED,
    "Shoulder Stall": FeedbackCode.SHOULDER_STALL_LOCKED,
    "Double Hand Stall": FeedbackCode.DOUBLE_HAND_STALL_LOCKED,
    "Bottle in a tin": FeedbackCode.BOTTLE_IN_TIN_LOCKED,
}


def _rule_result_calls_missing_feedback_code(path: Path) -> list[int]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    missing: list[int] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        is_rule_result = (
            isinstance(func, ast.Name) and func.id == "RuleResult"
        ) or (isinstance(func, ast.Attribute) and func.attr == "RuleResult")
        if not is_rule_result:
            continue
        keys = {kw.arg for kw in node.keywords if kw.arg}
        if "feedback_code" not in keys:
            missing.append(node.lineno)
        if "feedback_category" in keys:
            missing.append(node.lineno)
    return missing


def test_enabled_rule_modules_set_feedback_code_on_every_rule_result():
    missing: list[str] = []
    for name in ENABLED_RULE_MODULES:
        path = _RULES_DIR / name
        lines = _rule_result_calls_missing_feedback_code(path)
        for line in lines:
            missing.append(f"{name}:{line}")
    assert missing == [], f"RuleResult paths missing feedback_code: {missing}"


def test_enabled_movements_have_positive_locked_codes():
    for movement in ENABLED_MOVEMENTS:
        code = POSITIVE_LOCKED_BY_MOVEMENT[movement]
        assert is_registered(code)
        assert category_for(code) == FeedbackCategory.TECHNIQUE


def test_phase_a_hand_stall_codes_remain_stable():
    assert FeedbackCode.HAND_STALL_LOCKED.value == "hand_stall_locked"
    assert FeedbackCode.PROP_NOT_UPRIGHT.value == "prop_not_upright"
    assert FeedbackCode.PALM_NOT_OPEN.value == "palm_not_open"
    assert FeedbackCode.PROP_NOT_DETECTED.value == "prop_not_detected"


def _bottle(
    cx: int = 320,
    cy: int = 240,
    *,
    w: int = 40,
    h: int = 90,
) -> BottleDetection:
    return BottleDetection(
        x1=cx - w // 2,
        y1=cy - h // 2,
        x2=cx + w // 2,
        y2=cy + h // 2,
        confidence=0.9,
    )


def _wide_shaker(cx: int = 320, cy: int = 280) -> BottleDetection:
    return BottleDetection(
        x1=cx - 70,
        y1=cy - 20,
        x2=cx + 70,
        y2=cy + 20,
        confidence=0.9,
    )


def _open_palm(x: float = 0.5, y: float = 0.5) -> HandLandmarks:
    wrist = Point2D(x, y + 0.04)
    middle_mcp = Point2D(x, y - 0.04)
    tips = {
        8: Point2D(x - 0.04, y - 0.12),
        12: Point2D(x, y - 0.13),
        16: Point2D(x + 0.035, y - 0.12),
        20: Point2D(x + 0.05, y - 0.10),
    }
    return HandLandmarks(
        points={
            0: wrist,
            4: Point2D(x - 0.05, y),
            5: Point2D(x - 0.03, y - 0.02),
            9: middle_mcp,
            13: Point2D(x + 0.025, y - 0.02),
            17: Point2D(x + 0.04, y - 0.01),
            **tips,
        },
        handedness="Right",
    )


def _pose_with_arm(*, side: str = "right") -> PoseLandmarks:
    # MediaPipe: left elbow/wrist 13/15, right 14/16; shoulders 11/12.
    points: dict[int, Point2D] = {
        11: Point2D(0.40, 0.30),
        12: Point2D(0.60, 0.30),
    }
    if side == "right":
        points[14] = Point2D(0.62, 0.45)
        points[16] = Point2D(0.64, 0.60)
    else:
        points[13] = Point2D(0.38, 0.45)
        points[15] = Point2D(0.36, 0.60)
    return PoseLandmarks(
        points=points,
        visibility={index: 0.9 for index in points},
    )


def _stable(bottle: BottleDetection, frames: int = 6) -> dict:
    center = bottle.center_normalized(640, 480)
    return {"bottle_history": [(center.x, center.y)] * frames}


@pytest.mark.parametrize(
    "movement,setup",
    [
        (
            "Hand Stall",
            lambda: (
                _bottle(cx=352, cy=250, h=90, w=40),
                None,
                HandsResult(hands=[_open_palm(0.55, 0.55)]),
                _stable(_bottle(cx=352, cy=250, h=90, w=40)),
            ),
        ),
    ],
)
def test_representative_success_codes_are_registered(movement, setup):
    bottle, pose, hands, state = setup()
    result, _, _ = evaluate_movement(
        movement, bottle, pose, hands, None, state
    )
    # Not all synthetic setups lock; assert that whatever returns is coded.
    assert result.feedback_code is not None
    assert is_registered(result.feedback_code)


def test_missing_prop_uses_shared_environment_code_across_enabled_movements():
    coded_movements = [
        m
        for m in ENABLED_MOVEMENTS
        if m not in {"Double Hand Stall", "Bottle in a tin"}
    ]
    for movement in coded_movements:
        result, _, _ = evaluate_movement(movement, None, None, None, None)
        assert result.feedback_code == FeedbackCode.PROP_NOT_DETECTED.value, movement
        assert category_for(result.feedback_code) == FeedbackCategory.ENVIRONMENT


def test_double_hand_stall_zero_bottles_coded():
    result, _, _ = double_hand_stall.evaluate(
        None, None, None, None, bottles=[]
    )
    assert result.feedback_code == FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE.value


def test_bottle_in_a_tin_both_missing_coded():
    result, _, _ = bottle_in_a_tin.evaluate(None, None, None, None, None)
    assert result.feedback_code == FeedbackCode.BOTH_PROPS_NOT_DETECTED.value


def test_forearm_and_elbow_alignment_failures_use_shared_target_code():
    bottle = _bottle(cx=100, cy=100)
    pose = _pose_with_arm()
    hands = HandsResult(hands=[_open_palm(0.5, 0.5)])
    forearm, _, _ = arm_stall.evaluate(bottle, pose, hands, None, _stable(bottle))
    elbow, _, _ = elbow_stall.evaluate(bottle, pose, hands, None, _stable(bottle))
    assert forearm.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    assert elbow.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value


def test_reverse_forearm_missing_pose_coded():
    result, _, _ = upper_forearm_stall.evaluate(_bottle(), None, None, None)
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value


def test_shoulder_missing_pose_coded():
    result, _, _ = shoulder_stall.evaluate(_bottle(), None, None, None)
    assert result.feedback_code == FeedbackCode.SHOULDERS_NOT_VISIBLE.value


def test_one_finger_missing_index_coded():
    # Palm-only landmarks without full index chain.
    hand = HandLandmarks(
        points={0: Point2D(0.5, 0.5), 9: Point2D(0.5, 0.45)},
        handedness="Right",
    )
    result, _, _ = one_finger_stall.evaluate(
        _bottle(), None, HandsResult(hands=[hand]), None
    )
    assert result.feedback_code == FeedbackCode.INDEX_FINGER_NOT_VISIBLE.value


def test_normal_grip_missing_hands_uses_shared_visibility_code():
    result, _, _ = normal_grip.evaluate(_bottle(), None, None, None)
    assert result.feedback_code == FeedbackCode.HAND_NOT_VISIBLE.value


def test_claw_tilted_bottle_uses_prop_not_upright():
    tilted = _bottle(w=100, h=50)
    hands = HandsResult(hands=[_open_palm(0.5, 0.35)])
    result, _, _ = claw_grip.evaluate(tilted, None, hands, None)
    assert result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value


def test_rules_do_not_author_feedback_category_attribute():
    for name in ENABLED_RULE_MODULES:
        source = (_RULES_DIR / name).read_text(encoding="utf-8")
        assert "feedback_category" not in source


def test_module_exports_cover_enabled_catalog():
    # Sanity: imports resolve for every enabled evaluator.
    assert callable(normal_grip.evaluate)
    assert callable(bartenders_grip.evaluate)
    assert callable(reverse_grip.evaluate)
    assert callable(claw_grip.evaluate)
    assert callable(hand_stall.evaluate)
    assert callable(one_finger_stall.evaluate)
    assert callable(arm_stall.evaluate)
    assert callable(elbow_stall.evaluate)
    assert callable(upper_forearm_stall.evaluate)
    assert callable(shoulder_stall.evaluate)
    assert callable(double_hand_stall.evaluate)
    assert callable(bottle_in_a_tin.evaluate)


def _assert_coded(
    result,
    *,
    expected_code: str,
    expected_category: FeedbackCategory,
    feedback_type: str | None = None,
    feedback_contains: str | None = None,
):
    assert result.feedback_code, "feedback_code must be nonempty"
    assert result.feedback_code == expected_code
    assert is_registered(result.feedback_code)
    assert category_for(result.feedback_code) == expected_category
    assert not hasattr(result, "feedback_category") or not getattr(
        result, "feedback_category", None
    )
    if feedback_type is not None:
        assert result.feedback_type == feedback_type
    if feedback_contains is not None:
        assert feedback_contains.lower() in result.feedback.lower()
    assert result.feedback
    assert result.posture_status in {"stable", "unstable", "unknown"}


def test_visibility_and_environment_excluded_from_technique_category():
    for code in (
        FeedbackCode.PROP_NOT_DETECTED,
        FeedbackCode.HAND_NOT_VISIBLE,
        FeedbackCode.HAND_NOT_FULLY_VISIBLE,
        FeedbackCode.POSE_ARM_NOT_VISIBLE,
        FeedbackCode.SHOULDERS_NOT_VISIBLE,
        FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE,
        FeedbackCode.BOTH_PROPS_NOT_DETECTED,
        FeedbackCode.BOTTLE_NOT_DETECTED,
        FeedbackCode.SHAKER_NOT_DETECTED,
    ):
        cat = category_for(code)
        assert cat in {FeedbackCategory.VISIBILITY, FeedbackCategory.ENVIRONMENT}


@pytest.mark.parametrize(
    "movement",
    [m for m in ENABLED_MOVEMENTS if m not in {"Double Hand Stall", "Bottle in a tin"}],
)
def test_every_simple_movement_missing_prop_is_environment_coded(movement):
    result, _, _ = evaluate_movement(movement, None, None, None, None)
    _assert_coded(
        result,
        expected_code=FeedbackCode.PROP_NOT_DETECTED.value,
        expected_category=FeedbackCategory.ENVIRONMENT,
        feedback_type="error",
    )


def test_hand_stall_fail_fast_branches_are_coded():
    # Closed palm after prop+hand present.
    bottle = _bottle(cx=320, cy=250)
    closed = HandLandmarks(
        points={
            0: Point2D(0.5, 0.54),
            4: Point2D(0.45, 0.5),
            5: Point2D(0.47, 0.48),
            9: Point2D(0.5, 0.46),
            13: Point2D(0.525, 0.48),
            17: Point2D(0.54, 0.49),
            8: Point2D(0.47, 0.475),
            12: Point2D(0.5, 0.455),
            16: Point2D(0.525, 0.475),
            20: Point2D(0.54, 0.485),
        },
        handedness="Right",
    )
    result, _, _ = hand_stall.evaluate(
        bottle, None, HandsResult(hands=[closed]), None, _stable(bottle)
    )
    _assert_coded(
        result,
        expected_code=FeedbackCode.PALM_NOT_OPEN.value,
        expected_category=FeedbackCategory.TECHNIQUE,
        feedback_type="warning",
        feedback_contains="palm",
    )


def test_one_finger_tilted_prop_coded():
    tilted = _bottle(w=100, h=50)
    tip_hand = HandLandmarks(
        points={
            0: Point2D(0.5, 0.55),
            5: Point2D(0.5, 0.50),
            6: Point2D(0.5, 0.47),
            7: Point2D(0.5, 0.44),
            8: Point2D(0.5, 0.40),
            9: Point2D(0.52, 0.50),
            12: Point2D(0.54, 0.52),
            16: Point2D(0.56, 0.53),
            20: Point2D(0.58, 0.54),
            4: Point2D(0.46, 0.52),
        },
        handedness="Right",
    )
    result, _, _ = one_finger_stall.evaluate(
        tilted, None, HandsResult(hands=[tip_hand]), None
    )
    _assert_coded(
        result,
        expected_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
        expected_category=FeedbackCategory.TECHNIQUE,
    )


def test_normal_and_reverse_grip_missing_hands_coded():
    for movement, module in (
        ("Normal Grip", normal_grip),
        ("Reverse Grip", reverse_grip),
    ):
        result, _, _ = module.evaluate(_bottle(), None, None, None)
        _assert_coded(
            result,
            expected_code=FeedbackCode.HAND_NOT_VISIBLE.value,
            expected_category=FeedbackCategory.VISIBILITY,
        )


def test_double_hand_need_two_bottles_coded():
    result, _, _ = double_hand_stall.evaluate(
        _bottle(), None, None, None, bottles=[_bottle()]
    )
    _assert_coded(
        result,
        expected_code=FeedbackCode.NEED_TWO_BOTTLES.value,
        expected_category=FeedbackCategory.ENVIRONMENT,
    )


def test_double_hand_missing_hands_coded():
    bottles = [_bottle(cx=280), _bottle(cx=360)]
    result, _, _ = double_hand_stall.evaluate(
        bottles[0], None, None, None, bottles=bottles
    )
    _assert_coded(
        result,
        expected_code=FeedbackCode.BOTH_HANDS_NOT_VISIBLE.value,
        expected_category=FeedbackCategory.VISIBILITY,
    )


def test_bottle_in_a_tin_distinguishes_bottle_and_shaker_technique():
    upright_bottle = _bottle(cx=320, cy=250, w=40, h=100)
    wide_shaker = _wide_shaker(cx=320, cy=300)
    tilted_bottle = _bottle(cx=320, cy=250, w=100, h=50)
    upright_shaker = BottleDetection(
        x1=300, y1=200, x2=340, y2=360, confidence=0.9
    )

    bottle_issue, _, _ = bottle_in_a_tin.evaluate(
        tilted_bottle, wide_shaker, None, None, None
    )
    _assert_coded(
        bottle_issue,
        expected_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
        expected_category=FeedbackCategory.TECHNIQUE,
        feedback_contains="bottle",
    )

    shaker_issue, _, _ = bottle_in_a_tin.evaluate(
        upright_bottle, upright_shaker, None, None, None
    )
    _assert_coded(
        shaker_issue,
        expected_code=FeedbackCode.SHAKER_NOT_HORIZONTAL.value,
        expected_category=FeedbackCategory.TECHNIQUE,
        feedback_contains="shaker",
    )
    assert bottle_issue.feedback_code != shaker_issue.feedback_code


def test_bottle_in_a_tin_missing_bottle_or_shaker_coded():
    bottle_only, _, _ = bottle_in_a_tin.evaluate(
        _bottle(), None, None, None, None
    )
    _assert_coded(
        bottle_only,
        expected_code=FeedbackCode.SHAKER_NOT_DETECTED.value,
        expected_category=FeedbackCategory.ENVIRONMENT,
    )
    shaker_only, _, _ = bottle_in_a_tin.evaluate(
        None, _wide_shaker(), None, None, None
    )
    _assert_coded(
        shaker_only,
        expected_code=FeedbackCode.BOTTLE_NOT_DETECTED.value,
        expected_category=FeedbackCategory.ENVIRONMENT,
    )


def test_shoulder_below_shoulder_coded():
    # Bottle clearly below both shoulders (requires visibility metadata).
    bottle = _bottle(cx=320, cy=400)
    pose = PoseLandmarks(
        points={
            11: Point2D(0.40, 0.30),
            12: Point2D(0.60, 0.30),
        },
        visibility={11: 0.9, 12: 0.9},
    )
    result, _, _ = shoulder_stall.evaluate(bottle, pose, None, None)
    assert result.feedback_code in {
        FeedbackCode.PROP_BELOW_SHOULDER.value,
        FeedbackCode.PROP_NOT_ON_SHOULDER.value,
    }
    assert is_registered(result.feedback_code)
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE


def test_reverse_forearm_far_from_segment_coded():
    bottle = _bottle(cx=100, cy=100)
    pose = _pose_with_arm()
    result, _, _ = upper_forearm_stall.evaluate(bottle, pose, None, None)
    assert result.feedback_code in {
        FeedbackCode.PROP_TOO_NEAR_ELBOW.value,
        FeedbackCode.PROP_TOO_NEAR_MID_FOREARM.value,
        FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM.value,
    }
    assert is_registered(result.feedback_code)
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE


def test_prop_aware_hand_stall_uses_prop_neutral_identity():
    tilted = _bottle(w=100, h=50)
    hands = HandsResult(hands=[_open_palm(0.5, 0.55)])
    bottle_result, _, _ = evaluate_movement(
        "Hand Stall",
        tilted,
        None,
        hands,
        None,
        _stable(tilted),
        prop_label="Bottle",
    )
    shaker_result, _, _ = evaluate_movement(
        "Hand Stall",
        tilted,
        None,
        hands,
        None,
        _stable(tilted),
        prop_label="Cocktail Shaker",
    )
    assert bottle_result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    assert shaker_result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    assert "bottle" in bottle_result.feedback.lower()
    assert "cocktail shaker" in shaker_result.feedback.lower()


def test_unknown_feedback_code_remains_legacy_safe():
    assert category_for("totally_unknown_code") is None
    assert is_registered("totally_unknown_code") is False
    assert category_for(None) is None
    assert category_for("") is None


# Paths that are difficult to hit with fully realistic synthetic grip geometry
# (bartender wrap / claw multi-finger curl) remain covered by AST feedback_code
# presence checks above plus helper-level locked success constants.
