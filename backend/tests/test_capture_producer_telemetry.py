"""Aggregated camera-producer contention telemetry (no physical webcam)."""

from __future__ import annotations

import logging
import threading
import time

from config import TARGET_FPS
from test_camera_selection import (
    _FakeCap,
    _blank_frame,
    _default_profile,
    _reset_shared,
    _usable_frame,
)
from vision import camera as camera_mod
from vision.pipeline_telemetry import (
    CaptureProducerMetrics,
    CaptureProducerSnapshot,
    format_perf_line,
    PipelineTimings,
)


def test_read_timing_aggregation():
    metrics = CaptureProducerMetrics()
    metrics.record_read(0.041)
    metrics.record_read(0.074)

    snap = metrics.snapshot(reset=False)
    assert abs(snap.read_avg_ms - 57.5) < 0.01
    assert abs(snap.read_max_ms - 74.0) < 0.01
    assert snap.read_count == 2


def test_publish_interval_aggregation():
    metrics = CaptureProducerMetrics()
    metrics.record_usable(interval_s=None)
    metrics.record_usable(interval_s=0.050)
    metrics.record_usable(interval_s=0.090)

    snap = metrics.snapshot(reset=False)
    assert snap.usable_frames == 3
    assert abs(snap.interval_avg_ms - 70.0) < 0.01
    assert abs(snap.interval_max_ms - 90.0) < 0.01


def test_failed_and_blank_frame_counters():
    metrics = CaptureProducerMetrics()
    metrics.record_failed_read()
    metrics.record_failed_read()
    metrics.record_usable(interval_s=0.05)

    snap = metrics.snapshot(reset=False)
    assert snap.failed_reads == 2
    assert snap.usable_frames == 1


def test_loop_gap_aggregation():
    metrics = CaptureProducerMetrics()
    metrics.record_gap(0.002)
    metrics.record_gap(0.012)

    snap = metrics.snapshot(reset=False)
    assert abs(snap.gap_avg_ms - 7.0) < 0.01
    assert abs(snap.gap_max_ms - 12.0) < 0.01


def test_snapshot_reset_clears_interval_counters_but_keeps_identity():
    metrics = CaptureProducerMetrics(
        backend_label="DirectShow + MJPG",
        reported_fps=20.0,
    )
    metrics.record_read(0.040)
    metrics.record_failed_read()
    metrics.record_usable(interval_s=0.050)
    metrics.record_gap(0.003)

    first = metrics.snapshot(reset=True)
    assert first.usable_frames == 1
    assert first.failed_reads == 1
    assert first.backend_label == "DirectShow + MJPG"
    assert first.reported_fps == 20.0

    second = metrics.snapshot(reset=False)
    assert second.usable_frames == 0
    assert second.failed_reads == 0
    assert second.read_count == 0
    assert second.interval_count == 0
    assert second.gap_count == 0
    assert second.read_avg_ms == 0.0
    assert second.backend_label == "DirectShow + MJPG"
    assert second.reported_fps == 20.0


def test_metrics_snapshot_is_thread_safe():
    metrics = CaptureProducerMetrics(backend_label="test", reported_fps=20.0)
    errors: list[BaseException] = []
    stop = threading.Event()

    def _write():
        try:
            index = 0
            while not stop.is_set():
                metrics.record_read(0.010 + (index % 5) * 0.001)
                if index % 7 == 0:
                    metrics.record_failed_read()
                else:
                    metrics.record_usable(interval_s=0.050)
                metrics.record_gap(0.001)
                index += 1
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    def _read():
        try:
            for _ in range(400):
                snap = metrics.snapshot(reset=False)
                assert snap.failed_reads >= 0
                assert snap.usable_frames >= 0
                assert snap.read_count >= 0
                if snap.read_count > 0:
                    assert snap.read_avg_ms <= snap.read_max_ms + 1e-6
                if snap.interval_count > 0:
                    assert snap.interval_avg_ms <= snap.interval_max_ms + 1e-6
                if snap.gap_count > 0:
                    assert snap.gap_avg_ms <= snap.gap_max_ms + 1e-6
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    writers = [threading.Thread(target=_write) for _ in range(3)]
    readers = [threading.Thread(target=_read) for _ in range(3)]
    for thread in writers + readers:
        thread.start()
    for thread in readers:
        thread.join(timeout=2.0)
        assert not thread.is_alive()
    stop.set()
    for thread in writers:
        thread.join(timeout=2.0)
        assert not thread.is_alive()
    assert errors == []


def _wait_until(predicate, *, timeout: float = 2.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.005)
    return False


def test_producer_records_read_and_publish_intervals(monkeypatch):
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    clock = {"t": 100.0}

    class _ClockCap(_FakeCap):
        def read(self):
            clock["t"] += 0.041
            return super().read()

    monkeypatch.setattr(camera_mod.time, "perf_counter", lambda: clock["t"])

    cap = _ClockCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    assert camera_mod._start_capture_producer(
        cap,
        width=64,
        height=48,
        backend_label="DirectShow + MJPG",
        reported_fps=20.0,
    )

    assert _wait_until(
        lambda: camera_mod.snapshot_capture_producer_telemetry(reset=False).usable_frames >= 3
    )
    snap = camera_mod.snapshot_capture_producer_telemetry(reset=True)
    assert snap.usable_frames >= 3
    assert snap.failed_reads == 0
    assert snap.read_avg_ms >= 40.0
    assert snap.read_max_ms >= snap.read_avg_ms
    assert snap.interval_count >= 2
    assert snap.backend_label == "DirectShow + MJPG"
    assert snap.reported_fps == 20.0
    camera_mod._stop_capture_producer()


