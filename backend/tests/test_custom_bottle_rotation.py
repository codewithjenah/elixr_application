import math
import asyncio
import json

import pytest
import numpy as np

from assessment.custom_movement.template_engine import (
    FailureCode,
    FrameSample,
    Landmark,
    MovementTemplate,
    _observed_rotation,
    build_template,
    compare_sequence,
    validate_sequence,
)
from vision.bottle_orientation import BottleKeypoint, BottleOrientation
from vision.bottle_orientation_detector import (
    BottleOrientationDetector, _parse_pose_rows, validated_orientation_asset,
)
import vision.bottle_orientation_detector as orientation_detector_module
from vision.types import PropDetection
from api import websocket as websocket_api


def _observation(angle: float, *, confidence: float = 0.95):
    top = BottleKeypoint(0.5 - 0.12 * math.cos(angle), 0.5 - 0.12 * math.sin(angle), confidence)
    base = BottleKeypoint(0.5 + 0.12 * math.cos(angle), 0.5 + 0.12 * math.sin(angle), confidence)
    return BottleOrientation.observed(top, base, confidence)


def _sequence(turns: float, *, gap=(), track_change=None, count=41):
    result = []
    for index in range(count):
        angle = turns * 2 * math.pi * index / (count - 1)
        result.append(FrameSample(
            timestamp_ms=index * 50,
            prop=Landmark(0.5, 0.4 - 0.1 * math.sin(math.pi * index / (count - 1))),
            prop_metadata={"track_id": 1 if track_change is None or index < track_change else 2},
            orientation=None if index in gap else _observation(angle),
        ))
    return tuple(result)


def test_directed_axis_requires_both_confident_keypoints():
    assert _observation(0).angle_rad == pytest.approx(0)
    assert _observation(math.pi / 2).angle_rad == pytest.approx(math.pi / 2)
    assert _observation(0, confidence=0.49) is None
    diagonal = BottleOrientation.observed(
        BottleKeypoint(0.4, 0.4, 0.9),
        BottleKeypoint(0.4 + 0.1 * 3 / 4, 0.5, 0.9),
        0.9,
        image_aspect_ratio=4 / 3,
    )
    assert diagonal.angle_rad == pytest.approx(math.pi / 4)


def test_wrap_direction_and_turn_counts():
    one = _observed_rotation(_sequence(1))[1]
    two = _observed_rotation(_sequence(2))[1]
    reverse = _observed_rotation(_sequence(-1))[1]
    assert one == pytest.approx(2 * math.pi, abs=0.01)
    assert two == pytest.approx(4 * math.pi, abs=0.01)
    assert reverse == pytest.approx(-2 * math.pi, abs=0.01)


def test_gaps_and_track_changes_do_not_invent_turns():
    brief = _sequence(1, gap=(20,))
    long = _sequence(1, gap=range(15, 26))
    changed = _sequence(1, track_change=20)
    assert _observed_rotation(brief)[1] < 2 * math.pi
    assert _observed_rotation(brief)[3] < 1
    assert _observed_rotation(changed)[1] < 2 * math.pi
    assert build_template([changed] * 3).feature_capabilities["prop_rotation"] is False
    assert FailureCode.TRACK_LOSS in validate_sequence(changed, ("prop_translation",), require_rotation=True).codes
    assert not validate_sequence(long, ("prop_translation",), require_rotation=True).valid
    assert FailureCode.INSUFFICIENT_ORIENTATION in validate_sequence(long, ("prop_translation",), require_rotation=True).codes


def test_three_references_learn_rotation_and_score_a_plain_toss_lower():
    references = [_sequence(1) for _ in range(3)]
    template = build_template(references)
    assert template.schema_version == 2
    assert template.feature_capabilities["prop_rotation"] is True
    assert MovementTemplate.from_dict(template.to_dict()).to_dict() == template.to_dict()
    genuine = compare_sequence(template, _sequence(1))
    plain = compare_sequence(template, _sequence(0))
    multi = compare_sequence(template, _sequence(2))
    opposite = compare_sequence(template, _sequence(-1))
    assert genuine.total > plain.total + 2
    assert genuine.total > multi.total + 2
    assert genuine.total > opposite.total + 2


