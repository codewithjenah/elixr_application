"""Custom movement sessions use only the selected prop class from the combined model.

A real ``CombinedPropDetector`` runs with an injected inference backend that
emits raw class IDs, so class resolution, per-class confidence, tracking, and
session normalization are all exercised without model weights or a camera.
"""

from __future__ import annotations

import time
from types import SimpleNamespace

import numpy as np
import pytest

from api import websocket as websocket_api
from assessment.custom_movement import build_template
from assessment.readiness import ReadinessObservation
from vision.prop_detector import CombinedPropDetector, PropDetector
from vision.prop_inference import PropInferenceBackend, RawDetection
from test_custom_movement_session import _held_grip

BOTTLE, SHAKER = 0, 1


class _RawBackend(PropInferenceBackend):
    runtime_name = "fake"
    provider = "fake"

    def __init__(self, raw: list[RawDetection]):
        self.raw = raw

    @property
    def names(self):
        return {BOTTLE: "flair_bottle", SHAKER: "shaker_bottle"}

    def load(self):
        pass

    def infer(self, frame, **kwargs):
        return list(self.raw)


def _raw(class_id: int, x1: int = 100) -> RawDetection:
    return RawDetection(class_id, 0.9, x1, 100, x1 + 40, 200)


@pytest.fixture
def backend(monkeypatch):
    fake = _RawBackend([])
    constructed: list[str] = []

    def detector(prop_type="bottle", **_):
        constructed.append(prop_type)
        return PropDetector(
            prop_type=prop_type,
            combined_detector=CombinedPropDetector(inference_backend=fake),
        )

    monkeypatch.setattr(websocket_api, "PropDetector", detector)
    monkeypatch.setattr(websocket_api, "BottleDetector", lambda **kw: detector("bottle", **kw))
    fake.constructed = constructed
    return fake


def _session(prop_type: str, mode: str = "custom_capture"):
    kwargs = {}
    if mode == "custom_assessment":
        kwargs["custom_movement_template"] = build_template(
            [_held_grip()], movement_behavior="static"
        ).to_dict()
    return websocket_api.VisionSession(
        "Custom Movement", session_mode=mode, prop_type=prop_type, **kwargs,
    )


def _frame():
    return np.zeros((480, 640, 3), dtype=np.uint8)


@pytest.mark.parametrize("mode", ("custom_capture", "custom_assessment"))
def test_shaker_session_uses_only_shaker_class(backend, mode):
    session = _session("shaker", mode)
    try:
        assert backend.constructed == ["shaker"]
        backend.raw = [_raw(BOTTLE)]
        bottle_only = session._detect_normalized_props(_frame())
        assert bottle_only.selected_detected is False
        assert bottle_only.primary == () and bottle_only.annotation == ()

        backend.raw = [_raw(SHAKER, x1=300)]
        shaker = session._detect_normalized_props(_frame())
        assert shaker.selected_detected is True
        assert [box.x1 for box in shaker.primary] == [300]
        assert [box.x1 for box in shaker.annotation] == [300]
    finally:
        session.close()


def test_shaker_capture_visibility_and_sample_follow_shaker_class(backend):
    session = _session("shaker")
    try:
        def observe(normalized):
            # Same observation the production readiness/capture path builds.
            session._observe_custom_capture_visibility(ReadinessObservation(
                has_camera_frame=True, bottles=list(normalized.bottles),
                shakers=list(normalized.shakers), hands=None, pose=None,
            ))
            return session._custom_capture_visible[0]

        backend.raw = [_raw(BOTTLE)]
        assert observe(session._detect_normalized_props(_frame())) is False

        backend.raw = [_raw(BOTTLE), _raw(SHAKER, x1=300)]
        normalized = session._detect_normalized_props(_frame())
        assert observe(normalized) is True
        session._custom_samples = []
        session._custom_capture_started_at = time.monotonic()
        session._record_custom_sample(
            captured=SimpleNamespace(captured_at_monotonic=time.monotonic()),
            frame=_frame(), normalized=normalized,
            hands=None, pose=None, yolo_attempted=True,
        )
        sample = session._custom_samples[0]
        assert sample.prop is not None
        assert sample.prop.x == pytest.approx(320 / 640)
        assert sample.prop_metadata["class"] == "shaker"
    finally:
        session.close()


def test_bottle_to_shaker_session_replacement_drops_bottle_tracks(backend):
    bottle = _session("bottle")
    backend.raw = [_raw(BOTTLE)]
    assert bottle._detect_normalized_props(_frame()).selected_detected is True
    bottle.close()

    shaker = _session("shaker")
    try:
        assert backend.constructed == ["bottle", "shaker"]
        # Same physical bottle still in view: it must not satisfy the shaker.
        normalized = shaker._detect_normalized_props(_frame())
        assert normalized.selected_detected is False
        assert shaker._last_live_bottles == []
        boxes, _ = shaker._presentation_boxes(
            captured_at=time.monotonic(), generation=0, run_yolo=True,
        )
        assert boxes == []
    finally:
        shaker.close()


def test_bottle_custom_session_still_uses_bottle_class(backend):
    session = _session("bottle", "custom_assessment")
    try:
        assert backend.constructed == ["bottle"]
        backend.raw = [_raw(SHAKER)]
        assert session._detect_normalized_props(_frame()).selected_detected is False
        backend.raw = [_raw(BOTTLE)]
        assert session._detect_normalized_props(_frame()).selected_detected is True
    finally:
        session.close()