def test_producer_counts_blank_and_failed_reads(monkeypatch):
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    class _MixedCap(_FakeCap):
        def __init__(self):
            super().__init__()
            self._script = [
                (True, _blank_frame()),
                (False, None),
                (True, _usable_frame()),
                (True, _usable_frame()),
            ]

        def read(self):
            self.reads += 1
            if self._script:
                return self._script.pop(0)
            return True, _usable_frame()

    cap = _MixedCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(cap, width=64, height=48)

    assert _wait_until(
        lambda: camera_mod.snapshot_capture_producer_telemetry(reset=False).usable_frames >= 2
        and camera_mod.snapshot_capture_producer_telemetry(reset=False).failed_reads >= 2
    )
    snap = camera_mod.snapshot_capture_producer_telemetry(reset=True)
    assert snap.failed_reads >= 2
    assert snap.usable_frames >= 2
    camera_mod._stop_capture_producer()


def test_producer_telemetry_reset_between_intervals(monkeypatch):
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    class _GateCap(_FakeCap):
        def __init__(self):
            super().__init__()
            self.gate = threading.Event()
            self.gate.set()
            self.in_read = threading.Event()

        def read(self):
            self.in_read.set()
            self.gate.wait()
            try:
                return super().read()
            finally:
                self.in_read.clear()

    cap = _GateCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(
        cap,
        width=64,
        height=48,
        backend_label="Media Foundation + MJPG",
        reported_fps=float(TARGET_FPS),
    )
    assert _wait_until(
        lambda: camera_mod.snapshot_capture_producer_telemetry(reset=False).usable_frames >= 2
    )
    cap.gate.clear()
    assert cap.in_read.wait(timeout=2.0)
    try:
        prev = None
        for _ in range(40):
            current = camera_mod.snapshot_capture_producer_telemetry(
                reset=False
            ).usable_frames
            if prev is not None and current == prev:
                break
            prev = current
            time.sleep(0.005)
        first = camera_mod.snapshot_capture_producer_telemetry(reset=True)
        assert first.usable_frames >= 2
        second = camera_mod.snapshot_capture_producer_telemetry(reset=False)
        assert second.usable_frames == 0
        assert second.failed_reads == 0
        assert second.backend_label == "Media Foundation + MJPG"
        assert second.reported_fps == float(TARGET_FPS)
    finally:
        cap.gate.set()
        camera_mod._stop_capture_producer()


def test_producer_does_not_log_every_usable_frame(monkeypatch, caplog):
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    cap = _FakeCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    with caplog.at_level(logging.DEBUG, logger="vision.camera"):
        camera_mod._start_capture_producer(cap, width=64, height=48)
        assert _wait_until(
            lambda: camera_mod.snapshot_capture_producer_telemetry(reset=False).usable_frames >= 8
        )
        snap = camera_mod.snapshot_capture_producer_telemetry(reset=False)
        assert snap.usable_frames >= 8
        frame_logs = [
            record.getMessage()
            for record in caplog.records
            if "frame" in record.getMessage().lower()
        ]
        assert frame_logs == []
    camera_mod._stop_capture_producer()


def test_format_perf_line_includes_capture_contention_fields():
    timings = PipelineTimings()
    timings.add("jpeg", 0.004)
    timings.add("end_to_end", 0.006)
    snapshot = CaptureProducerSnapshot(
        usable_frames=45,
        failed_reads=0,
        read_count=45,
        read_sum_s=45 * 0.041,
        read_max_s=0.074,
        interval_count=44,
        interval_sum_s=44 * 0.066,
        interval_max_s=0.101,
        gap_count=45,
        gap_sum_s=45 * 0.002,
        gap_max_s=0.012,
        backend_label="DirectShow + MJPG",
        reported_fps=20.0,
    )
    line = format_perf_line(
        timings,
        preview_fps=15.1,
        ai_fps=9.0,
        capture_fps=15.1,
        elapsed_s=3.0,
        overwrite_delta=2,
        target_fps=20.0,
        yolo_skip=2,
        imgsz=640,
        lifecycle="active",
        processed=45,
        ticks=45,
        capture_snapshot=snapshot,
    )
    assert "capture=15.1fps" in line
    assert "capture_read_avg=41.0ms" in line
    assert "capture_read_max=74.0ms" in line
    assert "capture_interval_avg=66.0ms" in line
    assert "capture_interval_max=101.0ms" in line
    assert "capture_gap_avg=2.0ms" in line
    assert "capture_gap_max=12.0ms" in line
    assert "capture_fail=0" in line
    assert "capture_usable=45" in line
    assert "capture_backend=DirectShow + MJPG" in line
    assert "capture_prop_fps=20" in line
    assert "\n" not in line


def test_empty_snapshot_has_zero_averages():
    snap = CaptureProducerSnapshot()
    assert snap.read_avg_ms == 0.0
    assert snap.read_max_ms == 0.0
    assert snap.interval_avg_ms == 0.0
    assert snap.gap_avg_ms == 0.0
    assert snap.usable_frames == 0
    assert snap.failed_reads == 0
