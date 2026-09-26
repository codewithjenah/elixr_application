import time
import uuid
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from assessment.custom_movement import FrameSample, Landmark, build_template
from assessment.custom_movement.completion import (
    MOVEMENT_COMPLETED,
    MOVEMENT_DETECTED,
    WAITING_FOR_MOVEMENT,
    evaluate_completion,
    find_movement_start_index,
)
from assessment.custom_movement.template_engine import validate_assessment_sequence
from assessment.readiness import ReadinessObservation
from api import websocket as websocket_api
from schemas.feedback import FeedbackMessage
from config import YOLO_FRAME_SKIP
from vision.camera import CapturedFrame
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection
from vision.hands_detector import HandsDetector
from test_session_lifecycle import StubHandsDetector, _patch_vision


@pytest.fixture(autouse=True)
def _reference_video_double(monkeypatch, tmp_path):
    class FakeRecorder:
        def __init__(self, **kwargs):
            self.started = time.monotonic()
            self.path = tmp_path / f"reference_{uuid.uuid4().hex}.mp4"

        def start(self):
            pass

        def stop(self):
            self.path.write_bytes(b"test video")
            started = self.started
            return SimpleNamespace(
                local_path=str(self.path),
                frame_capture_times=tuple(started + index * .1 for index in range(20)),
                fps=10.0,
                video_ms_for_capture=lambda observed: max(0, round((observed - started) * 1000)),
            )

        def cancel(self):
            self.path.unlink(missing_ok=True)

    monkeypatch.setattr(websocket_api, "SubmissionRecorder", FakeRecorder)


def _set_samples(session, samples):
    session._custom_samples = list(samples)
    started = session._custom_video_recorder.started
    session._custom_sample_capture_times = [started + index * .1 for index in range(len(samples))]


def _visible(session):
    session._custom_capture_visible = (True, True, True)
    session._custom_capture_observed_at = time.monotonic()


@pytest.mark.parametrize("raw_label,semantic", (("Left", "right"), ("Right", "left")))
def test_raw_mediapipe_handedness_is_shared_by_authoring_and_assessment(raw_label, semantic):
    raw = SimpleNamespace(
        hand_landmarks=[[SimpleNamespace(x=.3, y=.4)]],
        handedness=[[SimpleNamespace(category_name=raw_label)]],
    )
    hands = HandsDetector._to_hands_result(raw)
    assert hands.hands[0].handedness.lower() == semantic
    for mode in ("custom_capture", "custom_assessment"):
        session = websocket_api.VisionSession(
            "Custom Movement", session_mode=mode,
            custom_movement_template=(
                build_template([_reference(), _reference()]).to_dict()
                if mode == "custom_assessment" else None
            ),
        )
        session._custom_samples = []
        session._custom_capture_started_at = 10.0
        captured = SimpleNamespace(captured_at_monotonic=10.1)
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        normalized = SimpleNamespace(primary=[])
        session._record_custom_sample(
            captured=captured, frame=frame, normalized=normalized,
            hands=hands, pose=None, yolo_attempted=True,
        )
        assert any(key.startswith(f"{semantic}:") for key in session._custom_samples[0].hands)


@pytest.mark.parametrize("visible,accepted", (
    ((False, True, True), False),
    ((True, False, True), False),
    ((True, True, False), False),
    ((True, True, True), True),
))
def test_capture_start_requires_current_prop_hand_and_upper_body(visible, accepted):
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    session._custom_person_count = 1
    session._custom_person_observed_at = time.monotonic()
    session._custom_capture_visible = visible
    session._custom_capture_observed_at = time.monotonic()
    result = session.start_custom_capture(duration_seconds=15)
    assert result[0] is accepted
    if accepted:
        session._custom_video_recorder.cancel()


def test_custom_visibility_accepts_one_real_hand_and_rejects_missing_inputs():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    prop = PropDetection(x1=10, y1=10, x2=20, y2=30, confidence=.9)
    pose = PoseLandmarks(
        points={index: Point2D(.4, .3) for index in (11, 12, 13, 15)},
        visibility={index: .9 for index in (11, 12, 13, 15)},
    )
    hands = HandsResult(hands=[HandLandmarks(
        points={0: Point2D(.3, .4), 9: Point2D(.3, .35)},
        handedness="Left",
    )])
    session._observe_custom_capture_visibility(ReadinessObservation(
        has_camera_frame=True, bottles=[prop], hands=hands, pose=pose,
    ))
    assert session._custom_capture_visible == (True, True, True)
    session._observe_custom_capture_visibility(ReadinessObservation(
        has_camera_frame=True, bottles=[prop], hands=None, pose=pose,
    ))
    assert session._custom_capture_visible == (True, False, True)
    session._observe_custom_capture_visibility(ReadinessObservation(
        has_camera_frame=True, bottles=[prop], hands=hands, pose=None,
    ))
    assert session._custom_capture_visible == (True, True, False)


def _accepted_reference(session):
    session._custom_person_count = 1
    session._custom_person_observed_at = time.monotonic()
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())
    accepted, code, quality = session.stop_custom_capture()
    assert (accepted, code) == (True, None)
    return quality


def test_reference_drafts_have_stable_ids_and_delete_only_selected_clip():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    first, middle, last = [_accepted_reference(session) for _ in range(3)]
    assert len({first["reference_id"], middle["reference_id"], last["reference_id"]}) == 3
    assert all(Path(item["local_file_path"]).exists() for item in (first, middle, last))
    assert session.delete_custom_reference(middle["reference_id"]) == 2
    assert not Path(middle["local_file_path"]).exists()
    assert Path(first["local_file_path"]).exists()
    assert Path(last["local_file_path"]).exists()
    assert session.build_custom_template()["reference_count"] == 2
    assert session.delete_custom_reference(first["reference_id"]) == 1
    with pytest.raises(ValueError, match="invalid_reference_count"):
        session.build_custom_template()
    session.close()
    assert not Path(last["local_file_path"]).exists()


