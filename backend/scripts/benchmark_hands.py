"""Benchmark MediaPipe HandLandmarker VIDEO cost. Diagnostic only.

Does not change production HandsDetector defaults.

Run from backend/:

    python scripts/benchmark_hands.py
    python scripts/benchmark_hands.py --images parity_frames
    python scripts/benchmark_hands.py --no-camera --synthetic
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.hands_benchmark import (
    agreement_rates,
    classify_scene,
    cycle_frames,
    load_image_frames,
    result_signature,
    synthetic_scene_frames,
)
from vision.hands_detector import HandsDetector
from vision.hands_diagnostics import timing_stats
from vision.types import BottleDetection


def _print_stats(label: str, samples_s: list[float]) -> None:
    stats = timing_stats(samples_s)
    print(
        f"{label}: mean={stats['mean_ms']:.2f}ms median={stats['median_ms']:.2f}ms "
        f"p95={stats['p95_ms']:.2f}ms fps={stats['fps']:.2f} n={int(stats['count'])}"
    )


def _capture_camera_frames(count: int, timeout_s: float) -> list[np.ndarray]:
    from vision.camera import CameraCapture

    camera = CameraCapture()
    if not camera.open():
        raise RuntimeError("Camera unavailable.")
    frames: list[np.ndarray] = []
    last_sequence: int | None = None
    deadline = time.monotonic() + timeout_s
    try:
        while len(frames) < count and time.monotonic() < deadline:
            captured = camera.peek_latest(newer_than=last_sequence, timeout=0.25)
            if captured is None:
                continue
            last_sequence = captured.sequence
            frames.append(captured.frame.copy())
    finally:
        camera.release()
    if not frames:
        raise RuntimeError("Camera opened but produced no frames.")
    return frames


def _maybe_detect_bottle(frame: np.ndarray) -> BottleDetection | None:
    detector = getattr(_maybe_detect_bottle, "_detector", None)
    if detector is False:
        return None
    if detector is None:
        try:
            from vision.bottle_detector import BottleDetector

            loaded = BottleDetector()
            loaded.ensure_ready()
            _maybe_detect_bottle._detector = loaded
            detector = loaded
        except Exception:
            _maybe_detect_bottle._detector = False
            return None
    try:
        bottles = detector.detect(frame)
    except Exception:
        return None
    if not bottles:
        return None
    return bottles[0]


def _run_detector(
    detector: HandsDetector,
    frames: list[np.ndarray],
    *,
    warmup: int,
    bottles: list[BottleDetection | None] | None = None,
) -> tuple[list[float], list[tuple[int, int]], list[str]]:
    for index in range(warmup):
        bottle = None if bottles is None else bottles[index % len(bottles)]
        detector.detect(frames[index % len(frames)], bottle=bottle)
    detector.stats.reset()
    samples: list[float] = []
    signatures: list[tuple[int, int]] = []
    scenes: list[str] = []
    for index, frame in enumerate(frames):
        bottle = None if bottles is None else bottles[index]
        started = time.perf_counter()
        result = detector.detect(frame, bottle=bottle)
        samples.append(time.perf_counter() - started)
        signatures.append(result_signature(result))
        scenes.append(
            classify_scene(
                result,
                bottle,
                frame_width=frame.shape[1],
                frame_height=frame.shape[0],
            )
        )
    return samples, signatures, scenes


def _print_scene_breakdown(scenes: list[str]) -> None:
    counts: dict[str, int] = {}
    for scene in scenes:
        counts[scene] = counts.get(scene, 0) + 1
    parts = [f"{name}={count}" for name, count in sorted(counts.items())]
    print("Scene buckets: " + ", ".join(parts))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmup", type=int, default=12)
    parser.add_argument("--runs", type=int, default=80)
    parser.add_argument("--capture-frames", type=int, default=40)
    parser.add_argument("--capture-timeout", type=float, default=8.0)
    parser.add_argument(
        "--images",
        type=Path,
        default=None,
        help="Directory of real JPEG/PNG frames (preferred when available).",
    )
    parser.add_argument("--no-camera", action="store_true")
    parser.add_argument(
        "--synthetic",
        action="store_true",
        help="Include deterministic synthetic frames when real frames are scarce.",
    )
    parser.add_argument(
        "--save",
        type=Path,
        default=None,
        help="Optional directory to write captured frames for reuse.",
    )
    args = parser.parse_args()

    labeled_synthetic = synthetic_scene_frames(
        height=FRAME_HEIGHT,
        width=FRAME_WIDTH,
    )
    frames: list[np.ndarray] = []
    source = "none"
    if args.images is not None:
        frames = load_image_frames(args.images)
        source = f"images:{args.images}"
    elif not args.no_camera:
        try:
            frames = _capture_camera_frames(
                args.capture_frames,
                args.capture_timeout,
            )
            source = f"camera:{len(frames)}"
        except Exception as exc:
            print(f"Camera capture skipped: {exc}")
            source = "camera_failed"

    if args.synthetic or not frames:
        frames.extend(list(labeled_synthetic.values()))
        if source == "none" or source == "camera_failed":
            source = "synthetic"
        else:
            source = f"{source}+synthetic"

    unique_frames = frames
    replay = cycle_frames(unique_frames, max(args.runs, len(unique_frames)))
    print(
        f"Hands benchmark source={source} unique_frames={len(unique_frames)} "
        f"replay={len(replay)} size={replay[0].shape} warmup={args.warmup} "
        f"model=hand_landmarker.task mode=VIDEO thresholds=0.5"
    )

    bottles: list[BottleDetection | None] = [None] * len(replay)
    if args.images is not None or source.startswith("camera"):
        bottle_cache: dict[int, BottleDetection | None] = {}
        for index, frame in enumerate(replay):
            key = index % len(unique_frames)
            if key not in bottle_cache:
                bottle_cache[key] = _maybe_detect_bottle(unique_frames[key])
            bottles[index] = bottle_cache[key]

    one = HandsDetector(max_num_hands=1)
    two = HandsDetector(max_num_hands=2)
    try:
        samples_1, sig_1, scenes_1 = _run_detector(
            one,
            replay,
            warmup=args.warmup,
        )
        samples_2, sig_2, scenes_2 = _run_detector(
            two,
            replay,
            warmup=args.warmup,
        )
        agree = agreement_rates(sig_1, sig_2)
        print("--- num_hands VIDEO (fallbacks off) ---")
        _print_stats("num_hands=1", samples_1)
        _print_stats("num_hands=2", samples_2)
        delta_ms = timing_stats(samples_2)["mean_ms"] - timing_stats(samples_1)["mean_ms"]
        print(
            f"delta mean (2-1)={delta_ms:.2f}ms "
            f"detection_count_agree={agree['detection_count_agree'] * 100:.1f}% "
            f"landmark_availability_agree={agree['landmark_availability_agree'] * 100:.1f}% "
            f"frames={int(agree['frames'])}"
        )
        _print_scene_breakdown(scenes_2)
        by_scene: dict[str, tuple[list[float], list[float]]] = {}
        for scene, s1, s2 in zip(scenes_2, samples_1, samples_2):
            bucket = by_scene.setdefault(scene, ([], []))
            bucket[0].append(s1)
            bucket[1].append(s2)
        for scene, (one_samples, two_samples) in sorted(by_scene.items()):
            one_stats = timing_stats(one_samples)
            two_stats = timing_stats(two_samples)
            print(
                f"  scene={scene} n={len(two_samples)} "
                f"hands1={one_stats['mean_ms']:.2f}ms "
                f"hands2={two_stats['mean_ms']:.2f}ms "
                f"delta={two_stats['mean_ms'] - one_stats['mean_ms']:.2f}ms"
            )
        print(
            "Note: agreement is same-frame 1-vs-2. Two-hand scenes are expected "
            "to disagree on detection count."
        )
    finally:
        one.close()
        two.close()

    print("--- production-like fallbacks on num_hands=2 ---")
    rotated = HandsDetector(
        max_num_hands=2,
        rotated_fallback=True,
    )
    bartender = HandsDetector(
        max_num_hands=2,
        bartender_roi_fallback=True,
    )
    try:
        rot_samples, _, _ = _run_detector(rotated, replay, warmup=args.warmup)
        rot_snap = rotated.stats.snapshot()
        _print_stats("rotated_fallback detect() total", rot_samples)
        print(
            f"rotated_fallback split: primary_mean={rot_snap['primary_mean_ms']:.2f}ms "
            f"primary_p95={rot_snap['primary_p95_ms']:.2f}ms "
            f"rotated_calls={rot_snap['rotated_calls']} "
            f"rotated_mean={rot_snap['rotated_mean_ms']:.2f}ms "
            f"rotated_p95={rot_snap['rotated_p95_ms']:.2f}ms "
            f"activation={rot_snap['fallback_activation_rate'] * 100:.1f}%"
        )
        roi_samples, _, _ = _run_detector(
            bartender,
            replay,
            warmup=args.warmup,
            bottles=bottles,
        )
        roi_snap = bartender.stats.snapshot()
        _print_stats("bartender_roi_fallback detect() total", roi_samples)
        print(
            f"bartender_roi_fallback split: primary_mean={roi_snap['primary_mean_ms']:.2f}ms "
            f"primary_p95={roi_snap['primary_p95_ms']:.2f}ms "
            f"roi_calls={roi_snap['bartender_calls']} "
            f"roi_image={roi_snap['bartender_image_calls']} "
            f"roi_mean={roi_snap['bartender_mean_ms']:.2f}ms "
            f"roi_p95={roi_snap['bartender_p95_ms']:.2f}ms "
            f"activation={roi_snap['fallback_activation_rate'] * 100:.1f}%"
        )
    finally:
        rotated.close()
        bartender.close()

    if args.save is not None:
        import cv2

        args.save.mkdir(parents=True, exist_ok=True)
        for index, frame in enumerate(unique_frames, start=1):
            path = args.save / f"{index:03d}.jpg"
            cv2.imwrite(str(path), frame)
        print(f"Saved {len(unique_frames)} frames to {args.save}")


if __name__ == "__main__":
    main()
