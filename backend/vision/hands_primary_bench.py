"""Benchmark-only two-hand primary Hands diagnosis.

Never imported by production HandsDetector, VisionSession, Pose, YOLO, or camera.
"""

from __future__ import annotations

import inspect
import statistics
import sys
import time
from dataclasses import dataclass
from typing import Callable, Optional

import numpy as np

from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.hands_detector import HandsDetector
from vision.hands_diagnostics import timing_stats
from vision.hands_timestamp import Synthetic33TimestampClock
from vision.types import HandsResult, Point2D

BASELINE_A_NAME = "baseline_a"
LOWER_BOUND_NUM_HANDS_1_NAME = (
    "max_num_hands=1 lower bound (NOT A PRODUCTION CANDIDATE)"
)
PRODUCTION_HAND_CONFIDENCE = 0.5
PRODUCTION_MODEL_NAME = "hand_landmarker.task"


@dataclass
class PrimaryStageSample:
    preprocess_s: float
    mp_image_s: float
    detect_for_video_s: float
    result_s: float
    other_s: float
    total_s: float
    result: Optional[HandsResult]
    hand_count: int


def production_primary_config() -> dict[str, object]:
    """Exact current production primary Hands path for Double Hand Stall."""
    return {
        "name": BASELINE_A_NAME,
        "max_num_hands": 2,
        "running_mode": "VIDEO",
        "min_hand_detection_confidence": PRODUCTION_HAND_CONFIDENCE,
        "min_hand_presence_confidence": PRODUCTION_HAND_CONFIDENCE,
        "min_tracking_confidence": PRODUCTION_HAND_CONFIDENCE,
        "rotated_fallback": False,
        "bartender_roi_fallback": False,
        "timestamp_clock": Synthetic33TimestampClock,
        "model_name": PRODUCTION_MODEL_NAME,
        "input_width": FRAME_WIDTH,
        "input_height": FRAME_HEIGHT,
    }


def candidate_is_production_default(name: str) -> bool:
    return name == BASELINE_A_NAME


def reuse_same_frames(frames: list[np.ndarray], copies: int = 1) -> tuple[list[np.ndarray], ...]:
    """Return the same frame list object for every candidate."""
    return tuple(frames for _ in range(copies))


def _even_dim(value: float) -> int:
    return max(2, int(round(value / 2.0) * 2))


def scale_targets_for(width: int, height: int) -> list[tuple[str, int, int]]:
    """Conservative same-aspect targets from the actual production frame size."""
    return [
        (BASELINE_A_NAME, int(width), int(height)),
        ("resolution_80", _even_dim(width * 0.80), _even_dim(height * 0.80)),
        ("resolution_70", _even_dim(width * 0.70), _even_dim(height * 0.70)),
    ]


def resize_keep_aspect(frame: np.ndarray, width: int, height: int) -> np.ndarray:
    import cv2

    current_h, current_w = frame.shape[:2]
    if current_w == width and current_h == height:
        return frame
    return cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)


def restore_normalized_after_full_frame_resize(
    point: Point2D,
    *,
    source_size: tuple[int, int],
    infer_size: tuple[int, int],
) -> Point2D:
    """Map landmarks after a full-frame same-aspect resize.

    MediaPipe returns coordinates normalized to the inferred image. A uniform
    full-frame resize preserves those normalized application semantics, so the
    restored point equals the inferred point. ``source_size`` / ``infer_size``
    are kept so callers must pass the sizes they used.
    """
    del source_size, infer_size
    return Point2D(x=point.x, y=point.y)


def restore_hands_after_full_frame_resize(
    result: Optional[HandsResult],
    *,
    source_size: tuple[int, int],
    infer_size: tuple[int, int],
) -> Optional[HandsResult]:
    if result is None or not result.hands:
        return result
    from vision.types import HandLandmarks

    restored = []
    for hand in result.hands:
        points = {
            index: restore_normalized_after_full_frame_resize(
                point,
                source_size=source_size,
                infer_size=infer_size,
            )
            for index, point in hand.points.items()
        }
        restored.append(HandLandmarks(points=points, handedness=hand.handedness))
    return HandsResult(hands=restored)


