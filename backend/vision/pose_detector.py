import logging
import math
from dataclasses import dataclass
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


@dataclass(frozen=True)
class PosePersonCandidate:
    """Visible torso anchors from one current-frame MediaPipe candidate."""

    shoulders: tuple[float, float, float] | None = None
    hips: tuple[float, float, float] | None = None


def distinct_person_count(candidates: tuple[PosePersonCandidate, ...]) -> int:
    """Count bodies only when corresponding torso anchors separate them.

    Distances are normalized to image width/height; the width term scales the
    separation test with the apparent body size. Incomparable pairs are
    ambiguous and must not certify either one or two performers.
    """
    valid = [
        candidate for candidate in candidates
        if candidate.shoulders is not None or candidate.hips is not None
    ]
    # An extra unanchored pose could be a partly occluded second person.
    # It cannot certify single-person readiness, but also cannot reject a
    # recording as multiple people without spatial evidence.
    if len(valid) != len(candidates):
        return 0
    if len(valid) <= 1:
        return len(valid)
    first, second = valid[:2]
    comparable = [
        (a, b)
        for a, b in (
            (first.shoulders, second.shoulders),
            (first.hips, second.hips),
        )
        if a is not None and b is not None
    ]
    if not comparable:
        return 0
    # Normalize against apparent shoulder/hip width. The narrow uncertain
    # band returns zero: it must neither reject a reference as two people nor
    # certify a reference as one person from weakly separated candidates.
    separation = [
        (
            math.hypot(a[0] - b[0], a[1] - b[1]),
            max(a[2], b[2]),
        )
        for a, b in comparable
    ]
    if all(distance <= max(0.035, 0.35 * width) for distance, width in separation):
        return 1
    if all(distance > max(0.08, 0.45 * width) for distance, width in separation):
        return 2
    return 0


def _candidate(landmarks) -> PosePersonCandidate:
    def anchor(left: int, right: int) -> tuple[float, float, float] | None:
        if len(landmarks) <= right:
            return None
        a, b = landmarks[left], landmarks[right]
        if (
            float(getattr(a, "visibility", 1.0) or 0.0) < 0.5
            or float(getattr(b, "visibility", 1.0) or 0.0) < 0.5
        ):
            return None
        return ((a.x + b.x) / 2, (a.y + b.y) / 2, abs(a.x - b.x))

    return PosePersonCandidate(shoulders=anchor(11, 12), hips=anchor(23, 24))


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
        self.last_person_candidates: tuple[PosePersonCandidate, ...] = ()
        self.last_distinct_person_count = 0

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
        self.last_person_candidates = tuple(
            _candidate(item) for item in result.pose_landmarks
        )
        self.last_distinct_person_count = distinct_person_count(
            self.last_person_candidates
        )
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
