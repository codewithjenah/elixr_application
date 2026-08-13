"""Registry integrity, category derivation, hold_target_ms, and schema tests."""

from __future__ import annotations

from assessment.feedback_codes import (
    FeedbackCategory,
    FeedbackCode,
    category_for,
    is_registered,
    registered_codes,
)
from assessment.hold_validator import HoldValidator
from assessment.rule_engine import evaluate_movement
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
    track_bottle_stability,
)
from schemas.feedback import FeedbackMessage
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _bottle_on_palm(
    x: float = 0.50,
    y: float = 0.55,
    *,
    width: int = 40,
    height: int = 80,
    dy: float = 0.01,
) -> BottleDetection:
    bx = int(round(x * 640))
    by = int(round((y - dy) * 480))
    return BottleDetection(
        x1=bx - width // 2,
        y1=by - height,
        x2=bx + width // 2,
        y2=by,
        confidence=0.9,
    )


def _open_palm_hand(
    x: float = 0.5,
    y: float = 0.5,
    handedness: str = "Right",
    *,
    closed: bool = False,
) -> HandLandmarks:
    wrist = Point2D(x, y + 0.04)
    middle_mcp = Point2D(x, y - 0.04)
    if closed:
        tips = {
            8: Point2D(x - 0.03, y - 0.025),
            12: Point2D(x, y - 0.045),
            16: Point2D(x + 0.025, y - 0.025),
            20: Point2D(x + 0.04, y - 0.015),
        }
    else:
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
        handedness=handedness,
    )


def _stable_state(bottle: BottleDetection, frames: int = 6) -> dict:
    center = bottle.center_normalized(640, 480)
    return {"bottle_history": [(center.x, center.y)] * frames}


def test_every_registered_code_has_exactly_one_category():
    codes = list(FeedbackCode)
    assert len(codes) == len(set(c.value for c in codes))
    for code in codes:
        category = category_for(code)
        assert category is not None
        assert isinstance(category, FeedbackCategory)


def test_no_duplicate_code_values():
    values = [c.value for c in registered_codes()]
    assert len(values) == len(set(values))


def test_unknown_and_missing_codes_have_no_category():
    assert category_for(None) is None
    assert category_for("") is None
    assert category_for("not_a_real_code") is None
    assert is_registered("not_a_real_code") is False


def test_phase_a_categories_cover_technique_visibility_environment():
    categories = {category_for(code) for code in FeedbackCode}
    assert FeedbackCategory.TECHNIQUE in categories
    assert FeedbackCategory.VISIBILITY in categories
    assert FeedbackCategory.ENVIRONMENT in categories
    assert FeedbackCategory.SYSTEM.value == "system"


def test_category_values_serialize_as_strings():
    for category in FeedbackCategory:
        message = FeedbackMessage(
            bottle_detected=True,
            movement="Hand Stall",
            feedback="test",
            feedback_type="warning",
            posture_status="unstable",
            feedback_category=category.value,
        )
        dumped = message.model_dump()
        assert dumped["feedback_category"] == category.value


def test_check_bottle_visible_emits_registry_code_and_unchanged_message():
    result = check_bottle_visible(None, prop_label="Bottle")
    assert result is not None
    assert result.feedback_code == FeedbackCode.PROP_NOT_DETECTED.value
    assert result.feedback == "Bottle not detected. Keep the bottle visible."
    assert category_for(result.feedback_code) == FeedbackCategory.ENVIRONMENT


def test_check_hands_visible_emits_registry_code():
    result = check_hands_visible(None)
    assert result is not None
    assert result.feedback_code == FeedbackCode.HAND_NOT_VISIBLE.value
    assert result.feedback == "Hand not detected. Keep your hand in frame."
    assert category_for(result.feedback_code) == FeedbackCategory.VISIBILITY


def test_hand_stall_success_emits_locked_code():
    bottle = _bottle_on_palm(0.55, 0.55)
    hands = HandsResult(hands=[_open_palm_hand(0.55, 0.55)])
    result, _, _ = evaluate_movement(
        "Hand Stall", bottle, None, hands, None, _stable_state(bottle)
    )
    assert result.feedback_type == "positive"
    assert result.feedback == "Hand stall locked in."
    assert result.feedback_code == FeedbackCode.HAND_STALL_LOCKED.value
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE


def test_hand_stall_closed_palm_emits_palm_not_open():
    bottle = _bottle_on_palm(0.50, 0.55)
    hands = HandsResult(hands=[_open_palm_hand(0.50, 0.55, closed=True)])
    result, _, _ = evaluate_movement(
        "Hand Stall", bottle, None, hands, None, _stable_state(bottle)
    )
    assert result.feedback_type == "warning"
    assert result.feedback == "Open your palm and extend your fingers."
    assert result.feedback_code == FeedbackCode.PALM_NOT_OPEN.value


