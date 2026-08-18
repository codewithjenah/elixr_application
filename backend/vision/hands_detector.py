import logging
import time
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from vision.hands_diagnostics import HandsCallStats
from vision.hands_timestamp import (
    HandsTimestampClock,
    default_timestamp_clock,
)
from vision.grip_geometry import (
    BARTENDER_CONTACT_BOTTOM_FRACTION,
    bartender_contact_zone,
    bartender_control_point,
    point_in_zone,
)
from vision.model_assets import ensure_hand_model
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
)

logger = logging.getLogger(__name__)

_BARTENDER_CROP_WIDTH_FACTOR = 2.5
_BARTENDER_CROP_TOP_FRACTION = 0.05
_BARTENDER_CROP_BOTTOM_FRACTION = 0.65

CropBounds = tuple[int, int, int, int]


def _clockwise_point_to_original(point: Point2D) -> Point2D:
    return Point2D(x=point.y, y=1.0 - point.x)


def _counterclockwise_point_to_original(
    point: Point2D,
) -> Point2D:
    return Point2D(x=1.0 - point.y, y=point.x)


def _counterclockwise_crop_point_to_frame(
    point: Point2D,
    bounds: CropBounds,
    *,
    frame_width: int,
    frame_height: int,
) -> Point2D:
    left, top, right, bottom = bounds
    crop_point = _counterclockwise_point_to_original(point)
    return Point2D(
        x=(
            left + crop_point.x * (right - left)
        ) / frame_width,
        y=(
            top + crop_point.y * (bottom - top)
        ) / frame_height,
    )


