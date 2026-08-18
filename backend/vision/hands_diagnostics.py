"""Diagnostic-only Hands inference counters. Detection behavior is unchanged."""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field


def percentile_ms(samples_s: list[float], pct: float) -> float:
    if not samples_s:
        return 0.0
    ordered = sorted(samples_s)
    index = min(len(ordered) - 1, max(0, int(round((pct / 100.0) * (len(ordered) - 1)))))
    return ordered[index] * 1000.0


def timing_stats(samples_s: list[float]) -> dict[str, float]:
    if not samples_s:
        return {
            "count": 0.0,
            "mean_ms": 0.0,
            "median_ms": 0.0,
            "p95_ms": 0.0,
            "fps": 0.0,
        }
    mean = statistics.fmean(samples_s)
    return {
        "count": float(len(samples_s)),
        "mean_ms": mean * 1000.0,
        "median_ms": statistics.median(samples_s) * 1000.0,
        "p95_ms": percentile_ms(samples_s, 95),
        "fps": (1.0 / mean) if mean > 0 else 0.0,
    }


@dataclass
class HandsCallStats:
    """Per-interval (or per-benchmark) Hands call split."""

    detect_calls: int = 0
    primary_video_samples_s: list[float] = field(default_factory=list)
    rotated_fallback_samples_s: list[float] = field(default_factory=list)
    bartender_roi_samples_s: list[float] = field(default_factory=list)
    bartender_roi_image_calls: int = 0
    fallback_activated_calls: int = 0

    def record_primary(self, seconds: float) -> None:
        self.primary_video_samples_s.append(max(0.0, seconds))

    def record_rotated(self, seconds: float) -> None:
        self.rotated_fallback_samples_s.append(max(0.0, seconds))

    def record_bartender_roi(self, seconds: float, *, ran_image: bool) -> None:
        self.bartender_roi_samples_s.append(max(0.0, seconds))
        if ran_image:
            self.bartender_roi_image_calls += 1

    def mark_fallback_activated(self) -> None:
        self.fallback_activated_calls += 1

    def fallback_activation_rate(self) -> float:
        if self.detect_calls <= 0:
            return 0.0
        return self.fallback_activated_calls / self.detect_calls

    def snapshot(self) -> dict[str, float | int]:
        primary = timing_stats(self.primary_video_samples_s)
        rotated = timing_stats(self.rotated_fallback_samples_s)
        bartender = timing_stats(self.bartender_roi_samples_s)
        return {
            "detect_calls": self.detect_calls,
            "primary_calls": int(primary["count"]),
            "primary_mean_ms": primary["mean_ms"],
            "primary_median_ms": primary["median_ms"],
            "primary_p95_ms": primary["p95_ms"],
            "primary_fps": primary["fps"],
            "rotated_calls": int(rotated["count"]),
            "rotated_mean_ms": rotated["mean_ms"],
            "rotated_median_ms": rotated["median_ms"],
            "rotated_p95_ms": rotated["p95_ms"],
            "bartender_calls": int(bartender["count"]),
            "bartender_image_calls": self.bartender_roi_image_calls,
            "bartender_mean_ms": bartender["mean_ms"],
            "bartender_median_ms": bartender["median_ms"],
            "bartender_p95_ms": bartender["p95_ms"],
            "fallback_activated_calls": self.fallback_activated_calls,
            "fallback_activation_rate": self.fallback_activation_rate(),
        }

    def format_line(self) -> str:
        snap = self.snapshot()
        rate_pct = float(snap["fallback_activation_rate"]) * 100.0
        return (
            f"hands_primary={snap['primary_mean_ms']:.1f}ms "
            f"p95={snap['primary_p95_ms']:.1f}ms "
            f"n={snap['primary_calls']} "
            f"hands_rot={snap['rotated_calls']}/{snap['detect_calls']} "
            f"rot_mean={snap['rotated_mean_ms']:.1f}ms "
            f"rot_p95={snap['rotated_p95_ms']:.1f}ms "
            f"hands_roi={snap['bartender_image_calls']}/{snap['detect_calls']} "
            f"roi_mean={snap['bartender_mean_ms']:.1f}ms "
            f"roi_p95={snap['bartender_p95_ms']:.1f}ms "
            f"hands_fallback={rate_pct:.1f}%"
        )

    def reset(self) -> None:
        self.detect_calls = 0
        self.primary_video_samples_s.clear()
        self.rotated_fallback_samples_s.clear()
        self.bartender_roi_samples_s.clear()
        self.bartender_roi_image_calls = 0
        self.fallback_activated_calls = 0
