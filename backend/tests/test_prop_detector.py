from __future__ import annotations

import time
from pathlib import Path

import numpy as np
import pytest

import config
import vision.prop_detector as prop_detector_mod
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
    def __init__(self, names, boxes, expected_conf: float = 0.4):
        self.names = names
        self._boxes = boxes
        self._expected_conf = expected_conf
        self.call_count = 0

    def __call__(self, frame, **kwargs):
        self.call_count += 1
        assert frame.shape == (32, 32, 3)
        assert kwargs["conf"] == pytest.approx(self._expected_conf)
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


def test_resolves_reversed_numeric_class_ids():
    bottle_id, shaker_id, names = resolve_bottle_and_shaker_class_ids(
        {0: "shaker_bottle", 1: "flair_bottle"}
    )

    assert bottle_id == 1
    assert shaker_id == 0
    assert names[1] == "flair_bottle"
    assert names[0] == "shaker_bottle"


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


def test_gap_confidence_keeps_shaker_and_drops_bottle(tmp_path: Path, monkeypatch):
    """Shaker boxes in the bottle/shaker threshold gap are kept; bottles are not."""
    bottle_threshold = 0.50
    shaker_threshold = 0.35
    gap_confidence = 0.40
    monkeypatch.setattr(prop_detector_mod, "YOLO_BOTTLE_CONFIDENCE", bottle_threshold)
    monkeypatch.setattr(prop_detector_mod, "YOLO_SHAKER_CONFIDENCE", shaker_threshold)

    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(
        _verified_names(),
        [
            _FakeBox(0, gap_confidence, [1, 1, 10, 10]),
            _FakeBox(1, gap_confidence, [2, 3, 12, 20]),
        ],
        expected_conf=shaker_threshold,
    )
    detector = CombinedPropDetector(
        model_path=model_path,
        model_loader=lambda _: model,
    )

    result = detector.detect_all(np.zeros((32, 32, 3), dtype=np.uint8))

    assert model.call_count == 1
    assert result.bottles == []
    assert len(result.shakers) == 1
    assert result.shakers[0].confidence == pytest.approx(gap_confidence)
    assert result.shakers[0].x1 == 2


def test_reversed_class_ids_still_split_bottle_and_shaker(tmp_path: Path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(
        {0: "shaker_bottle", 1: "flair_bottle"},
        [
            _FakeBox(1, 0.99, [1, 1, 10, 10]),
            _FakeBox(0, 0.91, [2, 3, 12, 20]),
        ],
    )
    detector = CombinedPropDetector(
        model_path=model_path,
        model_loader=lambda _: model,
    )

    result = detector.detect_all(np.zeros((32, 32, 3), dtype=np.uint8))

    assert detector.bottle_class_id == 1
    assert detector.shaker_class_id == 0
    assert len(result.bottles) == 1
    assert len(result.shakers) == 1
    assert result.bottles[0].x1 == 1
    assert result.shakers[0].x1 == 2


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


def _combined_detector(
    tmp_path: Path, boxes: list[_FakeBox]
) -> tuple[CombinedPropDetector, _FakeModel]:
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"weights")
    model = _FakeModel(_verified_names(), boxes)
    return CombinedPropDetector(
        model_path=model_path,
        model_loader=lambda _: model,
    ), model


