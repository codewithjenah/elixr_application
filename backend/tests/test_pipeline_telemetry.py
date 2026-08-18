"""Deterministic tests for CV pipeline performance telemetry."""

from __future__ import annotations

from vision.pipeline_telemetry import (
    PipelineTimings,
    classify_bottleneck,
    format_perf_line,
    interval_rate,
    monotonic_counter_delta,
)


def test_interval_rate_uses_window_not_lifetime_totals():
    assert interval_rate(60, 3.0) == 20.0
    assert interval_rate(0, 3.0) == 0.0
    assert interval_rate(10, 0.0) == 0.0
    # A later 60-frame window of 6s is 10 fps, not a cumulative blend.
    assert interval_rate(60, 6.0) == 10.0


def test_monotonic_counter_delta_handles_slot_replacement():
    assert monotonic_counter_delta(current=90, previous=40) == 50
    # Slot/producer restart resets the counter; do not report a huge wrap.
    assert monotonic_counter_delta(current=5, previous=90) == 5
    assert monotonic_counter_delta(current=0, previous=0) == 0


def test_yolo_skip_frames_do_not_dilute_average_inference_time():
    timings = PipelineTimings()
    timings.add("yolo", 0.050)
    timings.add("processing_total", 0.080)
    # Skipped YOLO frame: processing still recorded, yolo is not.
    timings.add("processing_total", 0.012)

    assert timings.count("yolo") == 1
    assert timings.average_ms("yolo") == 50.0
    assert abs(timings.average_ms("processing_total") - 46.0) < 0.01


def test_frame_age_tracks_average_and_max():
    timings = PipelineTimings()
    timings.add_frame_age(0.010)
    timings.add_frame_age(0.040)
    timings.add_frame_age(0.018)

    assert abs(timings.frame_age_avg_ms - 22.666) < 0.01
    assert timings.frame_age_max_ms == 40.0


def test_over_budget_percentage_uses_end_to_end_samples():
    timings = PipelineTimings()
    timings.add("end_to_end", 0.030)
    timings.add("end_to_end", 0.080)
    timings.add("end_to_end", 0.090)

    assert timings.count("end_to_end") == 3
    assert abs(timings.over_budget_pct(budget_s=0.050) - (200.0 / 3.0)) < 0.01


def test_reset_clears_interval_aggregates():
    timings = PipelineTimings()
    timings.add("yolo", 0.040)
    timings.add("end_to_end", 0.090)
    timings.add_frame_age(0.020)
    timings.reset()

    assert timings.count("yolo") == 0
    assert timings.count("end_to_end") == 0
    assert timings.frame_age_avg_ms == 0.0
    assert timings.frame_age_max_ms == 0.0
    assert timings.over_budget_pct(budget_s=0.050) == 0.0


def test_healthy_when_output_meets_target_even_if_ai_is_largest_slice():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=19.5,
        capture_fps=30.0,
        over_budget_pct=8.0,
        overwrite_delta=40,
        processed=60,
        stage_sums={
            "yolo": 1.2,
            "hands": 0.4,
            "pose": 0.3,
            "jpeg": 0.1,
            "encode": 0.05,
            "serialize": 0.04,
            "send": 0.06,
            "camera": 0.05,
            "end_to_end": 2.4,
        },
    )
    assert label == "HEALTHY"


def test_ai_inference_when_models_dominate_a_slow_interval():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=10.0,
        capture_fps=30.0,
        over_budget_pct=80.0,
        overwrite_delta=50,
        processed=60,
        stage_sums={
            "yolo": 3.6,
            "hands": 0.9,
            "pose": 1.2,
            "jpeg": 0.2,
            "encode": 0.1,
            "serialize": 0.1,
            "send": 0.1,
            "camera": 0.05,
            "end_to_end": 6.4,
        },
    )
    assert label == "AI_INFERENCE"


def test_jpeg_encoding_when_encode_stage_dominates():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=8.0,
        capture_fps=30.0,
        over_budget_pct=90.0,
        overwrite_delta=40,
        processed=60,
        stage_sums={
            "yolo": 0.3,
            "hands": 0.1,
            "pose": 0.1,
            "jpeg": 4.5,
            "encode": 0.2,
            "serialize": 0.1,
            "send": 0.1,
            "camera": 0.05,
            "end_to_end": 5.5,
        },
    )
    assert label == "JPEG_ENCODING"


def test_transport_when_base64_json_and_send_dominate():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=9.0,
        capture_fps=30.0,
        over_budget_pct=85.0,
        overwrite_delta=35,
        processed=60,
        stage_sums={
            "yolo": 0.4,
            "hands": 0.2,
            "pose": 0.1,
            "jpeg": 0.3,
            "encode": 1.5,
            "serialize": 1.2,
            "send": 2.0,
            "camera": 0.05,
            "end_to_end": 6.0,
        },
    )
    assert label == "TRANSPORT"


