from __future__ import annotations

import numpy as np
import pytest

from vision.dual_prop_detector import DualPropDetector, DualPropResult, ModelLoadError
from vision.prop_detector import CombinedDetectionResult
from vision.types import PropDetection


class _StubCombinedDetector:
    def __init__(
        self,
        *,
        bottles: list[PropDetection] | None = None,
        shakers: list[PropDetection] | None = None,
        fail: bool = False,
    ):
        self._bottles = bottles or []
        self._shakers = shakers or []
        self._fail = fail
        self.ensure_ready_calls = 0
        self.detect_all_calls = 0

    def ensure_ready(self) -> None:
        self.ensure_ready_calls += 1
        if self._fail:
            raise ModelLoadError("stub load failure")

    def detect_all(self, frame):
        self.detect_all_calls += 1
        return CombinedDetectionResult(
            bottles=list(self._bottles),
            shakers=list(self._shakers),
        )


def _bottle(conf: float = 0.9) -> PropDetection:
    return PropDetection(x1=1, y1=1, x2=10, y2=40, confidence=conf)


def _shaker(conf: float = 0.9) -> PropDetection:
    return PropDetection(x1=1, y1=1, x2=40, y2=10, confidence=conf)


def _frame() -> np.ndarray:
    return np.zeros((32, 32, 3), dtype=np.uint8)


def test_ensure_ready_validates_one_combined_model():
    combined = _StubCombinedDetector()
    dual = DualPropDetector(combined_detector=combined)

    dual.ensure_ready()

    assert combined.ensure_ready_calls == 1


def test_model_load_failure_propagates():
    combined = _StubCombinedDetector(fail=True)
    dual = DualPropDetector(combined_detector=combined)

    with pytest.raises(ModelLoadError):
        dual.ensure_ready()


def test_detect_runs_exactly_one_inference():
    combined = _StubCombinedDetector(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(combined_detector=combined)

    dual.detect(_frame())

    assert combined.detect_all_calls == 1


def test_bottle_and_shaker_come_from_same_inference():
    combined = _StubCombinedDetector(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(combined_detector=combined)

    result = dual.detect(_frame())

    assert isinstance(result, DualPropResult)
    assert len(result.bottles) == 1
    assert len(result.shakers) == 1
    assert result.bottles is not result.shakers
    assert all(isinstance(b, PropDetection) for b in result.bottles)
    assert all(isinstance(s, PropDetection) for s in result.shakers)


def test_empty_current_frame_replaces_previous_detections():
    combined = _StubCombinedDetector(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(combined_detector=combined)

    first = dual.detect(_frame())
    assert len(first.bottles) == 1
    assert len(first.shakers) == 1

    combined._bottles = []
    combined._shakers = []
    second = dual.detect(_frame())

    assert second.bottles == []
    assert second.shakers == []
    assert combined.detect_all_calls == 2


def test_reset_cache_remains_compatible():
    combined = _StubCombinedDetector(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(combined_detector=combined)

    dual.detect(_frame())
    dual.reset_cache()
    result = dual.detect(_frame())

    assert len(result.bottles) == 1
    assert len(result.shakers) == 1


class _StubCombinedDetectorWithTracks(_StubCombinedDetector):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.reset_tracks_calls = 0

    def reset_tracks(self) -> None:
        self.reset_tracks_calls += 1


def test_reset_cache_resets_combined_prop_tracks():
    combined = _StubCombinedDetectorWithTracks(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(combined_detector=combined)

    dual.reset_cache()

    assert combined.reset_tracks_calls == 1


def test_disabled_detector_returns_empty_results_without_inference():
    combined = _StubCombinedDetector(bottles=[_bottle()], shakers=[_shaker()])
    dual = DualPropDetector(enabled=False, combined_detector=combined)

    result = dual.detect(_frame())

    assert result.bottles == []
    assert result.shakers == []
    assert combined.detect_all_calls == 0
