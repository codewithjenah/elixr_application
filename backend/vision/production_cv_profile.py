"""Aggregate production VisionSession CV timings. Diagnostic only.

Does not change detector construction, fallback rules, YOLO settings, or
session scoring. AI e2e in this module is ``processing_total`` (worker time),
not WebSocket send.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from assessment.hands_profile import HandsMovementProfile, hands_profile_for
from assessment.rule_engine import (
    movement_max_hands,
    movement_requires_hands,
    movement_requires_pose,
)
from vision.hands_diagnostics import HandsCallStats, timing_stats
from vision.pipeline_telemetry import (
    CaptureProducerSnapshot,
    PipelineTimings,
    interval_rate,
)

# Distinct production detector paths requested for live profiling.
# Reverse Grip is optional: same YOLO + max_num_hands=1 family as several
# stalls, but unlike Normal Grip it has no rotated/ROI fallback.
REPRESENTATIVE_MOVEMENTS: tuple[tuple[str, str], ...] = (
    ("Normal Grip", "YOLO + Hands max=1 + rotated fallback"),
    ("Bartender's Grip", "YOLO + Hands max=1 + immediate ROI fallback"),
    ("Claw Grip", "YOLO + Hands max=1 + rotated fallback"),
    ("Double Hand Stall", "YOLO + Hands max=2, no fallback"),
    ("Shoulder Stall", "YOLO + Pose; Hands disabled"),
)
OPTIONAL_NO_FALLBACK_MOVEMENT = "Reverse Grip"

_DOMINANT_SHARE = 0.50
_DOMINANT_MARGIN = 1.4
_FALLBACK_SHARE = 0.25
_FALLBACK_ACTIVATION = 0.20
_CAMERA_SHARE = 0.50
_ORCHESTRATION_SHARE = 0.50


@dataclass(frozen=True)
class ProductionCvSnapshot:
    movement: str
    requires_hands: bool
    requires_pose: bool
    hands_max: int
    hands_enabled: bool
    pose_enabled: bool
    warmup_s: float
    measured_s: float
    preview_fps: float
    ai_fps: float
    capture_fps: float
    capture_read_mean_ms: float
    capture_failures: int
    preview_drops: int
    ai_e2e_mean_ms: float
    ai_e2e_p95_ms: float
    preview_e2e_mean_ms: float
    yolo_calls: int
    yolo_mean_ms: float
    yolo_median_ms: float
    yolo_p95_ms: float
    yolo_calls_per_sec: float
    hands_mean_ms: float | None
    hands_p95_ms: float | None
    hands_primary_calls: int | None
    hands_primary_mean_ms: float | None
    hands_primary_p95_ms: float | None
    pose_mean_ms: float | None
    pose_p95_ms: float | None
    pose_calls: int | None
    fallback_type: str | None
    fallback_calls: int | None
    fallback_successes: int | None
    fallback_failures: int | None
    fallback_activation_pct: float | None
    fallback_mean_ms: float | None
    fallback_p95_ms: float | None
    yolo_share_pct: float
    hands_share_pct: float | None
    pose_share_pct: float | None
    fallback_share_pct: float | None
    share_notes: str
    bottleneck: str


def begin_measurement(session: Any) -> None:
    """Clear interval aggregates after warmup. Detector flags stay unchanged."""
    timings = getattr(session, "timings", None)
    if timings is not None and hasattr(timings, "reset"):
        timings.reset()
    preview = getattr(session, "preview_timings", None)
    if preview is not None and hasattr(preview, "reset"):
        preview.reset()
    hands = getattr(session, "hands_detector", None)
    stats = getattr(hands, "stats", None) if hands is not None else None
    reset = getattr(stats, "reset", None)
    if callable(reset):
        reset()


def _na_ms(enabled: bool, value: float) -> float | None:
    if not enabled:
        return None
    return value


def _fallback_type(stats: HandsCallStats | None) -> str | None:
    if stats is None:
        return None
    snap = stats.snapshot()
    rotated = int(snap["rotated_calls"])
    bartender = int(snap["bartender_calls"])
    if rotated > 0 and bartender > 0:
        return "rotated+bartender_roi"
    if rotated > 0:
        return "rotated"
    if bartender > 0:
        return "bartender_roi"
    if int(snap["fallback_activated_calls"]) > 0:
        return "fallback"
    return None


def _fallback_samples(stats: HandsCallStats) -> list[float]:
    return list(stats.rotated_fallback_samples_s) + list(
        stats.bartender_roi_samples_s
    )


def snapshot_from_parts(
    *,
    movement: str,
    preview_timings: PipelineTimings,
    ai_timings: PipelineTimings,
    elapsed_s: float,
    preview_frames: int,
    ai_frames: int,
    warmup_s: float,
    measured_s: float,
    capture: CaptureProducerSnapshot,
    preview_drops: int,
    hands_stats: HandsCallStats | None = None,
    hands_enabled: bool | None = None,
    pose_enabled: bool | None = None,
    profile: HandsMovementProfile | None = None,
) -> ProductionCvSnapshot:
    row = profile if profile is not None else hands_profile_for(movement)
    if hands_enabled is None:
        hands_enabled = row.active_scheduled_hands
    if pose_enabled is None:
        pose_enabled = row.active_needs_pose

    processing_sum = ai_timings.sum_s("processing_total")
    yolo_sum = ai_timings.sum_s("yolo")
    hands_sum = ai_timings.sum_s("hands")
    pose_sum = ai_timings.sum_s("pose")
    yolo_share = (yolo_sum / processing_sum * 100.0) if processing_sum > 0 else 0.0
    hands_share = (
        (hands_sum / processing_sum * 100.0)
        if hands_enabled and processing_sum > 0
        else None
    )
    pose_share = (
        (pose_sum / processing_sum * 100.0)
        if pose_enabled and processing_sum > 0
        else None
    )

    fallback_type = None
    fallback_calls = None
    fallback_successes = None
    fallback_failures = None
    fallback_activation_pct = None
    fallback_mean_ms = None
    fallback_p95_ms = None
    fallback_extra_s = 0.0
    primary_calls = None
    primary_mean = None
    primary_p95 = None
    if hands_enabled and hands_stats is not None:
        hs = hands_stats.snapshot()
        fallback_type = _fallback_type(hands_stats)
        fallback_calls = int(hs["fallback_activated_calls"])
        fallback_successes = int(hs["fallback_successes"])
        fallback_failures = int(hs["fallback_failures"])
        fallback_activation_pct = float(hs["fallback_activation_rate"]) * 100.0
        samples = _fallback_samples(hands_stats)
        if samples:
            fb = timing_stats(samples)
            fallback_mean_ms = fb["mean_ms"]
            fallback_p95_ms = fb["p95_ms"]
        fallback_extra_s = float(hs["fallback_extra_latency_ms"]) / 1000.0
        primary_calls = int(hs["primary_calls"])
        primary_mean = float(hs["primary_mean_ms"])
        primary_p95 = float(hs["primary_p95_ms"])

    fallback_share = None
    if hands_enabled and processing_sum > 0 and hands_stats is not None:
        fallback_share = fallback_extra_s / processing_sum * 100.0

    share_notes = (
        "YOLO/Hands/Pose percentages are estimates: stage_sum / AI "
        "processing_total_sum. Stages are sequential and non-overlapping. "
        "Fallback percentage is a subset of Hands (not additive with Hands). "
        "AI e2e is processing_total (excludes WebSocket send)."
    )

    ai_e2e_mean = ai_timings.average_ms("processing_total")
    ai_e2e_p95 = ai_timings.percentile_ms("processing_total", 95)
    preview_e2e = preview_timings.average_ms("processing_total")
    if preview_e2e <= 0:
        preview_e2e = preview_timings.average_ms("end_to_end")

    snap = ProductionCvSnapshot(
        movement=movement,
        requires_hands=movement_requires_hands(movement),
        requires_pose=movement_requires_pose(movement),
        hands_max=movement_max_hands(movement),
        hands_enabled=hands_enabled,
        pose_enabled=pose_enabled,
        warmup_s=warmup_s,
        measured_s=measured_s,
        preview_fps=interval_rate(preview_frames, elapsed_s),
        ai_fps=interval_rate(ai_frames, elapsed_s),
        capture_fps=interval_rate(capture.usable_frames, elapsed_s),
        capture_read_mean_ms=capture.read_avg_ms,
        capture_failures=capture.failed_reads,
        preview_drops=preview_drops,
        ai_e2e_mean_ms=ai_e2e_mean,
        ai_e2e_p95_ms=ai_e2e_p95,
        preview_e2e_mean_ms=preview_e2e,
        yolo_calls=ai_timings.count("yolo"),
        yolo_mean_ms=ai_timings.average_ms("yolo"),
        yolo_median_ms=ai_timings.median_ms("yolo"),
        yolo_p95_ms=ai_timings.percentile_ms("yolo", 95),
        yolo_calls_per_sec=interval_rate(ai_timings.count("yolo"), elapsed_s),
        hands_mean_ms=_na_ms(hands_enabled, ai_timings.average_ms("hands")),
        hands_p95_ms=_na_ms(hands_enabled, ai_timings.percentile_ms("hands", 95)),
        hands_primary_calls=primary_calls if hands_enabled else None,
        hands_primary_mean_ms=primary_mean if hands_enabled else None,
        hands_primary_p95_ms=primary_p95 if hands_enabled else None,
        pose_mean_ms=_na_ms(pose_enabled, ai_timings.average_ms("pose")),
        pose_p95_ms=_na_ms(pose_enabled, ai_timings.percentile_ms("pose", 95)),
        pose_calls=ai_timings.count("pose") if pose_enabled else None,
        fallback_type=fallback_type if hands_enabled else None,
        fallback_calls=fallback_calls if hands_enabled else None,
        fallback_successes=fallback_successes if hands_enabled else None,
        fallback_failures=fallback_failures if hands_enabled else None,
        fallback_activation_pct=(
            fallback_activation_pct if hands_enabled else None
        ),
        fallback_mean_ms=fallback_mean_ms if hands_enabled else None,
        fallback_p95_ms=fallback_p95_ms if hands_enabled else None,
        yolo_share_pct=yolo_share,
        hands_share_pct=hands_share,
        pose_share_pct=pose_share,
        fallback_share_pct=fallback_share if hands_enabled else None,
        share_notes=share_notes,
        bottleneck="unknown",
    )
    object.__setattr__(snap, "bottleneck", classify_stage_bottleneck(snap))
    return snap


def collect_session_snapshot(
    session: Any,
    *,
    elapsed_s: float,
    preview_frames: int,
    ai_frames: int,
    warmup_s: float,
    measured_s: float,
    preview_drops: int,
    capture: CaptureProducerSnapshot,
) -> ProductionCvSnapshot:
    hands = getattr(session, "hands_detector", None)
    stats = getattr(hands, "stats", None) if hands is not None else None
    if stats is not None and not isinstance(stats, HandsCallStats):
        stats = None
    return snapshot_from_parts(
        movement=session.movement,
        preview_timings=session.preview_timings,
        ai_timings=session.timings,
        elapsed_s=elapsed_s,
        preview_frames=preview_frames,
        ai_frames=ai_frames,
        warmup_s=warmup_s,
        measured_s=measured_s,
        capture=capture,
        preview_drops=preview_drops,
        hands_stats=stats,
        hands_enabled=hands is not None,
        pose_enabled=getattr(session, "pose_detector", None) is not None,
        profile=hands_profile_for(session.movement),
    )


def classify_stage_bottleneck(snap: ProductionCvSnapshot) -> str:
    """Dominant recurring CV cost. Uses stage time, not FPS alone."""
    if snap.ai_e2e_mean_ms <= 0:
        return "unknown"

    yolo_share = snap.yolo_share_pct / 100.0
    hands_share = (snap.hands_share_pct or 0.0) / 100.0
    pose_share = (snap.pose_share_pct or 0.0) / 100.0
    fallback_share = (snap.fallback_share_pct or 0.0) / 100.0
    activation = (snap.fallback_activation_pct or 0.0) / 100.0
    primary_hands_share = max(0.0, hands_share - fallback_share)

    processing_ms = snap.ai_e2e_mean_ms
    camera_share = 0.0
    if processing_ms > 0 and snap.capture_read_mean_ms > 0:
        # Capture read is on the producer thread, not inside AI e2e.
        # Only classify camera/read when capture FPS is clearly starved
        # relative to preview and read cost is large vs AI e2e.
        if snap.capture_fps > 0 and snap.preview_fps > 0:
            if snap.capture_fps < snap.preview_fps * 0.8:
                camera_share = min(1.0, snap.capture_read_mean_ms / processing_ms)

    accounted = yolo_share + hands_share + pose_share
    orchestration_share = max(0.0, 1.0 - accounted)

    if (
        snap.hands_enabled
        and fallback_share >= _FALLBACK_SHARE
        and activation >= _FALLBACK_ACTIVATION
        and fallback_share >= yolo_share
        and fallback_share >= primary_hands_share
        and fallback_share >= pose_share
    ):
        return "Hands fallback"

    ranked = [
        ("YOLO", yolo_share),
        ("primary Hands", primary_hands_share if snap.hands_enabled else 0.0),
        ("Pose", pose_share if snap.pose_enabled else 0.0),
        ("camera/read", camera_share),
        ("orchestration/locking", orchestration_share),
    ]
    ranked.sort(key=lambda item: item[1], reverse=True)
    top_name, top_share = ranked[0]
    second_share = ranked[1][1] if len(ranked) > 1 else 0.0
    clearly = top_share >= _DOMINANT_SHARE and (
        second_share <= 0 or top_share >= second_share * _DOMINANT_MARGIN
    )
    if clearly:
        if top_name == "camera/read" and top_share < _CAMERA_SHARE:
            return "mixed"
        if top_name == "orchestration/locking" and top_share < _ORCHESTRATION_SHARE:
            return "mixed"
        return top_name
    if top_share < 0.01:
        return "unknown"
    return "mixed"


def _fmt(value: float | None, pattern: str = "{:.1f}") -> str:
    if value is None:
        return "N/A"
    return pattern.format(value)


def format_comparison_table(rows: list[ProductionCvSnapshot]) -> str:
    headers = (
        "Movement",
        "Preview FPS",
        "AI FPS",
        "AI e2e mean",
        "AI e2e p95",
        "YOLO mean/p95",
        "Hands mean/p95",
        "Pose mean/p95",
        "Fallback %",
        "Fallback mean/p95",
        "Capture fail",
        "Preview drops",
    )
    lines = [" | ".join(headers)]
    lines.append(" | ".join("-" * len(h) for h in headers))
    for snap in rows:
        yolo = f"{snap.yolo_mean_ms:.1f}/{snap.yolo_p95_ms:.1f}"
        hands = (
            "N/A"
            if snap.hands_mean_ms is None
            else f"{snap.hands_mean_ms:.1f}/{snap.hands_p95_ms:.1f}"
        )
        pose = (
            "N/A"
            if snap.pose_mean_ms is None
            else f"{snap.pose_mean_ms:.1f}/{snap.pose_p95_ms:.1f}"
        )
        fb = (
            "N/A"
            if snap.fallback_mean_ms is None
            else f"{snap.fallback_mean_ms:.1f}/{snap.fallback_p95_ms:.1f}"
        )
        lines.append(
            " | ".join(
                [
                    snap.movement,
                    f"{snap.preview_fps:.1f}",
                    f"{snap.ai_fps:.1f}",
                    f"{snap.ai_e2e_mean_ms:.1f}",
                    f"{snap.ai_e2e_p95_ms:.1f}",
                    yolo,
                    hands,
                    pose,
                    _fmt(snap.fallback_activation_pct),
                    fb,
                    str(snap.capture_failures),
                    str(snap.preview_drops),
                ]
            )
        )
    return "\n".join(lines)


def format_snapshot_report(snap: ProductionCvSnapshot) -> str:
    lines = [
        f"Movement: {snap.movement}",
        f"requires_hands={snap.requires_hands} requires_pose={snap.requires_pose} "
        f"hands_max={snap.hands_max}",
        f"hands_enabled={snap.hands_enabled} pose_enabled={snap.pose_enabled}",
        f"warmup_s={snap.warmup_s:.1f} measured_s={snap.measured_s:.1f}",
        f"capture_fps={snap.capture_fps:.1f} capture_read_mean_ms="
        f"{snap.capture_read_mean_ms:.1f} capture_failures={snap.capture_failures}",
        f"preview_fps={snap.preview_fps:.1f} preview_e2e_ms="
        f"{snap.preview_e2e_mean_ms:.1f} preview_drops={snap.preview_drops}",
        f"ai_fps={snap.ai_fps:.1f} ai_e2e_mean_ms={snap.ai_e2e_mean_ms:.1f} "
        f"ai_e2e_p95_ms={snap.ai_e2e_p95_ms:.1f}",
        "AI e2e is VisionSession processing_total (latest-frame wait + detectors "
        "+ evaluate). Excludes WebSocket send.",
        f"YOLO calls={snap.yolo_calls} mean={snap.yolo_mean_ms:.1f}ms "
        f"median={snap.yolo_median_ms:.1f}ms p95={snap.yolo_p95_ms:.1f}ms "
        f"calls/sec={snap.yolo_calls_per_sec:.1f} share={snap.yolo_share_pct:.1f}%",
        f"Hands total mean={_fmt(snap.hands_mean_ms)} p95={_fmt(snap.hands_p95_ms)} "
        f"share={_fmt(snap.hands_share_pct)}%",
        f"Hands primary n={snap.hands_primary_calls} "
        f"mean={_fmt(snap.hands_primary_mean_ms)} "
        f"p95={_fmt(snap.hands_primary_p95_ms)}",
        f"Fallback type={snap.fallback_type or 'N/A'} "
        f"activation={_fmt(snap.fallback_activation_pct)}% "
        f"calls={snap.fallback_calls} ok={snap.fallback_successes} "
        f"fail={snap.fallback_failures} mean={_fmt(snap.fallback_mean_ms)} "
        f"p95={_fmt(snap.fallback_p95_ms)} share={_fmt(snap.fallback_share_pct)}%",
        f"Pose calls={snap.pose_calls} mean={_fmt(snap.pose_mean_ms)} "
        f"p95={_fmt(snap.pose_p95_ms)} share={_fmt(snap.pose_share_pct)}%",
        snap.share_notes,
        f"bottleneck={snap.bottleneck}",
    ]
    return "\n".join(lines)
