from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

import config
from vision.prop_detector import (
    CombinedDetectionResult,
    CombinedPropDetector,
    ModelLoadError,
    PropDetector,
    resolve_bottle_and_shaker_class_ids,
    resolve_prop_class_id,
)


class _FakeBox:
    def __init__(self, class_id: int, confidence: float, coords: list[int]):
        self.cls = np.array([class_id])
        self.conf = np.array([confidence])
        self.xyxy = np.array([coords])


class _FakeResult:
    def __init__(self, boxes):
        self.boxes = boxes


class _FakeModel:
    def __init__(self, names, boxes):
        self.names = names
        self._boxes = boxes
        self.call_count = 0

    def __call__(self, frame, **kwargs):
        self.call_count += 1
        assert frame.shape == (32, 32, 3)
        assert kwargs["conf"] == pytest.approx(0.4)
        assert kwargs["iou"] == pytest.approx(0.45)
        assert kwargs["max_det"] == 4
        assert kwargs["imgsz"] == 640
        return [_FakeResult(self._boxes)]


def _verified_names() -> dict[int, str]:
    return {0: "flair_bottle", 1: "shaker_bottle"}


def test_resolves_bottle_and_shaker_from_same_model_mapping():
    bottle_id, shaker_id, names = resolve_bottle_and_shaker_class_ids(
        _verified_names()
    )

    assert bottle_id == 0
    assert shaker_id == 1
    assert names == _verified_names()


def test_resolves_actual_normalized_model_labels():
    bottle_id, _ = resolve_prop_class_id({0: "flair_bottle"}, "bottle")
    shaker_id, _ = resolve_prop_class_id({1: "shaker_bottle"}, "shaker")

    assert bottle_id == 0
    assert shaker_id == 1


def test_rejects_model_missing_bottle_class():
    with pytest.raises(ModelLoadError, match="Could not resolve the bottle class"):
        resolve_bottle_and_shaker_class_ids({0: "shaker_bottle"})


def test_rejects_model_missing_shaker_class():
    with pytest.raises(ModelLoadError, match="Could not resolve the shaker class"):
        resolve_bottle_and_shaker_class_ids({0: "flair_bottle"})


def test_rejects_duplicate_or_ambiguous_matching_classes():
    with pytest.raises(ModelLoadError, match="Could not resolve the bottle class"):
        resolve_bottle_and_shaker_class_ids(
            {0: "flair_bottle", 1: "FLAIR-BOTTLE"},
        )

    with pytest.raises(ModelLoadError, match="Could not resolve the shaker class"):
        resolve_prop_class_id({0: "shaker_bottle", 1: "shaker-bottle"}, "shaker")


def test_bottle_only_filtering_from_combined_result(tmp_path: Path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(
        _verified_names(),
        [
            _FakeBox(0, 0.99, [1, 1, 10, 10]),
            _FakeBox(1, 0.91, [2, 3, 12, 20]),
        ],
    )
    detector = PropDetector(
        "bottle",
        model_path=model_path,
        model_loader=lambda _: model,
    )

    detections = detector.detect(np.zeros((32, 32, 3), dtype=np.uint8))

    assert model.call_count == 1
    assert len(detections) == 1
    assert detections[0].x1 == 1


def test_shaker_only_filtering_from_combined_result(tmp_path: Path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(
        _verified_names(),
        [
            _FakeBox(0, 0.99, [1, 1, 10, 10]),
            _FakeBox(1, 0.91, [2, 3, 12, 20]),
        ],
    )
    detector = PropDetector(
        "shaker",
        model_path=model_path,
        model_loader=lambda _: model,
    )

    detections = detector.detect(np.zeros((32, 32, 3), dtype=np.uint8))

    assert model.call_count == 1
    assert len(detections) == 1
    assert detections[0].x1 == 2


def test_detect_all_returns_both_lists_from_one_inference(tmp_path: Path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(
        _verified_names(),
        [
            _FakeBox(0, 0.99, [1, 1, 10, 10]),
            _FakeBox(1, 0.91, [2, 3, 12, 20]),
        ],
    )
    detector = PropDetector(
        "bottle",
        model_path=model_path,
        model_loader=lambda _: model,
    )

    result = detector.detect_all(np.zeros((32, 32, 3), dtype=np.uint8))

    assert model.call_count == 1
    assert isinstance(result, CombinedDetectionResult)
    assert len(result.bottles) == 1
    assert len(result.shakers) == 1
    assert result.bottles is not result.shakers


def test_default_model_path_is_absolute_backend_models_best_pt():
    detector = CombinedPropDetector(
        model_loader=lambda _: pytest.fail("loader should not run"),
    )

    assert detector.model_path.is_absolute()
    assert detector.model_path == config.YOLO_MODEL_PATH
    assert detector.model_path.name == "best.pt"
    assert detector.model_path.parent.name == "models"


def test_missing_model_raises_clear_load_error(tmp_path: Path):
    detector = CombinedPropDetector(
        model_path=tmp_path / "missing.pt",
        model_loader=lambda _: pytest.fail("loader should not run"),
    )

    with pytest.raises(ModelLoadError, match="missing"):
        detector.ensure_ready()


def test_yolo_is_loaded_lazily(tmp_path: Path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    loaded_paths: list[str] = []

    def loader(path: str):
        loaded_paths.append(path)
        return _FakeModel(_verified_names(), [])

    detector = PropDetector(
        "shaker",
        model_path=model_path,
        model_loader=loader,
    )

    assert loaded_paths == []
    detector.ensure_ready()
    assert loaded_paths == [str(model_path.resolve())]
    assert detector.resolved_class_id == 1
