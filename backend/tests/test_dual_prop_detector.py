from __future__ import annotations

import numpy as np
import pytest

from vision.dual_prop_detector import DualPropDetector, DualPropResult, ModelLoadError
from vision.types import PropDetection


class _StubDetector:
    def __init__(self, detections: list[PropDetection], *, fail: bool = False):
        self._detections = detections
        self._fail = fail
        self.ensure_ready_calls = 0
        self.detect_calls = 0

    def ensure_ready(self) -> None:
        self.ensure_ready_calls += 1
        if self._fail:
            raise ModelLoadError("stub load failure")

    def detect(self, frame):
        self.detect_calls += 1
        return list(self._detections)


def _bottle(conf: float = 0.9) -> PropDetection:
    return PropDetection(x1=1, y1=1, x2=10, y2=40, confidence=conf)


def _shaker(conf: float = 0.9) -> PropDetection:
    return PropDetection(x1=1, y1=1, x2=40, y2=10, confidence=conf)


def _frame() -> np.ndarray:
    return np.zeros((32, 32, 3), dtype=np.uint8)


def test_ensure_ready_validates_both_models():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    dual.ensure_ready()

    assert bottle_det.ensure_ready_calls == 1
    assert shaker_det.ensure_ready_calls == 1


def test_bottle_model_failure_raises_model_load_error():
    bottle_det = _StubDetector([], fail=True)
    shaker_det = _StubDetector([])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    with pytest.raises(ModelLoadError):
        dual.ensure_ready()


def test_shaker_model_failure_raises_model_load_error():
    bottle_det = _StubDetector([])
    shaker_det = _StubDetector([], fail=True)
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    with pytest.raises(ModelLoadError):
        dual.ensure_ready()


def test_first_two_calls_initialize_both_caches_starting_with_bottle():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    first = dual.detect(_frame())
    assert bottle_det.detect_calls == 1
    assert shaker_det.detect_calls == 0
    assert len(first.bottles) == 1
    assert first.shakers == []

    second = dual.detect(_frame())
    assert bottle_det.detect_calls == 1
    assert shaker_det.detect_calls == 1
    assert len(second.bottles) == 1
    assert len(second.shakers) == 1


def test_bottle_and_shaker_results_stay_separate_and_typed():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    dual.detect(_frame())
    result = dual.detect(_frame())

    assert isinstance(result, DualPropResult)
    assert result.bottles is not result.shakers
    assert all(isinstance(b, PropDetection) for b in result.bottles)
    assert all(isinstance(s, PropDetection) for s in result.shakers)


def test_alternating_inference_updates_one_cached_prop_at_a_time():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    dual.detect(_frame())  # refreshes bottle
    dual.detect(_frame())  # refreshes shaker
    dual.detect(_frame())  # refreshes bottle again
    assert bottle_det.detect_calls == 2
    assert shaker_det.detect_calls == 1


def test_cached_detections_are_preserved_between_alternating_updates():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    dual.detect(_frame())
    result_after_shaker_only_target = dual.detect(_frame())
    # Bottle cache from the first call must still be present even though this
    # call only refreshed the shaker.
    assert len(result_after_shaker_only_target.bottles) == 1
    assert len(result_after_shaker_only_target.shakers) == 1

    # Now refresh bottle with an empty detection; shaker cache must persist.
    bottle_det._detections = []
    result_after_bottle_refresh = dual.detect(_frame())
    assert result_after_bottle_refresh.bottles == []
    assert len(result_after_bottle_refresh.shakers) == 1


def test_reset_cache_clears_both_caches_and_restarts_alternation():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(bottle_detector=bottle_det, shaker_detector=shaker_det)

    dual.detect(_frame())
    dual.detect(_frame())
    dual.reset_cache()

    # Alternation restarts at bottle.
    result = dual.detect(_frame())
    assert bottle_det.detect_calls == 2
    assert shaker_det.detect_calls == 1
    assert len(result.bottles) == 1
    assert result.shakers == []


def test_disabled_detector_returns_empty_results_without_calling_detectors():
    bottle_det = _StubDetector([_bottle()])
    shaker_det = _StubDetector([_shaker()])
    dual = DualPropDetector(
        enabled=False, bottle_detector=bottle_det, shaker_detector=shaker_det
    )

    result = dual.detect(_frame())

    assert result.bottles == []
    assert result.shakers == []
    assert bottle_det.detect_calls == 0
    assert shaker_det.detect_calls == 0
