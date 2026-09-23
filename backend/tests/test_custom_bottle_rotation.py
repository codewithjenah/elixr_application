import math
import asyncio
import json

import pytest
import numpy as np
import cv2

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
from vision.bottle_marker_detector import BottleMarkerDetector
import vision.bottle_orientation_detector as orientation_detector_module
from vision.types import PropDetection
from api import websocket as websocket_api


_ORANGE = (0, 120, 255)  # BGR; OpenCV hue ~14
_YELLOW = (0, 255, 255)  # BGR; OpenCV hue 30


def _marked_frame(top=(160, 55), base=(160, 165), *, box=None):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    if top is not None:
        cv2.circle(frame, top, 8, _ORANGE, -1)
    if base is not None:
        cv2.circle(frame, base, 8, _YELLOW, -1)
    return frame, box or PropDetection(105, 35, 215, 185, 0.9, track_id=1)


@pytest.mark.parametrize(
    ("top", "base", "angle"),
    [
        ((160, 55), (160, 165), math.pi / 2),
        ((160, 165), (160, 55), -math.pi / 2),
        ((110, 110), (210, 110), 0),
        ((210, 110), (110, 110), math.pi),
        ((120, 65), (200, 145), math.pi / 4),
    ],
)
def test_color_markers_directed_at_any_projected_angle(top, base, angle):
    frame, box = _marked_frame(top, base)
    detector = BottleMarkerDetector()
    observed = detector.observe(frame, box)
    assert observed is not None
    assert math.cos(observed.angle_rad) == pytest.approx(math.cos(angle), abs=0.04)
    assert math.sin(observed.angle_rad) == pytest.approx(math.sin(angle), abs=0.04)
    assert 0.5 <= observed.confidence < 1.0
    assert detector.provider == "color_markers"
    assert detector.available


@pytest.mark.parametrize(("top", "base"), [(None, (160, 165)), ((160, 55), None), (None, None)])
def test_missing_marker_never_produces_orientation(top, base):
    frame, box = _marked_frame(top, base)
    assert BottleMarkerDetector().observe(frame, box) is None


def test_marker_evidence_must_be_inside_confirmed_bottle_roi():
    detector = BottleMarkerDetector()
    frame, box = _marked_frame((40, 55), (160, 165))
    assert detector.observe(frame, box) is None
    frame, box = _marked_frame()
    assert detector.observe(frame, box) is not None
    assert detector.observe(frame, PropDetection(105, 35, 215, 185, 0.1)) is None
    assert detector.observe(frame, PropDetection(105, 35, 215, 185, 0.9, yolo_confirmed=False)) is None


def test_noise_huge_area_low_saturation_and_ambiguity_are_rejected():
    detector = BottleMarkerDetector()
    frame, box = _marked_frame(top=None)
    frame[55, 160] = _ORANGE
    assert detector.observe(frame, box) is None
    frame, box = _marked_frame(top=None)
    frame[40:120, 110:205] = _ORANGE
    assert detector.observe(frame, box) is None
    frame, box = _marked_frame(top=None)
    cv2.circle(frame, (160, 55), 8, (150, 160, 170), -1)
    assert detector.observe(frame, box) is None
    frame, box = _marked_frame()
    cv2.circle(frame, (185, 55), 8, _ORANGE, -1)
    assert detector.observe(frame, box) is None


def test_hues_are_disjoint_and_edge_roi_clips():
    from config import MARKER_ORANGE_HUE, MARKER_YELLOW_HUE
    assert MARKER_ORANGE_HUE[1] < MARKER_YELLOW_HUE[0]
    frame, _ = _marked_frame((12, 15), (12, 75))
    assert BottleMarkerDetector().observe(
        frame, PropDetection(0, 0, 36, 90, 0.9)
    ) is not None


def test_marker_configuration_rejects_invalid_boundaries(monkeypatch):
    from config import _marker_hue_range, _marker_ratio
    monkeypatch.setenv("MARKER_TEST_HUE", "0,179")
    assert _marker_hue_range("MARKER_TEST_HUE", "5,18") == (0, 179)
    for invalid in ("-1,10", "10,180", "20,10", "5", "red,12"):
        monkeypatch.setenv("MARKER_TEST_HUE", invalid)
        with pytest.raises(ValueError):
            _marker_hue_range("MARKER_TEST_HUE", "5,18")
    for invalid in ("0", "1", "-0.01", "nan"):
        monkeypatch.setenv("MARKER_TEST_RATIO", invalid)
        with pytest.raises(ValueError):
            _marker_ratio("MARKER_TEST_RATIO", "0.004")


def test_marker_observations_build_and_assess_rotation_without_onnx(tmp_path):
    assert not validated_orientation_asset(tmp_path / "missing.onnx", tmp_path / "missing.json")
    detector = BottleMarkerDetector()
    samples = []
    box = PropDetection(105, 35, 215, 185, 0.9, track_id=1)
    for index in range(41):
        angle = math.pi / 2 + 2 * math.pi * index / 40
        top = (round(160 - 48 * math.cos(angle)), round(110 - 48 * math.sin(angle)))
        base = (round(160 + 48 * math.cos(angle)), round(110 + 48 * math.sin(angle)))
        frame, _ = _marked_frame(top, base, box=box)
        samples.append(FrameSample(
            timestamp_ms=index * 50,
            prop=Landmark(0.5, 0.5),
            prop_metadata={"track_id": 1},
            orientation=detector.observe(frame, box),
        ))
    assert all(sample.orientation is not None for sample in samples)
    template = build_template([tuple(samples)] * 3)
    assert template.feature_capabilities["prop_rotation"] is True
    assert compare_sequence(template, tuple(samples)).total > compare_sequence(template, _sequence(0)).total
    missing = tuple(FrameSample(
        timestamp_ms=sample.timestamp_ms, prop=sample.prop,
        prop_metadata=sample.prop_metadata, orientation=None,
    ) for sample in samples)
    assert FailureCode.INSUFFICIENT_ORIENTATION in validate_sequence(
        missing, ("prop_translation",), require_rotation=True
    ).codes
    assert build_template([missing] * 3).feature_capabilities["prop_rotation"] is False


def test_only_custom_bottle_sessions_enable_color_orientation(monkeypatch):
    monkeypatch.setattr(websocket_api, "BottleMarkerDetector", BottleMarkerDetector)
    capture = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    assert capture._orientation_enabled
    assert capture._orientation_detector.provider == "color_markers"
    official = websocket_api.VisionSession("Normal Grip")
    assert official._orientation_detector is None
    shaker = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture", prop_type="shaker"
    )
    assert shaker._orientation_detector is None


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


def test_aliased_frame_step_is_not_counted():
    samples = (
        FrameSample(timestamp_ms=0, prop=Landmark(0.5, 0.5), prop_metadata={"track_id": 1}, orientation=_observation(0)),
        FrameSample(timestamp_ms=50, prop=Landmark(0.5, 0.5), prop_metadata={"track_id": 1}, orientation=_observation(0.9 * math.pi)),
    )
    angles, total, _, pair_coverage = _observed_rotation(samples)
    assert angles == [0.0, None]
    assert total == 0.0
    assert pair_coverage == 0.0


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