def test_reference_trim_rebases_samples_and_invalid_edit_preserves_prior_trim():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    first = _accepted_reference(session)
    draft = session._custom_references[0]
    assert draft.samples[0].timestamp_ms == 0
    assert draft.samples[-1].timestamp_ms == 900
    result = session.trim_custom_reference(first["reference_id"], 100, 800)
    assert result["trim_start_ms"] == 100
    assert [sample.timestamp_ms for sample in draft.effective_samples()] == list(range(0, 800, 100))
    with pytest.raises(ValueError, match="invalid_trim_range"):
        session.trim_custom_reference(first["reference_id"], 100, 150)
    assert (draft.trim_start_ms, draft.trim_end_ms) == (100, 800)
    session.trim_custom_reference(first["reference_id"], 0, draft.video_duration_ms)
    assert draft.effective_samples() == draft.samples
    session.close()


def _reference(*, sides=("left",), moving_pose=False):
    frames = []
    for index in range(10):
        pose = {
            "11": Landmark(0.3, 0.3),
            "12": Landmark(0.7, 0.3),
            "15": Landmark(0.35 + (0.02 * index if moving_pose else 0.0), 0.5),
        }
        frames.append(
            FrameSample(
                timestamp_ms=index * 100,
                pose=pose,
                hands={
                    side: Landmark(0.25 if side == "left" else 0.75, 0.45)
                    for side in sides
                },
                prop=Landmark(0.2 + 0.03 * index, 0.4),
            )
        )
    return tuple(frames)


def _template(*, sides=("left",), moving_pose=False):
    return build_template(
        [_reference(sides=sides, moving_pose=moving_pose) for _ in range(3)]
    )


def test_custom_assessment_completion_detects_a_fast_full_sequence():
    template = _template()

    assert evaluate_completion(template, _reference()) == MOVEMENT_COMPLETED


def test_custom_assessment_completion_allows_a_slow_full_sequence():
    template = _template()
    slow = tuple(
        replace(frame, timestamp_ms=frame.timestamp_ms * 4)
        for frame in _reference()
    )

    assert evaluate_completion(template, slow) == MOVEMENT_COMPLETED


def test_custom_assessment_completion_rejects_stationary_and_final_pose_only():
    template = _template()
    reference = _reference()
    stationary_prop = tuple(
        replace(frame, prop=reference[0].prop) for frame in reference
    )
    final_pose = reference[-1]
    final_pose_only = tuple(
        replace(
            frame,
            pose=final_pose.pose,
            hands=final_pose.hands,
            prop=final_pose.prop,
        )
        for frame in reference
    )

    assert evaluate_completion(template, stationary_prop) == WAITING_FOR_MOVEMENT
    assert evaluate_completion(template, final_pose_only) == WAITING_FOR_MOVEMENT


def _grip_reference(*, reverse=False):
    frames = []
    for index in range(20):
        in_hold = index >= 8
        grip_y = 0.58 if reverse else 0.43
        hand_y = grip_y if in_hold else 0.68
        frames.append(FrameSample(
            timestamp_ms=index * 100,
            pose={"11": Landmark(0.3, 0.3), "12": Landmark(0.7, 0.3),
                  "13": Landmark(0.35, 0.43), "15": Landmark(0.36, hand_y)},
            hands={
                "left:0": Landmark(0.36, hand_y),
                "left:9": Landmark(0.38, hand_y - 0.04),
                "left:8": Landmark(0.41 if reverse else 0.34, hand_y - 0.07),
                "left:4": Landmark(0.32 if reverse else 0.41, hand_y - 0.02),
            },
            prop=Landmark(0.38, grip_y if in_hold else 0.68),
        ))
    return tuple(frames)


@pytest.mark.parametrize("reverse", (False, True))
def test_static_grip_completes_after_stable_hold_without_movement(reverse):
    reference = _grip_reference(reverse=reverse)
    template = build_template([reference, reference], movement_behavior="static")
    assert template.movement_behavior == "static"
    assert template.schema_version == 3
    assert websocket_api.CustomMovementTemplate.from_dict(template.to_dict()) == template
    hold = tuple(replace(frame, timestamp_ms=index * 100)
                 for index, frame in enumerate(reference[8:]))
    assert evaluate_completion(template, hold[:8]) != MOVEMENT_COMPLETED
    assert evaluate_completion(template, hold) == MOVEMENT_COMPLETED


def test_static_grip_rejects_wrong_grip_and_missing_required_landmarks():
    reference = _grip_reference()
    template = build_template([reference, reference], movement_behavior="static")
    reverse = _grip_reference(reverse=True)
    wrong = tuple(replace(frame, timestamp_ms=index * 100)
                  for index, frame in enumerate(reverse[8:]))
    hand_only_wrong = tuple(replace(
        frame,
        hands={
            **frame.hands,
            "left:8": Landmark(0.41, frame.hands["left:8"].y),
            "left:4": Landmark(0.32, frame.hands["left:4"].y),
        },
    ) for frame in reference[8:])
    missing = tuple(replace(frame, hands={}) for frame in reference[8:])
    assert evaluate_completion(template, wrong) != MOVEMENT_COMPLETED
    assert evaluate_completion(template, hand_only_wrong) != MOVEMENT_COMPLETED
    assert evaluate_completion(template, missing) != MOVEMENT_COMPLETED