def _has_bartender_candidate(
    hands: Optional[HandsResult],
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> bool:
    if hands is None:
        return False

    zone = bartender_contact_zone(
        bottle,
        frame_width=frame_width,
        frame_height=frame_height,
        bottom_fraction=BARTENDER_CONTACT_BOTTOM_FRACTION,
    )
    return any(
        control is not None and point_in_zone(control, zone)
        for hand in hands.hands
        for control in [bartender_control_point(hand)]
    )


def _bartender_crop_bounds(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> Optional[CropBounds]:
    bottle_width = bottle.x2 - bottle.x1
    bottle_height = bottle.y2 - bottle.y1
    if bottle_width <= 0 or bottle_height <= 0:
        return None

    center_x = (bottle.x1 + bottle.x2) / 2.0
    crop_width = bottle_width * _BARTENDER_CROP_WIDTH_FACTOR
    left = max(0, round(center_x - crop_width / 2.0))
    right = min(
        frame_width,
        round(center_x + crop_width / 2.0),
    )
    top = max(
        0,
        round(
            bottle.y1
            - bottle_height * _BARTENDER_CROP_TOP_FRACTION
        ),
    )
    bottom = min(
        frame_height,
        round(
            bottle.y1
            + bottle_height * _BARTENDER_CROP_BOTTOM_FRACTION
        ),
    )

    if right <= left or bottom <= top:
        return None
    return left, top, right, bottom


def _merge_hands(
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
    *,
    max_num_hands: int,
) -> Optional[HandsResult]:
    if recovered is None or not recovered.hands:
        return primary

    primary_hands = [] if primary is None else primary.hands
    merged = (recovered.hands + primary_hands)[:max_num_hands]
    return HandsResult(hands=merged)


class HandsDetector:
    def __init__(
        self,
        max_num_hands: int = 2,
        rotated_fallback: bool = False,
        bartender_roi_fallback: bool = False,
        timestamp_clock: Optional[HandsTimestampClock] = None,
    ):
        self._model_path = ensure_hand_model()
        self._max_num_hands = max_num_hands
        self._rotated_fallback = rotated_fallback
        self._bartender_roi_fallback = bartender_roi_fallback
        # None keeps production VIDEO timestamps at previous + 33 ms.
        self.timestamp_clock = default_timestamp_clock(timestamp_clock)
        self.timestamp_clock.reset()
        self._landmarker = self._create_landmarker(
            vision.RunningMode.VIDEO
        )
        self._fallback_landmarker: Optional[
            vision.HandLandmarker
        ] = None
        self._timestamp_ms = int(
            getattr(self.timestamp_clock, "last_timestamp_ms", 0) or 0
        )
        self._pending_captured_at: Optional[float] = None
        self._hands_stats = HandsCallStats()

    @property
    def max_num_hands(self) -> int:
        return self._max_num_hands

    @property
    def stats(self) -> HandsCallStats:
        existing = getattr(self, "_hands_stats", None)
        if not isinstance(existing, HandsCallStats):
            existing = HandsCallStats()
            self._hands_stats = existing
        return existing

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

    def _image_landmarker(self) -> vision.HandLandmarker:
        if self._fallback_landmarker is None:
            self._fallback_landmarker = self._create_landmarker(
                vision.RunningMode.IMAGE
            )
        return self._fallback_landmarker

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
        self._timestamp_ms = self.timestamp_clock.next_ms(
            self._pending_captured_at
        )
        result = self._landmarker.detect_for_video(
            self._to_mp_image(frame),
            self._timestamp_ms,
        )
        return self._to_hands_result(result)

    def _detect_rotated(
        self,
        frame: np.ndarray,
    ) -> Optional[HandsResult]:
        rotated_frame = cv2.rotate(
            frame,
            cv2.ROTATE_90_CLOCKWISE,
        )
        result = self._image_landmarker().detect(
            self._to_mp_image(rotated_frame)
        )
        return self._to_hands_result(result, rotated=True)

    def _detect_bartender_roi(
        self,
        frame: np.ndarray,
        bottle: BottleDetection,
    ) -> Optional[HandsResult]:
        frame_height, frame_width = frame.shape[:2]
        bounds = _bartender_crop_bounds(
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
        if bounds is None:
            return None

        left, top, right, bottom = bounds
        crop = frame[top:bottom, left:right]
        if crop.size == 0:
            return None

        rotated_crop = cv2.rotate(
            crop,
            cv2.ROTATE_90_COUNTERCLOCKWISE,
        )
        self.stats.bartender_roi_image_calls += 1
        raw_result = self._image_landmarker().detect(
            self._to_mp_image(rotated_crop)
        )
        crop_hands = self._to_hands_result(raw_result)
        if crop_hands is None:
            return None

        restored: list[HandLandmarks] = []
        for hand in crop_hands.hands:
            points = {
                index: _counterclockwise_crop_point_to_frame(
                    point,
                    bounds,
                    frame_width=frame_width,
                    frame_height=frame_height,
                )
                for index, point in hand.points.items()
            }
            restored.append(
                HandLandmarks(
                    points=points,
                    handedness=hand.handedness,
                )
            )

        return HandsResult(hands=restored)

    def detect(
        self,
        frame: np.ndarray,
        bottle: Optional[BottleDetection] = None,
        *,
        captured_at_monotonic: Optional[float] = None,
    ) -> Optional[HandsResult]:
        stats = self.stats
        stats.detect_calls += 1
        fallback_used = False
        self._pending_captured_at = captured_at_monotonic

        t0 = time.perf_counter()
        hands = self._detect_primary(frame)
        stats.record_primary(time.perf_counter() - t0)
        stats.record_primary_outcome(
            hands is not None and bool(hands.hands)
        )

        rotated_recovered = False
        if hands is None and self._rotated_fallback:
            t0 = time.perf_counter()
            hands = self._detect_rotated(frame)
            stats.record_rotated(time.perf_counter() - t0)
            fallback_used = True
            rotated_recovered = hands is not None and bool(hands.hands)
            stats.record_rotated_outcome(rotated_recovered)

        if not self._bartender_roi_fallback or bottle is None:
            if fallback_used:
                stats.mark_fallback_activated()
                stats.record_fallback_frame(
                    attempted=True,
                    recovered=rotated_recovered,
                )
            return hands

        frame_height, frame_width = frame.shape[:2]
        if _has_bartender_candidate(
            hands,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        ):
            if fallback_used:
                stats.mark_fallback_activated()
                stats.record_fallback_frame(
                    attempted=True,
                    recovered=rotated_recovered,
                )
            return hands

        t0 = time.perf_counter()
        recovered = self._detect_bartender_roi(frame, bottle)
        stats.record_bartender_roi(
            time.perf_counter() - t0,
            ran_image=False,
        )
        fallback_used = True
        merged = _merge_hands(
            hands,
            recovered,
            max_num_hands=self._max_num_hands,
        )
        bartender_recovered = _has_bartender_candidate(
            merged,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
        stats.record_bartender_outcome(bartender_recovered)
        stats.mark_fallback_activated()
        stats.record_fallback_frame(
            attempted=True,
            recovered=rotated_recovered or bartender_recovered,
        )
        return merged

    def close(self) -> None:
        self._landmarker.close()
        if self._fallback_landmarker is not None:
            self._fallback_landmarker.close()
        self.timestamp_clock.reset()
        self._timestamp_ms = int(
            getattr(self.timestamp_clock, "last_timestamp_ms", 0) or 0
        )
        self._pending_captured_at = None