def test_hand_stall_stability_failure_still_reports_other_criteria():
    bottle = _bottle_on_palm(0.55, 0.55)
    hands = HandsResult(hands=[_open_palm_hand(0.55, 0.55)])
    state = None
    for index in range(6):
        moving = _bottle_on_palm(0.55 + index * 0.05, 0.55)
        state, _ = track_bottle_stability(state, moving)
    result, _, _ = evaluate_movement(
        "Hand Stall", bottle, None, hands, None, state
    )
    assert result.feedback_code == FeedbackCode.PROP_NOT_STEADY.value
    assert result.feedback == "Hold the bottle steady on your open palm."
    assert result.criterion_results is not None
    assert result.criterion_results["technique"].satisfied is True
    assert result.criterion_results["prop_positioning"].satisfied is True
    assert result.criterion_results["stability"].satisfied is False
    assert (
        result.criterion_results["stability"].reason_code
        == FeedbackCode.PROP_NOT_STEADY.value
    )


def test_hand_stall_closed_palm_still_evaluates_other_criteria():
    bottle = _bottle_on_palm(0.50, 0.55)
    hands = HandsResult(hands=[_open_palm_hand(0.50, 0.55, closed=True)])
    result, _, _ = evaluate_movement(
        "Hand Stall", bottle, None, hands, None, _stable_state(bottle)
    )
    assert result.feedback_code == FeedbackCode.PALM_NOT_OPEN.value
    assert result.criterion_results is not None
    assert result.criterion_results["technique"].satisfied is False
    assert result.criterion_results["prop_positioning"].observed is True
    assert result.criterion_results["stability"].observed is True


def test_hand_stall_missing_bottle_does_not_claim_criteria():
    result, _, _ = evaluate_movement(
        "Hand Stall",
        None,
        None,
        HandsResult(hands=[_open_palm_hand()]),
        None,
    )
    assert result.feedback_code == FeedbackCode.PROP_NOT_DETECTED.value
    assert not result.criterion_results


def test_hand_stall_missing_bottle_uses_shared_code():
    result, _, _ = evaluate_movement(
        "Hand Stall",
        None,
        None,
        HandsResult(hands=[_open_palm_hand()]),
        None,
    )
    assert result.feedback_code == FeedbackCode.PROP_NOT_DETECTED.value


def test_hand_stall_tilted_bottle_emits_not_upright():
    bottle = _bottle_on_palm(0.50, 0.55, width=100, height=60)
    hands = HandsResult(hands=[_open_palm_hand(0.50, 0.55)])
    result, _, _ = evaluate_movement(
        "Hand Stall", bottle, None, hands, None, _stable_state(bottle)
    )
    assert result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    assert "upright" in result.feedback.lower()


def test_phase_a_prop_neutral_codes_are_registered_once():
    expected = {
        FeedbackCode.PROP_NOT_UPRIGHT,
        FeedbackCode.PROP_BASE_NOT_ON_PALM,
        FeedbackCode.PROP_NOT_ABOVE_PALM,
        FeedbackCode.PROP_NOT_STEADY,
    }
    registered = set(registered_codes())
    assert expected <= registered
    legacy_bottle_values = {
        "bottle_not_upright",
        "bottle_base_not_on_palm",
        "bottle_not_above_palm",
        "bottle_not_steady",
    }
    assert legacy_bottle_values.isdisjoint({c.value for c in registered})


def test_phase_b_positive_locked_codes_are_registered():
    expected = {
        FeedbackCode.NORMAL_GRIP_LOCKED,
        FeedbackCode.BARTENDER_GRIP_LOCKED,
        FeedbackCode.REVERSE_GRIP_LOCKED,
        FeedbackCode.CLAW_GRIP_LOCKED,
        FeedbackCode.HAND_STALL_LOCKED,
        FeedbackCode.ONE_FINGER_STALL_LOCKED,
        FeedbackCode.FOREARM_STALL_LOCKED,
        FeedbackCode.ELBOW_STALL_LOCKED,
        FeedbackCode.REVERSE_FOREARM_STALL_LOCKED,
        FeedbackCode.SHOULDER_STALL_LOCKED,
        FeedbackCode.DOUBLE_HAND_STALL_LOCKED,
        FeedbackCode.BOTTLE_IN_TIN_LOCKED,
    }
    registered = set(registered_codes())
    assert expected <= registered
    for code in expected:
        assert category_for(code) == FeedbackCategory.TECHNIQUE


def test_phase_b_shared_technique_codes_are_registered():
    expected = {
        FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET,
        FeedbackCode.HAND_NOT_AT_NECK,
        FeedbackCode.BOTH_PALMS_NOT_OPEN,
        FeedbackCode.BOTH_PROPS_NOT_STEADY,
        FeedbackCode.SHAKER_NOT_HORIZONTAL,
    }
    registered = set(registered_codes())
    assert expected <= registered