def test_static_assessment_scores_only_completed_hold_after_neutral_entry():
    reference = _grip_reference()
    template = build_template([reference, reference], movement_behavior="static")
    session = websocket_api.VisionSession(
        "Normal Grip", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(reference)
    session._custom_assessment_progress = MOVEMENT_COMPLETED
    result = session.finish_custom_assessment()
    assert result["total"] >= 7
    assert result["assessment_outcome"] == "competent"
    assert result["sequence_duration_ms"] == 900
    session.close()


def test_static_hold_completes_at_thirty_fps_without_timestamp_alignment():
    final = _grip_reference()[-1]
    hold = tuple(replace(final, timestamp_ms=index * 33) for index in range(40))
    template = build_template([hold, hold], movement_behavior="static")
    assert evaluate_completion(template, hold[:24]) != MOVEMENT_COMPLETED
    assert evaluate_completion(template, hold) == MOVEMENT_COMPLETED


def test_static_references_reject_unstable_or_inconsistent_endings():
    normal = _grip_reference()
    reverse = _grip_reference(reverse=True)
    with pytest.raises(ValueError, match="inconsistent_static_references"):
        build_template([normal, reverse], movement_behavior="static")
    unstable = tuple(
        replace(frame, prop=Landmark(0.38 + 0.12 * (index % 2), frame.prop.y))
        if index >= 11 else frame
        for index, frame in enumerate(normal)
    )
    with pytest.raises(ValueError, match="unstable_static_reference"):
        build_template([normal, unstable], movement_behavior="static")


def test_custom_assessment_completion_waits_for_the_rest_of_a_partial_sequence():
    template = _template()
    reference = _reference()
    partial = tuple(reference[:4]) + tuple(
        replace(reference[3], timestamp_ms=index * 100)
        for index in range(4, 8)
    )

    assert evaluate_completion(template, partial) == MOVEMENT_DETECTED


def test_custom_assessment_uses_observed_motion_quorum_for_noisy_pose():
    template = _template(moving_pose=True)
    reference = _reference(moving_pose=True)
    prop_only = tuple(replace(frame, pose=reference[0].pose) for frame in reference)

    assert evaluate_completion(template, prop_only) == MOVEMENT_COMPLETED


def test_dynamic_completion_rejects_reverse_trajectory_and_near_final_partial():
    template = _template()
    reference = _reference()
    reverse = tuple(replace(frame, prop=reference[-1 - index].prop)
                    for index, frame in enumerate(reference))
    near_final = reference[:8]
    assert evaluate_completion(template, reverse) == MOVEMENT_DETECTED
    assert evaluate_completion(template, near_final) == MOVEMENT_DETECTED


def test_dynamic_completion_tolerates_fast_execution_and_short_detector_losses():
    template = _template(moving_pose=True)
    reference = _reference(moving_pose=True)
    fast = tuple(replace(frame, timestamp_ms=index * 55)
                 for index, frame in enumerate(reference))
    assert evaluate_completion(template, fast) == MOVEMENT_COMPLETED
    for modality in ("pose", "hands", "prop"):
        dropped = tuple(replace(frame, **{modality: {} if modality != "prop" else None})
                        if index == 5 else frame
                        for index, frame in enumerate(reference))
        assert evaluate_completion(template, dropped) == MOVEMENT_COMPLETED
    isolated = tuple(replace(frame, prop=None) if index in {2, 6} else frame
                     for index, frame in enumerate(reference))
    assert evaluate_completion(template, isolated) == MOVEMENT_COMPLETED


def test_assessment_capture_stop_uses_live_observability_policy():
    template = _template()
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = [
        replace(frame, timestamp_ms=index * 50, prop=None if index in {3, 4, 5} else frame.prop)
        for index, frame in enumerate(_reference())
    ]
    accepted, code, quality = session.stop_custom_capture()
    assert (accepted, code) == (True, None)
    assert quality["valid"] is True
    session.close()


def test_unobserved_lead_in_does_not_poison_a_fully_observed_attempt():
    template = _template()
    lead_in = tuple(FrameSample(index * 100, hands={"left": Landmark(.25, .45)})
                    for index in range(8))
    full = tuple(replace(frame, timestamp_ms=frame.timestamp_ms + 800)
                 for frame in _reference())
    samples = lead_in + full
    assert evaluate_completion(template, samples) == MOVEMENT_COMPLETED
    start = find_movement_start_index(template, samples)
    assert start is not None and start >= len(lead_in)
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(samples)
    session._custom_assessment_progress = MOVEMENT_COMPLETED
    session._custom_assessment_movement_start_index = start
    assert session.stop_custom_capture()[:2] == (True, None)
    assert session.finish_custom_assessment()["total"] >= 7
    session.close()


@pytest.mark.parametrize("modality", ("prop", "hands", "pose"))
def test_dynamic_prolonged_required_detector_loss_is_unassessable(modality):
    template = _template(moving_pose=True)
    reference = _reference(moving_pose=True)
    lost = tuple(replace(frame, **{modality: {} if modality != "prop" else None})
                 if 3 <= index <= 7 else frame
                 for index, frame in enumerate(reference))
    assert evaluate_completion(template, lost) != MOVEMENT_COMPLETED
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(lost)
    session._custom_assessment_progress = MOVEMENT_DETECTED
    with pytest.raises(ValueError, match="missing_modality|track_loss"):
        session.finish_custom_assessment()
    session.close()


def test_required_pose_cannot_be_replaced_by_unrelated_visible_landmark():
    template = _template(moving_pose=True)
    sparse = tuple(replace(frame, pose={"11": frame.pose["11"]})
                   for frame in _reference(moving_pose=True))
    validation = validate_assessment_sequence(
        sparse, template.required_modalities,
        required_hand_sides=template.required_hand_sides, template=template,
    )
    assert any(code.value == "missing_modality" for code in validation.codes)
    assert evaluate_completion(template, sparse) != MOVEMENT_COMPLETED

    grip = _grip_reference()
    static_template = build_template([grip, grip], movement_behavior="static")
    partial_hand = tuple(replace(frame, hands={"left:0": frame.hands["left:0"]})
                         for frame in grip[8:])
    hand_validation = validate_assessment_sequence(
        partial_hand, static_template.required_modalities,
        required_hand_sides=static_template.required_hand_sides,
        template=static_template,
    )
    assert any(code.value == "missing_modality" for code in hand_validation.codes)


def test_full_low_quality_sequence_completes_and_scores_needs_improvement():
    template = _template()
    jittered_slow = tuple(replace(
        frame,
        timestamp_ms=frame.timestamp_ms * 4,
        prop=Landmark(frame.prop.x + (.08 if index % 2 else -.08), frame.prop.y),
    ) for index, frame in enumerate(_reference()))
    assert evaluate_completion(template, jittered_slow) == MOVEMENT_COMPLETED
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(jittered_slow)
    session._custom_assessment_progress = MOVEMENT_COMPLETED
    assert session.stop_custom_capture()[:2] == (True, None)
    result = session.finish_custom_assessment()
    assert result["total"] < 7
    assert result["assessment_outcome"] == "needs_improvement"
    assert result["score_percent"] == round(result["total"] * 100 / 12, 1)
    session.close()


def test_static_hold_tolerates_isolated_jitter_but_not_sustained_drift():
    final = _grip_reference()[-1]
    hold = tuple(replace(final, timestamp_ms=index * 33) for index in range(40))
    template = build_template([hold, hold], movement_behavior="static")
    def with_noise(indices):
        return tuple(replace(frame, prop=Landmark(frame.prop.x + .2, frame.prop.y))
                     if index in indices else frame
                     for index, frame in enumerate(hold))
    one_noisy = with_noise({19})
    noisy = with_noise({10, 19})
    too_many = with_noise({12, 15, 18, 21, 24})
    drift = tuple(replace(frame, prop=Landmark(frame.prop.x + .2, frame.prop.y))
                  if index >= 32 else frame
                  for index, frame in enumerate(hold))
    assert evaluate_completion(template, one_noisy) == MOVEMENT_COMPLETED
    assert evaluate_completion(template, noisy) == MOVEMENT_COMPLETED
    assert evaluate_completion(template, too_many) != MOVEMENT_COMPLETED
    assert evaluate_completion(template, drift) != MOVEMENT_COMPLETED


def test_completed_static_hold_stays_terminal_until_stop():
    reference = _grip_reference()
    template = build_template([reference, reference], movement_behavior="static")
    session = websocket_api.VisionSession(
        "Normal Grip", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(reference[8:])
    session._custom_capture_started_at = time.monotonic() - 1
    session._custom_assessment_progress = MOVEMENT_COMPLETED
    prior_count = len(session._custom_samples)
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    session._record_custom_sample(
        captured=SimpleNamespace(captured_at_monotonic=time.monotonic()),
        frame=frame, normalized=SimpleNamespace(primary=[]),
        hands=None, pose=None, yolo_attempted=True,
    )
    assert session._custom_assessment_progress == MOVEMENT_COMPLETED
    assert len(session._custom_samples) == prior_count
    session.close()


def test_custom_feedback_schema_accepts_static_progress_and_optional_cues():
    base = dict(
        bottle_detected=True, movement="Custom Movement", feedback="Hold steady",
        feedback_type="positive", posture_status="unknown",
    )
    legacy = FeedbackMessage(**base)
    assert legacy.custom_assessment_cue is None
    message = FeedbackMessage(
        **base, custom_assessment_progress="position_detected",
        custom_assessment_cue="hold_steady", custom_assessment_cue_sequence=2,
    )
    assert message.model_dump()["custom_assessment_progress"] == "position_detected"
    assert message.model_dump()["custom_assessment_cue_sequence"] == 2


def test_custom_cue_sequence_deduplicates_and_resets_per_attempt():
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=_template().to_dict(),
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    session._set_custom_assessment_cue("release")
    session._set_custom_assessment_cue("release")
    assert session._custom_assessment_cue_sequence == 1
    session._set_custom_assessment_cue("airborne")
    assert session._custom_assessment_cue_sequence == 2
    session._custom_samples = None
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    assert session._custom_assessment_cue is None
    assert session._custom_assessment_cue_sequence == 0
    session.close()


def test_current_confirmed_frames_emit_ordered_release_cues_once():
    path = ((0, 0), (0, 0), (.4, -.04), (.6, -.10),
            (.4, -.04), (0, 0), (0, 0), (0, 0))
    reference = tuple(FrameSample(
        index * 100, hands={"left": Landmark(0, 0)}, prop=Landmark(x, y),
    ) for index, (x, y) in enumerate(path))
    template = build_template(
        [reference, reference], ("hands", "prop_translation")
    )
    assert template.feature_capabilities["release_catch"] is True
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = []
    session._custom_capture_started_at = time.monotonic() - 1
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    hands = HandsResult(hands=[HandLandmarks(
        points={0: Point2D(0, 0)}, handedness="left",
    )])
    cues = []
    for index, (x, y) in enumerate(path):
        detection = PropDetection(
            x1=x * 100 - 2, y1=y * 100 - 2,
            x2=x * 100 + 2, y2=y * 100 + 2, confidence=.95,
            yolo_confirmed=True,
        )
        session._record_custom_sample(
            captured=SimpleNamespace(
                captured_at_monotonic=session._custom_capture_started_at + index * .1,
            ),
            frame=frame,
            normalized=session._normalize_detections(bottles=[detection], shakers=[]),
            hands=hands, pose=None, yolo_attempted=True,
        )
        if session._custom_assessment_cue_sequence > len(cues):
            cues.append(session._custom_assessment_cue)
    assert cues[:4] == ["release", "airborne", "apex", "catch"]
    assert len(cues) == len(set(cues))
    session.close()


def test_custom_assessment_preserves_short_release_catch_events_in_long_capture():
    reference = tuple(
        FrameSample(
            timestamp_ms=index * 100,
            pose={"11": Landmark(0.3, 0.3), "12": Landmark(0.7, 0.3)},
            hands={"left": Landmark(0.0, 0.0)},
            prop=Landmark(x, y),
        )
        for index, (x, y) in enumerate(
            (
                (0.0, 0.0),
                (0.0, 0.0),
                (0.4, -0.04),
                (0.6, -0.10),
                (0.4, -0.04),
                (0.0, 0.0),
                (0.0, 0.0),
                (0.0, 0.0),
            )
        )
    )
    template = build_template(
        [reference, reference, reference],
        ("pose", "hands", "prop_translation"),
    )
    tail = tuple(
        replace(
            reference[-1],
            timestamp_ms=reference[-1].timestamp_ms + index * 100,
        )
        for index in range(1, 294)
    )

    assert template.feature_capabilities["release_catch"] is True
    assert evaluate_completion(template, reference + tail) == MOVEMENT_COMPLETED
    missed_apex = tuple(replace(frame, prop=None) if index == 3 else frame
                        for index, frame in enumerate(reference))
    assert "airborne" not in {
        event.kind for event in websocket_api.detect_prop_events(missed_apex)
    }
    assert evaluate_completion(template, missed_apex) == MOVEMENT_COMPLETED


@pytest.mark.parametrize(
    ("progress", "error_code"),
    (
        (WAITING_FOR_MOVEMENT, "custom_movement_not_detected"),
        (MOVEMENT_DETECTED, "custom_assessment_incomplete"),
    ),
)
def test_custom_assessment_cannot_score_before_completion(progress, error_code):
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_assessment",
        custom_movement_template=_template().to_dict(),
    )
    session._custom_samples = list(_reference())
    session._custom_assessment_progress = progress

    with pytest.raises(ValueError, match=error_code):
        session.finish_custom_assessment()

    session.close()


def test_low_control_assessment_feedback_coaches_smooth_prop_motion():
    template = _template()
    jittered = tuple(
        replace(
            frame,
            prop=Landmark(
                frame.prop.x + (0.08 if index % 2 == 0 else -0.08),
                frame.prop.y,
            ),
        )
        for index, frame in enumerate(_reference())
    )
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(jittered)
    session._custom_assessment_progress = websocket_api.CUSTOM_ASSESSMENT_COMPLETED

    result = session.finish_custom_assessment()

    assert result["component_scores"]["Control/stability"] <= 1
    assert (
        "Keep the prop movement steady and smooth through each transition."
        in result["feedback"]
    )
    session.close()


def test_rejected_short_capture_clears_backend_capture_state():
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture"
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    session._custom_person_count = 1
    session._custom_person_observed_at = time.monotonic()
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    assert session._custom_samples is not None

    accepted, code, _ = session.stop_custom_capture()

    assert accepted is False
    assert code == "custom_capture_not_recording"
    assert session._custom_samples is None
    assert session._custom_capture_deadline is None
    session.close()


def _performer_pose(center_x=0.5, *, hips_only=False):
    left, right = (23, 24) if hips_only else (11, 12)
    return SimpleNamespace(
        points={
            left: SimpleNamespace(x=center_x - 0.1, y=0.6 if hips_only else 0.3),
            right: SimpleNamespace(x=center_x + 0.1, y=0.6 if hips_only else 0.3),
        },
        visibility={left: 0.9, right: 0.9},
    )


def test_custom_capture_requires_one_hand_and_upper_body():
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_capture",
        readiness_spec={"hands": "two_hands", "body": "upper_body"},
    )

    assert session.readiness_spec == {"hands": "one_hand", "body": "upper_body"}
    assert session._hands_needed is True
    assert session._pose_needed is True
    assert session._hands_max == 2
    assert session._yolo_frame_skip == 1


