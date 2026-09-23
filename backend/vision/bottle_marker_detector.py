"""Directed bottle orientation from orange neck and yellow base tape.

Only a current, YOLO-confirmed bottle box may authorize this ROI operation.
The caller owns bottle identity; colors never create a prop detection.
"""

from __future__ import annotations

import time

import cv2
import numpy as np

from config import (
    MARKER_MAX_BLOB_AREA_RATIO,
    MARKER_MIN_BLOB_AREA_RATIO,
    MARKER_MIN_SATURATION,
    MARKER_MIN_SEPARATION_RATIO,
    MARKER_MIN_VALUE,
    MARKER_ORANGE_HUE,
    MARKER_YELLOW_HUE,
    YOLO_BOTTLE_CONFIDENCE,
)
from vision.bottle_orientation import BottleKeypoint, BottleOrientation
from vision.types import PropDetection


class BottleMarkerDetector:
    provider = "color_markers"
    available = True

    def __init__(self) -> None:
        self.last_inference_ms = 0.0

    def ensure_ready(self) -> None:
        pass

    def close(self) -> None:
        pass

    @staticmethod
    def _candidate(hsv: np.ndarray, hue: tuple[int, int]) -> tuple[float, float, float] | None:
        mask = cv2.inRange(
            hsv,
            (hue[0], MARKER_MIN_SATURATION, MARKER_MIN_VALUE),
            (hue[1], 255, 255),
        )
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
        roi_area = hsv.shape[0] * hsv.shape[1]
        candidates = []
        for index in range(1, count):
            area = int(stats[index, cv2.CC_STAT_AREA])
            ratio = area / roi_area
            if ratio > MARKER_MAX_BLOB_AREA_RATIO:
                return None
            if not MARKER_MIN_BLOB_AREA_RATIO <= ratio <= MARKER_MAX_BLOB_AREA_RATIO:
                continue
            left = stats[index, cv2.CC_STAT_LEFT]
            top = stats[index, cv2.CC_STAT_TOP]
            right = left + stats[index, cv2.CC_STAT_WIDTH]
            bottom = top + stats[index, cv2.CC_STAT_HEIGHT]
            pixels = hsv[top:bottom, left:right, 1:3][
                labels[top:bottom, left:right] == index
            ]
            quality = min(float(pixels[:, 0].mean()) / 255, float(pixels[:, 1].mean()) / 255)
            # Both color strength and sufficient blob area contribute. Never
            # report certainty from hue membership alone.
            area_quality = min(1.0, ratio / (4 * MARKER_MIN_BLOB_AREA_RATIO))
            confidence = min(0.95, 0.50 + 0.35 * quality + 0.10 * area_quality)
            candidates.append((float(centroids[index, 0]), float(centroids[index, 1]), confidence))
        # Two plausible components of the same color are ambiguous. This is
        # safer than selecting the largest colored object in the bottle box.
        return candidates[0] if len(candidates) == 1 else None

    def observe(self, frame: np.ndarray, prop: PropDetection) -> BottleOrientation | None:
        start = time.perf_counter()
        try:
            return self._observe(frame, prop)
        finally:
            self.last_inference_ms = (time.perf_counter() - start) * 1000

    def _observe(self, frame: np.ndarray, prop: PropDetection) -> BottleOrientation | None:
        if not prop.yolo_confirmed or prop.confidence < YOLO_BOTTLE_CONFIDENCE:
            return None
        if frame.ndim != 3 or frame.shape[2] != 3:
            return None
        height, width = frame.shape[:2]
        box_width, box_height = prop.x2 - prop.x1, prop.y2 - prop.y1
        if box_width <= 0 or box_height <= 0:
            return None
        # Tape at either physical end can touch the detector box boundary.
        margin_x, margin_y = max(1, round(box_width * 0.02)), max(1, round(box_height * 0.02))
        x1, y1 = max(0, prop.x1 - margin_x), max(0, prop.y1 - margin_y)
        x2, y2 = min(width, prop.x2 + margin_x), min(height, prop.y2 + margin_y)
        if x2 <= x1 or y2 <= y1:
            return None
        hsv = cv2.cvtColor(frame[y1:y2, x1:x2], cv2.COLOR_BGR2HSV)
        orange = self._candidate(hsv, MARKER_ORANGE_HUE)
        yellow = self._candidate(hsv, MARKER_YELLOW_HUE)
        if orange is None or yellow is None:
            return None
        if np.hypot(orange[0] - yellow[0], orange[1] - yellow[1]) < (
            MARKER_MIN_SEPARATION_RATIO * max(box_width, box_height)
        ):
            return None
        top = BottleKeypoint((x1 + orange[0]) / width, (y1 + orange[1]) / height, orange[2])
        base = BottleKeypoint((x1 + yellow[0]) / width, (y1 + yellow[1]) / height, yellow[2])
        return BottleOrientation.observed(top, base, prop.confidence, image_aspect_ratio=width / height)