def test_detect_all_assigns_stable_track_ids_across_frames(tmp_path: Path):
    detector, model = _combined_detector(
        tmp_path,
        [
            _FakeBox(0, 0.95, [20, 10, 100, 90]),
            _FakeBox(0, 0.90, [220, 10, 300, 90]),
        ],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert {bottle.track_id for bottle in first.bottles} == {1, 2}

    model._boxes = [
        _FakeBox(0, 0.91, [40, 10, 120, 90]),
        _FakeBox(0, 0.88, [200, 10, 280, 90]),
    ]
    second = detector.detect_all(frame)

    first_by_x = sorted(first.bottles, key=lambda bottle: bottle.x1)
    second_by_x = sorted(second.bottles, key=lambda bottle: bottle.x1)
    assert second_by_x[0].track_id == first_by_x[0].track_id
    assert second_by_x[1].track_id == first_by_x[1].track_id


def test_bottles_and_shakers_use_independent_trackers(tmp_path: Path):
    detector, _model = _combined_detector(
        tmp_path,
        [
            _FakeBox(0, 0.99, [1, 1, 10, 40]),
            _FakeBox(1, 0.91, [20, 1, 60, 15]),
        ],
    )

    result = detector.detect_all(np.zeros((32, 32, 3), dtype=np.uint8))

    assert len(result.bottles) == 1
    assert len(result.shakers) == 1
    assert result.bottles[0].track_id == 1
    assert result.shakers[0].track_id == 1


def test_reset_tracks_restarts_bottle_ids(tmp_path: Path):
    detector, model = _combined_detector(
        tmp_path,
        [_FakeBox(0, 0.99, [1, 1, 10, 40])],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert first.bottles[0].track_id == 1

    detector.reset_tracks()
    model._boxes = [_FakeBox(0, 0.99, [200, 1, 240, 40])]
    second = detector.detect_all(frame)
    assert second.bottles[0].track_id == 1


def test_one_frame_yolo_miss_keeps_tracked_bottle_and_shaker(tmp_path: Path):
    """A momentary empty YOLO result must not collapse live prop lists."""
    detector, model = _combined_detector(
        tmp_path,
        [
            _FakeBox(0, 0.99, [20, 10, 100, 90]),
            _FakeBox(1, 0.91, [2, 3, 12, 20]),
        ],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert len(first.bottles) == 1
    assert len(first.shakers) == 1
    assert first.bottles[0].yolo_confirmed is True
    assert first.shakers[0].yolo_confirmed is True
    bottle_id = first.bottles[0].track_id
    shaker_id = first.shakers[0].track_id

    model._boxes = []
    missed = detector.detect_all(frame)

    assert len(missed.bottles) == 1
    assert len(missed.shakers) == 1
    assert missed.bottles[0].track_id == bottle_id
    assert missed.shakers[0].track_id == shaker_id
    assert missed.bottles[0].yolo_confirmed is False
    assert missed.shakers[0].yolo_confirmed is False


def test_spatial_jump_returns_one_live_bottle(tmp_path: Path):
    """A far YOLO box must not leave the previous unmatched bottle in detect_all()."""
    detector, model = _combined_detector(
        tmp_path,
        [_FakeBox(0, 0.99, [10, 10, 50, 90])],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert len(first.bottles) == 1
    first_id = first.bottles[0].track_id

    model._boxes = [_FakeBox(0, 0.99, [200, 10, 240, 90])]
    jumped = detector.detect_all(frame)

    assert len(jumped.bottles) == 1
    assert jumped.bottles[0].track_id != first_id
    assert jumped.bottles[0].x1 == 200
    assert jumped.bottles[0].yolo_confirmed is True


def test_one_of_two_bottles_occluded_keeps_unmatched_live_box(tmp_path: Path):
    """Double-hand occlusion: one YOLO box still returns two live bottles."""
    detector, model = _combined_detector(
        tmp_path,
        [
            _FakeBox(0, 0.99, [10, 10, 50, 90]),
            _FakeBox(0, 0.90, [200, 10, 240, 90]),
        ],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)

    first = detector.detect_all(frame)
    assert len(first.bottles) == 2
    left_id = next(bottle.track_id for bottle in first.bottles if bottle.x1 == 10)
    right_id = next(bottle.track_id for bottle in first.bottles if bottle.x1 == 200)

    model._boxes = [_FakeBox(0, 0.99, [12, 10, 52, 90])]
    occluded = detector.detect_all(frame)

    assert len(occluded.bottles) == 2
    by_id = {bottle.track_id: bottle for bottle in occluded.bottles}
    assert by_id[left_id].yolo_confirmed is True
    assert by_id[right_id].yolo_confirmed is False


def test_extrapolate_detections_falls_back_when_track_is_new(tmp_path: Path):
    detector, _model = _combined_detector(
        tmp_path,
        [_FakeBox(0, 0.99, [40, 10, 80, 90])],
    )
    frame = np.zeros((32, 32, 3), dtype=np.uint8)
    result = detector.detect_all(frame)

    bottles, shakers = detector.extrapolate_detections(
        bottles=result.bottles,
        shakers=result.shakers,
        now=time.monotonic() + 1.0,
    )

    assert bottles == result.bottles
    assert shakers == result.shakers
