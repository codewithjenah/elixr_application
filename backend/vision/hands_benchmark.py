"""Reusable Hands benchmark helpers. No production detector defaults change here."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import numpy as np

from vision.types import BottleDetection, HandsResult


def result_signature(result: Optional[HandsResult]) -> tuple[int, int]:
    """(hand_count, landmark_point_count) for agreement checks."""
    if result is None or not result.hands:
        return (0, 0)
    landmark_count = 0
    for hand in result.hands:
        landmark_count += sum(1 for point in hand.points.values() if point is not None)
    return (len(result.hands), landmark_count)


def landmark_availability(result: Optional[HandsResult]) -> bool:
    count, landmarks = result_signature(result)
    return count > 0 and landmarks > 0


def classify_scene(
    result: Optional[HandsResult],
    bottle: Optional[BottleDetection] = None,
    *,
    frame_width: int = 640,
    frame_height: int = 480,
) -> str:
    """Coarse scene bucket for reporting. Occlusion is bbox overlap, not CV truth."""
    n_hands, _ = result_signature(result)
    if n_hands <= 0:
        return "no_hand"
    occluded = False
    if bottle is not None and result is not None:
        for hand in result.hands:
            palm = hand.palm_center()
            if palm is None:
                continue
            px = palm.x * frame_width
            py = palm.y * frame_height
            if bottle.x1 <= px <= bottle.x2 and bottle.y1 <= py <= bottle.y2:
                occluded = True
                break
    if n_hands >= 2:
        return "two_hands"
    if occluded:
        return "hand_occluded_by_bottle"
    if bottle is not None:
        return "one_hand_and_bottle"
    return "one_hand"


def agreement_rates(
    signatures_a: list[tuple[int, int]],
    signatures_b: list[tuple[int, int]],
) -> dict[str, float]:
    if not signatures_a or len(signatures_a) != len(signatures_b):
        return {
            "frames": 0.0,
            "detection_count_agree": 0.0,
            "landmark_availability_agree": 0.0,
        }
    count_agree = 0
    landmark_agree = 0
    for left, right in zip(signatures_a, signatures_b):
        if left[0] == right[0]:
            count_agree += 1
        left_avail = left[0] > 0 and left[1] > 0
        right_avail = right[0] > 0 and right[1] > 0
        if left_avail == right_avail:
            landmark_agree += 1
    n = len(signatures_a)
    return {
        "frames": float(n),
        "detection_count_agree": count_agree / n,
        "landmark_availability_agree": landmark_agree / n,
    }


def load_image_frames(directory: Path) -> list[np.ndarray]:
    import cv2

    if not directory.is_dir():
        raise FileNotFoundError(f"Image directory not found: {directory}")
    paths = sorted(
        [
            path
            for path in directory.iterdir()
            if path.suffix.lower() in {".jpg", ".jpeg", ".png"}
        ]
    )
    frames: list[np.ndarray] = []
    for path in paths:
        frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if frame is None:
            raise FileNotFoundError(f"Failed to read image: {path}")
        frames.append(frame)
    if not frames:
        raise FileNotFoundError(f"No JPEG/PNG frames in {directory}")
    return frames


def synthetic_scene_frames(
    *,
    height: int = 480,
    width: int = 640,
) -> dict[str, np.ndarray]:
    """Deterministic stand-ins. They are not real hands; used when camera is absent."""
    rng = np.random.default_rng(20260818)
    no_hand = np.zeros((height, width, 3), dtype=np.uint8)
    clutter = rng.integers(0, 40, size=(height, width, 3), dtype=np.uint8)
    one_blob = np.full((height, width, 3), 18, dtype=np.uint8)
    one_blob[180:320, 240:360] = (40, 70, 190)
    two_blob = one_blob.copy()
    two_blob[180:320, 400:520] = (40, 70, 190)
    occluded = one_blob.copy()
    occluded[200:360, 250:370] = (18, 48, 210)
    return {
        "no_hand": no_hand,
        "clutter": clutter,
        "one_hand_and_bottle": one_blob,
        "two_hands": two_blob,
        "hand_occluded_by_bottle": occluded,
    }


def cycle_frames(frames: list[np.ndarray], count: int) -> list[np.ndarray]:
    if not frames:
        raise ValueError("frames must not be empty")
    return [frames[index % len(frames)] for index in range(count)]
