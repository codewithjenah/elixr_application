"""Production CV profiler: aggregation only. Does not change detector behavior."""

from __future__ import annotations

import inspect

from api import websocket as websocket_api
from assessment.hands_profile import hands_profile_for
from config import MOVEMENT_CONFIG, YOLO_CONFIDENCE, YOLO_IMGSZ, YOLO_IOU
from test_session_lifecycle import StubHandsDetector, _activate_prepared, _patch_vision
from vision.hands_detector import HandsDetector
from vision.hands_diagnostics import HandsCallStats
from vision.pipeline_telemetry import CaptureProducerSnapshot, PipelineTimings
from vision.production_cv_profile import (
    OPTIONAL_NO_FALLBACK_MOVEMENT,
    REPRESENTATIVE_MOVEMENTS,
    begin_measurement,
    classify_stage_bottleneck,
    collect_session_snapshot,
    format_comparison_table,
    format_snapshot_report,
    snapshot_from_parts,
)


def test_representative_movements_cover_distinct_detector_paths():
    names = [row[0] for row in REPRESENTATIVE_MOVEMENTS]
    assert "Normal Grip" in names
    assert "Bartender's Grip" in names
    assert "Claw Grip" in names
    assert "Double Hand Stall" in names
    assert "Shoulder Stall" in names
    assert OPTIONAL_NO_FALLBACK_MOVEMENT == "Reverse Grip"
    reverse = hands_profile_for("Reverse Grip")
    normal = hands_profile_for("Normal Grip")
    assert reverse.rotated_fallback is False
    assert reverse.bartender_roi_fallback is False
    assert reverse.semantic_max_hands == 1
    assert normal.rotated_fallback is True


def test_warmup_samples_are_excluded_from_steady_state_snapshot():
    warmup = PipelineTimings()
    warmup.add("yolo", 0.500)
    warmup.add("processing_total", 0.600)
    measured = PipelineTimings()
    measured.add("yolo", 0.040)
    measured.add("yolo", 0.050)
    measured.add("processing_total", 0.080)
    measured.add("processing_total", 0.090)

    snap = snapshot_from_parts(
        movement="Normal Grip",
        preview_timings=PipelineTimings(),
        ai_timings=measured,
        elapsed_s=2.0,
        preview_frames=40,
        ai_frames=20,
        warmup_s=5.0,
        measured_s=2.0,
        capture=CaptureProducerSnapshot(usable_frames=40, failed_reads=0),
        preview_drops=0,
    )
    assert snap.warmup_s == 5.0
    assert snap.measured_s == 2.0
    assert abs(snap.yolo_mean_ms - 45.0) < 0.01
    assert snap.yolo_p95_ms == 50.0
    assert abs(snap.ai_e2e_mean_ms - 85.0) < 0.01


def test_disabled_stages_are_na_and_zero_counts():
    ai = PipelineTimings()
    ai.add("yolo", 0.040)
    ai.add("pose", 0.030)
    ai.add("processing_total", 0.080)
    snap = snapshot_from_parts(
        movement="Shoulder Stall",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        capture=CaptureProducerSnapshot(),
        preview_drops=0,
        hands_stats=None,
        hands_enabled=False,
        pose_enabled=True,
    )
    assert snap.hands_enabled is False
    assert snap.pose_enabled is True
    assert snap.hands_mean_ms is None
    assert snap.fallback_activation_pct is None
    assert snap.pose_mean_ms == 30.0
    line = format_comparison_table([snap])
    assert "N/A" in line
    assert "Shoulder Stall" in line


def test_fallback_counts_and_nested_percentage_label():
    stats = HandsCallStats()
    stats.detect_calls = 10
    for _ in range(10):
        stats.record_primary(0.020)
    stats.record_rotated(0.080)
    stats.mark_fallback_activated()
    stats.record_rotated_outcome(True)
    stats.record_fallback_frame(attempted=True, recovered=True)

    ai = PipelineTimings()
    for _ in range(10):
        ai.add("hands", 0.028)
        ai.add("yolo", 0.040)
        ai.add("processing_total", 0.080)

    snap = snapshot_from_parts(
        movement="Claw Grip",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        capture=CaptureProducerSnapshot(),
        preview_drops=1,
        hands_stats=stats,
        hands_enabled=True,
        pose_enabled=False,
    )
    assert snap.fallback_activation_pct == 10.0
    assert snap.fallback_calls == 1
    assert snap.fallback_successes == 1
    assert snap.fallback_type == "rotated"
    assert snap.fallback_mean_ms == 80.0
    assert "subset of Hands" in snap.share_notes
    assert "estimate" in snap.share_notes.lower()


def test_timing_aggregation_and_effective_yolo_rate():
    ai = PipelineTimings()
    for _ in range(8):
        ai.add("yolo", 0.050)
        ai.add("processing_total", 0.100)
    snap = snapshot_from_parts(
        movement="Normal Grip",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=2.0,
        preview_frames=40,
        ai_frames=16,
        warmup_s=5.0,
        measured_s=2.0,
        capture=CaptureProducerSnapshot(usable_frames=40, failed_reads=2),
        preview_drops=3,
    )
    assert snap.ai_fps == 8.0
    assert snap.preview_fps == 20.0
    assert snap.yolo_calls == 8
    assert snap.yolo_calls_per_sec == 4.0
    assert snap.capture_failures == 2
    assert snap.preview_drops == 3


