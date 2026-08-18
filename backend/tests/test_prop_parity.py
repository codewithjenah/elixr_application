"""Deterministic comparison of YOLO runtime detections."""

from __future__ import annotations

import pytest

from vision.prop_inference import RawDetection
from vision.prop_parity import (
    ParityMismatch,
    compare_raw_detections,
    summarize_parity,
    threshold_crossing_mismatch,
)


def test_identical_detections_pass_parity():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80), RawDetection(1, 0.70, 5, 5, 15, 12)]
    report = compare_raw_detections(left, left)
    assert report.passed
    assert report.count_left == 2
    assert report.count_right == 2
    assert report.mean_iou == pytest.approx(1.0)
    assert report.max_confidence_delta == pytest.approx(0.0)
    assert report.mismatches == []


def test_class_swap_is_semantic_failure():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    right = [RawDetection(1, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, right)
    assert report.passed is False
    assert any(item.kind == "class" for item in report.mismatches)


def test_missing_detection_is_semantic_failure():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, [])
    assert report.passed is False
    assert any(item.kind == "count" for item in report.mismatches)


def test_small_confidence_and_box_jitter_is_accepted():
    left = [RawDetection(0, 0.400, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.408, 11, 20, 41, 81)]
    report = compare_raw_detections(left, right)
    assert report.passed
    assert report.max_confidence_delta == pytest.approx(0.008)
    assert report.min_iou > 0.9


def test_material_box_shift_fails_iou():
    left = [RawDetection(0, 0.90, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.90, 80, 20, 110, 80)]
    report = compare_raw_detections(left, right)
    assert report.passed is False
    assert any(item.kind == "iou" for item in report.mismatches)


def test_confidence_crossing_elixr_threshold_is_rejected():
    left = [RawDetection(0, 0.41, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.39, 10, 20, 40, 80)]
    assert threshold_crossing_mismatch(
        left[0].confidence,
        right[0].confidence,
        threshold=0.40,
    )
    report = compare_raw_detections(
        left,
        right,
        bottle_conf=0.40,
        shaker_conf=0.40,
    )
    assert report.passed is False
    assert any(item.kind == "threshold" for item in report.mismatches)


def test_summarize_parity_includes_counts():
    report = compare_raw_detections(
        [RawDetection(0, 0.9, 1, 1, 10, 10)],
        [RawDetection(0, 0.9, 1, 1, 10, 10)],
    )
    text = summarize_parity(report)
    assert "passed=True" in text
    assert "pairs=1" in text
    assert isinstance(ParityMismatch("count", "x"), ParityMismatch)
