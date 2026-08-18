"""Aggregated CV pipeline timing diagnostics (no session-behavior side effects)."""

from __future__ import annotations

import threading
from typing import Mapping

PIPELINE_STAGE_ORDER = (
    "camera",
    "yolo",
    "hands",
    "pose",
    "evaluate",
    "annotate",
    "jpeg",
    "encode",
    "serialize",
    "send",
    "processing_total",
    "end_to_end",
)

_AI_STAGES = ("yolo", "hands", "pose")
_JPEG_STAGES = ("jpeg",)
_TRANSPORT_STAGES = ("encode", "serialize", "send")
_CAMERA_STAGES = ("camera",)

_HEALTHY_MIN_OUTPUT_RATIO = 0.90
_HEALTHY_MAX_OVER_BUDGET_PCT = 20.0
_DOMINANT_SHARE = 0.50
_DOMINANT_MARGIN = 1.4
_CAMERA_FPS_RATIO = 0.80
_CAMERA_OVERWRITE_RATIO = 0.15

_BOTTLENECK_LABELS = {
    "ai": "AI_INFERENCE",
    "jpeg": "JPEG_ENCODING",
    "transport": "TRANSPORT",
    "camera": "CAMERA_CAPTURE",
}


def interval_rate(count: int, elapsed_s: float) -> float:
    """Frames-or-events per second for one logging window only."""
    if count <= 0 or elapsed_s <= 0:
        return 0.0
    return count / elapsed_s


def monotonic_counter_delta(*, current: int, previous: int) -> int:
    """Positive delta for a counter that may reset when a slot/producer is replaced."""
    if current < previous:
        return max(0, current)
    return current - previous


