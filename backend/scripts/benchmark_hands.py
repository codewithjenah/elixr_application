"""Benchmark MediaPipe HandLandmarker VIDEO cost. Diagnostic only.

Does not change production HandsDetector defaults.

Run from backend/:

    python scripts/benchmark_hands.py
    python scripts/benchmark_hands.py --images parity_frames
    python scripts/benchmark_hands.py --no-camera --synthetic
    python scripts/benchmark_hands.py --ab-timestamps
    python scripts/benchmark_hands.py --ab-timestamps --save hands_timestamp_frames
    python scripts/benchmark_hands.py --ab-fallbacks --images hands_timestamp_frames --manifest hands_timestamp_frames/manifest.json --ab-only
    python scripts/benchmark_hands.py --capture-bartender --save hands_bartender_frames
    python scripts/benchmark_hands.py --abc-roi --ab-only --images hands_bartender_frames --manifest hands_bartender_frames/manifest.json
    python scripts/benchmark_hands.py --crop-benchmark --images hands_bartender_frames --manifest hands_bartender_frames/manifest.json
    python scripts/benchmark_hands.py --capture-double-hand --save hands_double_hand_frames
    python scripts/benchmark_hands.py --primary-breakdown --images hands_double_hand_frames --manifest hands_double_hand_frames/manifest.json
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
    SCENE_TAGS,
    TimedCaptureFrame,
    agreement_rates,
    apply_scene_tags,
    bottle_from_manifest,
    bottle_to_manifest,
    classify_scene,
    continuity_metrics,
    cycle_frames,
    evaluate_capture_quality,
    fallback_ab_replay,
    freeze_bottles,
    landmark_jitter_metrics,
    load_capture_manifest,
    load_image_frames,
    parse_scene_tag_spec,
    parse_tag_range_args,
    recovered_frames_due_to_fallback,
    relative_captured_at,
    relative_time_ms,
    result_signature,
    save_capture_manifest,
    synthetic_scene_frames,
    usable_detection_rate,
)
from vision.hands_capture import (
    DOUBLE_HAND_READY_PROMPT,
    make_owned_camera_hooks,
    run_user_triggered_bartender_capture,
)
from vision.hands_crop_policies import (
    CROP_A,
    CROP_B,
    CROP_C,
    CROP_D,
    CROP_VARIANTS_WITH_D,
    classify_roi_outcome,
    compare_recoveries,
    crop_bounds_for,
    crop_containment,
    eligible_frame_indices,
    recommend_crop_trial,
    run_bartender_roi_crop,
    select_debug_examples,
    summarize_crop_areas,
    write_crop_debug_image,
)
from vision.hands_detector import (
    HandsDetector,
    _bartender_crop_bounds,
    _counterclockwise_crop_point_to_frame,
    _has_bartender_candidate,
    _merge_hands,
)
from vision.hands_diagnostics import timing_stats
from vision.hands_roi_policies import (
    ConsecutiveMissRoiPolicy,
    ImmediateRoiPolicy,
    StrategyReplay,
    classify_immediate_recoveries,
    evaluate_policy_frame,
    first_miss_recovery_indices,
    measure_recovery_delay,
    measure_recovery_delay_for_indices,
    n2_recommendation,
    summarize_strategy,
)
from vision.hands_primary_bench import (
    LOWER_BOUND_NUM_HANDS_1_NAME,
    estimated_ai_e2e_ms,
    inspect_mediapipe_hands_runtime,
    inspect_primary_python_work,
    landmark_coordinate_deviation,
    production_primary_config,
    reuse_same_frames,
    scale_targets_for,
    stage_share_pct,
    summarize_stage_timings,
    time_production_primary,
    two_hand_quality,
)
from vision.hands_timestamp import (
    CaptureMonotonicTimestampClock,
    Synthetic33TimestampClock,
)
from vision.types import BottleDetection, HandsResult


_AB_SCENARIOS = (
    (
        "Normal Grip",
        {
            "max_num_hands": 1,
            "rotated_fallback": True,
            "bartender_roi_fallback": False,
        },
    ),
    (
        "Claw Grip",
        {
            "max_num_hands": 1,
            "rotated_fallback": True,
            "bartender_roi_fallback": False,
        },
    ),
    (
        "Bartender's Grip",
        {
            "max_num_hands": 1,
            "rotated_fallback": False,
            "bartender_roi_fallback": True,
        },
    ),
)


def _print_stage_block(label: str, samples) -> dict:
    summary = summarize_stage_timings(samples)
    shares = stage_share_pct(summary)
    quality = two_hand_quality([item.result for item in samples])
    print(f"--- {label} ---")
    for name in (
        "preprocess",
        "mp_image",
        "detect_for_video",
        "result",
        "other",
        "total",
    ):
        stats = summary[name]
        share = ""
        if name != "total":
            share = f" share={shares[name]:.1f}%"
        print(
            f"  {name}: mean={stats['mean_ms']:.2f}ms "
            f"median={stats['median_ms']:.2f}ms "
            f"p95={stats['p95_ms']:.2f}ms{share} n={int(stats['count'])}"
        )
    print(
        f"  two-hand quality: both={quality['both_hands_rate'] * 100:.1f}% "
        f"one={quality['one_hand_rate'] * 100:.1f}% "
        f"zero={quality['zero_hand_rate'] * 100:.1f}% "
        f"transitions={int(quality['hand_count_transitions'])} "
        f"longest_zero={int(quality['longest_missing_hand_streak'])} "
        f"longest_<2={int(quality['longest_below_two_hands_streak'])} "
        f"dhs_two_palm={quality['dhs_two_palm_evidence_rate'] * 100:.1f}% "
        f"handedness_changes={int(quality['handedness_changes'])}"
    )
    return {"summary": summary, "shares": shares, "quality": quality}


def _warmup_primary(detector: HandsDetector, frames: list[np.ndarray], warmup: int) -> None:
    count = min(warmup, len(frames))
    for index in range(count):
        time_production_primary(detector, frames[index])


def _measure_primary(
    detector: HandsDetector,
    frames: list[np.ndarray],
    *,
    infer_size: tuple[int, int] | None = None,
) -> list:
    samples = []
    for frame in frames:
        samples.append(
            time_production_primary(
                detector,
                frame,
                infer_size=infer_size,
            )
        )
    return samples


def _run_primary_breakdown(frames: list[np.ndarray], warmup: int) -> None:
    runtime = inspect_mediapipe_hands_runtime()
    python_work = inspect_primary_python_work()
    config = production_primary_config()
    height, width = frames[0].shape[:2]
    print("--- MediaPipe runtime ---")
    print(
        f"version={runtime['version']} platform={runtime['platform']} "
        f"delegates={runtime['delegate_names']} "
        f"gpu_in_api={runtime['gpu_in_api']} "
        f"gpu_supported={runtime['gpu_supported']}"
    )
    print(f"gpu_reason={runtime['gpu_reason']}")
    print("--- production primary config (benchmark A) ---")
    print(
        f"name={config['name']} max_num_hands={config['max_num_hands']} "
        f"mode={config['running_mode']} thresholds="
        f"{config['min_hand_detection_confidence']} "
        f"model={config['model_name']} "
        f"configured_frame={config['input_width']}x{config['input_height']} "
        f"actual_frame={width}x{height} "
        f"timestamp=+33 fallbacks=off"
    )
    print("--- redundant CPU work ---")
    print(
        f"cvtColor={python_work['cvtcolor_calls_in_primary_path']} "
        f"frame.copy={python_work['frame_copy_calls_in_primary_path']} "
        f"detect_for_video={python_work['detect_for_video_calls']} "
        f"mp.Image={python_work['mp_image_constructions']} "
        f"meaningful_redundancy={python_work['meaningful_redundancy']} "
        f"candidate_b_created={python_work['candidate_b_created']}"
    )
    print(python_work["notes"])

    shared_a, shared_b, shared_c, shared_one = reuse_same_frames(frames, copies=4)
    assert shared_a is frames and shared_b is frames
    assert shared_c is frames and shared_one is frames

    baseline = HandsDetector(
        max_num_hands=2,
        rotated_fallback=False,
        bartender_roi_fallback=False,
    )
    lower = HandsDetector(
        max_num_hands=1,
        rotated_fallback=False,
        bartender_roi_fallback=False,
    )
    scaled_detectors: dict[str, HandsDetector] = {}
    try:
        _warmup_primary(baseline, shared_a, warmup)
        baseline_samples = _measure_primary(baseline, shared_a)
        baseline_report = _print_stage_block(
            "A EXACT CURRENT PRODUCTION PRIMARY (max_num_hands=2, no fallback)",
            baseline_samples,
        )

        _warmup_primary(lower, shared_one, warmup)
        lower_samples = _measure_primary(lower, shared_one)
        _print_stage_block(
            LOWER_BOUND_NUM_HANDS_1_NAME,
            lower_samples,
        )
        print(
            "The max_num_hands=1 pass is a diagnostic lower bound only. "
            "Double Hand Stall requires two hands."
        )

        targets = scale_targets_for(width, height)
        baseline_results = [item.result for item in baseline_samples]
        for name, infer_w, infer_h in targets[1:]:
            infer_size = (infer_w, infer_h)
            detector = HandsDetector(
                max_num_hands=2,
                rotated_fallback=False,
                bartender_roi_fallback=False,
            )
            scaled_detectors[name] = detector
            count = min(warmup, len(shared_b))
            for index in range(count):
                time_production_primary(
                    detector,
                    shared_b[index],
                    infer_size=infer_size,
                )
            scaled_samples = _measure_primary(
                detector,
                shared_c,
                infer_size=infer_size,
            )
            report = _print_stage_block(
                f"resolution diagnostic {name} {infer_w}x{infer_h} "
                "(NOT production; same-aspect resize)",
                scaled_samples,
            )
            deviation = landmark_coordinate_deviation(
                baseline_results,
                [item.result for item in scaled_samples],
            )
            print(
                f"  landmark deviation vs A: compared={int(deviation['compared_frames'])} "
                f"mean={deviation['mean_displacement']:.6f} "
                f"p95={deviation['p95_displacement']:.6f}"
            )
            base_both = baseline_report["quality"]["both_hands_rate"]
            cand_both = report["quality"]["both_hands_rate"]
            print(
                f"  both-hand delta vs A: "
                f"{(cand_both - base_both) * 100:.1f} percentage points"
            )

        yolo_mean = 23.3
        pose_mean = 0.0
        hands_a = baseline_report["summary"]["total"]["mean_ms"]
        print("--- estimated sequential AI e2e (Hands change only; YOLO/Pose closed) ---")
        print(
            f"using previously verified DHS YOLO mean={yolo_mean:.1f}ms "
            f"pose={pose_mean:.1f}ms (not remeasured here)"
        )
        print(
            f"A estimated e2e="
            f"{estimated_ai_e2e_ms(yolo_mean_ms=yolo_mean, hands_mean_ms=hands_a):.1f}ms "
            f"est. cap={1000.0 / max(hands_a + yolo_mean, 1e-6):.1f} sequential FPS"
        )
    finally:
        baseline.close()
        lower.close()
        for detector in scaled_detectors.values():
            detector.close()


def _print_stats(label: str, samples_s: list[float]) -> None:
    stats = timing_stats(samples_s)
    print(
        f"{label}: mean={stats['mean_ms']:.2f}ms median={stats['median_ms']:.2f}ms "
        f"p95={stats['p95_ms']:.2f}ms fps={stats['fps']:.2f} n={int(stats['count'])}"
    )


def _capture_camera_frames(count: int, timeout_s: float) -> list[np.ndarray]:
    frames, _records = _capture_timed_camera_frames(count, timeout_s)
    return frames


def _capture_timed_camera_frames(
    count: int,
    timeout_s: float,
    *,
    camera=None,
    progress_every: int = 0,
    print_fn=print,
) -> tuple[list[np.ndarray], list[TimedCaptureFrame]]:
    from vision.camera import CameraCapture

    owns_camera = camera is None
    if owns_camera:
        camera = CameraCapture()
        if not camera.open():
            raise RuntimeError("Camera unavailable.")
    frames: list[np.ndarray] = []
    records: list[TimedCaptureFrame] = []
    last_sequence: int | None = None
    origin: float | None = None
    deadline = time.monotonic() + timeout_s
    try:
        while len(frames) < count and time.monotonic() < deadline:
            captured = camera.peek_latest(newer_than=last_sequence, timeout=0.25)
            if captured is None:
                continue
            last_sequence = captured.sequence
            if origin is None:
                origin = captured.captured_at_monotonic
            frames.append(captured.frame.copy())
            records.append(
                TimedCaptureFrame(
                    filename=f"{len(frames):04d}.jpg",
                    sequence=captured.sequence,
                    captured_at_monotonic=captured.captured_at_monotonic,
                    relative_time_ms=relative_time_ms(
                        captured.captured_at_monotonic,
                        origin,
                    ),
                )
            )
            if progress_every and len(frames) % progress_every == 0:
                print_fn(f"Capturing: {len(frames)} / {count}")
        if progress_every and frames and len(frames) % progress_every != 0:
            print_fn(f"Capturing: {len(frames)} / {count}")
    finally:
        if owns_camera:
            camera.release()
    if not frames:
        raise RuntimeError("Camera opened but produced no frames.")
    return frames, records


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


def _close_bottle_detector() -> None:
    detector = getattr(_maybe_detect_bottle, "_detector", None)
    closer = getattr(detector, "close", None) if detector and detector is not False else None
    if callable(closer):
        closer()
    _maybe_detect_bottle._detector = None


def _run_detector(
    detector: HandsDetector,
    frames: list[np.ndarray],
    *,
    warmup: int,
    bottles: list[BottleDetection | None] | None = None,
    captured_at: list[float | None] | None = None,
) -> tuple[list[float], list[tuple[int, int]], list[str]]:
    for index in range(warmup):
        bottle = None if bottles is None else bottles[index % len(bottles)]
        stamp = None if captured_at is None else captured_at[index % len(captured_at)]
        detector.detect(
            frames[index % len(frames)],
            bottle=bottle,
            captured_at_monotonic=stamp,
        )
    detector.stats.reset()
    samples: list[float] = []
    signatures: list[tuple[int, int]] = []
    scenes: list[str] = []
    for index, frame in enumerate(frames):
        bottle = None if bottles is None else bottles[index]
        stamp = None if captured_at is None else captured_at[index]
        started = time.perf_counter()
        result = detector.detect(
            frame,
            bottle=bottle,
            captured_at_monotonic=stamp,
        )
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


def _run_detector_detailed(
    detector: HandsDetector,
    frames: list[np.ndarray],
    *,
    warmup: int,
    bottles: list[BottleDetection | None] | None = None,
    captured_at: list[float | None] | None = None,
    require_bartender_candidate: bool = False,
) -> dict:
    def _bottle_at(index: int) -> BottleDetection | None:
        if bottles is None:
            return None
        return bottles[index % len(bottles)]

    def _captured_at(index: int) -> float | None:
        if captured_at is None:
            return None
        return captured_at[index]

    for index in range(warmup):
        detector.detect(
            frames[index % len(frames)],
            bottle=_bottle_at(index),
            captured_at_monotonic=_captured_at(index % len(frames)),
        )
    detector.stats.reset()
    samples: list[float] = []
    signatures: list[tuple[int, int]] = []
    scenes: list[str] = []
    primary_hits: list[bool] = []
    hand_counts: list[int] = []
    landmark_available: list[bool] = []
    usable: list[bool] = []
    results: list[HandsResult | None] = []
    primary_results: list[HandsResult | None] = []
    measured = frames[warmup:] if warmup < len(frames) else frames
    measure_offset = warmup if warmup < len(frames) else 0
    for local_index, frame in enumerate(measured):
        index = measure_offset + local_index
        bottle = _bottle_at(index)
        stamp = _captured_at(index)
        started = time.perf_counter()
        result = detector.detect(
            frame,
            bottle=bottle,
            captured_at_monotonic=stamp,
        )
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
        hit = bool(detector.stats.last_primary_hit)
        primary_hits.append(hit)
        count, landmarks = result_signature(result)
        hand_counts.append(count)
        available = count > 0 and landmarks > 0
        landmark_available.append(available)
        if require_bartender_candidate:
            usable.append(
                _has_bartender_candidate(
                    result,
                    bottle,
                    frame_width=frame.shape[1],
                    frame_height=frame.shape[0],
                )
                if bottle is not None
                else False
            )
        else:
            usable.append(available)
        results.append(result)
        primary_results.append(result if hit else None)
    return {
        "samples_s": samples,
        "signatures": signatures,
        "scenes": scenes,
        "primary_hits": primary_hits,
        "hand_counts": hand_counts,
        "landmark_available": landmark_available,
        "usable": usable,
        "results": results,
        "primary_results": primary_results,
        "stats": detector.stats.snapshot(),
        "continuity": continuity_metrics(
            primary_hits=primary_hits,
            hand_counts=hand_counts,
            landmark_available=landmark_available,
        ),
        "usable_continuity": continuity_metrics(
            primary_hits=usable,
            hand_counts=hand_counts,
            landmark_available=usable,
        ),
        "jitter_final": landmark_jitter_metrics(results),
        "jitter_primary": landmark_jitter_metrics(primary_results),
    }


def _print_scene_breakdown(scenes: list[str]) -> None:
    counts: dict[str, int] = {}
    for scene in scenes:
        counts[scene] = counts.get(scene, 0) + 1
    parts = [f"{name}={count}" for name, count in sorted(counts.items())]
    print("Scene buckets: " + ", ".join(parts))


def _print_capture_intervals(records: list[TimedCaptureFrame]) -> None:
    if len(records) < 2:
        print("Capture intervals: n=1 (no dt)")
        return
    deltas_s = [
        max(0.0, later.captured_at_monotonic - earlier.captured_at_monotonic)
        for earlier, later in zip(records, records[1:])
    ]
    stats = timing_stats(deltas_s)
    print(
        f"Capture intervals: mean={stats['mean_ms']:.2f}ms "
        f"median={stats['median_ms']:.2f}ms p95={stats['p95_ms']:.2f}ms "
        f"n={int(stats['count'])} "
        f"span_ms={records[-1].relative_time_ms}"
    )


def _save_timed_frames(
    directory: Path,
    frames: list[np.ndarray],
    records: list[TimedCaptureFrame],
) -> None:
    import cv2

    directory.mkdir(parents=True, exist_ok=True)
    saved_records: list[TimedCaptureFrame] = []
    for frame, record in zip(frames, records):
        path = directory / record.filename
        cv2.imwrite(str(path), frame)
        saved_records.append(record)
    save_capture_manifest(directory / "manifest.json", saved_records)
    print(f"Saved {len(saved_records)} timed frames to {directory}")


def _load_timed_images(
    image_dir: Path,
    manifest_path: Path,
) -> tuple[list[np.ndarray], list[TimedCaptureFrame]]:
    records = load_capture_manifest(manifest_path)
    frames: list[np.ndarray] = []
    import cv2

    for record in records:
        path = image_dir / record.filename
        frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if frame is None:
            raise FileNotFoundError(f"Failed to read image: {path}")
        frames.append(frame)
    return frames, records


def _pass_metrics(label: str, report: dict) -> dict[str, float]:
    snap = report["stats"]
    combined = timing_stats(report["samples_s"])
    continuity = report["continuity"]
    jitter_primary = report["jitter_primary"]
    jitter_final = report["jitter_final"]
    detect_calls = max(1, int(snap["detect_calls"]))
    return {
        "label": label,
        "primary_calls": float(snap["primary_calls"]),
        "primary_mean_ms": float(snap["primary_mean_ms"]),
        "primary_median_ms": float(snap["primary_median_ms"]),
        "primary_p95_ms": float(snap["primary_p95_ms"]),
        "primary_success_rate": float(snap["primary_success_rate"]),
        "primary_empty_rate": (
            float(snap["primary_empty_calls"]) / detect_calls
        ),
        "rotated_calls": float(snap["rotated_calls"]),
        "rotated_activation_pct": (
            100.0 * float(snap["rotated_calls"]) / detect_calls
        ),
        "bartender_calls": float(snap["bartender_calls"]),
        "bartender_image_calls": float(snap["bartender_image_calls"]),
        "bartender_activation_pct": (
            100.0 * float(snap["bartender_calls"]) / detect_calls
        ),
        "fallback_mean_ms": (
            float(snap["rotated_mean_ms"])
            if snap["rotated_calls"]
            else float(snap["bartender_mean_ms"])
        ),
        "fallback_p95_ms": (
            float(snap["rotated_p95_ms"])
            if snap["rotated_calls"]
            else float(snap["bartender_p95_ms"])
        ),
        "fallback_activation_pct": 100.0 * float(snap["fallback_activation_rate"]),
        "hands_mean_ms": combined["mean_ms"],
        "hands_median_ms": combined["median_ms"],
        "hands_p95_ms": combined["p95_ms"],
        "hands_fps": combined["fps"],
        "miss_transitions": continuity["primary_miss_transitions"],
        "longest_miss_run": continuity["longest_primary_miss_run"],
        "hand_count_changes": continuity["hand_count_changes"],
        "landmark_continuity": continuity["landmark_availability_continuity"],
        "jitter_primary_mean": jitter_primary["mean_displacement"],
        "jitter_primary_p95": jitter_primary["p95_displacement"],
        "jitter_final_mean": jitter_final["mean_displacement"],
        "jitter_final_p95": jitter_final["p95_displacement"],
        "jitter_primary_pairs": jitter_primary["pairs"],
        "fallback_attempts": float(snap.get("fallback_attempts", 0)),
        "fallback_successes": float(snap.get("fallback_successes", 0)),
        "fallback_failures": float(snap.get("fallback_failures", 0)),
        "fallback_recovery_rate": float(snap.get("fallback_recovery_rate", 0.0)),
        "fallback_wasted_rate": float(snap.get("fallback_wasted_rate", 0.0)),
        "rotated_attempts": float(snap.get("rotated_attempts", 0)),
        "rotated_successes": float(snap.get("rotated_successes", 0)),
        "rotated_failures": float(snap.get("rotated_failures", 0)),
        "bartender_attempts": float(snap.get("bartender_attempts", 0)),
        "bartender_successes": float(snap.get("bartender_successes", 0)),
        "bartender_failures": float(snap.get("bartender_failures", 0)),
        "rotated_mean_ms": float(snap["rotated_mean_ms"]),
        "rotated_median_ms": float(snap["rotated_median_ms"]),
        "rotated_p95_ms": float(snap["rotated_p95_ms"]),
        "bartender_mean_ms": float(snap["bartender_mean_ms"]),
        "bartender_median_ms": float(snap["bartender_median_ms"]),
        "bartender_p95_ms": float(snap["bartender_p95_ms"]),
        "fallback_extra_latency_ms": float(
            snap.get("fallback_extra_latency_ms", 0.0)
        ),
        "rotated_cost_per_recovery_ms": float(
            snap.get("rotated_cost_per_recovery_ms", 0.0)
        ),
        "bartender_cost_per_recovery_ms": float(
            snap.get("bartender_cost_per_recovery_ms", 0.0)
        ),
        "usable_rate": usable_detection_rate(report.get("usable", []))["usable_rate"],
        "no_hand_rate": usable_detection_rate(report.get("usable", []))["no_hand_rate"],
        "usable_miss_transitions": float(
            report.get("usable_continuity", continuity)["primary_miss_transitions"]
        ),
        "usable_longest_miss_run": float(
            report.get("usable_continuity", continuity)["longest_primary_miss_run"]
        ),
        "usable_landmark_continuity": float(
            report.get("usable_continuity", continuity)[
                "landmark_availability_continuity"
            ]
        ),
    }


def _print_ab_table(scenario: str, pass_a: dict, pass_b: dict) -> None:
    rows = [
        ("primary_calls", "{:.0f}", False),
        ("primary_mean_ms", "{:.2f}", True),
        ("primary_median_ms", "{:.2f}", True),
        ("primary_p95_ms", "{:.2f}", True),
        ("primary_success_rate", "{:.1%}", False),
        ("primary_empty_rate", "{:.1%}", True),
        ("rotated_calls", "{:.0f}", True),
        ("rotated_activation_pct", "{:.1f}%", True),
        ("bartender_calls", "{:.0f}", True),
        ("bartender_activation_pct", "{:.1f}%", True),
        ("fallback_activation_pct", "{:.1f}%", True),
        ("fallback_mean_ms", "{:.2f}", True),
        ("fallback_p95_ms", "{:.2f}", True),
        ("hands_mean_ms", "{:.2f}", True),
        ("hands_median_ms", "{:.2f}", True),
        ("hands_p95_ms", "{:.2f}", True),
        ("hands_fps", "{:.2f}", False),
        ("miss_transitions", "{:.0f}", True),
        ("longest_miss_run", "{:.0f}", True),
        ("hand_count_changes", "{:.0f}", True),
        ("landmark_continuity", "{:.1%}", False),
        ("jitter_primary_mean", "{:.5f}", True),
        ("jitter_primary_p95", "{:.5f}", True),
        ("jitter_primary_pairs", "{:.0f}", False),
    ]
    print(f"--- A/B timestamp table: {scenario} ---")
    print(f"{'metric':<28} {'A +33':>12} {'B real':>12} {'delta(B-A)':>12}")
    for key, fmt, lower_is_better in rows:
        left = pass_a[key]
        right = pass_b[key]
        if fmt.endswith("%") and not fmt.endswith("%}"):
            # percentages already scaled to 0-100 except *_rate
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = f"{right - left:+.1f}"
        elif fmt == "{:.1%}":
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = f"{(right - left) * 100:+.1f}pp"
        else:
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = fmt.format(right - left)
            if not delta_text.startswith("-"):
                delta_text = "+" + delta_text
        marker = ""
        if left != right and key not in {"primary_calls", "jitter_primary_pairs"}:
            improved = (right < left) if lower_is_better else (right > left)
            marker = "  improved" if improved else "  worse"
        print(
            f"{key:<28} {left_text:>12} {right_text:>12} {delta_text:>12}{marker}"
        )


def _run_ab_scenario(
    name: str,
    config: dict,
    frames: list[np.ndarray],
    records: list[TimedCaptureFrame],
    bottles: list[BottleDetection | None],
    warmup: int,
) -> tuple[dict, dict, dict, dict]:
    origin = records[0].captured_at_monotonic
    relative_seconds = [
        relative_captured_at(record.captured_at_monotonic, origin)
        for record in records
    ]
    synthetic = HandsDetector(
        timestamp_clock=Synthetic33TimestampClock(),
        **config,
    )
    capture = HandsDetector(
        timestamp_clock=CaptureMonotonicTimestampClock(),
        **config,
    )
    try:
        report_a = _run_detector_detailed(
            synthetic,
            frames,
            warmup=warmup,
            bottles=bottles,
            captured_at=[None] * len(frames),
        )
        report_b = _run_detector_detailed(
            capture,
            frames,
            warmup=warmup,
            bottles=bottles,
            captured_at=relative_seconds,
        )
    finally:
        synthetic.close()
        capture.close()
    pass_a = _pass_metrics("A synthetic +33", report_a)
    pass_b = _pass_metrics("B capture monotonic", report_b)
    _print_ab_table(name, pass_a, pass_b)
    print(f"A scenes ({name}):")
    _print_scene_breakdown(report_a["scenes"])
    print(f"B scenes ({name}):")
    _print_scene_breakdown(report_b["scenes"])
    return pass_a, pass_b, report_a, report_b


def _resolve_frozen_bottles(
    frames: list[np.ndarray],
    records: list[TimedCaptureFrame],
) -> list[BottleDetection | None]:
    from_manifest = [bottle_from_manifest(record.bottle) for record in records]
    if len(from_manifest) == len(frames) and any(
        bottle is not None for bottle in from_manifest
    ):
        print("Bottle detections: reused frozen manifest boxes")
        return freeze_bottles(from_manifest)
    detected = [_maybe_detect_bottle(frame) for frame in frames]
    frozen = freeze_bottles(detected)
    found = sum(1 for bottle in frozen if bottle is not None)
    print(f"Bottle detections: computed once per frame bottles={found}/{len(frames)}")
    return frozen


def _print_fallback_ab_table(scenario: str, pass_a: dict, pass_b: dict) -> None:
    rows = [
        ("primary_calls", "{:.0f}", False),
        ("primary_successes_rate", "{:.1%}", False),
        ("primary_mean_ms", "{:.2f}", True),
        ("primary_median_ms", "{:.2f}", True),
        ("primary_p95_ms", "{:.2f}", True),
        ("fallback_attempts", "{:.0f}", True),
        ("fallback_successes", "{:.0f}", False),
        ("fallback_failures", "{:.0f}", True),
        ("fallback_recovery_rate", "{:.1%}", False),
        ("fallback_wasted_rate", "{:.1%}", True),
        ("rotated_attempts", "{:.0f}", True),
        ("rotated_successes", "{:.0f}", False),
        ("rotated_failures", "{:.0f}", True),
        ("rotated_mean_ms", "{:.2f}", True),
        ("rotated_median_ms", "{:.2f}", True),
        ("rotated_p95_ms", "{:.2f}", True),
        ("bartender_attempts", "{:.0f}", True),
        ("bartender_successes", "{:.0f}", False),
        ("bartender_failures", "{:.0f}", True),
        ("bartender_mean_ms", "{:.2f}", True),
        ("bartender_median_ms", "{:.2f}", True),
        ("bartender_p95_ms", "{:.2f}", True),
        ("fallback_extra_latency_ms", "{:.2f}", True),
        ("rotated_cost_per_recovery_ms", "{:.2f}", True),
        ("bartender_cost_per_recovery_ms", "{:.2f}", True),
        ("hands_mean_ms", "{:.2f}", True),
        ("hands_median_ms", "{:.2f}", True),
        ("hands_p95_ms", "{:.2f}", True),
        ("hands_fps", "{:.2f}", False),
        ("usable_rate", "{:.1%}", False),
        ("no_hand_rate", "{:.1%}", True),
        ("usable_miss_transitions", "{:.0f}", True),
        ("usable_longest_miss_run", "{:.0f}", True),
        ("hand_count_changes", "{:.0f}", True),
        ("usable_landmark_continuity", "{:.1%}", False),
        ("jitter_final_mean", "{:.5f}", True),
        ("jitter_final_p95", "{:.5f}", True),
        ("recovered_frames_due_to_fallback", "{:.0f}", False),
    ]
    print(f"--- A/B fallback table: {scenario} ---")
    print(f"{'metric':<34} {'A fallback':>12} {'B none':>12} {'delta(B-A)':>12}")
    for key, fmt, lower_is_better in rows:
        if key == "primary_successes_rate":
            left = pass_a["primary_success_rate"]
            right = pass_b["primary_success_rate"]
        else:
            left = pass_a.get(key, 0.0)
            right = pass_b.get(key, 0.0)
        if fmt.endswith("%") and not fmt.endswith("%}"):
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = f"{right - left:+.1f}"
        elif fmt == "{:.1%}":
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = f"{(right - left) * 100:+.1f}pp"
        else:
            left_text = fmt.format(left)
            right_text = fmt.format(right)
            delta_text = fmt.format(right - left)
            if not str(delta_text).startswith("-"):
                delta_text = "+" + delta_text
        marker = ""
        if left != right and key not in {
            "recovered_frames_due_to_fallback",
            "fallback_attempts",
            "fallback_successes",
        }:
            improved = (right < left) if lower_is_better else (right > left)
            marker = "  improved" if improved else "  worse"
        print(
            f"{key:<34} {left_text:>12} {right_text:>12} {delta_text:>12}{marker}"
        )


def _run_fallback_ab_scenario(
    name: str,
    config: dict,
    frames: list[np.ndarray],
    bottles: list[BottleDetection | None],
    captured_at: list[float | None],
    warmup: int,
) -> tuple[dict, dict, dict, dict]:
    replay = fallback_ab_replay(
        frames,
        bottles=bottles,
        captured_at=captured_at,
        max_num_hands=int(config["max_num_hands"]),
        rotated_fallback=bool(config["rotated_fallback"]),
        bartender_roi_fallback=bool(config["bartender_roi_fallback"]),
    )
    require_bartender = bool(config["bartender_roi_fallback"])
    detector_a = HandsDetector(
        timestamp_clock=Synthetic33TimestampClock(),
        **replay["kwargs_a"],
    )
    detector_b = HandsDetector(
        timestamp_clock=Synthetic33TimestampClock(),
        **replay["kwargs_b"],
    )
    try:
        report_a = _run_detector_detailed(
            detector_a,
            replay["frames_a"],
            warmup=warmup,
            bottles=replay["bottles_a"],
            captured_at=replay["captured_at_a"],
            require_bartender_candidate=require_bartender,
        )
        report_b = _run_detector_detailed(
            detector_b,
            replay["frames_b"],
            warmup=warmup,
            bottles=replay["bottles_b"],
            captured_at=replay["captured_at_b"],
            require_bartender_candidate=require_bartender,
        )
    finally:
        detector_a.close()
        detector_b.close()
    pass_a = _pass_metrics("A fallback on", report_a)
    pass_b = _pass_metrics("B fallback off", report_b)
    recovered = recovered_frames_due_to_fallback(
        report_a["usable"],
        report_b["usable"],
    )
    pass_a["recovered_frames_due_to_fallback"] = float(recovered)
    pass_b["recovered_frames_due_to_fallback"] = 0.0
    _print_fallback_ab_table(name, pass_a, pass_b)
    print(
        f"{name}: recovered_frames_due_to_fallback={recovered} "
        f"recovery={pass_a['fallback_recovery_rate']:.1%} "
        f"wasted={pass_a['fallback_wasted_rate']:.1%} "
        f"cost_rot={pass_a['rotated_cost_per_recovery_ms']:.1f}ms "
        f"cost_roi={pass_a['bartender_cost_per_recovery_ms']:.1f}ms "
        f"usable {pass_a['usable_rate']:.1%} -> {pass_b['usable_rate']:.1%} "
        f"Hands p95 {pass_a['hands_p95_ms']:.1f} -> {pass_b['hands_p95_ms']:.1f}ms"
    )
    print(f"A scenes ({name}):")
    _print_scene_breakdown(report_a["scenes"])
    print(f"B scenes ({name}):")
    _print_scene_breakdown(report_b["scenes"])
    return pass_a, pass_b, report_a, report_b


def _summarize_ab(results: list[tuple[str, dict, dict]]) -> None:
    print("--- A/B hypothesis ---")
    print(
        "Hypothesis: real capture timing -> better VIDEO temporal fidelity "
        "-> fewer primary misses -> fewer IMAGE fallbacks -> lower Hands p95."
    )
    material = False
    for name, pass_a, pass_b in results:
        miss_delta = pass_b["primary_empty_rate"] - pass_a["primary_empty_rate"]
        fb_delta = (
            pass_b["fallback_activation_pct"] - pass_a["fallback_activation_pct"]
        )
        p95_delta = pass_b["hands_p95_ms"] - pass_a["hands_p95_ms"]
        success_delta = (
            pass_b["primary_success_rate"] - pass_a["primary_success_rate"]
        )
        helped = miss_delta <= -0.03 or fb_delta <= -3.0
        if helped:
            material = True
        print(
            f"{name}: success {pass_a['primary_success_rate']:.1%} -> "
            f"{pass_b['primary_success_rate']:.1%} ({success_delta * 100:+.1f}pp) "
            f"fallback {pass_a['fallback_activation_pct']:.1f}% -> "
            f"{pass_b['fallback_activation_pct']:.1f}% ({fb_delta:+.1f}pp) "
            f"Hands p95 {pass_a['hands_p95_ms']:.1f} -> "
            f"{pass_b['hands_p95_ms']:.1f}ms ({p95_delta:+.1f}ms)"
        )
    if material:
        print(
            "Result: real timestamps reduced misses/fallbacks enough to be "
            "worth a production trial."
        )
    else:
        print(
            "Result: real timestamps did not reduce misses/fallbacks "
            "meaningfully on this sequence."
        )


def _print_roi_policy_table(label: str, metrics: dict, delay: dict | None) -> None:
    print(f"--- Bartender ROI policy: {label} ---")
    rows = [
        ("eligible_frames", "{:.0f}"),
        ("attempts", "{:.0f}"),
        ("successes", "{:.0f}"),
        ("failures", "{:.0f}"),
        ("recovery_rate", "{:.1%}"),
        ("wasted_rate", "{:.1%}"),
        ("roi_mean_ms", "{:.2f}"),
        ("roi_median_ms", "{:.2f}"),
        ("roi_p95_ms", "{:.2f}"),
        ("total_roi_time_ms", "{:.2f}"),
        ("primary_calls", "{:.0f}"),
        ("primary_hand_success", "{:.0f}"),
        ("primary_no_hand_rate", "{:.1%}"),
        ("primary_mean_ms", "{:.2f}"),
        ("primary_median_ms", "{:.2f}"),
        ("primary_p95_ms", "{:.2f}"),
        ("usable_frames", "{:.0f}"),
        ("usable_rate", "{:.1%}"),
        ("no_candidate_rate", "{:.1%}"),
        ("longest_usable_miss_run", "{:.0f}"),
        ("miss_transitions", "{:.0f}"),
        ("continuity", "{:.1%}"),
        ("hand_count_changes", "{:.0f}"),
        ("hands_mean_ms", "{:.2f}"),
        ("hands_median_ms", "{:.2f}"),
        ("hands_p95_ms", "{:.2f}"),
        ("hands_fps", "{:.2f}"),
    ]
    for key, fmt in rows:
        value = metrics.get(key, 0.0)
        print(f"{key:<28} {fmt.format(value)}")
    if delay is not None:
        print(f"{'a_recoveries':<28} {delay['a_recoveries']:.0f}")
        print(f"{'preserved_recoveries':<28} {delay.get('preserved_recoveries', delay['immediate_recoveries']):.0f}")
        print(f"{'delayed_recoveries':<28} {delay['delayed_recoveries']:.0f}")
        print(f"{'lost_recoveries':<28} {delay['lost_recoveries']:.0f}")
        print(
            f"{'mean_recovery_delay_frames':<28} "
            f"{delay['mean_recovery_delay_frames']:.2f}"
        )
        print(
            f"{'mean_recovery_delay_ms':<28} {delay['mean_recovery_delay_ms']:.2f}"
        )
        print(
            f"{'max_recovery_delay_frames':<28} "
            f"{delay['max_recovery_delay_frames']:.0f}"
        )
        print(
            f"{'max_recovery_delay_ms':<28} {delay['max_recovery_delay_ms']:.2f}"
        )
    waste = metrics.get("waste_counts") or {}
    if waste:
        total_waste = sum(waste.values())
        print("Wasted ROI reasons:")
        for reason, count in sorted(waste.items(), key=lambda item: (-item[1], item[0])):
            pct = (100.0 * count / total_waste) if total_waste else 0.0
            print(f"  {reason}: {count} ({pct:.1f}%)")
    elif metrics["failures"] > 0:
        print("Wasted ROI reasons: (none classified)")


def _print_capture_quality(quality: dict) -> None:
    print("--- Capture quality ---")
    print(f"total captured frames: {quality['total_captured_frames']}")
    print(f"measured frames: {quality['measured_frames']}")
    print(f"span_ms: {quality['span_ms']}")
    print(
        f"capture interval mean/median/p95 ms: "
        f"{quality['interval_mean_ms']:.2f} / "
        f"{quality['interval_median_ms']:.2f} / "
        f"{quality['interval_p95_ms']:.2f}"
    )
    print(
        f"bottle-present: {quality['bottle_present_frames']} "
        f"({quality['bottle_present_rate']:.1%})"
    )
    print(
        f"primary-hand-present: {quality['primary_hand_present_frames']} "
        f"({quality['primary_hand_present_rate']:.1%})"
    )
    print("Scene coverage (human tags):")
    for tag in SCENE_TAGS:
        print(f"  {tag}: {quality['tag_counts'].get(tag, 0)}")
    print(f"longest consecutive no-bottle run: {quality['longest_no_bottle_run']}")
    print(f"longest consecutive no-hand run: {quality['longest_no_hand_run']}")
    for note in quality.get("notes") or []:
        print(note)
    if quality["valid_for_production_decision"]:
        print("Capture quality: VALID FOR PRODUCTION DECISION")
    else:
        print("CAPTURE INVALID FOR PRODUCTION DECISION")
        for reason in quality.get("invalid_reasons") or []:
            print(f"  - {reason}")


def _scene_tag_breakdown(
    records: list[TimedCaptureFrame],
    replay_a: StrategyReplay,
    replay_b: StrategyReplay,
) -> dict[str, dict]:
    reports: dict[str, dict] = {}
    n = min(len(records), len(replay_a.events), len(replay_b.events))
    for tag in SCENE_TAGS:
        indexes = [i for i in range(n) if records[i].scene_tag == tag]
        if not indexes:
            continue
        def _rate(replay: StrategyReplay) -> float:
            flags = [replay.usable[i] for i in indexes]
            return sum(1 for flag in flags if flag) / len(flags) if flags else 0.0

        def _roi(replay: StrategyReplay, key: str) -> int:
            return sum(1 for i in indexes if replay.events[i].get(key))

        def _hands(replay: StrategyReplay) -> float:
            samples = [replay.hands_samples_s[i] for i in indexes]
            return timing_stats(samples)["mean_ms"]

        a_rec_idx = []
        previous = False
        for i in indexes:
            recovered_now = bool(
                replay_a.events[i].get("ran_roi") and replay_a.events[i].get("recovered")
            )
            if recovered_now and not previous:
                a_rec_idx.append(i)
            previous = recovered_now
        lost = 0
        if a_rec_idx:
            lost = int(
                measure_recovery_delay_for_indices(
                    replay_a.events,
                    replay_b.events,
                    a_rec_idx,
                )["lost_recoveries"]
            )
        reports[tag] = {
            "frames": len(indexes),
            "usable_a": _rate(replay_a),
            "usable_b": _rate(replay_b),
            "roi_attempts_a": _roi(replay_a, "ran_roi"),
            "roi_attempts_b": _roi(replay_b, "ran_roi"),
            "recoveries_a": len(a_rec_idx),
            "recoveries_b": _roi(replay_b, "recovered"),
            "lost_recoveries": lost,
            "hands_mean_a": _hands(replay_a),
            "hands_mean_b": _hands(replay_b),
        }
    return reports


def _run_abc_roi_benchmark(
    frames: list[np.ndarray],
    bottles: list[BottleDetection | None],
    records: list[TimedCaptureFrame],
    warmup: int,
) -> dict:
    measure_offset = warmup if warmup < len(frames) else 0
    measured_frames = frames[measure_offset:]
    measured_bottles = bottles[measure_offset:]
    measured_records = records[measure_offset:] if records else []
    detector = HandsDetector(
        max_num_hands=1,
        rotated_fallback=False,
        bartender_roi_fallback=False,
        timestamp_clock=Synthetic33TimestampClock(),
    )
    policies = {
        "A": ImmediateRoiPolicy(),
        "B": ConsecutiveMissRoiPolicy(n=2),
    }
    replays = {name: StrategyReplay(label=name) for name in policies}
    primary_hits: list[bool] = []
    snap = {}
    primary_cache: list[tuple[HandsResult | None, float]] = []
    quality: dict | None = None
    try:
        for index in range(warmup):
            detector.detect(
                frames[index % len(frames)],
                bottle=bottles[index % len(bottles)],
                captured_at_monotonic=None,
            )
        detector.stats.reset()
        for local, frame in enumerate(measured_frames):
            bottle = measured_bottles[local]
            started = time.perf_counter()
            primary = detector.detect(
                frame,
                bottle=bottle,
                captured_at_monotonic=None,
            )
            primary_s = time.perf_counter() - started
            primary_cache.append((primary, primary_s))
            primary_hits.append(bool(primary is not None and primary.hands))
        snap = detector.stats.snapshot()
        tags_supplied = any(record.scene_tag for record in measured_records)
        quality = evaluate_capture_quality(
            measured_records
            if measured_records
            else [
                TimedCaptureFrame(
                    filename=f"{index:04d}.jpg",
                    sequence=index,
                    captured_at_monotonic=0.0,
                    relative_time_ms=0,
                )
                for index in range(len(measured_frames))
            ],
            measured_bottles,
            primary_hits,
            tags_supplied=tags_supplied,
        )
        _print_capture_quality(quality)

        for local, frame in enumerate(measured_frames):
            bottle = measured_bottles[local]
            rel_ms = 0
            if local < len(measured_records):
                rel_ms = measured_records[local].relative_time_ms
            primary, primary_s = primary_cache[local]
            roi_cache: tuple[HandsResult | None, float] | None = None

            def roi_fn(
                current_frame=frame,
                current_bottle=bottle,
            ):
                nonlocal roi_cache
                if current_bottle is None:
                    return None, 0.0
                if roi_cache is None:
                    roi_started = time.perf_counter()
                    roi_cache = (
                        detector._detect_bartender_roi(
                            current_frame,
                            current_bottle,
                        ),
                        time.perf_counter() - roi_started,
                    )
                return roi_cache

            height, width = frame.shape[:2]
            primary_usable = False
            if bottle is not None:
                primary_usable = _has_bartender_candidate(
                    primary,
                    bottle,
                    frame_width=width,
                    frame_height=height,
                )
            primary_had_hand = bool(primary is not None and primary.hands)
            for name, policy in policies.items():
                outcome = evaluate_policy_frame(
                    policy,
                    primary=primary,
                    bottle=bottle,
                    frame_width=width,
                    frame_height=height,
                    roi_fn=roi_fn,
                    max_num_hands=1,
                )
                replay = replays[name]
                if outcome.eligible:
                    replay.eligible += 1
                if outcome.ran_roi:
                    replay.attempts += 1
                    replay.roi_samples_s.append(outcome.roi_seconds)
                    if outcome.recovered:
                        replay.successes += 1
                    else:
                        replay.failures += 1
                        if outcome.waste_reason:
                            replay.waste_reasons.append(outcome.waste_reason)
                replay.hands_samples_s.append(
                    primary_s + (outcome.roi_seconds if outcome.ran_roi else 0.0)
                )
                usable = False
                if bottle is not None:
                    usable = _has_bartender_candidate(
                        outcome.output,
                        bottle,
                        frame_width=width,
                        frame_height=height,
                    )
                replay.usable.append(usable)
                replay.hand_counts.append(
                    0 if outcome.output is None else len(outcome.output.hands)
                )
                replay.events.append(
                    {
                        "ran_roi": outcome.ran_roi,
                        "recovered": outcome.recovered,
                        "primary_usable": primary_usable,
                        "primary_had_hand": primary_had_hand,
                        "bottle_present": bottle is not None,
                        "relative_time_ms": rel_ms,
                        "usable": usable,
                    }
                )
        snap = detector.stats.snapshot()
    finally:
        detector.close()

    summaries = {
        name: summarize_strategy(replay) for name, replay in replays.items()
    }
    primary_success = float(sum(1 for hit in primary_hits if hit))
    primary_n = float(len(primary_hits) or 1)
    for summary in summaries.values():
        summary["primary_calls"] = float(snap.get("primary_calls", len(primary_hits)))
        summary["primary_hand_success"] = primary_success
        summary["primary_no_hand_rate"] = 1.0 - (primary_success / primary_n)
        summary["primary_mean_ms"] = float(snap.get("primary_mean_ms", 0.0))
        summary["primary_median_ms"] = float(snap.get("primary_median_ms", 0.0))
        summary["primary_p95_ms"] = float(snap.get("primary_p95_ms", 0.0))
        summary["no_candidate_rate"] = 1.0 - float(summary["usable_rate"])
    delay_b = measure_recovery_delay(replays["A"].events, replays["B"].events)
    miss_buckets = classify_immediate_recoveries(replays["A"].events)
    first_miss_idx = first_miss_recovery_indices(replays["A"].events)
    first_miss_cmp = measure_recovery_delay_for_indices(
        replays["A"].events,
        replays["B"].events,
        first_miss_idx,
    )
    print(
        "--- Bartender ROI A/B (same frames, frozen YOLO, shared primary) ---"
    )
    print(
        "Production remains A/immediate. B is benchmark-only N=2. "
        "Usable = bartender candidate (landmarks 4/8 control in contact zone), "
        "not merely any hand."
    )
    _print_roi_policy_table("A CURRENT immediate", summaries["A"], None)
    _print_roi_policy_table("B N=2 consecutive miss", summaries["B"], delay_b)
    print("--- Immediate A recovery miss buckets ---")
    print(f"A recoveries: {miss_buckets['a_recoveries']}")
    print(f"first miss: {miss_buckets['first_miss']}")
    print(f"second miss: {miss_buckets['second_miss']}")
    print(f"third+: {miss_buckets['third_or_later']}")
    print(f"primary had no hand: {miss_buckets['primary_no_hand']}")
    print(
        "primary saw a hand but bartender control point was outside zone: "
        f"{miss_buckets['primary_hand_outside_zone']}"
    )
    print("--- First-miss safety ---")
    print(f"first-miss A recoveries: {len(first_miss_idx)}")
    print(f"first-miss preserved: {first_miss_cmp['preserved_recoveries']:.0f}")
    print(f"first-miss delayed: {first_miss_cmp['delayed_recoveries']:.0f}")
    print(f"first-miss lost: {first_miss_cmp['lost_recoveries']:.0f}")
    attempts_saved_b = summaries["A"]["attempts"] - summaries["B"]["attempts"]
    latency_saved_b = (
        summaries["A"]["total_roi_time_ms"] - summaries["B"]["total_roi_time_ms"]
    )
    print(f"ROI attempts saved vs A: B={attempts_saved_b:.0f}")
    print(f"Total ROI latency saved vs A: B={latency_saved_b:.1f}ms")
    print(
        f"Usable candidate rate: A={summaries['A']['usable_rate']:.1%} "
        f"B={summaries['B']['usable_rate']:.1%} "
        f"({(summaries['B']['usable_rate'] - summaries['A']['usable_rate']) * 100:+.1f}pp)"
    )
    print(
        f"Longest usable-miss: A={summaries['A']['longest_usable_miss_run']:.0f} "
        f"B={summaries['B']['longest_usable_miss_run']:.0f}"
    )
    tags_supplied = any(record.scene_tag for record in measured_records)
    scene_reports = _scene_tag_breakdown(
        measured_records, replays["A"], replays["B"]
    )
    if not tags_supplied:
        print("Human scene tags were not supplied.")
    else:
        print("--- Scene-tag breakdown ---")
        for tag, row in scene_reports.items():
            print(
                f"{tag}: frames={row['frames']} "
                f"usable A={row['usable_a']:.1%} B={row['usable_b']:.1%} "
                f"ROI A={row['roi_attempts_a']} B={row['roi_attempts_b']} "
                f"recoveries A={row['recoveries_a']} B={row['recoveries_b']} "
                f"lost={row['lost_recoveries']} "
                f"Hands mean A={row['hands_mean_a']:.2f}ms B={row['hands_mean_b']:.2f}ms"
            )
    valid_hold_ok = True
    partial_ok = True
    if "valid_hold" in scene_reports:
        valid_hold_ok = (
            scene_reports["valid_hold"]["usable_a"]
            - scene_reports["valid_hold"]["usable_b"]
        ) <= 0.01
    elif tags_supplied:
        valid_hold_ok = False
    else:
        valid_hold_ok = False
    if "partial_occlusion" in scene_reports:
        partial_ok = (
            scene_reports["partial_occlusion"]["usable_a"]
            - scene_reports["partial_occlusion"]["usable_b"]
        ) <= 0.01
    elif tags_supplied:
        partial_ok = False
    else:
        partial_ok = False
    capture_valid = bool(quality and quality.get("valid_for_production_decision"))
    rec_b = n2_recommendation(
        summaries["A"],
        summaries["B"],
        delay_b,
        capture_valid=capture_valid,
        first_miss_lost=int(first_miss_cmp["lost_recoveries"]),
        valid_hold_ok=valid_hold_ok,
        partial_occlusion_ok=partial_ok,
    )
    print("--- N=2 decision criteria ---")
    for key in (
        "capture_valid",
        "attempts_materially_decrease",
        "roi_time_materially_decreases",
        "latency_materially_improves",
        "usable_rate_ok",
        "no_lost_recoveries",
        "delay_ok_for_coaching",
        "longest_miss_ok",
        "first_miss_ok",
        "valid_hold_ok",
        "partial_occlusion_ok",
    ):
        print(f"  {key}: {rec_b[key]}")
    if not capture_valid:
        print("KEEP CURRENT PRODUCTION BEHAVIOR UNTIL VALID CAPTURE EXISTS.")
    print(f"N=2 production_recommendation: {rec_b['production_recommendation']}")
    waste_a = summaries["A"].get("waste_counts") or {}
    waste_total = sum(waste_a.values())
    no_hand = waste_a.get("roi_returned_no_hand", 0)
    outside = waste_a.get("hand_outside_bartender_zone", 0)
    crop = waste_a.get("crop_likely_excludes_hand", 0)
    geom = waste_a.get("bottle_contact_geometry_impossible", 0)
    effectiveness_heavy = waste_total > 0 and (no_hand + outside + crop + geom) / waste_total >= 0.5
    gating_heavy = summaries["A"]["wasted_rate"] >= 0.5 and summaries["A"]["attempts"] > 0
    if effectiveness_heavy and summaries["A"]["recovery_rate"] < 0.25:
        problem = "weak ROI/crop effectiveness"
    elif gating_heavy and summaries["A"]["recovery_rate"] >= 0.25:
        problem = "excessive ROI frequency"
    elif waste_total > 0:
        problem = "both"
    else:
        problem = "insufficient wasted-ROI evidence"
    print(f"Dominant issue: {problem}")
    if not capture_valid:
        rec_b["use_n2"] = False
        rec_b["production_recommendation"] = "KEEP IMMEDIATE ROI"
    return {
        "summaries": summaries,
        "delay_b": delay_b,
        "miss_buckets": miss_buckets,
        "first_miss": first_miss_cmp,
        "scene_reports": scene_reports,
        "valid_hold_ok": valid_hold_ok,
        "partial_occlusion_ok": partial_ok,
        "primary_hits": primary_hits,
        "quality": quality,
        "recommendation": rec_b,
        "problem": problem,
    }


def _print_crop_variant_table(label: str, metrics: dict) -> None:
    print(f"--- Crop {label} ---")
    print(f"formula: {metrics.get('formula', '')}")
    rows = [
        ("mean_crop_width", "{:.1f}"),
        ("mean_crop_height", "{:.1f}"),
        ("mean_crop_area", "{:.0f}"),
        ("area_fraction", "{:.2%}"),
        ("eligible_frames", "{:.0f}"),
        ("attempts", "{:.0f}"),
        ("hand_returned", "{:.0f}"),
        ("successes", "{:.0f}"),
        ("failures", "{:.0f}"),
        ("recovery_rate", "{:.1%}"),
        ("wasted_rate", "{:.1%}"),
        ("roi_mean_ms", "{:.2f}"),
        ("roi_median_ms", "{:.2f}"),
        ("roi_p95_ms", "{:.2f}"),
        ("total_roi_time_ms", "{:.2f}"),
        ("usable_rate", "{:.1%}"),
        ("hands_mean_ms", "{:.2f}"),
        ("hands_median_ms", "{:.2f}"),
        ("hands_p95_ms", "{:.2f}"),
        ("hands_fps", "{:.2f}"),
    ]
    for key, fmt in rows:
        print(f"{key:<28} {fmt.format(metrics.get(key, 0.0))}")
    waste = metrics.get("waste_counts") or {}
    if waste:
        total = sum(waste.values())
        print("Failure breakdown:")
        for reason, count in sorted(waste.items(), key=lambda item: (-item[1], item[0])):
            pct = (100.0 * count / total) if total else 0.0
            print(f"  {reason}: {count} ({pct:.1f}%)")
    containment = metrics.get("containment") or {}
    if containment:
        print("Crop containment (primary hand vs this ROI, eligible frames with a primary hand):")
        print(
            f"  n={containment.get('n', 0)} "
            f"fully_inside={containment.get('fully_inside', 0)} "
            f"partially_inside={containment.get('partially_inside', 0)} "
            f"mostly_outside={containment.get('mostly_outside', 0)} "
            f"completely_outside={containment.get('completely_outside', 0)}"
        )
        print(
            f"  mean landmark fraction={containment.get('mean_landmark_fraction', 0.0):.1%} "
            f"wrist={containment.get('wrist_rate', 0.0):.1%} "
            f"thumb4={containment.get('thumb_rate', 0.0):.1%} "
            f"index8={containment.get('index_rate', 0.0):.1%} "
            f"bbox overlap={containment.get('mean_bbox_overlap', 0.0):.1%}"
        )


def _run_crop_benchmark(
    frames: list[np.ndarray],
    bottles: list[BottleDetection | None],
    records: list[TimedCaptureFrame],
    *,
    debug_dir: Path,
) -> dict:
    detector = HandsDetector(
        max_num_hands=1,
        rotated_fallback=False,
        bartender_roi_fallback=False,
    )
    primaries: list[HandsResult | None] = []
    primary_samples: list[float] = []
    try:
        detector.stats.reset()
        for frame, bottle in zip(frames, bottles):
            started = time.perf_counter()
            primary = detector.detect(
                frame,
                bottle=bottle,
                captured_at_monotonic=None,
            )
            primary_samples.append(time.perf_counter() - started)
            primaries.append(primary)
        height, width = frames[0].shape[:2]
        eligible = eligible_frame_indices(
            primaries,
            bottles,
            frame_width=width,
            frame_height=height,
        )
        print(f"Shared eligible frames: {len(eligible)}")
        print(f"A formula: {CROP_A.formula}")
        print(f"B formula: {CROP_B.formula}")
        print(f"C formula: {CROP_C.formula}")
        print(f"D formula: {CROP_D.formula}")

        variant_rows: dict[str, dict] = {}
        recovery_ids: dict[str, list[int]] = {geo.name: [] for geo in CROP_VARIANTS_WITH_D}
        per_eligible: list[dict] = []
        for index in eligible:
            frame = frames[index]
            bottle = bottles[index]
            primary = primaries[index]
            row = {
                "index": index,
                "sequence": (
                    records[index].sequence
                    if index < len(records)
                    else index + 1
                ),
                "filename": (
                    records[index].filename
                    if index < len(records)
                    else f"{index + 1:04d}.jpg"
                ),
                "variants": {},
            }
            for geometry in CROP_VARIANTS_WITH_D:
                bounds = crop_bounds_for(
                    geometry, bottle, width, height
                )
                started = time.perf_counter()
                if geometry.uses_production_formula and bottle is not None:
                    recovered = detector._detect_bartender_roi(frame, bottle)
                else:
                    recovered = run_bartender_roi_crop(detector, frame, bounds)
                roi_s = time.perf_counter() - started
                outcome = classify_roi_outcome(
                    primary=primary,
                    recovered=recovered,
                    bottle=bottle,
                    frame_width=width,
                    frame_height=height,
                    crop_bounds=bounds,
                )
                containment = crop_containment(
                    primary,
                    bounds,
                    frame_width=width,
                    frame_height=height,
                )
                merged_usable = False
                if bottle is not None:
                    merged = _merge_hands(
                        primary,
                        recovered,
                        max_num_hands=1,
                    )
                    merged_usable = _has_bartender_candidate(
                        merged,
                        bottle,
                        frame_width=width,
                        frame_height=height,
                    )
                stats = variant_rows.setdefault(
                    geometry.name,
                    {
                        "geometry": geometry,
                        "eligible": 0,
                        "attempts": 0,
                        "hand_returned": 0,
                        "successes": 0,
                        "failures": 0,
                        "roi_samples": [],
                        "hands_samples": [],
                        "usable": [],
                        "waste": [],
                        "containment": [],
                    },
                )
                stats["eligible"] += 1
                stats["attempts"] += 1
                stats["roi_samples"].append(roi_s)
                stats["roi_by_index"] = stats.get("roi_by_index", {})
                stats["roi_by_index"][index] = roi_s
                stats["hands_samples"].append(primary_samples[index] + roi_s)
                stats["usable"].append(merged_usable)
                stats["containment"].append(containment)
                if outcome["hand_returned"]:
                    stats["hand_returned"] += 1
                if outcome["valid_recovery"]:
                    stats["successes"] += 1
                    recovery_ids[geometry.name].append(index)
                else:
                    stats["failures"] += 1
                    stats["waste"].append(outcome["reason"])
                row["variants"][geometry.name] = {
                    "valid": outcome["valid_recovery"],
                    "reason": outcome["reason"],
                    "hand_returned": outcome["hand_returned"],
                    "containment": containment["status"],
                    "bounds": bounds,
                }
            per_eligible.append(row)

        summaries = {}
        for geometry in CROP_VARIANTS_WITH_D:
            stats = variant_rows[geometry.name]
            areas = summarize_crop_areas(
                [bottles[index] for index in eligible],
                geometry,
                frame_width=width,
                frame_height=height,
            )
            roi = timing_stats(stats["roi_samples"])
            full_hands: list[float] = []
            full_usable: list[bool] = []
            recovered_set = set(recovery_ids[geometry.name])
            eligible_set = set(eligible)
            for index, (primary, bottle) in enumerate(zip(primaries, bottles)):
                roi_s = stats.get("roi_by_index", {}).get(index, 0.0)
                full_hands.append(primary_samples[index] + roi_s)
                if bottle is None:
                    full_usable.append(False)
                    continue
                if index in eligible_set:
                    full_usable.append(index in recovered_set)
                else:
                    full_usable.append(
                        _has_bartender_candidate(
                            primary,
                            bottle,
                            frame_width=width,
                            frame_height=height,
                        )
                    )
            hands = timing_stats(full_hands)
            attempts = stats["attempts"]
            waste_counts: dict[str, int] = {}
            for reason in stats["waste"]:
                waste_counts[reason] = waste_counts.get(reason, 0) + 1
            contain_rows = [
                item
                for item in stats["containment"]
                if item.get("status") != "no_primary_hand"
            ]
            status_counts = {
                "fully_inside": 0,
                "partially_inside": 0,
                "mostly_outside": 0,
                "completely_outside": 0,
            }
            for item in contain_rows:
                status = item.get("status")
                if status in status_counts:
                    status_counts[status] += 1
            n_c = len(contain_rows)
            summaries[geometry.name] = {
                "formula": geometry.formula,
                "mean_crop_width": areas["mean_width"],
                "mean_crop_height": areas["mean_height"],
                "mean_crop_area": areas["mean_area"],
                "area_fraction": areas["area_fraction"],
                "eligible_frames": float(stats["eligible"]),
                "attempts": float(attempts),
                "hand_returned": float(stats["hand_returned"]),
                "successes": float(stats["successes"]),
                "failures": float(stats["failures"]),
                "recovery_rate": stats["successes"] / attempts if attempts else 0.0,
                "wasted_rate": stats["failures"] / attempts if attempts else 0.0,
                "roi_mean_ms": roi["mean_ms"],
                "roi_median_ms": roi["median_ms"],
                "roi_p95_ms": roi["p95_ms"],
                "total_roi_time_ms": sum(stats["roi_samples"]) * 1000.0,
                "usable_rate": (
                    sum(1 for item in full_usable if item) / len(full_usable)
                    if full_usable
                    else 0.0
                ),
                "hands_mean_ms": hands["mean_ms"],
                "hands_median_ms": hands["median_ms"],
                "hands_p95_ms": hands["p95_ms"],
                "hands_fps": hands["fps"],
                "waste_counts": waste_counts,
                "containment": {
                    "n": n_c,
                    **status_counts,
                    "mean_landmark_fraction": (
                        sum(item["landmark_fraction"] for item in contain_rows) / n_c
                        if n_c
                        else 0.0
                    ),
                    "wrist_rate": (
                        sum(1 for item in contain_rows if item["wrist_contained"]) / n_c
                        if n_c
                        else 0.0
                    ),
                    "thumb_rate": (
                        sum(1 for item in contain_rows if item["thumb_contained"]) / n_c
                        if n_c
                        else 0.0
                    ),
                    "index_rate": (
                        sum(1 for item in contain_rows if item["index_contained"]) / n_c
                        if n_c
                        else 0.0
                    ),
                    "mean_bbox_overlap": (
                        sum(item["bbox_overlap"] for item in contain_rows) / n_c
                        if n_c
                        else 0.0
                    ),
                },
            }

        cmp_b = compare_recoveries(
            a_ids=recovery_ids["A"], variant_ids=recovery_ids["B"]
        )
        cmp_c = compare_recoveries(
            a_ids=recovery_ids["A"], variant_ids=recovery_ids["C"]
        )
        cmp_d = compare_recoveries(
            a_ids=recovery_ids["A"], variant_ids=recovery_ids["D"]
        )
        _print_crop_variant_table("A CURRENT PRODUCTION CROP", summaries["A"])
        _print_crop_variant_table("B moderately expanded (benchmark-only)", summaries["B"])
        _print_crop_variant_table("C generous diagnostic (benchmark-only)", summaries["C"])
        _print_crop_variant_table(
            "D FULL-FRAME IMAGE DIAGNOSTIC CEILING ONLY", summaries["D"]
        )
        print("--- Recovery comparison vs A ---")
        print(f"A recovery frame indices: {recovery_ids['A']}")
        print(f"B recovery frame indices: {recovery_ids['B']}")
        print(f"C recovery frame indices: {recovery_ids['C']}")
        print(f"D recovery frame indices: {recovery_ids['D']}")
        print(f"B additional vs A: {cmp_b['additional']}")
        print(f"C additional vs A: {cmp_c['additional']}")
        print(f"D additional vs A: {cmp_d['additional']}")
        print(f"B lost vs A: {cmp_b['lost_vs_a']}")
        print(f"C lost vs A: {cmp_c['lost_vs_a']}")
        print(f"D lost vs A: {cmp_d['lost_vs_a']}")
        rec = recommend_crop_trial(
            a_successes=int(summaries["A"]["successes"]),
            b_successes=int(summaries["B"]["successes"]),
            c_successes=int(summaries["C"]["successes"]),
            b_lost=cmp_b["lost_count"],
            c_lost=cmp_c["lost_count"],
            b_additional=cmp_b["additional_count"],
            c_additional=cmp_c["additional_count"],
            a_recovery_rate=summaries["A"]["recovery_rate"],
            b_recovery_rate=summaries["B"]["recovery_rate"],
            c_recovery_rate=summaries["C"]["recovery_rate"],
            d_successes=int(summaries["D"]["successes"]),
            eligible=len(eligible),
            b_unhelpful=(
                int(summaries["B"]["waste_counts"].get("hand_outside_bartender_zone", 0))
                + int(summaries["B"]["waste_counts"].get("duplicate_unhelpful_hand", 0))
            ),
            c_unhelpful=(
                int(summaries["C"]["waste_counts"].get("hand_outside_bartender_zone", 0))
                + int(summaries["C"]["waste_counts"].get("duplicate_unhelpful_hand", 0))
            ),
        )
        print("--- Decision (benchmark only; production crop unchanged) ---")
        print(f"root diagnosis: {rec['root']}")
        print(f"best candidate: {rec['best']}")
        print(f"live production trial: {rec['live_trial']}")
        print(f"decision: {rec['decision']}")

        debug_events = []
        for row in per_eligible:
            variants = row["variants"]
            a_ok = variants["A"]["valid"]
            b_ok = variants["B"]["valid"]
            c_ok = variants["C"]["valid"]
            if a_ok:
                kind = "a_success"
            elif b_ok or c_ok:
                kind = "b_or_c_only"
            elif variants["A"]["reason"] == "crop_likely_excludes_hand":
                kind = "crop_excludes"
            else:
                kind = "all_fail"
            debug_events.append({**row, "kind": kind})
        chosen = select_debug_examples(debug_events, limit=8)
        debug_dir.mkdir(parents=True, exist_ok=True)
        written = []
        for item in chosen:
            index = item["index"]
            bottle = bottles[index]
            path = debug_dir / f"{item['kind']}_{item['filename']}"
            write_crop_debug_image(
                frames[index],
                bottle,
                {
                    name: item["variants"][name]["bounds"]
                    for name in ("A", "B", "C")
                },
                path,
            )
            written.append(str(path))
        print("--- Debug images (source frames unmodified) ---")
        for path in written:
            print(f"  {path}")
        return {
            "eligible": eligible,
            "summaries": summaries,
            "recovery_ids": recovery_ids,
            "recommendation": rec,
            "debug_paths": written,
        }
    finally:
        detector.close()


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
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Capture manifest with captured_at_monotonic (required for fair B).",
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
    parser.add_argument(
        "--ab-timestamps",
        action="store_true",
        help="Capture one sequence, then replay A=+33 vs B=real timestamps.",
    )
    parser.add_argument(
        "--ab-only",
        action="store_true",
        help="Skip the legacy num_hands benchmark and only run selected A/B.",
    )
    parser.add_argument(
        "--ab-fallbacks",
        action="store_true",
        help="Same-frame A=fallback on vs B=fallback off. Production defaults unchanged.",
    )
    parser.add_argument(
        "--movement",
        default="",
        help="Optional movement label stored on captured manifest frames.",
    )
    parser.add_argument(
        "--capture-bartender",
        action="store_true",
        help="User-triggered dedicated Bartender's Grip capture (default 180 frames).",
    )
    parser.add_argument(
        "--abc-roi",
        action="store_true",
        help="Benchmark-only bartender ROI policies A immediate vs B N=2.",
    )
    parser.add_argument(
        "--crop-benchmark",
        action="store_true",
        help=(
            "Benchmark-only bartender ROI crop geometries A/B/C (+D ceiling) "
            "on an existing capture. Does not change production crop."
        ),
    )
    parser.add_argument(
        "--crop-debug-dir",
        type=Path,
        default=Path("hands_bartender_crop_debug"),
        help="Gitignored directory for a small crop-debug image subset.",
    )
    parser.add_argument(
        "--scene-tag",
        default="",
        help=(
            "Optional whole-sequence human scene tag. "
            f"Allowed: {', '.join(SCENE_TAGS)}."
        ),
    )
    parser.add_argument(
        "--annotate-tags",
        default="",
        help="Human scene tags as tag:start-end,tag:start-end (1-based inclusive).",
    )
    parser.add_argument(
        "--tag-range",
        action="append",
        default=[],
        help="Human scene range start:end=tag (0 means frame 1; end inclusive).",
    )
    parser.add_argument(
        "--capture-countdown",
        type=float,
        default=1.0,
        help="Seconds between 3-2-1 countdown steps after ENTER (bartender capture).",
    )
    parser.add_argument(
        "--capture-double-hand",
        action="store_true",
        help=(
            "User-triggered Double Hand Stall capture (default 300 frames). "
            "ENTER then 3-2-1; does not start while positioning."
        ),
    )
    parser.add_argument(
        "--primary-breakdown",
        action="store_true",
        help=(
            "Benchmark-only primary Hands stage timing, resolution diagnostic, "
            "and max_num_hands=1 lower bound. Does not change production."
        ),
    )
    args = parser.parse_args()
    if args.capture_bartender:
        args.movement = args.movement or "Bartender's Grip"
        if args.save is None:
            args.save = Path("hands_bartender_frames")
        args.abc_roi = True
        args.ab_only = True
    if args.capture_double_hand:
        args.movement = args.movement or "Double Hand Stall"
        if args.save is None:
            args.save = Path("hands_double_hand_frames")
        args.primary_breakdown = True
        args.ab_only = True
        args.capture_frames = max(args.capture_frames, 300)
        args.capture_timeout = max(args.capture_timeout, 60.0)
    if args.abc_roi:
        args.ab_only = True
    if args.primary_breakdown:
        args.ab_only = True
        if args.images is None and args.capture_double_hand is False and args.no_camera:
            args.images = Path("hands_double_hand_frames")
            if args.manifest is None:
                args.manifest = Path("hands_double_hand_frames/manifest.json")
        args.ab_only = True
    if args.crop_benchmark:
        args.ab_only = True
        args.no_camera = True
        if args.images is None:
            args.images = Path("hands_bartender_frames")
        if args.manifest is None:
            args.manifest = Path("hands_bartender_frames/manifest.json")

    labeled_synthetic = synthetic_scene_frames(
        height=FRAME_HEIGHT,
        width=FRAME_WIDTH,
    )
    frames: list[np.ndarray] = []
    timed_records: list[TimedCaptureFrame] = []
    source = "none"
    if args.images is not None and args.manifest is not None:
        frames, timed_records = _load_timed_images(args.images, args.manifest)
        source = f"timed_images:{args.images}"
    elif args.images is not None:
        frames = load_image_frames(args.images)
        source = f"images:{args.images}"
    elif not args.no_camera:
        try:
            capture_count = args.capture_frames
            timeout = args.capture_timeout
            if args.capture_bartender or args.capture_double_hand:
                min_frames = 180 if args.capture_bartender else 300
                capture_count = max(args.capture_frames, min_frames)
                timeout = max(args.capture_timeout, 60.0)
                from vision.camera import CameraCapture

                def _capture_with_owned_camera(
                    *,
                    camera,
                    count,
                    timeout_s,
                    progress_every=30,
                    print_fn=print,
                    **_kwargs,
                ):
                    return _capture_timed_camera_frames(
                        count,
                        timeout_s,
                        camera=camera,
                        progress_every=progress_every,
                        print_fn=print_fn,
                    )

                def _preview_bottle(camera) -> None:
                    preview = camera.peek_latest(timeout=1.0)
                    if preview is not None:
                        _maybe_detect_bottle(preview.frame)

                open_camera, capture_frames, release_camera = make_owned_camera_hooks(
                    camera_factory=CameraCapture,
                    capture_frames_fn=_capture_with_owned_camera,
                    after_open=_preview_bottle,
                )

                def _open_camera() -> bool:
                    opened = open_camera()
                    if not opened:
                        print("Camera unavailable.")
                    return opened

                try:
                    session = run_user_triggered_bartender_capture(
                        count=capture_count,
                        timeout_s=timeout,
                        input_fn=input,
                        sleep_fn=lambda _seconds: time.sleep(
                            args.capture_countdown if args.capture_countdown > 0 else 1.0
                        ),
                        print_fn=print,
                        open_camera_fn=_open_camera,
                        capture_frames_fn=capture_frames,
                        release_fn=release_camera,
                        close_detectors_fn=_close_bottle_detector,
                        progress_every=30,
                        ready_prompt=(
                            DOUBLE_HAND_READY_PROMPT
                            if args.capture_double_hand
                            else None
                        ),
                    )
                    if session.cancelled or not session.run_benchmark:
                        print(session.message or "Capture cancelled. Benchmark was not run.")
                        return
                    frames, timed_records = session.frames, session.records
                    source = f"camera:{len(frames)}"
                finally:
                    release_camera()
            elif args.ab_timestamps or args.ab_fallbacks:
                capture_count = max(args.capture_frames, args.warmup + 40)
                timeout = max(args.capture_timeout, 20.0)
                frames, timed_records = _capture_timed_camera_frames(
                    capture_count,
                    timeout,
                )
                source = f"camera:{len(frames)}"
            else:
                frames, timed_records = _capture_timed_camera_frames(
                    capture_count,
                    timeout,
                )
                source = f"camera:{len(frames)}"
        except KeyboardInterrupt:
            print("Capture cancelled. Benchmark was not run.")
            _close_bottle_detector()
            return
        except Exception as exc:
            print(f"Camera capture skipped: {exc}")
            source = "camera_failed"
            _close_bottle_detector()

    if args.synthetic or (
        not frames
        and not args.abc_roi
        and not args.capture_bartender
        and not args.capture_double_hand
        and not args.crop_benchmark
        and not args.primary_breakdown
    ):
        frames.extend(list(labeled_synthetic.values()))
        if source == "none" or source == "camera_failed":
            source = "synthetic"
        else:
            source = f"{source}+synthetic"

    unique_frames = frames
    if not unique_frames:
        print("No frames available for benchmark or capture.")
        return
    if args.crop_benchmark and not timed_records:
        print(
            "crop-benchmark requires an existing capture directory and manifest. "
            "No new footage was captured."
        )
        return
    replay = unique_frames
    if not args.ab_only:
        replay = cycle_frames(unique_frames, max(args.runs, len(unique_frames)))
    print(
        f"Hands benchmark source={source} unique_frames={len(unique_frames)} "
        f"replay={len(replay)} size={replay[0].shape} warmup={args.warmup} "
        f"model=hand_landmarker.task mode=VIDEO thresholds=0.5"
    )
    if timed_records:
        _print_capture_intervals(timed_records)

    unique_bottles: list[BottleDetection | None]
    if timed_records and len(timed_records) == len(unique_frames):
        unique_bottles = _resolve_frozen_bottles(unique_frames, timed_records)
    elif args.images is not None or source.startswith("camera"):
        unique_bottles = freeze_bottles(
            [_maybe_detect_bottle(frame) for frame in unique_frames]
        )
        found = sum(1 for bottle in unique_bottles if bottle is not None)
        print(
            f"Bottle detections: computed once per unique frame "
            f"bottles={found}/{len(unique_frames)}"
        )
    else:
        unique_bottles = [None] * len(unique_frames)
    if timed_records:
        if args.scene_tag:
            if args.scene_tag not in SCENE_TAGS:
                raise SystemExit(
                    f"Unknown --scene-tag {args.scene_tag!r}; "
                    f"allowed: {', '.join(SCENE_TAGS)}"
                )
            timed_records = apply_scene_tags(
                timed_records,
                [(args.scene_tag, 1, len(timed_records))],
            )
        if args.annotate_tags:
            timed_records = apply_scene_tags(
                timed_records,
                parse_scene_tag_spec(args.annotate_tags),
            )
        if args.tag_range:
            timed_records = apply_scene_tags(
                timed_records,
                parse_tag_range_args(args.tag_range),
            )
        tagged = sum(1 for record in timed_records if record.scene_tag)
        if tagged:
            print(
                f"Human scene tags: labeled={tagged}/{len(timed_records)} "
                "(not inferred from Hands/YOLO)."
            )
        else:
            print("Human scene tags were not supplied.")
    bottles = [
        unique_bottles[index % len(unique_bottles)]
        for index in range(len(replay))
    ]

    if not args.ab_only:
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
            delta_ms = (
                timing_stats(samples_2)["mean_ms"] - timing_stats(samples_1)["mean_ms"]
            )
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
        if timed_records and len(timed_records) == len(unique_frames):
            labeled = []
            for record, bottle in zip(timed_records, unique_bottles):
                labeled.append(
                    TimedCaptureFrame(
                        filename=record.filename,
                        sequence=record.sequence,
                        captured_at_monotonic=record.captured_at_monotonic,
                        relative_time_ms=record.relative_time_ms,
                        movement_label=args.movement or record.movement_label,
                        scene_tag=record.scene_tag,
                        bottle=bottle_to_manifest(bottle),
                    )
                )
            _save_timed_frames(args.save, unique_frames, labeled)
        else:
            import cv2

            args.save.mkdir(parents=True, exist_ok=True)
            for index, frame in enumerate(unique_frames, start=1):
                path = args.save / f"{index:03d}.jpg"
                cv2.imwrite(str(path), frame)
            print(
                f"Saved {len(unique_frames)} frames to {args.save} "
                "(no capture timestamps; A/B B-side is not valid from this dump)"
            )

    if args.ab_timestamps:
        print("--- timestamp A/B (same frames, only clock differs) ---")
        if not timed_records or len(timed_records) != len(unique_frames):
            print(
                "A/B skipped: real timestamps were not captured. "
                "Do not invent 33 ms for pass B. Re-run with a live camera "
                "or --images plus --manifest."
            )
            return
        ab_bottles = bottles[: len(unique_frames)]
        if len(ab_bottles) != len(unique_frames):
            ab_bottles = [_maybe_detect_bottle(frame) for frame in unique_frames]
        ab_warmup = min(args.warmup, max(0, len(unique_frames) - 8))
        print(
            f"A/B frames={len(unique_frames)} warmup={ab_warmup} "
            f"measured={len(unique_frames) - ab_warmup} "
            "clocks=Synthetic33 vs CaptureMonotonic(relative)"
        )
        print(
            "Limitation: scene labels are inferred from detections, not from "
            "a movement-annotated capture. Normal Grip and Claw Grip share "
            "the same Hands detector config (max_num_hands=1, rotated fallback)."
        )
        summaries: list[tuple[str, dict, dict]] = []
        for name, config in _AB_SCENARIOS:
            pass_a, pass_b, _report_a, _report_b = _run_ab_scenario(
                name,
                config,
                unique_frames,
                timed_records,
                ab_bottles,
                ab_warmup,
            )
            summaries.append((name, pass_a, pass_b))
        _summarize_ab(summaries)

    if args.ab_fallbacks:
        print("--- fallback A/B (same frames, only fallback enable/disable differs) ---")
        print(
            "Clock=+33 production VIDEO timestamp. "
            "Pass A=current fallback, Pass B=fallback disabled. "
            "Bottle boxes are frozen once and reused."
        )
        ab_warmup = min(args.warmup, max(0, len(unique_frames) - 8))
        captured_at = [None] * len(unique_frames)
        print(
            f"fallback A/B frames={len(unique_frames)} warmup={ab_warmup} "
            f"measured={len(unique_frames) - ab_warmup} "
            "defaults: max_num_hands production still 2, timestamp_clock still +33"
        )
        print(
            "Limitation: unless --movement was stored on the manifest, "
            "Normal Grip and Claw Grip share the same physical frames and "
            "the same Hands config (max_num_hands=1, rotated fallback)."
        )
        for name, config in _AB_SCENARIOS:
            _run_fallback_ab_scenario(
                name,
                config,
                unique_frames,
                unique_bottles,
                captured_at,
                ab_warmup,
            )

    if args.primary_breakdown:
        print("--- two-hand primary Hands diagnosis (benchmark-only) ---")
        print(
            f"source={source} frames={len(unique_frames)} "
            f"size={unique_frames[0].shape} warmup={args.warmup} "
            "fallbacks off; YOLO/Pose/camera untouched"
        )
        try:
            _run_primary_breakdown(unique_frames, args.warmup)
        finally:
            _close_bottle_detector()

    if args.abc_roi:
        print("--- dedicated Bartender capture / ROI policy A vs N=2 ---")
        movement_labels = {
            record.movement_label for record in timed_records if record.movement_label
        }
        bottles_found = sum(1 for bottle in unique_bottles if bottle is not None)
        print(
            f"Capture summary: source={source} frames={len(unique_frames)} "
            f"timed={len(timed_records)} bottles={bottles_found}/{len(unique_frames)} "
            f"movement={args.movement or ','.join(sorted(movement_labels)) or '(unlabeled)'}"
        )
        if not timed_records:
            print(
                "Warning: no capture manifest timestamps; recovery delay ms "
                "cannot use real capture intervals."
            )
        ab_warmup = 0
        print(
            f"A/B warmup={ab_warmup} measured={len(unique_frames) - ab_warmup} "
            "YOLO frozen once; primary VIDEO shared; ROI IMAGE cached per frame."
        )
        try:
            _run_abc_roi_benchmark(
                unique_frames,
                unique_bottles,
                timed_records,
                ab_warmup,
            )
        finally:
            _close_bottle_detector()

    if args.crop_benchmark:
        print("--- Bartender ROI crop geometry A/B/C (shared frames/primary/YOLO) ---")
        bottles_found = sum(1 for bottle in unique_bottles if bottle is not None)
        print(
            f"Capture: source={source} frames={len(unique_frames)} "
            f"bottles={bottles_found}/{len(unique_frames)} "
            "production crop unchanged; B/C/D are benchmark-only."
        )
        try:
            _run_crop_benchmark(
                unique_frames,
                unique_bottles,
                timed_records,
                debug_dir=args.crop_debug_dir,
            )
        finally:
            _close_bottle_detector()


if __name__ == "__main__":
    main()