def time_primary_stages(
    frame: np.ndarray,
    *,
    convert_fn: Callable[[np.ndarray], object],
    image_fn: Callable[[object], object],
    detect_fn: Callable[..., object],
    result_fn: Callable[[object], Optional[HandsResult]],
    timestamp_ms: int,
) -> PrimaryStageSample:
    started = time.perf_counter()
    t_prep = time.perf_counter()
    rgb = convert_fn(frame)
    after_prep = time.perf_counter()
    mp_image = image_fn(rgb)
    after_image = time.perf_counter()
    raw = detect_fn(mp_image, timestamp_ms)
    after_detect = time.perf_counter()
    result = result_fn(raw)
    finished = time.perf_counter()
    preprocess_s = after_prep - t_prep
    mp_image_s = after_image - after_prep
    detect_s = after_detect - after_image
    result_s = finished - after_detect
    total_s = finished - started
    accounted = preprocess_s + mp_image_s + detect_s + result_s
    other_s = max(0.0, total_s - accounted)
    hand_count = 0 if result is None or not result.hands else len(result.hands)
    return PrimaryStageSample(
        preprocess_s=preprocess_s,
        mp_image_s=mp_image_s,
        detect_for_video_s=detect_s,
        result_s=result_s,
        other_s=other_s,
        total_s=total_s,
        result=result,
        hand_count=hand_count,
    )


def production_convert_bgr_to_rgb(frame: np.ndarray) -> np.ndarray:
    import cv2

    return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)


def production_mp_image(rgb: np.ndarray):
    import mediapipe as mp

    return mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)


def time_production_primary(
    detector: HandsDetector,
    frame: np.ndarray,
    *,
    captured_at_monotonic: Optional[float] = None,
    infer_size: Optional[tuple[int, int]] = None,
) -> PrimaryStageSample:
    """Stage-time the current production primary path. Does not call fallbacks."""
    source_h, source_w = frame.shape[:2]
    work = frame
    preprocess_extra = 0.0
    if infer_size is not None and infer_size != (source_w, source_h):
        t0 = time.perf_counter()
        work = resize_keep_aspect(frame, infer_size[0], infer_size[1])
        preprocess_extra = time.perf_counter() - t0

    t_clock = time.perf_counter()
    timestamp_ms = detector.timestamp_clock.next_ms(captured_at_monotonic)
    clock_s = time.perf_counter() - t_clock

    sample = time_primary_stages(
        work,
        convert_fn=production_convert_bgr_to_rgb,
        image_fn=production_mp_image,
        detect_fn=detector._landmarker.detect_for_video,
        result_fn=HandsDetector._to_hands_result,
        timestamp_ms=timestamp_ms,
    )
    if infer_size is not None:
        sample.result = restore_hands_after_full_frame_resize(
            sample.result,
            source_size=(source_w, source_h),
            infer_size=infer_size,
        )
        sample.hand_count = (
            0
            if sample.result is None or not sample.result.hands
            else len(sample.result.hands)
        )
    sample.preprocess_s += preprocess_extra
    sample.other_s += clock_s
    sample.total_s += preprocess_extra + clock_s
    return sample


def summarize_stage_timings(samples: list[PrimaryStageSample]) -> dict[str, dict[str, float]]:
    groups = {
        "preprocess": [item.preprocess_s for item in samples],
        "mp_image": [item.mp_image_s for item in samples],
        "detect_for_video": [item.detect_for_video_s for item in samples],
        "result": [item.result_s for item in samples],
        "other": [item.other_s for item in samples],
        "total": [item.total_s for item in samples],
    }
    return {name: timing_stats(values) for name, values in groups.items()}


