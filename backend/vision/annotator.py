import cv2
import numpy as np

from vision.types import BottleDetection, HandsResult, PoseLandmarks

GREEN = (183, 231, 110)
YELLOW = (107, 183, 255)
CYAN = (255, 200, 90)

# Upper-body pose connections (MediaPipe Pose indices) relevant to stalls.
_POSE_CONNECTIONS = (
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (11, 23),
    (12, 24),
    (23, 24),
)


def annotate_frame(
    frame: np.ndarray,
    bottles: list[BottleDetection] | None,
    hands: HandsResult | None,
    feedback: str,
    feedback_type: str,
    movement: str,
    score: int,
    pose: PoseLandmarks | None = None,
) -> np.ndarray:
    out = frame.copy()

    for bottle in bottles or []:
        cv2.rectangle(out, (bottle.x1, bottle.y1), (bottle.x2, bottle.y2), GREEN, 2)
        cx, cy = int(bottle.center.x), int(bottle.center.y)
        cv2.circle(out, (cx, cy), 4, GREEN, -1)

    if pose is not None:
        h, w = out.shape[:2]
        for a, b in _POSE_CONNECTIONS:
            pa = pose.get(a)
            pb = pose.get(b)
            if pa is None or pb is None:
                continue
            cv2.line(
                out,
                (int(pa.x * w), int(pa.y * h)),
                (int(pb.x * w), int(pb.y * h)),
                CYAN,
                2,
            )
        for idx in (11, 12, 13, 14, 15, 16, 23, 24):
            pt = pose.get(idx)
            if pt is None:
                continue
            cv2.circle(out, (int(pt.x * w), int(pt.y * h)), 4, CYAN, -1)

    if hands is not None:
        h, w = out.shape[:2]
        for hand in hands.hands:
            for pt in hand.points.values():
                cv2.circle(out, (int(pt.x * w), int(pt.y * h)), 2, YELLOW, -1)

    return out