class PipelineTimings:
    """Rolling stage timings logged at the FPS interval (not every frame).

    Meanings:
    * ``processing_total`` — worker time from process_* entry through encode return
      (includes waiting for the latest camera slot; excludes WebSocket send).
    * ``end_to_end`` — same start through completed WebSocket send (includes the
      asyncio scheduling gap after the worker returns).
    * ``frame_age`` — how old the consumed camera frame already was when
      processing began (producer/consumer lag; not a subset of the stage sums).
    * ``yolo`` — recorded only on frames that actually run inference, so skipped
      YOLO ticks do not dilute the average.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._sums: dict[str, float] = {name: 0.0 for name in PIPELINE_STAGE_ORDER}
        self._counts: dict[str, int] = {name: 0 for name in PIPELINE_STAGE_ORDER}
        self._maxs: dict[str, float] = {name: 0.0 for name in PIPELINE_STAGE_ORDER}
        self._end_to_end_samples: list[float] = []
        self._frame_age_sum = 0.0
        self._frame_age_count = 0
        self._frame_age_max = 0.0

    def add(self, stage: str, seconds: float) -> None:
        with self._lock:
            if stage not in self._sums:
                self._sums[stage] = 0.0
                self._counts[stage] = 0
                self._maxs[stage] = 0.0
            self._sums[stage] += seconds
            self._counts[stage] += 1
            if seconds > self._maxs[stage]:
                self._maxs[stage] = seconds
            if stage == "end_to_end":
                self._end_to_end_samples.append(seconds)

    def add_frame_age(self, seconds: float) -> None:
        with self._lock:
            self._frame_age_sum += seconds
            self._frame_age_count += 1
            if seconds > self._frame_age_max:
                self._frame_age_max = seconds

    def reset(self) -> None:
        with self._lock:
            for name in list(self._sums):
                self._sums[name] = 0.0
                self._counts[name] = 0
                self._maxs[name] = 0.0
            self._end_to_end_samples.clear()
            self._frame_age_sum = 0.0
            self._frame_age_count = 0
            self._frame_age_max = 0.0

    def count(self, stage: str) -> int:
        with self._lock:
            return self._counts.get(stage, 0)

    def sum_s(self, stage: str) -> float:
        with self._lock:
            return self._sums.get(stage, 0.0)

    def average_ms(self, stage: str) -> float:
        with self._lock:
            count = self._counts.get(stage, 0)
            if count <= 0:
                return 0.0
            return (self._sums[stage] / count) * 1000.0

    def max_ms(self, stage: str) -> float:
        with self._lock:
            return self._maxs.get(stage, 0.0) * 1000.0

    @property
    def frame_age_avg_ms(self) -> float:
        with self._lock:
            if self._frame_age_count <= 0:
                return 0.0
            return (self._frame_age_sum / self._frame_age_count) * 1000.0

    @property
    def frame_age_max_ms(self) -> float:
        with self._lock:
            return self._frame_age_max * 1000.0

    def over_budget_pct(self, *, budget_s: float) -> float:
        with self._lock:
            if budget_s <= 0 or not self._end_to_end_samples:
                return 0.0
            over = sum(1 for sample in self._end_to_end_samples if sample > budget_s)
            return (over / len(self._end_to_end_samples)) * 100.0

    def stage_sums(self) -> dict[str, float]:
        with self._lock:
            return dict(self._sums)

    def format_averages_ms(self, *, frame_budget_ms: float) -> str:
        with self._lock:
            parts: list[str] = []
            for name in PIPELINE_STAGE_ORDER:
                count = self._counts.get(name, 0)
                if count <= 0:
                    continue
                avg_ms = (self._sums[name] / count) * 1000.0
                over = "!" if avg_ms > frame_budget_ms and name in {
                    "processing_total",
                    "end_to_end",
                    "total",
                } else ""
                if name not in {"processing_total", "end_to_end", "total"} and avg_ms > (
                    frame_budget_ms * 0.35
                ):
                    over = "!"
                parts.append(f"{name}={avg_ms:.1f}ms{over}")
            if self._frame_age_count > 0:
                age_avg = (self._frame_age_sum / self._frame_age_count) * 1000.0
                age_max = self._frame_age_max * 1000.0
                parts.append(f"frame_age_avg={age_avg:.1f}ms")
                parts.append(f"frame_age_max={age_max:.1f}ms")
            return ", ".join(parts)


def _sum_stages(stage_sums: Mapping[str, float], names: tuple[str, ...]) -> float:
    return sum(float(stage_sums.get(name, 0.0)) for name in names)


def classify_bottleneck(
    *,
    target_fps: float,
    output_fps: float,
    capture_fps: float,
    over_budget_pct: float,
    overwrite_delta: int,
    processed: int,
    stage_sums: Mapping[str, float],
) -> str:
    """Conservative diagnostic label. Never changes session behavior."""
    if (
        target_fps > 0
        and output_fps >= target_fps * _HEALTHY_MIN_OUTPUT_RATIO
        and over_budget_pct < _HEALTHY_MAX_OVER_BUDGET_PCT
    ):
        return "HEALTHY"

    end_to_end = float(stage_sums.get("end_to_end", 0.0))
    if end_to_end <= 0:
        end_to_end = sum(float(value) for value in stage_sums.values())
    if end_to_end <= 0:
        return "MIXED"

    shares = {
        "ai": _sum_stages(stage_sums, _AI_STAGES) / end_to_end,
        "jpeg": _sum_stages(stage_sums, _JPEG_STAGES) / end_to_end,
        "transport": _sum_stages(stage_sums, _TRANSPORT_STAGES) / end_to_end,
        "camera": _sum_stages(stage_sums, _CAMERA_STAGES) / end_to_end,
    }

    producer_lagging = target_fps > 0 and capture_fps < target_fps * _CAMERA_FPS_RATIO
    overwrite_ratio = (
        overwrite_delta / processed if processed > 0 else 0.0
    )
    few_overwrites = overwrite_ratio < _CAMERA_OVERWRITE_RATIO
    ranked = sorted(shares.items(), key=lambda item: item[1], reverse=True)
    top_name, top_share = ranked[0]
    second_share = ranked[1][1] if len(ranked) > 1 else 0.0
    clearly_dominant = (
        top_share >= _DOMINANT_SHARE
        and (second_share <= 0 or top_share >= second_share * _DOMINANT_MARGIN)
    )

    if (
        top_name == "camera"
        and clearly_dominant
        and producer_lagging
        and few_overwrites
    ):
        return "CAMERA_CAPTURE"

    if clearly_dominant:
        return _BOTTLENECK_LABELS[top_name]

    return "MIXED"


def _merge_stage_sums(
    preview: Mapping[str, float],
    ai: Mapping[str, float] | None,
) -> dict[str, float]:
    merged = dict(preview)
    if not ai:
        return merged
    for name, value in ai.items():
        merged[name] = float(merged.get(name, 0.0)) + float(value)
    return merged


def format_perf_line(
    timings: PipelineTimings,
    *,
    output_fps: float | None = None,
    preview_fps: float | None = None,
    ai_fps: float = 0.0,
    capture_fps: float,
    elapsed_s: float,
    overwrite_delta: int,
    target_fps: float,
    yolo_skip: int,
    imgsz: int,
    lifecycle: str,
    processed: int,
    ticks: int,
    ai_timings: PipelineTimings | None = None,
    preview_replaced: int = 0,
    ai_overwrites: int = 0,
    ai_processed: int = 0,
) -> str:
    """One aggregated line for the FPS log interval."""
    preview = preview_fps if preview_fps is not None else (output_fps or 0.0)
    inference = ai_timings if ai_timings is not None else timings
    yolo_fps = interval_rate(inference.count("yolo"), elapsed_s)
    budget_s = (1.0 / target_fps) if target_fps > 0 else 0.0
    over_budget = timings.over_budget_pct(budget_s=budget_s)
    merged_sums = _merge_stage_sums(
        timings.stage_sums(),
        inference.stage_sums() if ai_timings is not None else None,
    )
    bottleneck = classify_bottleneck(
        target_fps=target_fps,
        output_fps=preview,
        capture_fps=capture_fps,
        over_budget_pct=over_budget,
        overwrite_delta=overwrite_delta,
        processed=processed,
        stage_sums=merged_sums,
    )

    stage_parts: list[str] = []
    stage_sources = (
        ("camera", timings),
        ("yolo", inference),
        ("hands", inference),
        ("pose", inference),
        ("evaluate", inference),
        ("annotate", timings),
        ("jpeg", timings),
        ("encode", timings),
        ("serialize", timings),
        ("send", timings),
    )
    for name, source in stage_sources:
        if source.count(name) <= 0:
            continue
        stage_parts.append(f"{name}={source.average_ms(name):.1f}ms")

    preview_e2e_ms = timings.average_ms("end_to_end")
    if preview_e2e_ms <= 0:
        preview_e2e_ms = timings.average_ms("processing_total")
    ai_e2e_ms = inference.average_ms("end_to_end")
    if ai_e2e_ms <= 0:
        ai_e2e_ms = inference.average_ms("processing_total")

    return (
        "CV PERF | "
        f"preview={preview:.1f}fps ai={ai_fps:.1f}fps capture={capture_fps:.1f}fps "
        f"yolo={yolo_fps:.1f}fps"
        f" | ai_frame_age avg={inference.frame_age_avg_ms:.1f}ms "
        f"max={inference.frame_age_max_ms:.1f}ms"
        f" | {' '.join(stage_parts)}"
        f" | preview_e2e={preview_e2e_ms:.1f}ms ai_e2e={ai_e2e_ms:.1f}ms"
        f" | preview_over_budget={over_budget:.0f}%"
        f" | preview_drops={preview_replaced} ai_overwrites={ai_overwrites} "
        f"slot_overwrites={overwrite_delta}"
        f" | bottleneck={bottleneck}"
        f" | lifecycle={lifecycle} target={target_fps:g} skip={yolo_skip} "
        f"imgsz={imgsz} preview_frames={processed} ai_frames={ai_processed} "
        f"ticks={ticks}"
    )
