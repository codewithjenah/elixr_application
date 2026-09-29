import logging
import time
from dataclasses import dataclass
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


@dataclass(frozen=True)
class HandsIndependentResult:
    """Current-frame hands before optional prop-dependent ROI recovery."""

    hands: Optional[HandsResult]
    rotated_attempted: bool
    rotated_recovered: bool


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


_DUPLICATE_PALM_DIST = 0.05


def _anchor(hand: HandLandmarks) -> Optional[Point2D]:
    palm = hand.palm_center()
    if palm is not None:
        return palm
    if not hand.points:
        return None
    return hand.points[min(hand.points)]


def _is_same_hand(a: HandLandmarks, b: HandLandmarks) -> bool:
    """Known equal handedness or co-located palms mean one physical hand."""
    known = {"Left", "Right"}
    if a.handedness in known and a.handedness == b.handedness:
        return True
    pa, pb = _anchor(a), _anchor(b)
    if pa is None or pb is None:
        return False
    dist = ((pa.x - pb.x) ** 2 + (pa.y - pb.y) ** 2) ** 0.5
    return dist <= _DUPLICATE_PALM_DIST


def _merge_hands(
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
    *,
    max_num_hands: int,
    fill_missing_only: bool = False,
) -> Optional[HandsResult]:
    if recovered is None or not recovered.hands:
        return primary

    primary_hands = [] if primary is None else primary.hands
    if not fill_missing_only:
        # Official Bartender recovery: an in-zone ROI hand may replace an
        # out-of-zone primary hand when capacity is full.
        merged = (recovered.hands + primary_hands)[:max_num_hands]
        return HandsResult(hands=merged)

    # Generic custom recovery: keep primary hands and add only distinct
    # current-frame ROI hands into the missing capacity.
    merged = list(primary_hands)[:max_num_hands]
    for hand in recovered.hands:
        if len(merged) >= max_num_hands:
            break
        if not hand.points or any(_is_same_hand(hand, kept) for kept in merged):
            continue
        merged.append(hand)
    return HandsResult(hands=merged)


class HandsDetector:
    uses_capture_timestamps = True

    def __init__(
        self,
        max_num_hands: int = 2,
        rotated_fallback: bool = False,
        bartender_roi_fallback: bool = False,
        timestamp_clock: Optional[HandsTimestampClock] = None,
        roi_only_when_below_capacity: bool = False,
        rotated_min_consecutive_misses: int = 1,
        rotated_sustained_interval: int = 1,
    ):
        self._model_path = ensure_hand_model()
        self._max_num_hands = max_num_hands
        self._rotated_fallback = rotated_fallback
        self._bartender_roi_fallback = bartender_roi_fallback
        self._roi_only_when_below_capacity = roi_only_when_below_capacity
        self._roi_skip_next = False
        self._rotated_min_consecutive_misses = max(1, rotated_min_consecutive_misses)
        self._rotated_sustained_interval = max(1, rotated_sustained_interval)
        self._primary_miss_streak = 0
        # Production VIDEO timestamps follow the actual captured-frame clock.
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
                # MediaPipe labels assume a mirrored selfie image. Detection
                # receives raw OpenCV frames; Flutter mirrors only its view.
                # Normalize once here for both capture and assessment.
                label = {"Left": "Right", "Right": "Left"}.get(label, label)

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
        independent = self.detect_independent(
            frame, captured_at_monotonic=captured_at_monotonic
        )
        return self.finish_with_prop(frame, independent, bottle)

    def detect_independent(
        self,
        frame: np.ndarray,
        *,
        captured_at_monotonic: Optional[float] = None,
    ) -> HandsIndependentResult:
        """Run VIDEO and rotated recovery without waiting for this frame's prop."""
        stats = self.stats
        stats.detect_calls += 1
        self._pending_captured_at = captured_at_monotonic

        t0 = time.perf_counter()
        hands = self._detect_primary(frame)
        stats.record_primary(time.perf_counter() - t0)
        stats.record_primary_outcome(
            hands is not None and bool(hands.hands)
        )
        if hands is None:
            self._primary_miss_streak = (
                getattr(self, "_primary_miss_streak", 0) + 1
            )
        else:
            self._primary_miss_streak = 0

        rotated_recovered = False
        rotated_attempted = False
        if hands is None and self._rotated_fallback and self._rotated_gate_open(stats):
            t0 = time.perf_counter()
            hands = self._detect_rotated(frame)
            stats.record_rotated(time.perf_counter() - t0)
            rotated_attempted = True
            rotated_recovered = hands is not None and bool(hands.hands)
            stats.record_rotated_outcome(rotated_recovered)

        return HandsIndependentResult(hands, rotated_attempted, rotated_recovered)

    def _rotated_gate_open(self, stats: HandsCallStats) -> bool:
        """Custom gate: rotate only after N consecutive primary misses, then
        every `interval` misses. Skipped frames return current-frame None;
        no earlier rotated result is carried forward. Defaults (1, 1) keep
        the immediate official behavior."""
        min_misses = getattr(self, "_rotated_min_consecutive_misses", 1)
        interval = getattr(self, "_rotated_sustained_interval", 1)
        streak = getattr(self, "_primary_miss_streak", 1)
        if streak >= min_misses and (streak - min_misses) % interval == 0:
            return True
        stats.record_rotated_gate_skip()
        return False

    def finish_with_prop(
        self,
        frame: np.ndarray,
        independent: HandsIndependentResult,
        bottle: Optional[BottleDetection],
    ) -> Optional[HandsResult]:
        """Optionally recover a hand near the current prop; never rerun VIDEO/Pose."""
        stats = self.stats
        hands = independent.hands
        fallback_used = independent.rotated_attempted
        rotated_recovered = independent.rotated_recovered

        if (
            not self._bartender_roi_fallback
            or bottle is None
            or (
                getattr(self, "_roi_only_when_below_capacity", False)
                and hands is not None
                and len(hands.hands) >= self._max_num_hands
                and all(hand.points for hand in hands.hands)
            )
        ):
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

        fill_missing_only = bool(
            getattr(self, "_roi_only_when_below_capacity", False)
        )
        if fill_missing_only and getattr(self, "_roi_skip_next", False):
            # Custom cooldown: after a wasted ROI attempt, skip one eligible
            # frame (CooldownRoiPolicy). Output stays current-frame primary.
            self._roi_skip_next = False
            stats.record_roi_cooldown_skip()
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
            fill_missing_only=fill_missing_only,
        )
        if fill_missing_only:
            before = 0 if hands is None else len(hands.hands)
            after = 0 if merged is None else len(merged.hands)
            self._roi_skip_next = after <= before
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

    @property
    def requires_current_prop(self) -> bool:
        """Whether detect() may consume current-frame prop geometry."""
        return self._bartender_roi_fallback

    def close(self) -> None:
        self._landmarker.close()
        if self._fallback_landmarker is not None:
            self._fallback_landmarker.close()
        self.timestamp_clock.reset()
        self._timestamp_ms = int(
            getattr(self.timestamp_clock, "last_timestamp_ms", 0) or 0
        )
        self._pending_captured_at = None
