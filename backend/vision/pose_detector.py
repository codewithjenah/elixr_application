import logging
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from vision.model_assets import ensure_pose_model
from vision.types import Point2D, PoseLandmarks

logger = logging.getLogger(__name__)

POSE_LANDMARK_INDICES = (
    11,  # left shoulder
    12,  # right shoulder
    13,  # left elbow
    14,  # right elbow
    15,  # left wrist
    16,  # right wrist
    23,  # left hip
    24,  # right hip
    25,  # left knee
    26,  # right knee
    27,  # left ankle
    28,  # right ankle
)


class PoseDetector:
    def __init__(self):
        model_path = ensure_pose_model()
        options = vision.PoseLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self._landmarker = vision.PoseLandmarker.create_from_options(options)
        self._timestamp_ms = 0

    def detect(self, frame: np.ndarray) -> Optional[PoseLandmarks]:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        self._timestamp_ms += 33
        result = self._landmarker.detect_for_video(mp_image, self._timestamp_ms)
        if not result.pose_landmarks:
            return None

        points: dict[int, Point2D] = {}
        visibility: dict[int, float] = {}
        landmarks = result.pose_landmarks[0]

        for idx in POSE_LANDMARK_INDICES:
            lm = landmarks[idx]
            points[idx] = Point2D(x=lm.x, y=lm.y)
            visibility[idx] = getattr(lm, "visibility", getattr(lm, "presence", 1.0))

        return PoseLandmarks(points=points, visibility=visibility)

    def close(self) -> None:
        self._landmarker.close()
