"""Startup diagnostics: milestone-once timings, percentiles, and serialization."""

from __future__ import annotations

import json

from vision.startup_diagnostics import (
    MARK_ACTIVATE_ACK,
    MARK_ACTIVATE_START,
    MARK_CAMERA_OPEN_END,
    MARK_CAMERA_OPEN_START,
    MARK_FIRST_JPEG_ENCODE,
    MARK_FIRST_JPEG_SEND,
    MARK_FIRST_USABLE,
    MARK_ORIGIN,
    MARK_PREPARE_END,
    MARK_READINESS_STABLE,
    MARK_READINESS_START,
    MARK_WARMUP_END,
    MARK_WARMUP_START,
    MemorySink,
    RaisingSink,
    START_CLASS_COLD,
    START_CLASS_WARM_CAMERA,
    StartupDiagnostics,
    aggregate_records,
    camera_diagnostic_identity,
    classify_start,
    infer_identity_stable_from_device_id,
    duration_ms,
    merge_backend_and_client,
    percentile,
    record_contains_image_payload,
    summarize_metric,
)


class FakeClock:
    def __init__(self, start: float = 100.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def test_duration_missing_marks_are_none_not_zero():
    assert duration_ms(None, 1.0) is None
    assert duration_ms(1.0, None) is None
    assert duration_ms(None, None) is None
    assert duration_ms(1.0, 1.0) == 0
    assert duration_ms(1.0, 1.250) == 250


def test_percentile_nearest_rank_is_deterministic():
    samples = [10.0, 20.0, 30.0, 40.0, 50.0]
    assert percentile(samples, 0) == 10.0
    assert percentile(samples, 50) == 30.0
    assert percentile(samples, 95) == 50.0
    assert percentile(samples, 100) == 50.0
    assert percentile([], 50) is None
    assert percentile([], 95) is None
    # n=20 nearest-rank p95 uses round(0.95 * 19) = 18.
    twenty = [float(i) for i in range(20)]
    assert percentile(twenty, 95) == 18.0


def test_summarize_metric_includes_sample_count():
    summary = summarize_metric([10.0, 20.0, 30.0])
    assert summary["n"] == 3
    assert summary["p50"] == 20.0
    assert summary["min"] == 10.0
    assert summary["max"] == 30.0
    empty = summarize_metric([])
    assert empty["n"] == 0
    assert empty["p50"] is None
    assert empty["p95"] is None


def test_marks_are_recorded_only_once_with_injectable_clock():
    clock = FakeClock(10.0)
    diag = StartupDiagnostics("session-a", clock=clock, sink=RaisingSink())
    assert diag.mark(MARK_ORIGIN) is True
    clock.advance(0.5)
    assert diag.mark(MARK_ORIGIN) is False
    assert diag.timestamp(MARK_ORIGIN) == 10.0
    assert diag.mark_attempts(MARK_ORIGIN) == 2


def test_missing_milestones_stay_null_in_record():
    clock = FakeClock()
    diag = StartupDiagnostics("session-b", clock=clock, sink=MemorySink())
    diag.mark(MARK_ORIGIN)
    record = diag.to_record()
    durations = record["durations_ms"]
    assert durations["prepare"] is None
    assert durations["camera_open"] is None
    assert durations["first_usable_frame"] is None
    assert durations["first_jpeg_encode"] is None
    assert durations["detector_warmup"] is None
    assert durations["readiness_stable"] is None
    assert durations["activate_ack"] is None
    assert 0 not in durations.values()
    assert record["status"] == "partial"


def test_failed_sample_does_not_invent_zero_durations():
    clock = FakeClock()
    diag = StartupDiagnostics("session-fail", clock=clock, sink=MemorySink())
    diag.mark(MARK_ORIGIN)
    clock.advance(0.2)
    diag.mark(MARK_CAMERA_OPEN_START)
    diag.fail("camera_open", "camera_unavailable")
    record = diag.to_record()
    assert record["status"] == "failed"
    assert record["failed_milestone"] == "camera_open"
    assert record["error_code"] == "camera_unavailable"
    assert record["durations_ms"]["camera_open"] is None
    assert record["durations_ms"]["first_jpeg_send"] is None


def test_camera_and_warmup_durations_are_separate():
    clock = FakeClock(0.0)
    diag = StartupDiagnostics("session-c", clock=clock, sink=MemorySink())
    diag.mark(MARK_ORIGIN)
    diag.mark(MARK_CAMERA_OPEN_START)
    clock.advance(0.400)
    diag.mark(MARK_FIRST_USABLE)
    clock.advance(0.100)
    diag.mark(MARK_CAMERA_OPEN_END)
    diag.mark(MARK_PREPARE_END)
    clock.advance(0.050)
    diag.mark(MARK_FIRST_JPEG_ENCODE)
    clock.advance(0.010)
    diag.mark(MARK_FIRST_JPEG_SEND)
    clock.advance(1.500)
    diag.mark(MARK_WARMUP_START)
    clock.advance(2.000)
    diag.mark(MARK_WARMUP_END)
    durations = diag.durations_ms()
    assert durations["camera_open"] == 500
    assert durations["first_usable_frame"] == 400
    assert durations["first_jpeg_encode"] == 550
    assert durations["first_jpeg_send"] == 560
    assert durations["detector_warmup"] == 2000
    assert durations["prepare"] == 500


def test_readiness_and_activation_are_separate_from_warmup():
    clock = FakeClock(0.0)
    diag = StartupDiagnostics("session-d", clock=clock, sink=MemorySink())
    diag.mark_at(MARK_WARMUP_START, 0.0)
    diag.mark_at(MARK_WARMUP_END, 1.0)
    diag.mark_at(MARK_READINESS_START, 1.1)
    diag.mark_at(MARK_READINESS_STABLE, 4.1)
    diag.mark_at(MARK_ACTIVATE_START, 9.0)
    diag.mark_at(MARK_ACTIVATE_ACK, 9.02)
    durations = diag.durations_ms()
    assert durations["detector_warmup"] == 1000
    assert durations["readiness_stable"] == 3000
    assert durations["activate_ack"] == 20


def test_cold_warm_classification_matches_model_lifetime():
    start, camera, model = classify_start(camera_reused=False)
    assert start == START_CLASS_COLD
    assert camera == START_CLASS_COLD
    assert model == START_CLASS_COLD

    start, camera, model = classify_start(camera_reused=True)
    assert start == START_CLASS_WARM_CAMERA
    assert camera == START_CLASS_WARM_CAMERA
    assert model == START_CLASS_COLD

    diag = StartupDiagnostics("warm-cam", sink=MemorySink())
    diag.set_camera_reused(True)
    record = diag.to_record()
    assert record["start_class"] == START_CLASS_WARM_CAMERA
    assert record["model_start_class"] == START_CLASS_COLD
    assert record["model_cache"] == "session_scoped"


def test_stale_session_cannot_overwrite_another_sample():
    clock = FakeClock()
    first = StartupDiagnostics("session-1", clock=clock, sink=MemorySink())
    second = StartupDiagnostics("session-2", clock=clock, sink=MemorySink())
    first.mark(MARK_ORIGIN)
    clock.advance(1.0)
    second.mark(MARK_ORIGIN)
    clock.advance(5.0)
    # A late first-session JPEG must not land on the new sample.
    first.mark(MARK_FIRST_JPEG_ENCODE)
    assert second.timestamp(MARK_FIRST_JPEG_ENCODE) is None
    assert first.timestamp(MARK_ORIGIN) != second.timestamp(MARK_ORIGIN)


def test_finalize_persists_once_and_hot_path_marks_do_not_write():
    sink = MemorySink()
    clock = FakeClock()
    diag = StartupDiagnostics("session-e", clock=clock, sink=sink)
    diag.mark(MARK_ORIGIN)
    clock.advance(0.1)
    diag.mark(MARK_FIRST_JPEG_ENCODE)
    assert sink.write_calls == 0
    first = diag.finalize()
    second = diag.finalize()
    assert sink.write_calls == 1
    assert first["session_id"] == "session-e"
    assert second["session_id"] == "session-e"


def test_hot_path_mark_does_not_call_sink():
    diag = StartupDiagnostics("session-hot", clock=FakeClock(), sink=RaisingSink())
    diag.mark(MARK_ORIGIN)
    diag.mark(MARK_FIRST_JPEG_ENCODE)
    diag.mark(MARK_FIRST_JPEG_SEND)


def test_serialization_contains_no_image_payload():
    clock = FakeClock()
    diag = StartupDiagnostics("session-f", clock=clock, sink=MemorySink())
    diag.mark(MARK_ORIGIN)
    diag.mark(MARK_FIRST_JPEG_ENCODE)
    record = diag.to_record()
    blob = json.dumps(record)
    assert "frame_jpeg_base64" not in blob
    assert "evidence_jpeg_base64" not in blob
    assert record_contains_image_payload(record) is False
    assert "session-f" in blob


def test_unstable_camera_identity_is_not_opencv_index():
    identity = camera_diagnostic_identity("opencv:1", identity_stable=False)
    assert identity["camera_diagnostic_id"] == "opencv_fallback"
    assert identity["identity_stable"] is False
    unverified = camera_diagnostic_identity("dev-a")
    assert unverified["identity_stable"] is False
    assert unverified["camera_diagnostic_id"] == "unstable"
    stable = camera_diagnostic_identity(
        r"\\?\usb#vid_1234",
        identity_stable=True,
        display_name="HD Webcam",
    )
    assert stable["identity_stable"] is True
    assert stable["camera_diagnostic_id"] != r"\\?\usb#vid_1234"
    assert stable["camera_display_name"] == "HD Webcam"
    assert "opencv:" not in stable["camera_diagnostic_id"]


def test_ingest_camera_timings_uses_provided_monotonic_values():
    diag = StartupDiagnostics("session-g", sink=MemorySink())
    diag.ingest_camera_timings(
        open_started_at=5.0,
        first_usable_at=5.2,
        open_completed_at=5.7,
        reused_shared=False,
        success=True,
    )
    durations = diag.durations_ms()
    assert durations["camera_open"] == 700
    assert durations["first_usable_frame"] == 200
    assert diag.to_record()["start_class"] == START_CLASS_COLD


def test_aggregate_groups_by_device_and_start_class_with_counts():
    cold = {
        "session_id": "a",
        "start_class": START_CLASS_COLD,
        "session_mode": "guided",
        "environment": {"pilot_device_id": "pilot-1"},
        "durations_ms": {"client_first_preview": 100, "camera_open": 80},
    }
    warm = {
        "session_id": "b",
        "start_class": START_CLASS_WARM_CAMERA,
        "session_mode": "guided",
        "environment": {"pilot_device_id": "pilot-1"},
        "durations_ms": {"client_first_preview": 40, "camera_open": 10},
    }
    other = {
        "session_id": "c",
        "start_class": START_CLASS_COLD,
        "session_mode": "guided",
        "environment": {"pilot_device_id": "pilot-2"},
        "durations_ms": {"client_first_preview": 120},
    }
    mixed = {
        "session_id": "d",
        "start_class": START_CLASS_COLD,
        "session_mode": "freestyle",
        "environment": {"pilot_device_id": "pilot-1"},
        "durations_ms": {"client_first_preview": 90},
    }
    report = aggregate_records([cold, warm, other, mixed])
    assert "n-1" in report["percentile_definition"]
    groups = {
        (g["pilot_device_id"], g["start_class"], g["session_mode"]): g
        for g in report["groups"]
    }
    assert groups[("pilot-1", START_CLASS_COLD, "guided")]["sample_count"] == 1
    assert groups[("pilot-1", START_CLASS_COLD, "guided")]["metrics"]["client_first_preview"]["n"] == 1
    assert groups[("pilot-1", START_CLASS_WARM_CAMERA, "guided")]["metrics"]["camera_open"]["n"] == 1
    assert groups[("pilot-2", START_CLASS_COLD, "guided")]["sample_count"] == 1
    assert groups[("pilot-1", START_CLASS_COLD, "freestyle")]["sample_count"] == 1


def test_merge_combines_client_and_backend_durations_by_session():
    backend = {
        "session_id": "s1",
        "start_class": START_CLASS_COLD,
        "durations_ms": {
            "camera_open": 500,
            "detector_warmup": 2000,
            "client_first_preview": None,
        },
        "environment": {"pilot_device_id": "pilot-1"},
    }
    client = {
        "session_id": "s1",
        "durations_ms": {
            "connection": 30,
            "prepare": 520,
            "client_first_preview": 700,
            "activate_ack": 12,
        },
    }
    merged = merge_backend_and_client(backend, client)
    assert merged["session_id"] == "s1"
    assert merged["durations_ms"]["camera_open"] == 500
    assert merged["durations_ms"]["detector_warmup"] == 2000
    assert merged["durations_ms"]["client_first_preview"] == 700
    assert merged["durations_ms"]["connection"] == 30
    assert merged["durations_ms"]["activate_ack"] == 12
    assert merged["start_class"] == START_CLASS_COLD
    assert merged["environment"]["pilot_device_id"] == "pilot-1"


def test_merge_prefers_backend_warm_camera_over_client_cold():
    backend = {
        "session_id": "s2",
        "start_class": START_CLASS_WARM_CAMERA,
        "camera_start_class": START_CLASS_WARM_CAMERA,
        "model_start_class": START_CLASS_COLD,
        "durations_ms": {"camera_open": 12},
        "environment": {"pilot_device_id": "hashed-host"},
    }
    client = {
        "session_id": "s2",
        "start_class": START_CLASS_COLD,
        "camera_start_class": START_CLASS_COLD,
        "model_start_class": START_CLASS_COLD,
        "durations_ms": {"client_first_preview": 80},
        "environment": {"pilot_device_id": "pilot-1"},
    }
    merged = merge_backend_and_client(backend, client)
    assert merged["start_class"] == START_CLASS_WARM_CAMERA
    assert merged["camera_start_class"] == START_CLASS_WARM_CAMERA
    assert merged["model_start_class"] == START_CLASS_COLD
    assert merged["environment"]["pilot_device_id"] == "pilot-1"


def test_device_path_is_inferred_stable_without_enumeration():
    assert infer_identity_stable_from_device_id("opencv:1") is False
    assert infer_identity_stable_from_device_id("dshow-name:Webcam:0") is False
    assert infer_identity_stable_from_device_id(r"\\?\usb#vid_1234") is True
    assert infer_identity_stable_from_device_id("dev-a") is False
