from typing import Optional

from config import (
    UPPER_FOREARM_ELBOW_ZONE,
    UPPER_FOREARM_MID_ZONE,
    UPPER_FOREARM_RATIO,
    UPPER_FOREARM_STALL_PROXIMITY,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    pose_upper_forearm_landmarks,
    track_bottle_stability,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    landmarks = pose_upper_forearm_landmarks(
        pose, bottle, ratio=UPPER_FOREARM_RATIO
    )
    if landmarks is None:
        return (
            RuleResult(
                feedback="Show your elbow and wrist so the reverse forearm can be tracked.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    elbow, upper, mid, _wrist = landmarks
    state, stable = track_bottle_stability(movement_state, bottle)
    bottle_center = bottle.center_normalized(640, 480)

    dist_elbow = _dist(bottle_center, elbow)
    dist_upper = _dist(bottle_center, upper)
    dist_mid = _dist(bottle_center, mid)

    if dist_elbow <= UPPER_FOREARM_ELBOW_ZONE and dist_elbow < dist_upper:
        return (
            RuleResult(
                feedback="Move the bottle away from the elbow onto the reverse forearm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if dist_mid <= UPPER_FOREARM_MID_ZONE and dist_mid < dist_upper:
        return (
            RuleResult(
                feedback="Keep the bottle on the reverse forearm, not the mid-forearm or wrist.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if dist_upper > UPPER_FOREARM_STALL_PROXIMITY:
        return (
            RuleResult(
                feedback="Balance the bottle on your reverse forearm between elbow and mid-arm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if not stable:
        return (
            RuleResult(
                feedback="Hold the bottle steady on your reverse forearm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    return (
        RuleResult(
            feedback="Reverse forearm stall locked in.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        state,
    )
