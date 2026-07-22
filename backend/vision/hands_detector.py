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


def _clockwise_point_to_original(point: Point2D) -> Point2D:
    return Point2D(x=point.y, y=1.0 - point.x)


class HandsDetector:
    def __init__(
        self,
        max_num_hands: int = 2,
        rotated_fallback: bool = False,
    ):
        self._model_path = ensure_hand_model()
        self._max_num_hands = max_num_hands
        self._rotated_fallback = rotated_fallback
        self._landmarker = self._create_landmarker(
            vision.RunningMode.VIDEO
        )
        self._fallback_landmarker: Optional[
            vision.HandLandmarker
        ] = None
        self._timestamp_ms = 0

    def _create_landmarker(
        self,
        running_mode: vision.RunningMode,
    ) -> vision.HandLandmarker:
        options = vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(
                model_asset_path=str(self._model_path)
            ),
            running_mode=running_mode,
            num_hands=self._max_num_hands,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        return vision.HandLandmarker.create_from_options(options)

    @staticmethod
    def _to_mp_image(frame: np.ndarray) -> mp.Image:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        return mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

    @staticmethod
    def _to_hands_result(
        result,
        *,
        rotated: bool = False,
    ) -> Optional[HandsResult]:
        if not result.hand_landmarks:
            return None

        hands: list[HandLandmarks] = []
        handedness = result.handedness or []

        for i, hand_lms in enumerate(result.hand_landmarks):
            label = "Unknown"
            if i < len(handedness) and handedness[i]:
                label = handedness[i][0].category_name

            points: dict[int, Point2D] = {}
            for idx, landmark in enumerate(hand_lms):
                point = Point2D(x=landmark.x, y=landmark.y)
                if rotated:
                    point = _clockwise_point_to_original(point)
                points[idx] = point

            hands.append(HandLandmarks(points=points, handedness=label))

        return HandsResult(hands=hands)

    def _detect_primary(
        self,
        frame: np.ndarray,
    ) -> Optional[HandsResult]:
        self._timestamp_ms += 33
        result = self._landmarker.detect_for_video(
            self._to_mp_image(frame),
            self._timestamp_ms,
        )
        return self._to_hands_result(result)

    def _detect_rotated(
        self,
        frame: np.ndarray,
    ) -> Optional[HandsResult]:
        if self._fallback_landmarker is None:
            self._fallback_landmarker = self._create_landmarker(
                vision.RunningMode.IMAGE
            )

        rotated_frame = cv2.rotate(
            frame,
            cv2.ROTATE_90_CLOCKWISE,
        )
        result = self._fallback_landmarker.detect(
            self._to_mp_image(rotated_frame)
        )
        return self._to_hands_result(result, rotated=True)

    def detect(self, frame: np.ndarray) -> Optional[HandsResult]:
        hands = self._detect_primary(frame)
        if hands is not None or not self._rotated_fallback:
            return hands
        return self._detect_rotated(frame)

    def close(self) -> None:
        self._landmarker.close()
        if self._fallback_landmarker is not None:
            self._fallback_landmarker.close()