def test_translation_and_inconsistent_rotation_do_not_claim_capability():
    translation = build_template([_sequence(0)] * 3)
    inconsistent = build_template([_sequence(1), _sequence(-1), _sequence(2)])
    assert translation.schema_version == 1
    assert translation.feature_capabilities["prop_rotation"] is False
    assert MovementTemplate.from_dict(translation.to_dict()).schema_version == 1
    assert inconsistent.feature_capabilities["prop_rotation"] is False


def test_missing_weights_never_enable_runtime(tmp_path):
    assert not validated_orientation_asset(tmp_path / "candidate.onnx", tmp_path / "validated.json")


def test_pose_output_uses_keypoints_and_requires_prop_association():
    # One-class Ultralytics pose output: xywh, class confidence, top xyz, base xyz.
    raw = np.array([[[320], [240], [100], [140], [0.95],
                     [320], [180], [0.9], [320], [300], [0.9]]], dtype=np.float32)
    matching = PropDetection(265, 165, 375, 315, 0.9)
    unrelated = PropDetection(20, 20, 80, 80, 0.9)
    observed = _parse_pose_rows(raw, letterboxed_hw=(480, 640), frame_hw=(480, 640), prop=matching)
    assert observed is not None
    assert observed.angle_rad == pytest.approx(math.pi / 2)
    assert _parse_pose_rows(raw, letterboxed_hw=(480, 640), frame_hw=(480, 640), prop=unrelated) is None
    oversized = raw.copy()
    oversized[0, 2, 0] = 500
    oversized[0, 3, 0] = 400
    assert _parse_pose_rows(oversized, letterboxed_hw=(480, 640), frame_hw=(480, 640), prop=matching) is None


def test_directml_orientation_inference_falls_back_to_cpu(monkeypatch, tmp_path):
    raw = np.array([[[320], [240], [100], [140], [0.95],
                     [320], [180], [0.9], [320], [300], [0.9]]], dtype=np.float32)
    providers_seen = []

    class FakeSession:
        def __init__(self, provider):
            self.provider = provider

        def get_inputs(self):
            return [type("Input", (), {"name": "images", "shape": [1, 3, 480, 640]})()]

        def get_outputs(self):
            return [type("Output", (), {"name": "output0"})()]

        def get_modelmeta(self):
            return type("Metadata", (), {"custom_metadata_map": {
                "task": "pose", "kpt_shape": "[2, 3]", "names": "{0: 'bottle'}",
            }})()

        def get_providers(self):
            return [self.provider]

        def run(self, names, inputs):
            if self.provider == "DmlExecutionProvider":
                raise RuntimeError("synthetic DML failure")
            return [raw]

    def factory(path, options, providers):
        selected = providers[0]
        provider = selected[0] if isinstance(selected, tuple) else selected
        providers_seen.append(provider)
        return FakeSession(provider)

    monkeypatch.setattr(orientation_detector_module, "validated_orientation_asset", lambda *args: True)
    monkeypatch.setattr(orientation_detector_module, "dml_is_available", lambda: True)
    detector = BottleOrientationDetector(
        onnx_path=tmp_path / "unused.onnx", manifest_path=tmp_path / "unused.json",
        session_factory=factory,
    )
    result = detector.observe(np.zeros((480, 640, 3), dtype=np.uint8), PropDetection(265, 165, 375, 315, 0.9))
    assert result is not None
    assert providers_seen == ["DmlExecutionProvider", "CPUExecutionProvider"]
    assert detector.provider == "CPUExecutionProvider"
    detector.close()


@pytest.mark.parametrize("code", ["orientation_model_unavailable", "invalid_schema"])
def test_custom_template_prepare_returns_specific_error(monkeypatch, code):
    def fail_session(*args, **kwargs):
        raise ValueError(code)

    monkeypatch.setattr(websocket_api, "VisionSession", fail_session)
    messages = []

    async def send(payload):
        messages.append(json.loads(payload))

    gate = {}
    asyncio.run(websocket_api._cv_session_loop(
        None, "Custom Movement", session_mode="custom_assessment",
        session_id="test", prepare_gate=gate, send_text=send,
    ))
    assert gate["error_code"] == code
    assert messages[0]["error_code"] == code
