import logging
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from vision.model_assets import ensure_pose_model
from vision.hands_timestamp import VideoTimestampClock
from vision.types import Point2D, PoseLandmarks

logger = logging.getLogger(__name__)


class PoseDetector:
    uses_capture_timestamps = True

    def __init__(self, *, max_poses: int = 1):
        if max_poses not in (1, 2):
            raise ValueError("max_poses must be 1 or 2")
        model_path = ensure_pose_model()
        options = vision.PoseLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=max_poses,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self._landmarker = vision.PoseLandmarker.create_from_options(options)
        self._timestamp_clock = VideoTimestampClock()
        self._timestamp_clock.reset()
        self.last_person_count = 0

    def detect(
        self,
        frame: np.ndarray,
        *,
        captured_at_monotonic: float | None = None,
    ) -> Optional[PoseLandmarks]:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        timestamp_ms = self._timestamp_clock.next_ms(captured_at_monotonic)
        result = self._landmarker.detect_for_video(mp_image, timestamp_ms)
        self.last_person_count = len(result.pose_landmarks)
        if not result.pose_landmarks:
            return None

        landmarks = result.pose_landmarks[0]
        points: dict[int, Point2D] = {}
        visibility: dict[int, float] = {}
        for idx, lm in enumerate(landmarks):
            points[idx] = Point2D(x=lm.x, y=lm.y)
            visibility[idx] = float(getattr(lm, "visibility", 1.0) or 0.0)

        return PoseLandmarks(points=points, visibility=visibility)

    def close(self) -> None:
        self._landmarker.close()
        self._timestamp_clock.reset()
