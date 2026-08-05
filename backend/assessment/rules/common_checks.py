import math
from typing import Optional

from config import (
    HAND_BOTTLE_PROXIMITY,
    PINCH_DISTANCE,
    SHOULDER_ABOVE_OFFSET,
    STALL_HISTORY_FRAMES,
    STALL_PROXIMITY,
    STALL_STABILITY_THRESHOLD,
    UPPER_FOREARM_RATIO,
    DOUBLE_HAND_OPEN_PALM_EXTENSION_RATIO,
    DOUBLE_HAND_MIN_EXTENDED_FINGERS,
)
from assessment.feedback_codes import FeedbackCode
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


def _prop_name(prop_label: str) -> str:
    return prop_label.strip() or "prop"


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


def pose_upper_forearm_landmarks(
    pose: Optional[PoseLandmarks],
    bottle: BottleDetection,
    *,
    ratio: float = UPPER_FOREARM_RATIO,
) -> Optional[tuple[Point2D, Point2D, Point2D, Point2D]]:
    """Nearest-arm elbow, upper-forearm target, mid-forearm, and wrist.

    The upper-forearm target is ``ratio`` of the way from elbow toward wrist
    (expected ~0.25–0.40), keeping the point distinct from the elbow joint and
    the ordinary 50% forearm midpoint used by Forearm Stall.
    """
    if pose is None:
        return None
    bottle_center = bottle.center_normalized(640, 480)
    best: Optional[tuple[Point2D, Point2D, Point2D, Point2D]] = None
    best_dist = float("inf")
    for elbow_i, wrist_i in ((13, 15), (14, 16)):
        elbow = pose.get(elbow_i)
        wrist = pose.get(wrist_i)
        if elbow is None or wrist is None:
            continue
        upper = Point2D(
            x=elbow.x + (wrist.x - elbow.x) * ratio,
            y=elbow.y + (wrist.y - elbow.y) * ratio,
        )
        mid = Point2D(
            x=(elbow.x + wrist.x) / 2.0,
            y=(elbow.y + wrist.y) / 2.0,
        )
        dist = _dist(upper, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best = (elbow, upper, mid, wrist)
    return best


def pose_upper_forearm_point(
    pose: Optional[PoseLandmarks],
    bottle: BottleDetection,
    *,
    ratio: float = UPPER_FOREARM_RATIO,
) -> Optional[Point2D]:
    """Upper-forearm stall point on the arm nearest the bottle."""
    landmarks = pose_upper_forearm_landmarks(pose, bottle, ratio=ratio)
    if landmarks is None:
        return None
    return landmarks[1]


def pose_shoulder_point(
    pose: Optional[PoseLandmarks],
    bottle: BottleDetection,
    *,
    above_offset: float = SHOULDER_ABOVE_OFFSET,
) -> Optional[Point2D]:
    """Expected bottle rest point slightly above the nearest visible shoulder.

    MediaPipe Pose shoulders: 11 (left), 12 (right). Image y increases downward,
    so "above" means a smaller y than the shoulder joint.
    """
    if pose is None:
        return None
    bottle_center = bottle.center_normalized(640, 480)
    best_shoulder: Optional[Point2D] = None
    best_dist = float("inf")
    for index in (11, 12):
        shoulder = pose.get(index)
        if shoulder is None:
            continue
        dist = _dist(shoulder, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best_shoulder = shoulder
    if best_shoulder is None:
        return None
    return Point2D(x=best_shoulder.x, y=best_shoulder.y - above_offset)


def pose_nearest_shoulder(
    pose: Optional[PoseLandmarks], bottle: BottleDetection
) -> Optional[Point2D]:
    """Nearest visible shoulder joint (without the above-offset target)."""
    if pose is None:
        return None
    bottle_center = bottle.center_normalized(640, 480)
    best: Optional[Point2D] = None
    best_dist = float("inf")
    for index in (11, 12):
        shoulder = pose.get(index)
        if shoulder is None:
            continue
        dist = _dist(shoulder, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best = shoulder
    return best


def check_bottle_visible(
    bottle: Optional[BottleDetection],
    *,
    prop_label: str = "Bottle",
) -> Optional[RuleResult]:
    if bottle is None:
        prop_name = _prop_name(prop_label)
        return RuleResult(
            feedback=f"{prop_name} not detected. Keep the {prop_name.lower()} visible.",
            feedback_type="error",
            posture_status="unknown",
            feedback_code=FeedbackCode.PROP_NOT_DETECTED.value,
        )
    return None


def check_hands_visible(hands: Optional[HandsResult]) -> Optional[RuleResult]:
    if hands is None or not hands.hands:
        return RuleResult(
            feedback="Hand not detected. Keep your hand in frame.",
            feedback_type="warning",
            posture_status="unknown",
            feedback_code=FeedbackCode.HAND_NOT_VISIBLE.value,
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
    prop_label: str = "Bottle",
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
        prop_name = _prop_name(prop_label)
        return RuleResult(
            feedback=f"Align the {prop_name.lower()} over the stall point.",
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


def visible_palm_centers(
    hands: Optional[HandsResult],
) -> list[Point2D]:
    """Return palm centers for hands with usable wrist + middle-MCP landmarks.

    Order follows the MediaPipe hand list and must not be treated as Left/Right.
    Hands missing landmarks required by ``palm_center()`` are skipped.
    """
    if hands is None or not hands.hands:
        return []
    palms: list[Point2D] = []
    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        palms.append(palm)
    return palms


def usable_hands_with_palms(
    hands: Optional[HandsResult],
) -> list[tuple[HandLandmarks, Point2D]]:
    """Hands that have a usable palm center, preserving MediaPipe list order."""
    if hands is None or not hands.hands:
        return []
    usable: list[tuple[HandLandmarks, Point2D]] = []
    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        usable.append((hand, palm))
    return usable


def is_open_palm(
    hand: HandLandmarks,
    *,
    extension_ratio: float = DOUBLE_HAND_OPEN_PALM_EXTENSION_RATIO,
    min_extended: int = DOUBLE_HAND_MIN_EXTENDED_FINGERS,
) -> bool:
    """Rotation-tolerant open-palm check via wrist-to-tip vs wrist-to-MCP.

    Uses index, middle, ring, and pinky. A finger counts as extended when the
    wrist-to-tip distance is at least ``extension_ratio`` times the wrist-to-MCP
    distance. Requires at least ``min_extended`` extended fingers.
    """
    wrist = hand.points.get(0)
    if wrist is None:
        return False

    extended = 0
    for mcp_index, tip_index in ((5, 8), (9, 12), (13, 16), (17, 20)):
        mcp = hand.points.get(mcp_index)
        tip = hand.points.get(tip_index)
        if mcp is None or tip is None:
            continue
        wrist_to_mcp = _dist(wrist, mcp)
        if wrist_to_mcp < 1e-6:
            continue
        wrist_to_tip = _dist(wrist, tip)
        if wrist_to_tip >= extension_ratio * wrist_to_mcp:
            extended += 1
    return extended >= min_extended


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