def test_custom_capture_requests_two_poses_only_for_reference_session(monkeypatch):
    constructed = []
    hands_constructed = []

    class FakePose:
        def __init__(self, **kwargs):
            constructed.append(kwargs)

        def close(self):
            pass

    class FakeHands:
        def __init__(self, **kwargs):
            hands_constructed.append(kwargs)

        def close(self):
            pass

    monkeypatch.setattr(websocket_api, "PoseDetector", FakePose)
    monkeypatch.setattr(websocket_api, "HandsDetector", FakeHands)
    capture = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    capture._ensure_readiness_detectors()
    assert constructed == [{"max_poses": 2}]
    assert len(hands_constructed) == 1
    assert hands_constructed[0]["max_num_hands"] == 2
    readiness_hands = capture.hands_detector
    capture._ensure_detectors()
    assert constructed == [{"max_poses": 2}]
    assert len(hands_constructed) == 1
    assert capture.hands_detector is readiness_hands
    ordinary = websocket_api.VisionSession("Hand Stall")
    ordinary._sync_landmark_detectors(needs_hands=False, needs_pose=True)
    assert constructed[-1] == {}


def test_custom_readiness_requires_hands_and_pose(monkeypatch):
    _patch_vision(monkeypatch)

    class VisibleHands(StubHandsDetector):
        def detect(self, frame, bottle=None):
            self.detect_calls += 1
            return HandsResult(hands=[HandLandmarks(
                points={0: Point2D(.2, .3)}, handedness="Left",
            )])

    monkeypatch.setattr(websocket_api, "HandsDetector", VisibleHands)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    try:
        assert session.readiness_spec == {"hands": "one_hand", "body": "upper_body"}
        assert session.start()
        assert session.begin_readiness()
        assert session._readiness_tracker._profile.needs_hands() is True
        detector = session.hands_detector
        assert isinstance(detector, VisibleHands)
        assert detector.max_num_hands == 2
        assert session.process_readiness_frame() is not None
        assert detector.detect_calls >= 1
        assert session._overlay_snapshot is not None
        assert session._overlay_snapshot.hands is not None
        assert session._preview_presentation_metadata(session._overlay_snapshot)[
            "hands_presentation_state"
        ] == "tracking"
        # The confirmation test supplies a stable snapshot after verifying the
        # custom profile; live visibility is checked again when recording.
        # later leave the frame. Activation keeps the warmed detector instance.
        session._latest_readiness_snapshot = SimpleNamespace(readiness_stable=True)
        session._latest_readiness_observed_at = time.monotonic()
        session._custom_person_count = 1
        session._custom_person_observed_at = time.monotonic()
        _visible(session)
        assert session.confirm_readiness() == (True, None)
        assert session.activate() == (True, None)
        assert session.hands_detector is detector
    finally:
        session.close()


