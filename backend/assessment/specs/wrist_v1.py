"""Pure backend evaluator for AssessmentSpec template balance_stall.wrist_v1.

Bottle + MediaPipe Pose wrists only. Not registered in the official rule
engine and not invoked by the WebSocket runtime.
"""

from __future__ import annotations

from typing import Optional

from config import HAND_STALL_UPRIGHT_ASPECT_RATIO
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_stall_proximity,
    pose_wrist_point_for_laterality,
    track_bottle_stability,
    uncertain_result,
)
from assessment.specs.assessment_spec import AssessmentSpec
from vision.types import BottleDetection, PoseLandmarks

_TEMPLATE_ID = "balance_stall.wrist_v1"
_SUPPORTED_LATERALITY = frozenset({"either", "left", "right"})


def _require_wrist_v1(spec: object) -> AssessmentSpec | object:
    try:
        schema_version = spec.schema_version
        template_id = spec.template_id
        prop = spec.prop
        target = spec.target
        laterality = spec.laterality
    except AttributeError as exc:
        raise ValueError(
            "Wrist v1 evaluator requires a validated AssessmentSpec "
            "for balance_stall.wrist_v1"
        ) from exc
    if (
        schema_version != 1
        or template_id != _TEMPLATE_ID
        or prop != "bottle"
        or target != "wrist"
        or laterality not in _SUPPORTED_LATERALITY
    ):
        raise ValueError(
            "Wrist v1 evaluator only accepts AssessmentSpec "
            "balance_stall.wrist_v1 (bottle, wrist)"
        )
    return spec


def _is_upright(bottle: BottleDetection) -> bool:
    width = max(1, bottle.x2 - bottle.x1)
    height = max(0, bottle.y2 - bottle.y1)
    return (height / width) >= HAND_STALL_UPRIGHT_ASPECT_RATIO


def _with_criteria(
    result: RuleResult,
    *,
    technique_fail: str | None,
    positioning_fail: str | None,
    stability_fail: str | None,
) -> RuleResult:
    return attach_criteria(
        result,
        evaluable_criterion_results(
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
            locked_code=FeedbackCode.WRIST_STALL_LOCKED.value,
        ),
    )


def evaluate(
    spec: AssessmentSpec,
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[dict]]:
    """Evaluate one Wrist Stall frame. Hands landmarks are not used."""
    spec = _require_wrist_v1(spec)

    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, movement_state

    wrist = pose_wrist_point_for_laterality(pose, bottle, spec.laterality)
    if wrist is None:
        return (
            uncertain_result(
                "Move back so your wrist and arm are visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            movement_state,
        )

    technique_fail = (
        None if _is_upright(bottle) else FeedbackCode.PROP_NOT_UPRIGHT.value
    )

    stall = check_stall_proximity(
        bottle,
        wrist,
        success_message="Wrist stall locked in.",
        success_code=FeedbackCode.WRIST_STALL_LOCKED.value,
        movement_state=movement_state,
    )
    positioning_fail = (
        None
        if stall.feedback_type == "positive"
        else stall.feedback_code
    )

    if technique_fail is None and positioning_fail is None:
        state, stable = track_bottle_stability(movement_state, bottle)
    else:
        _, stable = track_bottle_stability(
            dict(movement_state) if movement_state else None,
            bottle,
        )
        state = movement_state
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    def _credited(result: RuleResult) -> RuleResult:
        return _with_criteria(
            result,
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
        )

    if technique_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Keep the bottle upright on your wrist.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
                )
            ),
            state,
        )

    if positioning_fail is not None:
        return _credited(stall), state

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Hold the bottle steady on your wrist.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
                )
            ),
            state,
        )

    return _credited(stall), state
