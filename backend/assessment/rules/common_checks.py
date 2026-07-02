import math
from typing import Optional

from config import (
    BASKET_PROXIMITY,
    FLIP_ARC_THRESHOLD,
    FLIP_HISTORY_FRAMES,
    HAND_BOTTLE_PROXIMITY,
    HAND_SWITCH_PROXIMITY,
    PINCH_DISTANCE,
    SHOULDER_ALIGN_THRESHOLD,
    STALL_PROXIMITY,
    STANCE_JITTER_THRESHOLD,
    TAP_CONTACT_THRESHOLD,
)
from assessment.rules.base import RuleResult
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _angle(a: Point2D, b: Point2D, c: Point2D) -> float:
    """Angle at point b formed by a-b-c in degrees."""
    ba = (a.x - b.x, a.y - b.y)
    bc = (c.x - b.x, c.y - b.y)
    dot = ba[0] * bc[0] + ba[1] * bc[1]
    mag_ba = math.hypot(*ba)
    mag_bc = math.hypot(*bc)
    if mag_ba == 0 or mag_bc == 0:
        return 0.0
    cos_angle = max(-1.0, min(1.0, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cos_angle))


def check_bottle_visible(bottle: Optional[BottleDetection]) -> Optional[RuleResult]:
    if bottle is None:
        return RuleResult(
            feedback="Bottle not detected. Keep the bottle visible.",
            feedback_type="error",
            posture_status="unknown",
        )
    return None


def check_shoulder_alignment(pose: Optional[PoseLandmarks]) -> Optional[RuleResult]:
    if pose is None:
        return RuleResult(
            feedback="Body not detected. Step back so your upper body is visible.",
            feedback_type="warning",
            posture_status="unknown",
        )

    left = pose.get(11)
    right = pose.get(12)
    if left is None or right is None:
        return RuleResult(
            feedback="Shoulders not visible. Face the camera.",
            feedback_type="warning",
            posture_status="unknown",
        )

    if abs(left.y - right.y) > SHOULDER_ALIGN_THRESHOLD:
        return RuleResult(
            feedback="Keep shoulders level.",
            feedback_type="warning",
            posture_status="unstable",
        )
    return None