def test_camera_capture_when_producer_is_slow_and_overwrites_are_rare():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=8.0,
        capture_fps=7.5,
        over_budget_pct=70.0,
        overwrite_delta=1,
        processed=60,
        stage_sums={
            "yolo": 0.2,
            "hands": 0.1,
            "pose": 0.1,
            "jpeg": 0.2,
            "encode": 0.1,
            "serialize": 0.1,
            "send": 0.1,
            "camera": 3.5,
            "end_to_end": 5.0,
        },
    )
    assert label == "CAMERA_CAPTURE"


def test_mixed_when_no_category_is_clearly_dominant():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=11.0,
        capture_fps=28.0,
        over_budget_pct=60.0,
        overwrite_delta=20,
        processed=60,
        stage_sums={
            "yolo": 1.6,
            "hands": 0.4,
            "pose": 0.3,
            "jpeg": 1.8,
            "encode": 0.6,
            "serialize": 0.5,
            "send": 0.7,
            "camera": 0.2,
            "end_to_end": 6.5,
        },
    )
    assert label == "MIXED"


def test_high_overwrites_are_not_classified_as_camera_capture():
    label = classify_bottleneck(
        target_fps=20.0,
        output_fps=10.0,
        capture_fps=30.0,
        over_budget_pct=75.0,
        overwrite_delta=80,
        processed=60,
        stage_sums={
            "yolo": 3.5,
            "hands": 0.8,
            "pose": 1.0,
            "jpeg": 0.2,
            "encode": 0.1,
            "serialize": 0.1,
            "send": 0.1,
            "camera": 0.02,
            "end_to_end": 6.0,
        },
    )
    assert label == "AI_INFERENCE"


def test_format_perf_line_is_one_aggregated_summary():
    timings = PipelineTimings()
    for _ in range(3):
        timings.add("yolo", 0.058)
        timings.add("hands", 0.014)
        timings.add("pose", 0.021)
        timings.add("annotate", 0.008)
        timings.add("jpeg", 0.004)
        timings.add("encode", 0.003)
        timings.add("serialize", 0.001)
        timings.add("send", 0.002)
        timings.add("processing_total", 0.099)
        timings.add("end_to_end", 0.101)
        timings.add_frame_age(0.018)
    timings.add_frame_age(0.054)

    line = format_perf_line(
        timings,
        preview_fps=19.5,
        ai_fps=9.0,
        capture_fps=29.8,
        elapsed_s=3.0,
        overwrite_delta=42,
        target_fps=20.0,
        yolo_skip=2,
        imgsz=640,
        lifecycle="active",
        processed=60,
        ticks=60,
        preview_replaced=3,
        ai_overwrites=18,
        ai_processed=27,
    )

    assert line.startswith("CV PERF |")
    assert "preview=19.5fps" in line
    assert "ai=9.0fps" in line
    assert "capture=29.8fps" in line
    assert "yolo=" in line and "fps" in line
    assert "ai_frame_age avg=" in line
    assert "max=" in line
    assert "yolo=58.0ms" in line
    assert "hands=14.0ms" in line
    assert "pose=21.0ms" in line
    assert "annotate=8.0ms" in line
    assert "jpeg=4.0ms" in line
    assert "send=2.0ms" in line
    assert "preview_e2e=" in line
    assert "ai_e2e=" in line
    assert "preview_over_budget=" in line
    assert "preview_drops=3" in line
    assert "ai_overwrites=18" in line
    assert "slot_overwrites=42" in line
    assert "preview_frames=60" in line
    assert "ai_frames=27" in line
    assert "bottleneck=" in line
    assert "\n" not in line


def test_format_perf_line_includes_yolo_runtime_metadata():
    timings = PipelineTimings()
    timings.add("yolo", 0.050)
    timings.add("end_to_end", 0.080)
    line = format_perf_line(
        timings,
        preview_fps=19.0,
        ai_fps=11.0,
        capture_fps=25.0,
        elapsed_s=3.0,
        overwrite_delta=1,
        target_fps=20.0,
        yolo_skip=2,
        imgsz=640,
        lifecycle="active",
        processed=60,
        ticks=60,
        yolo_runtime="onnx_cpu",
        yolo_provider="CPUExecutionProvider",
        yolo_threads=8,
    )
    assert "yolo=50.0ms" in line
    assert "yolo=" in line and "fps" in line
    assert "yolo_runtime=onnx_cpu" in line
    assert "yolo_provider=CPUExecutionProvider" in line
    assert "yolo_threads=8" in line
    assert "\n" not in line
