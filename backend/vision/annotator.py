import cv2
import numpy as np

from vision.types import BottleDetection, HandsResult, PoseLandmarks

POSE_CONNECTIONS = (
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (11, 12),
    (23, 24),
    (11, 23),
    (12, 24),
    (23, 25),
    (25, 27),
    (24, 26),
    (26, 28),
)

PINK = (141, 77, 255)
GREEN = (183, 231, 110)
YELLOW = (107, 183, 255)
RED = (107, 107, 255)
WHITE = (245, 245, 245)


def annotate_frame(
    frame: np.ndarray,
    bottle: BottleDetection | None,
    pose: PoseLandmarks | None,
    hands: HandsResult | None,
    feedback: str,
    feedback_type: str,
    movement: str,
    score: int,
) -> np.ndarray:
    out = frame.copy()

    if bottle is not None:
        cv2.rectangle(out, (bottle.x1, bottle.y1), (bottle.x2, bottle.y2), GREEN, 2)
        cx, cy = int(bottle.center.x), int(bottle.center.y)
        cv2.circle(out, (cx, cy), 4, GREEN, -1)

    if pose is not None:
        h, w = out.shape[:2]
        for a, b in POSE_CONNECTIONS:
            pa = pose.get(a, min_visibility=0.3)
            pb = pose.get(b, min_visibility=0.3)
            if pa is None or pb is None:
                continue
            cv2.line(
                out,
                (int(pa.x * w), int(pa.y * h)),
                (int(pb.x * w), int(pb.y * h)),
                PINK,
                2,
            )
        for idx, pt in pose.points.items():
            if pose.visibility.get(idx, 0) < 0.3:
                continue
            cv2.circle(out, (int(pt.x * w), int(pt.y * h)), 3, PINK, -1)

    if hands is not None:
        h, w = out.shape[:2]
        for hand in hands.hands:
            for pt in hand.points.values():
                cv2.circle(out, (int(pt.x * w), int(pt.y * h)), 2, YELLOW, -1)

    return out