def test_hand_stall_bottle_and_shaker_share_prop_neutral_codes():
    bottle = _bottle_on_palm(0.50, 0.55, width=100, height=60)
    hands = HandsResult(hands=[_open_palm_hand(0.50, 0.55)])
    bottle_result, _, _ = evaluate_movement(
        "Hand Stall",
        bottle,
        None,
        hands,
        None,
        _stable_state(bottle),
        prop_label="Bottle",
    )
    shaker_result, _, _ = evaluate_movement(
        "Hand Stall",
        bottle,
        None,
        hands,
        None,
        _stable_state(bottle),
        prop_label="Cocktail Shaker",
    )
    assert bottle_result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    assert shaker_result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    assert "bottle" in bottle_result.feedback.lower()
    assert "cocktail shaker" in shaker_result.feedback.lower()
    assert bottle_result.feedback_code == shaker_result.feedback_code


def test_hold_target_ms_matches_confirmation_duration():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()
    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=0.0,
    )
    assert snapshot.hold_target_ms == 2500


def test_custom_confirmation_duration_sets_matching_hold_target():
    validator = HoldValidator(confirmation_seconds=1.0, max_frame_gap_seconds=0.5)
    validator.activate()
    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=0.0,
    )
    assert snapshot.hold_target_ms == 1000


def test_inactive_hold_snapshot_has_zero_target():
    validator = HoldValidator(confirmation_seconds=2.5)
    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=0.0,
    )
    assert snapshot.hold_target_ms == 0
    assert snapshot.hold_confirmed is False


def test_hold_confirmation_behavior_unchanged_with_target_field():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()
    t = 0.0
    snapshot = None
    while t <= 2.6:
        snapshot = validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=t,
        )
        t += 0.1
    assert snapshot is not None
    assert snapshot.hold_confirmed is True
    assert snapshot.hold_progress == 1.0
    assert snapshot.hold_target_ms == 2500


def test_feedback_message_optional_coaching_fields_serialize():
    message = FeedbackMessage(
        bottle_detected=True,
        movement="Hand Stall",
        feedback="Hand stall locked in.",
        feedback_type="positive",
        posture_status="stable",
        hold_target_ms=2500,
        feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
        feedback_category=FeedbackCategory.TECHNIQUE.value,
    )
    dumped = message.model_dump()
    assert dumped["hold_target_ms"] == 2500
    assert dumped["feedback_code"] == "hand_stall_locked"
    assert dumped["feedback_category"] == "technique"


def test_legacy_feedback_message_without_codes_remains_valid():
    message = FeedbackMessage(
        bottle_detected=True,
        movement="Hand Stall",
        feedback="Keep steady",
        feedback_type="warning",
        posture_status="unstable",
    )
    dumped = message.model_dump()
    assert dumped["feedback_code"] is None
    assert dumped["feedback_category"] is None
    assert dumped["hold_target_ms"] == 0


def test_rule_result_does_not_carry_feedback_category_field():
    from assessment.rules.base import RuleResult

    result = RuleResult(
        feedback="Hold steady",
        feedback_type="positive",
        posture_status="stable",
        feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
    )
    assert not hasattr(result, "feedback_category")
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE


def test_every_enabled_movement_positive_code_is_nonempty_and_technique():
    from assessment.feedback_codes import FeedbackCode as FC

    positives = [
        FC.NORMAL_GRIP_LOCKED,
        FC.BARTENDER_GRIP_LOCKED,
        FC.REVERSE_GRIP_LOCKED,
        FC.CLAW_GRIP_LOCKED,
        FC.HAND_STALL_LOCKED,
        FC.ONE_FINGER_STALL_LOCKED,
        FC.FOREARM_STALL_LOCKED,
        FC.ELBOW_STALL_LOCKED,
        FC.REVERSE_FOREARM_STALL_LOCKED,
        FC.SHOULDER_STALL_LOCKED,
        FC.DOUBLE_HAND_STALL_LOCKED,
        FC.BOTTLE_IN_TIN_LOCKED,
    ]
    assert len(positives) == len(set(positives))
    for code in positives:
        assert code.value
        assert category_for(code) == FeedbackCategory.TECHNIQUE


def test_shared_visibility_environment_not_technique():
    assert category_for(FeedbackCode.PROP_NOT_DETECTED) == FeedbackCategory.ENVIRONMENT
    assert category_for(FeedbackCode.HAND_NOT_VISIBLE) == FeedbackCategory.VISIBILITY
    assert category_for(FeedbackCode.HAND_NOT_FULLY_VISIBLE) == FeedbackCategory.VISIBILITY
    assert category_for(FeedbackCode.PROP_NOT_UPRIGHT) == FeedbackCategory.TECHNIQUE


def test_bottle_in_a_tin_codes_distinguish_props():
    assert FeedbackCode.PROP_NOT_UPRIGHT.value == "prop_not_upright"
    assert FeedbackCode.SHAKER_NOT_HORIZONTAL.value == "shaker_not_horizontal"
    assert FeedbackCode.BOTTLE_NOT_DETECTED.value == "bottle_not_detected"
    assert FeedbackCode.SHAKER_NOT_DETECTED.value == "shaker_not_detected"
    assert category_for(FeedbackCode.SHAKER_NOT_HORIZONTAL) == FeedbackCategory.TECHNIQUE
    assert category_for(FeedbackCode.BOTTLE_NOT_DETECTED) == FeedbackCategory.ENVIRONMENT