def test_active_custom_samples_use_current_hands_for_coverage(monkeypatch):
    _patch_vision(monkeypatch)

    class VisibleHands(StubHandsDetector):
        def detect_independent(self, frame, *, captured_at_monotonic=None):
            self.detect_calls += 1
            return HandsResult(hands=[
                HandLandmarks(points={0: Point2D(.2, .3)}, handedness="Left"),
                HandLandmarks(points={0: Point2D(.8, .3)}, handedness="Right"),
            ])

        def finish_with_prop(self, frame, independent, bottle):
            return independent

    monkeypatch.setattr(websocket_api, "HandsDetector", VisibleHands)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    try:
        assert session.start()
        assert session.activate() == (True, None)
        session._custom_samples = []
        session._custom_capture_started_at = 1000.0
        session._custom_capture_deadline = None
        session._custom_person_count = 1
        monkeypatch.setattr(session, "_observe_custom_people", lambda *a, **k: None)
        assert session.process_frame() is not None
        assert session.hands_detector.detect_calls >= 1
        assert session._custom_samples
        assert any(key.startswith("left:") for key in session._custom_samples[0].hands)
        assert any(key.startswith("right:") for key in session._custom_samples[0].hands)
        quality = session._custom_capture_diagnostics(tuple(session._custom_samples))
        assert quality["left_hand_coverage"] == 1.0
        assert quality["right_hand_coverage"] == 1.0
    finally:
        session.close()