def test_classify_yolo_when_it_dominates_every_ai_frame():
    ai = PipelineTimings()
    for _ in range(10):
        ai.add("yolo", 0.040)
        ai.add("hands", 0.010)
        ai.add("processing_total", 0.055)
        ai.add("camera", 0.002)
    snap = snapshot_from_parts(
        movement="Normal Grip",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        capture=CaptureProducerSnapshot(),
        preview_drops=0,
        hands_enabled=True,
        pose_enabled=False,
    )
    assert classify_stage_bottleneck(snap) == "YOLO"


def test_classify_fallback_only_when_frequency_and_latency_are_material():
    stats = HandsCallStats()
    stats.detect_calls = 10
    for _ in range(10):
        stats.record_primary(0.015)
        stats.record_bartender_roi(0.090, ran_image=True)
        stats.mark_fallback_activated()
        stats.record_bartender_outcome(True)
        stats.record_fallback_frame(attempted=True, recovered=True)
    ai = PipelineTimings()
    for _ in range(10):
        ai.add("yolo", 0.020)
        ai.add("hands", 0.110)
        ai.add("processing_total", 0.140)
    snap = snapshot_from_parts(
        movement="Bartender's Grip",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        capture=CaptureProducerSnapshot(),
        preview_drops=0,
        hands_stats=stats,
        hands_enabled=True,
        pose_enabled=False,
    )
    assert classify_stage_bottleneck(snap) == "Hands fallback"


def test_begin_measurement_resets_timings_and_hands_stats_not_detector_flags(
    monkeypatch,
):
    _patch_vision(monkeypatch)

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.stats = HandsCallStats()

        def detect(self, current_frame, bottle=None):
            self.stats.detect_calls += 1
            self.stats.record_primary(0.02)
            return super().detect(current_frame, bottle=bottle)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    session = websocket_api.VisionSession("Claw Grip")
    session.start()
    _activate_prepared(session)
    assert session.hands_detector is not None
    assert session.hands_detector.max_num_hands == 1
    assert session.hands_detector.rotated_fallback is True
    assert session.hands_detector.bartender_roi_fallback is False
    session.timings.add("yolo", 0.4)
    session.hands_detector.stats.detect_calls = 9
    session.hands_detector.stats.record_primary(0.4)
    begin_measurement(session)
    assert session.timings.count("yolo") == 0
    assert session.hands_detector.stats.detect_calls == 0
    assert session.hands_detector.max_num_hands == 1
    assert session.hands_detector.rotated_fallback is True
    session.close()


def test_collect_snapshot_respects_pose_only_and_double_hand_max(monkeypatch):
    _patch_vision(monkeypatch)
    shoulder = websocket_api.VisionSession("Shoulder Stall")
    shoulder.start()
    _activate_prepared(shoulder)
    assert shoulder.hands_detector is None
    assert shoulder.pose_detector is not None
    shoulder.timings.add("pose", 0.033)
    shoulder.timings.add("processing_total", 0.080)
    snap = collect_session_snapshot(
        shoulder,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        preview_drops=0,
        capture=CaptureProducerSnapshot(),
    )
    assert snap.hands_enabled is False
    assert snap.pose_enabled is True
    assert snap.hands_max == 0
    assert snap.requires_hands is False
    assert snap.requires_pose is True
    shoulder.close()

    double = websocket_api.VisionSession("Double Hand Stall")
    double.start()
    _activate_prepared(double)
    assert double.hands_detector is not None
    assert double.hands_detector.max_num_hands == 2
    assert double.pose_detector is None
    double.close()


def test_profiler_import_does_not_change_production_defaults():
    from vision import production_cv_profile as _mod  # noqa: F401

    assert inspect.signature(HandsDetector.__init__).parameters["max_num_hands"].default == 2
    assert MOVEMENT_CONFIG["Double Hand Stall"]["max_hands"] == 2
    assert MOVEMENT_CONFIG["Shoulder Stall"]["requires_hands"] is False
    assert YOLO_IMGSZ == 640
    assert YOLO_CONFIDENCE == 0.4
    assert YOLO_IOU == 0.45


def test_format_snapshot_report_labels_e2e_as_processing_total():
    ai = PipelineTimings()
    ai.add("yolo", 0.040)
    ai.add("processing_total", 0.080)
    snap = snapshot_from_parts(
        movement="Normal Grip",
        preview_timings=PipelineTimings(),
        ai_timings=ai,
        elapsed_s=1.0,
        preview_frames=20,
        ai_frames=10,
        warmup_s=5.0,
        measured_s=1.0,
        capture=CaptureProducerSnapshot(),
        preview_drops=0,
    )
    text = format_snapshot_report(snap)
    assert "processing_total" in text
    assert "WebSocket send" in text
    assert "warmup" in text.lower()
