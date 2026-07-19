import math
from typing import Optional

from config import (
    BASKET_PROXIMITY,
    HAND_BOTTLE_PROXIMITY,
    PINCH_DISTANCE,
    STALL_HISTORY_FRAMES,
    STALL_PROXIMITY,
    STALL_STABILITY_THRESHOLD,
    TAP_CONTACT_THRESHOLD,
)
from assessment.rules.base import RuleResult
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _nearest_pose_point(
    pose: Optional[PoseLandmarks],
    indices: tuple[int, ...],
    bottle: BottleDetection,
) -> Optional[Point2D]:
    if pose is None:
        return None
    bottle_center = bottle.center_normalized(640, 480)
    best: Optional[Point2D] = None
    best_dist = float("inf")
    for i in indices:
        point = pose.get(i)
        if point is None:
            continue
        dist = _dist(point, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best = point
    return best


def pose_wrist_point(
    pose: Optional[PoseLandmarks], bottle: BottleDetection
) -> Optional[Point2D]:
    # MediaPipe Pose wrists: 15 (left), 16 (right).
    return _nearest_pose_point(pose, (15, 16), bottle)


def pose_elbow_point(
    pose: Optional[PoseLandmarks], bottle: BottleDetection
) -> Optional[Point2D]:
    # MediaPipe Pose elbows: 13 (left), 14 (right).
    return _nearest_pose_point(pose, (13, 14), bottle)


def pose_forearm_point(
    pose: Optional[PoseLandmarks], bottle: BottleDetection
) -> Optional[Point2D]:
    """Midpoint of the elbow-wrist segment of whichever arm is nearest the bottle."""
    if pose is None:
        return None
    bottle_center = bottle.center_normalized(640, 480)
    best: Optional[Point2D] = None
    best_dist = float("inf")
    for elbow_i, wrist_i in ((13, 15), (14, 16)):
        elbow = pose.get(elbow_i)
        wrist = pose.get(wrist_i)
        if elbow is None or wrist is None:
            continue
        mid = Point2D(x=(elbow.x + wrist.x) / 2.0, y=(elbow.y + wrist.y) / 2.0)
        dist = _dist(mid, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best = mid
    return best


def check_bottle_visible(bottle: Optional[BottleDetection]) -> Optional[RuleResult]:
    if bottle is None:
        return RuleResult(
            feedback="Bottle not detected. Keep the bottle visible.",
            feedback_type="error",
            posture_status="unknown",
        )
    return None


def check_hands_visible(hands: Optional[HandsResult]) -> Optional[RuleResult]:
    if hands is None or not hands.hands:
        return RuleResult(
            feedback="Hand not detected. Keep your hand in frame.",
            feedback_type="warning",
            posture_status="unknown",
        )
    return None


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
    threshold: float = STALL_PROXIMITY,
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
            feedback="Align the bottle over the stall point.",
            feedback_type="warning",
            posture_status="unstable",
        )
    return RuleResult(
        feedback=success_message,
        feedback_type="positive",
        posture_status="stable",
    )


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


def track_bottle_stability(
    state: Optional[dict],
    bottle: BottleDetection,
    *,
    max_frames: int = STALL_HISTORY_FRAMES,
    threshold: float = STALL_STABILITY_THRESHOLD,
) -> tuple[dict, bool]:
    """Track recent bottle centers and report whether it is holding steady."""
    current = dict(state or {})
    history = list(current.get("bottle_history", []))
    center = bottle.center_normalized(640, 480)
    history.append((center.x, center.y))
    if len(history) > max_frames:
        history = history[-max_frames:]
    current["bottle_history"] = history

    if len(history) < 4:
        return current, True

    xs = [p[0] for p in history]
    ys = [p[1] for p in history]
    spread = max(max(xs) - min(xs), max(ys) - min(ys))
    return current, spread <= threshold


def check_pinch_grip(
    hand: HandLandmarks,
    bottle: BottleDetection,
    *,
    threshold: float = PINCH_DISTANCE,
    success_message: str = "Good pinch grip.",
) -> RuleResult:
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if thumb is None or index is None:
        return RuleResult(
            feedback="Keep thumb and index finger visible.",
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
        feedback=success_message,
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
