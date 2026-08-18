"""Deterministic comparison of YOLO runtime detections."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import pytest

from vision.prop_inference import RawDetection
from vision.prop_parity import (
    IMAGE_EXTENSIONS,
    STATUS_INSUFFICIENT_COVERAGE,
    STATUS_MINOR_NUMERIC_DRIFT,
    STATUS_PASS,
    STATUS_SEMANTIC_MISMATCH,
    COVERAGE_INSUFFICIENT,
    COVERAGE_SUFFICIENT,
    ParityMismatch,
    aggregate_directory_parity,
    compare_raw_detections,
    discover_parity_images,
    semantic_class_for,
    summarize_directory_parity,
    summarize_parity,
    threshold_for_class_id,
    threshold_crossing_mismatch,
)


PRODUCTION_NAMES = {0: "flair_bottle", 1: "shaker_bottle"}
REVERSED_NAMES = {0: "shaker_bottle", 1: "flair_bottle"}


def test_identical_detections_pass_parity():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80), RawDetection(1, 0.70, 5, 5, 15, 12)]
    report = compare_raw_detections(left, left, names=PRODUCTION_NAMES)
    assert report.passed
    assert report.status == STATUS_PASS
    assert report.count_left == 2
    assert report.count_right == 2
    assert report.mean_iou == pytest.approx(1.0)
    assert report.max_confidence_delta == pytest.approx(0.0)
    assert report.mismatches == []


def test_class_swap_is_semantic_failure():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    right = [RawDetection(1, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed is False
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert any(item.kind == "class" for item in report.mismatches)


def test_missing_detection_is_semantic_failure():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, [], names=PRODUCTION_NAMES)
    assert report.passed is False
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert any(item.kind == "count" for item in report.mismatches)


def test_small_confidence_and_box_jitter_is_accepted():
    left = [RawDetection(0, 0.400, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.408, 11, 20, 41, 81)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed
    assert report.status == STATUS_PASS
    assert report.max_confidence_delta == pytest.approx(0.008)
    assert report.min_iou > 0.9


def test_material_box_shift_fails_iou():
    left = [RawDetection(0, 0.90, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.90, 13, 20, 43, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
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
        names=PRODUCTION_NAMES,
    )
    assert report.passed is False
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert any(item.kind == "threshold" for item in report.mismatches)


def test_summarize_parity_includes_counts():
    report = compare_raw_detections(
        [RawDetection(0, 0.9, 1, 1, 10, 10)],
        [RawDetection(0, 0.9, 1, 1, 10, 10)],
        names=PRODUCTION_NAMES,
    )
    text = summarize_parity(report)
    assert "passed=True" in text
    assert "pairs=1" in text
    assert isinstance(ParityMismatch("count", "x"), ParityMismatch)


def test_semantic_class_resolution_uses_model_names_not_numeric_id():
    assert semantic_class_for(0, PRODUCTION_NAMES) == "bottle"
    assert semantic_class_for(1, PRODUCTION_NAMES) == "shaker"
    assert semantic_class_for(0, REVERSED_NAMES) == "shaker"
    assert semantic_class_for(1, REVERSED_NAMES) == "bottle"


def test_bottle_and_shaker_thresholds_follow_resolved_names():
    assert threshold_for_class_id(
        1,
        names=REVERSED_NAMES,
        bottle_conf=0.50,
        shaker_conf=0.30,
    ) == pytest.approx(0.50)
    assert threshold_for_class_id(
        0,
        names=REVERSED_NAMES,
        bottle_conf=0.50,
        shaker_conf=0.30,
    ) == pytest.approx(0.30)


def test_reversed_numeric_class_ids_still_match_same_semantic_boxes():
    left = [RawDetection(1, 0.91, 10, 20, 40, 80), RawDetection(0, 0.70, 5, 5, 15, 12)]
    right = [RawDetection(1, 0.91, 10, 20, 40, 80), RawDetection(0, 0.70, 5, 5, 15, 12)]
    report = compare_raw_detections(left, right, names=REVERSED_NAMES)
    assert report.passed
    assert report.status == STATUS_PASS
    assert report.bottle_count_left == 1
    assert report.shaker_count_left == 1


def test_reversed_ids_use_shaker_threshold_for_class_zero():
    left = [RawDetection(0, 0.41, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.39, 10, 20, 40, 80)]
    report = compare_raw_detections(
        left,
        right,
        bottle_conf=0.50,
        shaker_conf=0.40,
        names=REVERSED_NAMES,
    )
    assert report.passed is False
    assert any(item.kind == "threshold" for item in report.mismatches)
    below_both = compare_raw_detections(
        left,
        right,
        bottle_conf=0.40,
        shaker_conf=0.50,
        names=REVERSED_NAMES,
    )
    assert not any(item.kind == "threshold" for item in below_both.mismatches)


def test_iou_based_matching_is_not_list_index_order():
    left = [
        RawDetection(0, 0.90, 10, 20, 40, 80),
        RawDetection(0, 0.80, 200, 20, 230, 80),
    ]
    right = [
        RawDetection(0, 0.81, 201, 20, 231, 80),
        RawDetection(0, 0.89, 11, 20, 41, 80),
    ]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed
    assert report.pairs == 2
    assert report.min_iou > 0.9


def test_unmatched_pytorch_detection_is_reported():
    left = [
        RawDetection(0, 0.91, 10, 20, 40, 80),
        RawDetection(0, 0.80, 200, 20, 230, 80),
    ]
    right = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed is False
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert report.unmatched_left == 1
    assert report.unmatched_right == 0
    assert any(item.kind == "unmatched" for item in report.mismatches)


def test_unmatched_onnx_detection_is_reported():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    right = [
        RawDetection(0, 0.91, 10, 20, 40, 80),
        RawDetection(0, 0.80, 200, 20, 230, 80),
    ]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed is False
    assert report.unmatched_left == 0
    assert report.unmatched_right == 1
    assert any(item.kind == "unmatched" for item in report.mismatches)


def test_non_overlapping_same_class_boxes_are_unmatched_not_forced_pairs():
    left = [RawDetection(0, 0.90, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.90, 80, 20, 110, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed is False
    assert report.pairs == 0
    assert report.unmatched_left == 1
    assert report.unmatched_right == 1
    assert any(item.kind == "unmatched" for item in report.mismatches)


def test_confidence_numeric_drift_without_threshold_cross_is_minor():
    left = [RawDetection(0, 0.90, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.93, 10, 20, 40, 80)]
    report = compare_raw_detections(
        left,
        right,
        bottle_conf=0.40,
        shaker_conf=0.40,
        names=PRODUCTION_NAMES,
    )
    assert report.status == STATUS_MINOR_NUMERIC_DRIFT
    assert report.passed
    assert any(item.kind == "confidence" for item in report.mismatches)


def test_bottle_to_shaker_mismatch_is_semantic():
    left = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    right = [RawDetection(1, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert report.bottle_count_left == 1
    assert report.shaker_count_right == 1
    assert report.bottle_count_right == 0


def test_shaker_to_bottle_mismatch_is_semantic():
    left = [RawDetection(1, 0.91, 10, 20, 40, 80)]
    right = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.status == STATUS_SEMANTIC_MISMATCH
    assert report.shaker_count_left == 1
    assert report.bottle_count_right == 1


def test_multiple_same_class_detections_match_by_iou():
    left = [
        RawDetection(1, 0.88, 8, 8, 40, 24),
        RawDetection(1, 0.77, 180, 10, 220, 30),
        RawDetection(1, 0.70, 90, 40, 130, 70),
    ]
    right = [
        RawDetection(1, 0.71, 91, 40, 131, 70),
        RawDetection(1, 0.87, 9, 8, 41, 24),
        RawDetection(1, 0.76, 181, 10, 221, 30),
    ]
    report = compare_raw_detections(left, right, names=PRODUCTION_NAMES)
    assert report.passed
    assert report.pairs == 3
    assert report.shaker_count_left == 3
    assert report.unmatched_left == 0
    assert report.unmatched_right == 0


def test_discover_parity_images_finds_supported_extensions(tmp_path: Path):
    (tmp_path / "a.jpg").write_bytes(b"x")
    (tmp_path / "b.JPEG").write_bytes(b"x")
    (tmp_path / "c.png").write_bytes(b"x")
    (tmp_path / "notes.txt").write_bytes(b"x")
    (tmp_path / "d.webp").write_bytes(b"x")
    found = discover_parity_images(tmp_path)
    assert [path.name for path in found] == ["a.jpg", "b.JPEG", "c.png"]
    assert IMAGE_EXTENSIONS >= {".jpg", ".jpeg", ".png"}


def test_discover_parity_images_missing_directory(tmp_path: Path):
    with pytest.raises(FileNotFoundError, match="not found"):
        discover_parity_images(tmp_path / "missing")


def test_discover_parity_images_empty_directory(tmp_path: Path):
    with pytest.raises(FileNotFoundError, match="No .jpg"):
        discover_parity_images(tmp_path)


def test_directory_summary_counts_coverage_and_failures():
    bottle = compare_raw_detections(
        [RawDetection(0, 0.91, 10, 20, 40, 80)],
        [RawDetection(0, 0.91, 10, 20, 40, 80)],
        names=PRODUCTION_NAMES,
    )
    both = compare_raw_detections(
        [
            RawDetection(0, 0.91, 10, 20, 40, 80),
            RawDetection(1, 0.80, 5, 5, 15, 12),
        ],
        [
            RawDetection(0, 0.91, 10, 20, 40, 80),
            RawDetection(1, 0.80, 5, 5, 15, 12),
        ],
        names=PRODUCTION_NAMES,
    )
    miss = compare_raw_detections(
        [RawDetection(0, 0.91, 10, 20, 40, 80)],
        [],
        names=PRODUCTION_NAMES,
    )
    summary = aggregate_directory_parity(
        [
            ("bottle.jpg", bottle),
            ("both.jpg", both),
            ("miss.jpg", miss),
        ]
    )
    assert summary.images_tested == 3
    assert summary.images_with_bottle == 3
    assert summary.images_with_shaker == 1
    assert summary.images_with_both == 1
    assert summary.total_pytorch_detections == 4
    assert summary.total_onnx_detections == 3
    assert summary.semantic_mismatches == 1
    assert summary.passed is False
    assert summary.coverage_status == COVERAGE_SUFFICIENT
    assert summary.status == STATUS_SEMANTIC_MISMATCH
    text = summarize_directory_parity(summary)
    assert "images tested=3" in text
    assert "images with bottle=3" in text
    assert "images with shaker=1" in text
    assert "images with both=1" in text
    assert "PyTorch detections=4" in text
    assert "ONNX detections=3" in text
    assert "semantic mismatches=1" in text
    assert "coverage status=SUFFICIENT" in text
    assert "overall production-gate status=SEMANTIC_MISMATCH" in text
    assert "overall=PASS" not in text
    assert "miss.jpg" in text
    assert "bottle.jpg" not in text


def _empty_pair():
    return compare_raw_detections([], [], names=PRODUCTION_NAMES)


def _bottle_pair():
    box = [RawDetection(0, 0.91, 10, 20, 40, 80)]
    return compare_raw_detections(box, box, names=PRODUCTION_NAMES)


def _shaker_pair():
    box = [RawDetection(1, 0.80, 5, 5, 15, 12)]
    return compare_raw_detections(box, box, names=PRODUCTION_NAMES)


def _both_pair():
    boxes = [
        RawDetection(0, 0.91, 10, 20, 40, 80),
        RawDetection(1, 0.80, 5, 5, 15, 12),
    ]
    return compare_raw_detections(boxes, boxes, names=PRODUCTION_NAMES)


def test_zero_zero_real_detections_are_insufficient_coverage_not_pass():
    summary = aggregate_directory_parity(
        [(f"{index:03d}.jpg", _empty_pair()) for index in range(1, 21)]
    )
    assert summary.images_tested == 20
    assert summary.total_pytorch_detections == 0
    assert summary.total_onnx_detections == 0
    assert summary.semantic_mismatches == 0
    assert summary.threshold_crossings == 0
    assert summary.iou_failures == 0
    assert summary.images_with_bottle == 0
    assert summary.images_with_shaker == 0
    assert summary.images_with_both == 0
    assert summary.coverage_status == COVERAGE_INSUFFICIENT
    assert summary.status == STATUS_INSUFFICIENT_COVERAGE
    assert summary.passed is False
    text = summarize_directory_parity(summary)
    assert "overall=PASS" not in text
    assert "overall production-gate status=INSUFFICIENT_COVERAGE" in text
    assert "coverage status=INSUFFICIENT_COVERAGE" in text
    assert "SEMANTIC_MISMATCH" not in text


def test_bottle_only_dataset_is_insufficient_coverage():
    summary = aggregate_directory_parity(
        [("bottle.jpg", _bottle_pair()), ("empty.jpg", _empty_pair())]
    )
    assert summary.images_with_bottle == 1
    assert summary.images_with_shaker == 0
    assert summary.images_with_both == 0
    assert summary.semantic_mismatches == 0
    assert summary.coverage_status == COVERAGE_INSUFFICIENT
    assert summary.status == STATUS_INSUFFICIENT_COVERAGE
    assert summary.passed is False
    text = summarize_directory_parity(summary)
    assert "overall=PASS" not in text
    assert "SEMANTIC_MISMATCH" not in text


def test_shaker_only_dataset_is_insufficient_coverage():
    summary = aggregate_directory_parity(
        [("shaker.jpg", _shaker_pair())]
    )
    assert summary.images_with_bottle == 0
    assert summary.images_with_shaker == 1
    assert summary.images_with_both == 0
    assert summary.semantic_mismatches == 0
    assert summary.coverage_status == COVERAGE_INSUFFICIENT
    assert summary.status == STATUS_INSUFFICIENT_COVERAGE
    assert summary.passed is False


def test_bottle_and_shaker_coverage_with_parity_passes():
    summary = aggregate_directory_parity(
        [
            ("bottle.jpg", _bottle_pair()),
            ("shaker.jpg", _shaker_pair()),
        ]
    )
    assert summary.images_with_bottle == 1
    assert summary.images_with_shaker == 1
    assert summary.images_with_both == 0
    assert summary.coverage_status == COVERAGE_SUFFICIENT
    assert summary.status == STATUS_PASS
    assert summary.passed is True
    text = summarize_directory_parity(summary)
    assert "images with both=0" in text
    assert "overall production-gate status=PASS" in text


def test_same_image_bottle_and_shaker_coverage_is_reported_and_passes():
    summary = aggregate_directory_parity([("both.jpg", _both_pair())])
    assert summary.images_with_both == 1
    assert summary.coverage_status == COVERAGE_SUFFICIENT
    assert summary.status == STATUS_PASS
    assert summary.passed is True


def test_semantic_mismatch_fails_even_with_bottle_and_shaker_coverage():
    mismatch = compare_raw_detections(
        [RawDetection(0, 0.91, 10, 20, 40, 80)],
        [RawDetection(1, 0.91, 10, 20, 40, 80)],
        names=PRODUCTION_NAMES,
    )
    summary = aggregate_directory_parity(
        [
            ("swap.jpg", mismatch),
            ("shaker.jpg", _shaker_pair()),
        ]
    )
    assert summary.images_with_bottle >= 1
    assert summary.images_with_shaker >= 1
    assert summary.coverage_status == COVERAGE_SUFFICIENT
    assert summary.status == STATUS_SEMANTIC_MISMATCH
    assert summary.passed is False
    text = summarize_directory_parity(summary)
    assert "overall production-gate status=SEMANTIC_MISMATCH" in text
    assert "overall=PASS" not in text


def test_threshold_crossing_fails_production_gate():
    crossing = compare_raw_detections(
        [RawDetection(0, 0.41, 10, 20, 40, 80)],
        [RawDetection(0, 0.39, 10, 20, 40, 80)],
        bottle_conf=0.40,
        shaker_conf=0.40,
        names=PRODUCTION_NAMES,
    )
    summary = aggregate_directory_parity(
        [
            ("cross.jpg", crossing),
            ("shaker.jpg", _shaker_pair()),
        ]
    )
    assert summary.threshold_crossings >= 1
    assert summary.coverage_status == COVERAGE_SUFFICIENT
    assert summary.status == STATUS_SEMANTIC_MISMATCH
    assert summary.passed is False


def _load_validate_module():
    import importlib.util

    script = Path(__file__).resolve().parents[1] / "scripts" / "validate_prop_parity.py"
    spec = importlib.util.spec_from_file_location("validate_prop_parity", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_tiny_jpeg(path: Path) -> None:
    ok = cv2.imwrite(str(path), np.zeros((8, 8, 3), dtype=np.uint8))
    assert ok


class _StubParityBackend:
    names = {0: "flair_bottle", 1: "shaker_bottle"}

    def __init__(self, detections_by_name: dict[str, list[RawDetection]] | None = None):
        self.detections_by_name = detections_by_name or {}
        self.current_name = ""

    def load(self) -> None:
        return None

    def infer(self, frame, **kwargs):
        return list(self.detections_by_name.get(self.current_name, []))


def test_validate_script_zero_detections_exits_nonzero_insufficient(tmp_path: Path, monkeypatch, capsys):
    module = _load_validate_module()
    _write_tiny_jpeg(tmp_path / "001.jpg")
    backend = _StubParityBackend()
    monkeypatch.setattr(module, "_load_backends", lambda: (backend, backend))
    code = module.main(["--images", str(tmp_path)])
    output = capsys.readouterr().out
    assert code == 3
    assert "INSUFFICIENT_COVERAGE" in output
    assert "overall=PASS" not in output
    assert "PASS\n" not in output
    assert "FAIL: real-image semantic parity mismatch" not in output


def test_validate_script_parity_pass_exits_zero(tmp_path: Path, monkeypatch, capsys):
    module = _load_validate_module()
    _write_tiny_jpeg(tmp_path / "bottle.jpg")
    _write_tiny_jpeg(tmp_path / "shaker.jpg")
    detections = {
        "bottle.jpg": [RawDetection(0, 0.91, 10, 20, 40, 80)],
        "shaker.jpg": [RawDetection(1, 0.80, 5, 5, 15, 12)],
    }
    pytorch = _StubParityBackend(detections)
    onnx = _StubParityBackend(detections)
    original_load = module._load_bgr_image

    def load_image(path: Path):
        pytorch.current_name = path.name
        onnx.current_name = path.name
        return original_load(path)

    monkeypatch.setattr(module, "_load_backends", lambda: (pytorch, onnx))
    monkeypatch.setattr(module, "_load_bgr_image", load_image)
    code = module.main(["--images", str(tmp_path)])
    output = capsys.readouterr().out
    assert code == 0
    assert "overall production-gate status=PASS" in output


def test_validate_script_semantic_mismatch_exits_nonzero_mismatch(tmp_path: Path, monkeypatch, capsys):
    module = _load_validate_module()
    _write_tiny_jpeg(tmp_path / "bottle.jpg")
    _write_tiny_jpeg(tmp_path / "shaker.jpg")
    pytorch = _StubParityBackend(
        {
            "bottle.jpg": [RawDetection(0, 0.91, 10, 20, 40, 80)],
            "shaker.jpg": [RawDetection(1, 0.80, 5, 5, 15, 12)],
        }
    )
    onnx = _StubParityBackend(
        {
            "bottle.jpg": [RawDetection(1, 0.91, 10, 20, 40, 80)],
            "shaker.jpg": [RawDetection(1, 0.80, 5, 5, 15, 12)],
        }
    )
    original_load = module._load_bgr_image

    def load_image(path: Path):
        pytorch.current_name = path.name
        onnx.current_name = path.name
        return original_load(path)

    monkeypatch.setattr(module, "_load_backends", lambda: (pytorch, onnx))
    monkeypatch.setattr(module, "_load_bgr_image", load_image)
    code = module.main(["--images", str(tmp_path)])
    output = capsys.readouterr().out
    assert code == 1
    assert "SEMANTIC_MISMATCH" in output
    assert "INSUFFICIENT_COVERAGE: need" not in output
    assert "overall=PASS" not in output


def test_validate_script_missing_and_empty_image_directory(tmp_path: Path, monkeypatch):
    import importlib.util

    script = Path(__file__).resolve().parents[1] / "scripts" / "validate_prop_parity.py"
    spec = importlib.util.spec_from_file_location("validate_prop_parity", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    class _Names:
        names = {0: "flair_bottle", 1: "shaker_bottle"}

        def load(self) -> None:
            return None

    monkeypatch.setattr(module, "_load_backends", lambda: (_Names(), _Names()))
    assert module.main(["--images", str(tmp_path / "missing")]) == 2
    assert module.main(["--images", str(tmp_path)]) == 2
