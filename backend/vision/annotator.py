import cv2
import numpy as np

from vision.types import HandsResult, PoseLandmarks, PropDetection

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
    bottles: list[PropDetection] | None,
    hands: HandsResult | None,
    feedback: str,
    feedback_type: str,
    movement: str,
    score: int,
    pose: PoseLandmarks | None = None,
    prop_label: str = "Bottle",
) -> np.ndarray:
    out = frame.copy()

    for prop in bottles or []:
        cv2.rectangle(out, (prop.x1, prop.y1), (prop.x2, prop.y2), GREEN, 2)
        cx, cy = int(prop.center.x), int(prop.center.y)
        cv2.circle(out, (cx, cy), 4, GREEN, -1)
        cv2.putText(
            out,
            prop_label,
            (prop.x1, max(16, prop.y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            GREEN,
            1,
            cv2.LINE_AA,
        )

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