def test_custom_reference_rejects_confirmed_multiple_people_and_allows_retry():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    detector = SimpleNamespace(last_distinct_person_count=2)
    session.pose_detector = detector
    session._observe_custom_people(None)
    session._observe_custom_people(None)
    assert session.start_custom_capture(duration_seconds=15) == (
        False, "single_performer_required"
    )

    detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose())
    assert session.start_custom_capture(duration_seconds=15)[0] is False
    session._observe_custom_people(_performer_pose())
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())

    detector.last_distinct_person_count = 2
    session._observe_custom_people(None)
    assert session._custom_multiple_invalid is False
    detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose())
    assert session._custom_multiple_invalid is False
    session._observe_custom_people(_performer_pose())
    accepted, code, _ = session.stop_custom_capture()
    assert (accepted, code) == (True, None)
    assert session.custom_reference_count == 1
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())
    detector.last_distinct_person_count = 2
    observed_at = time.monotonic()
    session._observe_custom_people(None, captured_at_monotonic=observed_at)
    session._observe_custom_people(None, captured_at_monotonic=observed_at + .05)
    assert session._custom_multiple_invalid is False
    session._observe_custom_people(None, captured_at_monotonic=observed_at + .11)
    assert session._custom_multiple_invalid is True
    accepted, code, _ = session.stop_custom_capture()
    assert (accepted, code) == (False, "multiple_people_detected")
    assert session.custom_reference_count == 1
    assert session._custom_samples is None
    assert len(session._custom_references) == 1

    detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose())
    session._observe_custom_people(_performer_pose())
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())
    accepted, code, _ = session.stop_custom_capture()
    assert (accepted, code) == (True, None)
    assert session.custom_reference_count == 2


def test_transient_second_pose_cannot_switch_reference_performer():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    detector = SimpleNamespace(last_distinct_person_count=1)
    session.pose_detector = detector
    session._observe_custom_people(_performer_pose(0.3))
    session._observe_custom_people(_performer_pose(0.3))
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())
    detector.last_distinct_person_count = 2
    session._observe_custom_people(_performer_pose(0.3))
    assert session._custom_multiple_invalid is False
    detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose(0.7))
    assert session._custom_multiple_invalid is True
    accepted, code, _ = session.stop_custom_capture()
    assert (accepted, code) == (False, "multiple_people_detected")
    assert session.custom_reference_count == 0


def test_repeated_duplicate_candidates_do_not_contaminate_reference():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    detector = SimpleNamespace(last_person_count=1, last_distinct_person_count=1)
    session.pose_detector = detector
    session._observe_custom_people(_performer_pose())
    session._observe_custom_people(_performer_pose())
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())

    detector.last_person_count = 2  # MediaPipe's duplicate raw candidate.
    for _ in range(5):
        session._observe_custom_people(_performer_pose())
    assert session._custom_person_count == 1
    assert session._custom_multiple_invalid is False
    assert session.stop_custom_capture()[:2] == (True, None)


def test_transient_extra_pose_waits_for_comparable_anchor_without_false_switch():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    detector = SimpleNamespace(last_distinct_person_count=1)
    session.pose_detector = detector
    session._observe_custom_people(_performer_pose())
    session._observe_custom_people(_performer_pose())
    _visible(session)
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    _set_samples(session, _reference())
    detector.last_distinct_person_count = 2
    session._observe_custom_people(None)
    detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose(hips_only=True))
    assert session._custom_awaiting_identity is True
    assert session._custom_multiple_invalid is False
    session._observe_custom_people(_performer_pose())
    assert session._custom_awaiting_identity is False
    accepted, code, _ = session.stop_custom_capture()
    assert (accepted, code) == (True, None)


