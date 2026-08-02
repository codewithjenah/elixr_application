from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from vision.prop_detector import (
    ModelLoadError,
    PropDetector,
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

    def __call__(self, frame, **kwargs):
        assert frame.shape == (32, 32, 3)
        assert kwargs["conf"] == pytest.approx(0.4)
        assert kwargs["iou"] == pytest.approx(0.45)
        assert kwargs["max_det"] == 2
        return [_FakeResult(self._boxes)]


def test_resolves_verified_shaker_class_without_assuming_zero():
    class_id, names = resolve_prop_class_id(
        {0: "flair_bottle", 1: "shaker_bottle"},
        "shaker",
    )

    assert class_id == 1
    assert names == {0: "flair_bottle", 1: "shaker_bottle"}


def test_resolves_normalized_aliases_and_rejects_unrelated_class():
    class_id, _ = resolve_prop_class_id(
        {0: "cocktail-shaker"},
        "shaker",
    )
    assert class_id == 0

    with pytest.raises(ModelLoadError, match="Could not resolve"):
        resolve_prop_class_id({0: "person"}, "shaker")


def test_detector_is_lazy_and_loads_only_selected_absolute_model(tmp_path: Path):
    shaker_path = tmp_path / "shaker_best.pt"
    shaker_path.write_bytes(b"weights")
    loaded_paths: list[str] = []

    def loader(path: str):
        loaded_paths.append(path)
        return _FakeModel(
            {0: "flair_bottle", 1: "shaker_bottle"},
            [
                _FakeBox(0, 0.99, [1, 1, 10, 10]),
                _FakeBox(1, 0.91, [2, 3, 12, 20]),
            ],
        )

    detector = PropDetector(
        "shaker",
        model_path=shaker_path,
        model_loader=loader,
    )
    assert loaded_paths == []
    assert detector.model_path.is_absolute()

    detector.ensure_ready()
    detections = detector.detect(np.zeros((32, 32, 3), dtype=np.uint8))

    assert loaded_paths == [str(shaker_path.resolve())]
    assert detector.resolved_class_id == 1
    assert len(detections) == 1
    assert detections[0].x1 == 2


def test_missing_model_raises_clear_load_error(tmp_path: Path):
    detector = PropDetector(
        "bottle",
        model_path=tmp_path / "missing.pt",
        model_loader=lambda _: pytest.fail("loader should not run"),
    )

    with pytest.raises(ModelLoadError, match="missing"):
        detector.ensure_ready()
