"""Pure backend evaluator for AssessmentSpec template balance_stall.wrist_v1.

Bottle + MediaPipe Pose selected-arm geometry. Not registered in the official
rule engine. Template sessions dispatch here by validated template_id only.
"""

from __future__ import annotations

import math
from typing import Literal, Optional

from config import (
    FRAME_HEIGHT,
    FRAME_WIDTH,
    HAND_STALL_UPRIGHT_ASPECT_RATIO,
    WRIST_STALL_FOREARM_ALONG_RATIO,
    WRIST_STALL_FOREARM_BAND_RATIO,
    WRIST_STALL_LOCAL_RADIUS_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    track_bottle_stability,
    uncertain_result,
)
from assessment.specs.assessment_spec import AssessmentSpec
from vision.types import BottleDetection, Point2D, PoseLandmarks

_TEMPLATE_ID = "balance_stall.wrist_v1"
_SUPPORTED_LATERALITY = frozenset({"either", "left", "right"})
# MediaPipe Pose: anatomical left (wrist 15, elbow 13), right (wrist 16, elbow 14).
_ARM_JOINTS = {
    "left": (15, 13),
    "right": (16, 14),
}
_DEGENERATE_FOREARM = 1e-6
WristSupportClass = Literal["wrist", "forearm", "far"]


def _require_wrist_v1(spec: object) -> AssessmentSpec:
    if not isinstance(spec, AssessmentSpec):
        raise ValueError(
            "Wrist v1 evaluator requires a validated AssessmentSpec "
            "for balance_stall.wrist_v1"
        )
    if (
        spec.schema_version != 1
        or spec.template_id != _TEMPLATE_ID
        or spec.prop != "bottle"
        or spec.target != "wrist"
        or spec.laterality not in _SUPPORTED_LATERALITY
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


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def classify_wrist_support(
    support: Point2D,
    *,
    wrist: Point2D,
    elbow: Point2D,
) -> Optional[WristSupportClass]:
    """Classify bottle support relative to the selected wrist/forearm.

    Uses the bottle support point (typically bottom-center) and the
    elbow→wrist axis. Returns None when the forearm segment is degenerate.
    """
    forearm_x = wrist.x - elbow.x
    forearm_y = wrist.y - elbow.y
    forearm_len = math.hypot(forearm_x, forearm_y)
    if forearm_len < _DEGENERATE_FOREARM:
        return None

    unit_x = forearm_x / forearm_len
    unit_y = forearm_y / forearm_len
    dx = support.x - wrist.x
    dy = support.y - wrist.y
    # Positive toward the elbow (back along the wrist→elbow segment).
    along_to_elbow = -(dx * unit_x + dy * unit_y)
    perp = abs(dx * unit_y - dy * unit_x)
    radial = math.hypot(dx, dy)

    local_radius = WRIST_STALL_LOCAL_RADIUS_RATIO * forearm_len
    along_limit = WRIST_STALL_FOREARM_ALONG_RATIO * forearm_len
    forearm_band = WRIST_STALL_FOREARM_BAND_RATIO * forearm_len

    if along_to_elbow <= along_limit and radial <= local_radius:
        return "wrist"
    if (
        along_to_elbow > along_limit
        and along_to_elbow <= forearm_len + along_limit
        and perp <= forearm_band
    ):
        return "forearm"
    return "far"


def _complete_arm(
    pose: PoseLandmarks, laterality: str
) -> Optional[tuple[Point2D, Point2D]]:
    wrist_i, elbow_i = _ARM_JOINTS[laterality]
    wrist = pose.get(wrist_i)
    elbow = pose.get(elbow_i)
    if wrist is None or elbow is None:
        return None
    return wrist, elbow


def _selected_wrist_elbow(
    pose: Optional[PoseLandmarks],
    support: Point2D,
    laterality: str,
) -> Optional[tuple[Point2D, Point2D]]:
    if pose is None:
        return None
    if laterality in ("left", "right"):
        return _complete_arm(pose, laterality)

    best: Optional[tuple[Point2D, Point2D]] = None
    best_dist = float("inf")
    for side in ("left", "right"):
        arm = _complete_arm(pose, side)
        if arm is None:
            continue
        wrist, _elbow = arm
        dist = _dist(support, wrist)
        if dist < best_dist:
            best_dist = dist
            best = arm
    return best


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

    support = bottle.bottom_center_normalized(FRAME_WIDTH, FRAME_HEIGHT)
    arm = _selected_wrist_elbow(pose, support, spec.laterality)
    if arm is None:
        return (
            uncertain_result(
                "Move back so your wrist and arm are visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            movement_state,
        )

    wrist, elbow = arm
    contact = classify_wrist_support(support, wrist=wrist, elbow=elbow)
    if contact is None:
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

    if contact == "wrist":
        positioning_fail = None
        stall = RuleResult(
            feedback="Wrist stall locked in.",
            feedback_type="positive",
            posture_status="stable",
            feedback_code=FeedbackCode.WRIST_STALL_LOCKED.value,
        )
    elif contact == "forearm":
        positioning_fail = FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
        stall = RuleResult(
            feedback="Move the bottle down to your wrist.",
            feedback_type="warning",
            posture_status="unstable",
            feedback_code=FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value,
        )
    else:
        positioning_fail = FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
        stall = RuleResult(
            feedback="Align the bottle over the stall point.",
            feedback_type="warning",
            posture_status="unstable",
            feedback_code=FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value,
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
