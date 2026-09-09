from typing import Optional

from config import (
    ARM_STALL_PROXIMITY,
    DOUBLE_FOREARM_MAX_ALONG_FRACTION,
    DOUBLE_FOREARM_MIN_ALONG_FRACTION,
)
from assessment.calibration import scaled_proximity
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    along_wrist_to_elbow_fraction,
    pose_both_forearm_midpoints,
    track_bottle_stability,
    uncertain_result,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def _pair_bottles_to_forearms(
    bottles: list[BottleDetection],
    left_mid: Point2D,
    right_mid: Point2D,
) -> tuple[BottleDetection, BottleDetection]:
    b0, b1 = bottles[0], bottles[1]
    c0 = b0.center_normalized(640, 480)
    c1 = b1.center_normalized(640, 480)
    assignment_a = _dist(c0, left_mid) + _dist(c1, right_mid)
    assignment_b = _dist(c1, left_mid) + _dist(c0, right_mid)
    if assignment_a <= assignment_b:
        return b0, b1
    return b1, b0


def _assign_left_right_bottles(
    bottles: list[BottleDetection],
    left_mid: Point2D,
    right_mid: Point2D,
    movement_state: dict,
) -> tuple[BottleDetection, BottleDetection]:
    by_id = {
        bottle.track_id: bottle
        for bottle in bottles
        if bottle.track_id is not None
    }
    left_id = movement_state.get("left_track_id")
    right_id = movement_state.get("right_track_id")
    left = by_id.get(left_id) if isinstance(left_id, int) else None
    right = by_id.get(right_id) if isinstance(right_id, int) else None
    if left is not None and right is not None and left is not right:
        return left, right
    return _pair_bottles_to_forearms(bottles, left_mid, right_mid)


def _credited(
    result: RuleResult,
    *,
    positioning_fail: str | None = None,
    stability_fail: str | None = None,
) -> RuleResult:
    return attach_criteria(
        result,
        evaluable_criterion_results(
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
            locked_code=FeedbackCode.DOUBLE_FOREARM_STALL_LOCKED.value,
        ),
    )


def _bottle_on_forearm(
    bottle: BottleDetection,
    mid: Point2D,
    pose: PoseLandmarks,
    *,
    left: bool,
    movement_state: dict,
) -> bool:
    center = bottle.center_normalized(640, 480)
    threshold = scaled_proximity(ARM_STALL_PROXIMITY, movement_state)
    if _dist(center, mid) > threshold:
        return False
    elbow_i, wrist_i = (13, 15) if left else (14, 16)
    elbow = pose.get(elbow_i)
    wrist = pose.get(wrist_i)
    if elbow is None or wrist is None:
        return False
    along = along_wrist_to_elbow_fraction(center, elbow, wrist)
    return DOUBLE_FOREARM_MIN_ALONG_FRACTION <= along <= DOUBLE_FOREARM_MAX_ALONG_FRACTION


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    bottles: Optional[list[BottleDetection]] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    _ = hands
    bottle_list = list(bottles) if bottles is not None else (
        [bottle] if bottle is not None else []
    )

    if len(bottle_list) == 0:
        return (
            uncertain_result(
                "Keep both bottles visible.",
                code=FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE,
                feedback_type="error",
            ),
            prev_hip_center,
            movement_state,
        )

    if len(bottle_list) < 2:
        return (
            uncertain_result(
                "Use two bottles—one on each forearm.",
                code=FeedbackCode.NEED_TWO_BOTTLES,
            ),
            prev_hip_center,
            movement_state,
        )

    if len(bottle_list) > 2:
        bottle_list = sorted(
            bottle_list, key=lambda item: item.confidence, reverse=True
        )[:2]

    mids = pose_both_forearm_midpoints(pose)
    if mids is None or pose is None:
        return (
            uncertain_result(
                "Keep both arms fully visible, from elbow to wrist.",
                code=FeedbackCode.BOTH_ARMS_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    left_mid, right_mid = mids
    current = dict(movement_state or {})
    left_bottle, right_bottle = _assign_left_right_bottles(
        bottle_list, left_mid, right_mid, current
    )
    if left_bottle.track_id is not None:
        current["left_track_id"] = left_bottle.track_id
    if right_bottle.track_id is not None:
        current["right_track_id"] = right_bottle.track_id

    left_center = left_bottle.center_normalized(640, 480)
    right_center = right_bottle.center_normalized(640, 480)
    left_to_left = _dist(left_center, left_mid)
    left_to_right = _dist(left_center, right_mid)
    right_to_left = _dist(right_center, left_mid)
    right_to_right = _dist(right_center, right_mid)
    left_prefers_left = left_to_left < left_to_right
    right_prefers_right = right_to_right < right_to_left
    both_prefer_left = left_to_left < left_to_right and right_to_left < right_to_right
    both_prefer_right = left_to_right < left_to_left and right_to_right < right_to_left
    unique_assignment = left_prefers_left and right_prefers_right

    left_valid = _bottle_on_forearm(
        left_bottle, left_mid, pose, left=True, movement_state=current
    )
    right_valid = _bottle_on_forearm(
        right_bottle, right_mid, pose, left=False, movement_state=current
    )

    positioning_fail = None
    if (
        both_prefer_left
        or both_prefer_right
        or not unique_assignment
        or not left_valid
        or not right_valid
    ):
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value

    left_sub, left_stable = track_bottle_stability(
        current.get("left_forearm"),
        left_bottle,
        movement_state=current,
    )
    right_sub, right_stable = track_bottle_stability(
        current.get("right_forearm"),
        right_bottle,
        movement_state=current,
    )
    current["left_forearm"] = left_sub
    current["right_forearm"] = right_sub
    stability_fail = (
        None
        if left_stable and right_stable
        else FeedbackCode.BOTH_PROPS_NOT_STEADY.value
    )

    if positioning_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Balance one bottle on each forearm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Hold both bottles steady on the forearms.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTH_PROPS_NOT_STEADY.value,
                ),
                positioning_fail=None,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    return (
        _credited(
            RuleResult(
                feedback="Double forearm stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.DOUBLE_FOREARM_STALL_LOCKED.value,
            )
        ),
        prev_hip_center,
        current,
    )