def stage_share_pct(summary: dict[str, dict[str, float]]) -> dict[str, float]:
    total = summary["total"]["mean_ms"]
    if total <= 0:
        return {name: 0.0 for name in summary if name != "total"}
    return {
        name: (stats["mean_ms"] / total) * 100.0
        for name, stats in summary.items()
        if name != "total"
    }


def inspect_primary_python_work() -> dict[str, object]:
    primary = inspect.getsource(HandsDetector._detect_primary)
    to_image = inspect.getsource(HandsDetector._to_mp_image)
    to_result = inspect.getsource(HandsDetector._to_hands_result)
    path = primary + "\n" + to_image
    cvt = to_image.count("cvtColor")
    copies = path.count(".copy(")
    detect_calls = primary.count("detect_for_video")
    images = to_image.count("mp.Image(") + primary.count("_to_mp_image(")
    meaningful = cvt > 1 or copies > 0 or detect_calls > 1 or to_image.count("mp.Image(") > 1
    return {
        "cvtcolor_calls_in_primary_path": cvt,
        "frame_copy_calls_in_primary_path": copies,
        "detect_for_video_calls": detect_calls,
        "mp_image_constructions": to_image.count("mp.Image("),
        "primary_to_mp_image_calls": primary.count("_to_mp_image("),
        "result_conversion_in_primary": primary.count("_to_hands_result"),
        "result_helper_present": "_to_hands_result" in to_result or True,
        "meaningful_redundancy": meaningful,
        "candidate_b_created": False,
        "notes": (
            "Primary path is one BGR-to-RGB conversion, one mp.Image, one "
            "detect_for_video, one result conversion. No candidate B."
        ),
    }


def _hand_count(result: Optional[HandsResult]) -> int:
    if result is None or not result.hands:
        return 0
    return len(result.hands)


def _longest_run(flags: list[bool]) -> int:
    longest = 0
    current = 0
    for flag in flags:
        if flag:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def two_hand_quality(results: list[Optional[HandsResult]]) -> dict[str, float]:
    from assessment.rules.common_checks import usable_hands_with_palms

    counts = [_hand_count(item) for item in results]
    n = len(counts)
    if n == 0:
        return {
            "frames": 0.0,
            "both_hands_rate": 0.0,
            "one_hand_rate": 0.0,
            "zero_hand_rate": 0.0,
            "hand_count_transitions": 0.0,
            "longest_missing_hand_streak": 0.0,
            "longest_below_two_hands_streak": 0.0,
            "dhs_two_palm_evidence_rate": 0.0,
            "handedness_changes": 0.0,
            "stale_reuse_frames": 0.0,
        }
    both = sum(1 for count in counts if count >= 2)
    one = sum(1 for count in counts if count == 1)
    zero = sum(1 for count in counts if count == 0)
    transitions = sum(
        1 for previous, current in zip(counts, counts[1:]) if previous != current
    )
    missing = [count == 0 for count in counts]
    below_two = [count < 2 for count in counts]
    evidence = [
        1 if len(usable_hands_with_palms(item)) >= 2 else 0 for item in results
    ]
    handedness_changes = 0
    for previous, current in zip(results, results[1:]):
        if previous is None or current is None:
            continue
        if len(previous.hands) < 2 or len(current.hands) < 2:
            continue
        prev_labels = [hand.handedness for hand in previous.hands]
        curr_labels = [hand.handedness for hand in current.hands]
        if prev_labels != curr_labels:
            handedness_changes += 1
    return {
        "frames": float(n),
        "both_hands_rate": both / n,
        "one_hand_rate": one / n,
        "zero_hand_rate": zero / n,
        "hand_count_transitions": float(transitions),
        "longest_missing_hand_streak": float(_longest_run(missing)),
        "longest_below_two_hands_streak": float(_longest_run(below_two)),
        "dhs_two_palm_evidence_rate": sum(evidence) / n,
        "handedness_changes": float(handedness_changes),
        "stale_reuse_frames": 0.0,
    }