def check_stance_stability(
    pose: Optional[PoseLandmarks],
    prev_hip_center: Optional[Point2D],
) -> tuple[Optional[RuleResult], Optional[Point2D]]:
    if pose is None:
        return None, prev_hip_center

    left_hip = pose.get(23)
    right_hip = pose.get(24)
    left_knee = pose.get(25)
    right_knee = pose.get(26)
    left_ankle = pose.get(27)
    right_ankle = pose.get(28)

    if not all([left_hip, right_hip, left_knee, right_knee, left_ankle, right_ankle]):
        return None, prev_hip_center

    hip_center = Point2D(
        x=(left_hip.x + right_hip.x) / 2.0,
        y=(left_hip.y + right_hip.y) / 2.0,
    )

    stance_width = _dist(left_ankle, right_ankle)
    if stance_width < 0.08:
        return (
            RuleResult(
                feedback="Widen your stance for better balance.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            hip_center,
        )

    if prev_hip_center is not None:
        jitter = _dist(hip_center, prev_hip_center)
        if jitter > STANCE_JITTER_THRESHOLD:
            return (
                RuleResult(
                    feedback="Reduce body sway to stay stable.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                hip_center,
            )

    return None, hip_center


def check_hand_bottle_proximity(
    bottle: BottleDetection,
    target: Optional[Point2D],
    *,
    threshold: float = HAND_BOTTLE_PROXIMITY,
    far_message: str = "Move the bottle closer to your hand.",
    near_message: str = "Good hand-bottle alignment.",
) -> RuleResult:
    if target is None:
        return RuleResult(
            feedback="Hand not detected. Keep your hand in frame.",
            feedback_type="warning",
            posture_status="unknown",
        )

    bottle_center = bottle.center_normalized(640, 480)
    dist = _dist(bottle_center, target)
    if dist > threshold:
        return RuleResult(
            feedback=far_message,
            feedback_type="warning",
            posture_status="unstable",
        )
    return RuleResult(
        feedback=near_message,
        feedback_type="positive",
        posture_status="stable",
    )


def check_stall_proximity(
    bottle: BottleDetection,
    target: Optional[Point2D],
    *,
    success_message: str,
) -> RuleResult:
    if target is None:
        return RuleResult(
            feedback="Target body part not visible.",
            feedback_type="warning",
            posture_status="unknown",
        )

    bottle_center = bottle.center_normalized(640, 480)
    dist = _dist(bottle_center, target)
    if dist > STALL_PROXIMITY:
        return RuleResult(
            feedback="Align the bottle over the stall point.",
            feedback_type="warning",
            posture_status="unstable",
        )
    return RuleResult(
        feedback=success_message,
        feedback_type="positive",
        posture_status="stable",
    )


def _dominant_arm_points(pose: PoseLandmarks) -> tuple[Optional[Point2D], Optional[Point2D], Optional[Point2D]]:
    """Return shoulder, elbow, wrist for the arm with higher wrist visibility."""
    left_vis = pose.visibility.get(15, 0.0)
    right_vis = pose.visibility.get(16, 0.0)
    if left_vis >= right_vis:
        return pose.get(11), pose.get(13), pose.get(15)
    return pose.get(12), pose.get(14), pose.get(16)


def check_grip_angle(
    pose: Optional[PoseLandmarks],
    *,
    min_angle: float,
    max_angle: float,
    success_message: str,
    fail_message: str,
) -> RuleResult:
    if pose is None:
        return RuleResult(
            feedback="Body not detected. Step back so your arm is visible.",
            feedback_type="warning",
            posture_status="unknown",
        )

    shoulder, elbow, wrist = _dominant_arm_points(pose)
    if shoulder is None or elbow is None or wrist is None:
        return RuleResult(
            feedback="Arm not fully visible. Extend into frame.",
            feedback_type="warning",
            posture_status="unknown",
        )

    angle = _angle(shoulder, elbow, wrist)
    if min_angle <= angle <= max_angle:
        return RuleResult(
            feedback=success_message,
            feedback_type="positive",
            posture_status="stable",
        )
    return RuleResult(
        feedback=fail_message,
        feedback_type="warning",
        posture_status="unstable",
    )


def forearm_midpoint(pose: PoseLandmarks) -> Optional[Point2D]:
    shoulder, elbow, wrist = _dominant_arm_points(pose)
    if elbow is None or wrist is None:
        return None
    return Point2D(x=(elbow.x + wrist.x) / 2.0, y=(elbow.y + wrist.y) / 2.0)


def dominant_elbow(pose: PoseLandmarks) -> Optional[Point2D]:
    left_vis = pose.visibility.get(13, 0.0)
    right_vis = pose.visibility.get(14, 0.0)
    if left_vis >= right_vis:
        return pose.get(13)
    return pose.get(14)


def dominant_wrist(pose: PoseLandmarks) -> Optional[Point2D]:
    left_vis = pose.visibility.get(15, 0.0)
    right_vis = pose.visibility.get(16, 0.0)
    if left_vis >= right_vis:
        return pose.get(15)
    return pose.get(16)


def bottle_hand_distance(bottle: BottleDetection, point: Point2D) -> float:
    bottle_center = bottle.center_normalized(640, 480)
    return _dist(bottle_center, point)


def nearest_hand_to_bottle(
    hands: HandsResult,
    bottle: BottleDetection,
) -> tuple[Optional[HandLandmarks], Optional[Point2D]]:
    bottle_center = bottle.center_normalized(640, 480)
    best_hand: Optional[HandLandmarks] = None
    best_palm: Optional[Point2D] = None
    best_dist = float("inf")
    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        dist = _dist(palm, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best_hand = hand
            best_palm = palm
    return best_hand, best_palm


def check_pinch_grip(
    hand: HandLandmarks,
    bottle: BottleDetection,
    *,
    threshold: float = PINCH_DISTANCE,
) -> RuleResult:
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if thumb is None or index is None:
        return RuleResult(
            feedback="Keep thumb and index finger visible for the clip.",
            feedback_type="warning",
            posture_status="unknown",
        )

    pinch_dist = _dist(thumb, index)
    pinch_center = Point2D(
        x=(thumb.x + index.x) / 2.0,
        y=(thumb.y + index.y) / 2.0,
    )
    bottle_dist = bottle_hand_distance(bottle, pinch_center)

    if pinch_dist > threshold:
        return RuleResult(
            feedback="Pinch the bottle between thumb and fingers.",
            feedback_type="warning",
            posture_status="unstable",
        )
    if bottle_dist > HAND_BOTTLE_PROXIMITY:
        return RuleResult(
            feedback="Move the bottle into the pinch.",
            feedback_type="warning",
            posture_status="unstable",
        )
    return RuleResult(
        feedback="Good clip catch.",
        feedback_type="positive",
        posture_status="stable",
    )


def check_basket_hold(
    hand: HandLandmarks,
    bottle: BottleDetection,
    *,
    threshold: float = BASKET_PROXIMITY,
) -> RuleResult:
    palm = hand.palm_center()
    if palm is None:
        return RuleResult(
            feedback="Open your palm to form a basket hold.",
            feedback_type="warning",
            posture_status="unknown",
        )

    fingertips = [hand.points.get(i) for i in (8, 12, 16, 20)]
    if any(tip is None for tip in fingertips):
        return RuleResult(
            feedback="Keep fingers visible for the basket catch.",
            feedback_type="warning",
            posture_status="unknown",
        )

    bottle_center = bottle.center_normalized(640, 480)
    palm_dist = _dist(bottle_center, palm)
    if palm_dist > threshold:
        return RuleResult(
            feedback="Catch the bottle in a basket hold.",
            feedback_type="warning",
            posture_status="unstable",
        )

    avg_tip_y = sum(tip.y for tip in fingertips if tip is not None) / len(fingertips)
    if bottle_center.y < palm.y - 0.02:
        return RuleResult(
            feedback="Rest the bottle in your cupped palm.",
            feedback_type="warning",
            posture_status="unstable",
        )
    if avg_tip_y < palm.y:
        return RuleResult(
            feedback="Cup your fingers around the bottle base.",
            feedback_type="warning",
            posture_status="unstable",
        )

    return RuleResult(
        feedback="Solid basket hold.",
        feedback_type="positive",
        posture_status="stable",
    )


def update_bottle_history(
    state: Optional[dict],
    bottle: BottleDetection,
    max_frames: int = FLIP_HISTORY_FRAMES,
) -> dict:
    history = list((state or {}).get("bottle_history", []))
    center = bottle.center_normalized(640, 480)
    history.append((center.x, center.y))
    if len(history) > max_frames:
        history = history[-max_frames:]
    return {"bottle_history": history}


def _arc_detected(values: list[float], threshold: float) -> bool:
    if len(values) < 4:
        return False
    mid = len(values) // 2
    first_half = values[:mid]
    second_half = values[mid:]
    if not first_half or not second_half:
        return False
    first_trend = first_half[-1] - first_half[0]
    second_trend = second_half[-1] - second_half[0]
    return abs(first_trend) >= threshold and abs(second_trend) >= threshold and (
        first_trend * second_trend < 0
    )


def detect_vertical_flip(state: dict, *, threshold: float = FLIP_ARC_THRESHOLD) -> bool:
    history = state.get("bottle_history", [])
    if len(history) < 4:
        return False
    ys = [y for _, y in history]
    return _arc_detected(ys, threshold)


def detect_lateral_flip(state: dict, *, threshold: float = FLIP_ARC_THRESHOLD) -> bool:
    history = state.get("bottle_history", [])
    if len(history) < 4:
        return False
    xs = [x for x, _ in history]
    return _arc_detected(xs, threshold)


def detect_tap_pulse(
    state: Optional[dict],
    dist: float,
    *,
    threshold: float = TAP_CONTACT_THRESHOLD,
) -> tuple[dict, bool]:
    current = dict(state or {})
    in_contact = bool(current.get("in_contact", False))
    tap_count = int(current.get("tap_count", 0))
    tapped = False

    if dist <= threshold and not in_contact:
        in_contact = True
    elif dist > threshold and in_contact:
        in_contact = False
        tap_count += 1
        tapped = True

    current["in_contact"] = in_contact
    current["tap_count"] = tap_count
    return current, tapped


def detect_hand_switch(
    state: Optional[dict],
    hands: HandsResult,
    bottle: BottleDetection,
    *,
    threshold: float = HAND_SWITCH_PROXIMITY,
) -> tuple[dict, bool]:
    current = dict(state or {})
    hand, palm = nearest_hand_to_bottle(hands, bottle)
    if hand is None or palm is None:
        return current, False

    dist = bottle_hand_distance(bottle, palm)
    if dist > threshold:
        current["holding_hand"] = None
        return current, False

    active = hand.handedness
    previous = current.get("holding_hand")
    switched = previous is not None and previous != active and active in ("Left", "Right")
    current["holding_hand"] = active
    return current, switched


def torso_midline_x(pose: PoseLandmarks) -> Optional[float]:
    left = pose.get(11)
    right = pose.get(12)
    if left is None or right is None:
        return None
    return (left.x + right.x) / 2.0


def bottle_at_chest_level(
    bottle: BottleDetection,
    pose: PoseLandmarks,
    *,
    margin: float = 0.08,
) -> bool:
    left_shoulder = pose.get(11)
    right_shoulder = pose.get(12)
    left_hip = pose.get(23)
    right_hip = pose.get(24)
    if not all([left_shoulder, right_shoulder, left_hip, right_hip]):
        return False

    shoulder_y = (left_shoulder.y + right_shoulder.y) / 2.0
    hip_y = (left_hip.y + right_hip.y) / 2.0
    bottle_y = bottle.center_normalized(640, 480).y
    return (shoulder_y - margin) <= bottle_y <= (hip_y + margin)


def bottle_near_midline(
    bottle: BottleDetection,
    pose: PoseLandmarks,
    *,
    margin: float = 0.06,
) -> bool:
    midline = torso_midline_x(pose)
    if midline is None:
        return False
    bottle_x = bottle.center_normalized(640, 480).x
    return abs(bottle_x - midline) <= margin


def bottle_elbow_distance(bottle: BottleDetection, pose: PoseLandmarks) -> Optional[float]:
    elbow = dominant_elbow(pose)
    if elbow is None:
        return None
    return bottle_hand_distance(bottle, elbow)


def track_hand_transfer(
    state: Optional[dict],
    hands: HandsResult,
    bottle: BottleDetection,
    pose: Optional[PoseLandmarks],
    *,
    switch_threshold: float = HAND_SWITCH_PROXIMITY,
    require_chest_level: bool = False,
    require_midline: bool = False,
    midline_margin: float = 0.06,
    chest_margin: float = 0.08,
) -> tuple[dict, bool]:
    current, switched = detect_hand_switch(
        state, hands, bottle, threshold=switch_threshold
    )

    if pose is not None:
        if require_chest_level and bottle_at_chest_level(bottle, pose, margin=chest_margin):
            current["at_chest"] = True
        if require_midline and bottle_near_midline(bottle, pose, margin=midline_margin):
            current["crossed_midline"] = True

    return current, switched
