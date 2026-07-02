import logging
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from vision.model_assets import ensure_hand_model
from vision.types import HandLandmarks, HandsResult, Point2D

logger = logging.getLogger(__name__)


class HandsDetector:
    def __init__(self, max_num_hands: int = 2):
        model_path = ensure_hand_model()
        options = vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=max_num_hands,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self._landmarker = vision.HandLandmarker.create_from_options(options)
        self._timestamp_ms = 0

    def detect(self, frame: np.ndarray) -> Optional[HandsResult]:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        self._timestamp_ms += 33
        result = self._landmarker.detect_for_video(mp_image, self._timestamp_ms)
        if not result.hand_landmarks:
            return None

        hands: list[HandLandmarks] = []
        handedness = result.handedness or []

        for i, hand_lms in enumerate(result.hand_landmarks):
            label = "Unknown"
            if i < len(handedness) and handedness[i]:
                label = handedness[i][0].category_name

            points: dict[int, Point2D] = {}
            for idx, lm in enumerate(hand_lms):
                points[idx] = Point2D(x=lm.x, y=lm.y)

            hands.append(HandLandmarks(points=points, handedness=label))

        return HandsResult(hands=hands)

    def close(self) -> None:
        self._landmarker.close()