def test_custom_readiness_confirmation_requires_one_live_performer():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_READYING
    session._latest_readiness_snapshot = SimpleNamespace(readiness_stable=True)
    session._latest_readiness_observed_at = time.monotonic()
    session.pose_detector = SimpleNamespace(last_distinct_person_count=2)
    session._observe_custom_people(None)
    session._observe_custom_people(None)
    assert session.confirm_readiness() == (False, "single_performer_required")
    session.pose_detector.last_distinct_person_count = 1
    session._observe_custom_people(_performer_pose())
    session._observe_custom_people(_performer_pose())
    assert session.confirm_readiness() == (True, None)


def test_custom_assessment_readiness_is_derived_from_one_hand_template():
    template = _template()
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_assessment",
        readiness_spec={"hands": "two_hands", "body": "upper_body"},
        custom_movement_template=template.to_dict(),
    )

    assert session.readiness_spec == {"hands": "one_hand", "body": "none"}
    assert session._hands_needed is True
    assert session._pose_needed is False
    assert session._hands_max == 1
    assert session._orientation_detector is None


def test_endless_custom_target_validates_template_and_resets_on_official_target():
    template = _template().to_dict()
    session = websocket_api.VisionSession(
        "Free Practice", session_mode="endless", prop_type="bottle_and_shaker",
        endless_selected_prop="bottle",
        allowed_movements=[("Normal Grip", "bottle")],
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    assert session.set_endless_target(
        "custom_movement", "Normal Grip", "bottle", 1,
        "custom-1", "revision-1", {"invalid": True},
    ) == (False, "invalid_schema")
    assert session.set_endless_target(
        "custom_movement", "Normal Grip", "shaker", 1,
        "custom-1", "revision-1", template,
    ) == (False, "invalid_endless_target")
    assert session.set_endless_target(
        "custom_movement", "Normal Grip", "bottle", 1,
        "custom-1", "revision-1", template,
    ) == (True, None)
    assert session._custom_template is not None
    assert session._custom_target_id == "custom-1"
    assert session.set_endless_target(
        "movement", "Normal Grip", "bottle", 1,
    ) == (False, "stale_target_generation")
    assert session.set_endless_target(
        "movement", "Normal Grip", "bottle", 2,
    ) == (True, None)
    assert session._custom_template is None
    assert session._custom_samples is None
    assert session._custom_target_id is None
    assert session._evaluate_endless_custom_samples(12) is None
    session.close()


def test_endless_custom_sequence_uses_template_comparison_once():
    session = websocket_api.VisionSession(
        "Free Practice", session_mode="endless", prop_type="bottle_and_shaker",
        endless_selected_prop="bottle", session_id="session-custom",
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    template = _template().to_dict()
    assert session.set_endless_target(
        "custom_movement", "My Move", "bottle", 1,
        "custom-1", "revision-1", template,
    ) == (True, None)
    session._custom_samples = [replace(sample, prop=None) for sample in _reference()]
    session._custom_target_sample_count = 3
    assert session._evaluate_endless_custom_samples(10) is None
    assert session.drain_recognition_events() == []
    session._custom_samples = list(_reference())
    session._custom_target_sample_count = 3
    assert session._evaluate_endless_custom_samples(11) in {"perfect", "great", "nice"}
    events = session.drain_recognition_events()
    assert len(events) == 1
    assert events[0].target_generation == 1
    assert events[0].custom_movement_id == "custom-1"
    assert events[0].revision_id == "revision-1"
    assert session._evaluate_endless_custom_samples(12) is None
    assert session.drain_recognition_events() == []
    session.close()


def test_endless_custom_waits_for_learned_duration_before_recognition():
    session = websocket_api.VisionSession(
        "Free Practice", session_mode="endless", prop_type="bottle_and_shaker",
        endless_selected_prop="bottle", session_id="duration-check",
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    template = _template().to_dict()
    assert session.set_endless_target(
        "custom_movement", "My Move", "bottle", 1,
        "custom-1", "revision-1", template,
    ) == (True, None)
    short = tuple(
        replace(sample, timestamp_ms=index * 40)
        for index, sample in enumerate(_reference()[:8])
    )
    session._custom_samples = list(short)
    session._custom_target_sample_count = 3
    assert session._evaluate_endless_custom_samples(10) is None
    assert session.drain_recognition_events() == []
    session._custom_samples = list(_reference())
    session._custom_target_sample_count = 3
    assert session._evaluate_endless_custom_samples(11) is not None
    session.close()


def test_endless_custom_pause_preserves_capture_clock():
    session = websocket_api.VisionSession(
        "Free Practice", session_mode="endless", prop_type="bottle_and_shaker",
        endless_selected_prop="bottle",
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    assert session.set_endless_target(
        "custom_movement", "My Move", "bottle", 1,
        "custom-1", "revision-1", _template().to_dict(),
    ) == (True, None)
    started = session._custom_capture_started_at
    assert session.set_recognition_paused(True) == (True, None)
    assert session._custom_target_paused_at is not None
    session._custom_target_paused_at -= 2
    assert session.set_recognition_paused(False) == (True, None)
    assert session._custom_capture_started_at >= started + 2
    session.close()


@pytest.mark.parametrize("total,quality", ((6, None), (7, "nice"), (10, "great"), (12, "perfect")))
def test_endless_custom_quality_follows_existing_rubric_levels(monkeypatch, total, quality):
    session = websocket_api.VisionSession(
        "Free Practice", session_mode="endless", prop_type="bottle_and_shaker",
        endless_selected_prop="bottle",
    )
    session._lifecycle = websocket_api.SESSION_ACTIVE
    assert session.set_endless_target(
        "custom_movement", "My Move", "bottle", 1,
        "custom-1", "revision-1", _template().to_dict(),
    ) == (True, None)
    session._custom_samples = list(_reference())
    session._custom_target_sample_count = 3
    monkeypatch.setattr(websocket_api, "compare_custom_movement_sequence", lambda *_: SimpleNamespace(
        validation=SimpleNamespace(valid=True), total=total,
        rotation_diagnostics={"rotation_evidence": "verified"},
    ))
    assert session._evaluate_endless_custom_samples(15) == quality
    assert len(session.drain_recognition_events()) == (1 if quality else 0)
    session.close()


def test_custom_assessment_two_hand_and_pose_requirements_remain_enforced():
    template = _template(sides=("left", "right"), moving_pose=True)
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )

    assert session.readiness_spec == {
        "hands": "two_hands",
        "body": "upper_body",
    }
    assert session._hands_max == 2
    assert session._pose_needed is True


def test_official_session_keeps_global_yolo_cadence():
    session = websocket_api.VisionSession("Hand Stall")

    assert session._yolo_frame_skip == YOLO_FRAME_SKIP
    assert session._orientation_detector is None


def test_custom_capture_diagnostics_are_bounded_and_cause_oriented():
    samples = (
        FrameSample(
            0,
            pose={"11": Landmark(0.3, 0.3)},
            hands={"left:0:0": Landmark(0.2, 0.4)},
            prop=Landmark(0.2, 0.4),
            prop_metadata={
                "yolo_attempted": True,
                "yolo_confirmed": True,
                "track_id": 1,
            },
        ),
        FrameSample(100, prop_metadata={"yolo_attempted": True}),
        FrameSample(
            200,
            hands={"right:0:0": Landmark(0.8, 0.4)},
            prop=Landmark(0.4, 0.4),
            prop_metadata={
                "yolo_attempted": True,
                "yolo_confirmed": True,
                "track_id": 2,
            },
        ),
    )

    diagnostics = websocket_api.VisionSession._custom_capture_diagnostics(samples)

    assert diagnostics == {
        "orientation_inference_ms_mean": None,
        "orientation_provider": None,
        "effective_processing_fps": 10.0,
        "yolo_confirmation_rate": 0.667,
        "yolo_attempts": 3,
        "prop_track_changes": 1,
        "longest_prop_observation_gap_frames": 1,
        "pose_coverage": 0.333,
        "left_hand_coverage": 0.333,
        "right_hand_coverage": 0.333,
        "sequence_duration_ms": 200,
    }


def test_recorded_detection_preserves_yolo_attempt_for_diagnostics():
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_capture",
    )
    started = time.monotonic()
    session._custom_samples = []
    session._custom_capture_started_at = started
    session._custom_capture_deadline = None
    session._last_live_bottles = [
        PropDetection(10, 10, 30, 50, 0.9, track_id=4, yolo_confirmed=True)
    ]
    frame = np.zeros((100, 100, 3), dtype=np.uint8)

    session._record_custom_sample(
        captured=CapturedFrame(frame, started + 0.1, 1),
        frame=frame,
        normalized=websocket_api._NormalizedFrameDetections(
            primary=tuple(session._last_live_bottles),
            bottles=tuple(session._last_live_bottles),
            shakers=(),
            annotation=tuple(session._last_live_bottles),
            selected_detected=True,
            selected_count=1,
        ),
        hands=None,
        pose=None,
        yolo_attempted=True,
    )

    assert session._custom_samples is not None
    assert session._custom_samples[0].prop_metadata["yolo_attempted"] is True
    assert session._custom_capture_diagnostics(tuple(session._custom_samples))[
        "yolo_confirmation_rate"
    ] == 1.0


def test_unconfirmed_prop_without_prior_confirmation_is_not_sampled_or_drawn():
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    started = time.monotonic()
    session._custom_samples = []
    session._custom_capture_started_at = started
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    session._last_live_bottles = [
        PropDetection(10, 10, 30, 50, 0.9, track_id=4, yolo_confirmed=False)
    ]

    session._record_custom_sample(
        captured=CapturedFrame(frame, started + 0.1, 1),
        frame=frame,
        normalized=websocket_api._NormalizedFrameDetections(
            primary=(), bottles=(), shakers=(), annotation=(),
            selected_detected=False, selected_count=0,
        ),
        hands=None, pose=None, yolo_attempted=True,
    )

    assert session._custom_samples is not None
    assert session._custom_samples[0].prop is None
    assert session._custom_samples[0].prop_metadata == {"yolo_attempted": True}
    assert session._last_live_bottles[0].yolo_confirmed is False
    boxes, _ = session._presentation_boxes(
        captured_at=started + 0.1, generation=0, run_yolo=True
    )
    assert boxes == []


@pytest.mark.parametrize("session_mode", ("custom_capture", "custom_assessment"))
def test_render_only_landmark_cache_never_enters_custom_samples(session_mode):
    kwargs = (
        {"custom_movement_template": _template(
            sides=("left", "right"), moving_pose=True,
        ).to_dict()}
        if session_mode == "custom_assessment" else {}
    )
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode=session_mode, **kwargs,
    )
    started = time.monotonic()
    session._custom_samples = []
    session._custom_capture_started_at = started
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    hands = HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})])
    pose = PoseLandmarks(points={11: Point2D(.3, .3)})
    session._publish_presentation(
        captured=CapturedFrame(frame, started, 1), run_yolo=True,
        hands=hands, pose=pose, feedback="test", feedback_type="positive",
        prop_label="Bottle",
    )
    coasted = session._publish_presentation(
        captured=CapturedFrame(frame, started + .05, 2), run_yolo=True,
        hands=None, pose=None, feedback="test", feedback_type="warning",
        prop_label="Bottle",
    )
    assert coasted.hands is not None and coasted.pose is not None
    session._record_custom_sample(
        captured=CapturedFrame(frame, started + .05, 2), frame=frame,
        normalized=websocket_api._NormalizedFrameDetections(
            primary=(), bottles=(), shakers=(), annotation=(),
            selected_detected=False, selected_count=0,
        ),
        hands=None, pose=None, yolo_attempted=True,
    )
    assert session._custom_samples[0].hands == {}
    assert session._custom_samples[0].pose == {}
    session.close()