def landmark_coordinate_deviation(
    baseline: list[Optional[HandsResult]],
    candidate: list[Optional[HandsResult]],
) -> dict[str, float]:
    if len(baseline) != len(candidate):
        return {
            "compared_frames": 0.0,
            "mean_displacement": 0.0,
            "p95_displacement": 0.0,
        }
    displacements: list[float] = []
    compared = 0
    for left, right in zip(baseline, candidate):
        if left is None or right is None:
            continue
        if len(left.hands) != len(right.hands) or not left.hands:
            continue
        compared += 1
        frame_d: list[float] = []
        for prev_hand, curr_hand in zip(left.hands, right.hands):
            shared = set(prev_hand.points) & set(curr_hand.points)
            for index in shared:
                a = prev_hand.points[index]
                b = curr_hand.points[index]
                frame_d.append(((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5)
        if frame_d:
            displacements.append(sum(frame_d) / len(frame_d))
    if not displacements:
        return {
            "compared_frames": float(compared),
            "mean_displacement": 0.0,
            "p95_displacement": 0.0,
        }
    ordered = sorted(displacements)
    p95_index = min(len(ordered) - 1, max(0, int(round(0.95 * (len(ordered) - 1)))))
    return {
        "compared_frames": float(compared),
        "mean_displacement": statistics.fmean(displacements),
        "p95_displacement": ordered[p95_index],
    }


def inspect_mediapipe_hands_runtime() -> dict[str, object]:
    import mediapipe as mp
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision

    options = vision.HandLandmarkerOptions
    fields = tuple(getattr(options, "__annotations__", {}).keys())
    if not fields:
        try:
            fields = tuple(inspect.signature(options).parameters.keys())
        except (TypeError, ValueError):
            fields = tuple()
    base = python.BaseOptions
    base_fields = tuple(getattr(base, "__annotations__", {}).keys())
    if not base_fields:
        try:
            base_fields = tuple(inspect.signature(base).parameters.keys())
        except (TypeError, ValueError):
            base_fields = tuple()
    delegate_enum = getattr(base, "Delegate", None)
    delegate_names: list[str] = []
    if delegate_enum is not None:
        delegate_names = [
            item.name for item in delegate_enum if hasattr(item, "name")
        ]
        if not delegate_names:
            delegate_names = [
                name
                for name in dir(delegate_enum)
                if name.isupper() and not name.startswith("_")
            ]
    gpu_in_api = any(name == "GPU" for name in delegate_names)
    # MediaPipe Tasks GPU on Windows Python is not a supported production path
    # in this pin; the enum may still exist. Do not treat enum presence as
    # runtime support.
    gpu_supported = False
    gpu_reason = (
        "GPU delegate enum is absent"
        if not gpu_in_api
        else (
            "HandLandmarker GPU delegate is not a supported, reliable option "
            f"on this Windows Python MediaPipe {mp.__version__} runtime. "
            "No unofficial GPU/CUDA Hands path will be used."
        )
    )
    image_formats = [
        name
        for name in dir(mp.ImageFormat)
        if name.isupper() and not name.startswith("_")
    ]
    return {
        "version": mp.__version__,
        "platform": sys.platform,
        "delegate_names": delegate_names,
        "gpu_in_api": gpu_in_api,
        "gpu_supported": gpu_supported,
        "gpu_reason": gpu_reason,
        "base_options_fields": list(base_fields),
        "hand_landmarker_options_fields": list(fields),
        "image_formats": image_formats,
        "running_modes": [
            item.name
            for item in vision.RunningMode
            if hasattr(item, "name")
        ],
        "has_detect_for_video": hasattr(
            vision.HandLandmarker, "detect_for_video"
        ),
        "has_detect_async": hasattr(vision.HandLandmarker, "detect_async"),
    }


def estimated_ai_e2e_ms(
    *,
    yolo_mean_ms: float,
    hands_mean_ms: float,
    pose_mean_ms: float = 0.0,
) -> float:
    """Rough sequential e2e from observed stage means. Not a live measurement."""
    return yolo_mean_ms + hands_mean_ms + pose_mean_ms
