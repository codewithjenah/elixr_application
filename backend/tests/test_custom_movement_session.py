import time
import uuid
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from assessment.custom_movement import FrameSample, Landmark, build_template
from api import websocket as websocket_api
from config import YOLO_FRAME_SKIP
from vision.camera import CapturedFrame
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection


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


def _accepted_reference(session):
    session._custom_person_count = 1
    session._custom_person_observed_at = time.monotonic()
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


def _performer_pose(center_x=0.5, *, hips_only=False):
    left, right = (23, 24) if hips_only else (11, 12)
    return SimpleNamespace(
        points={
            left: SimpleNamespace(x=center_x - 0.1, y=0.6 if hips_only else 0.3),
            right: SimpleNamespace(x=center_x + 0.1, y=0.6 if hips_only else 0.3),
        },
        visibility={left: 0.9, right: 0.9},
    )


def test_custom_capture_uses_minimum_readiness_but_observes_all_modalities():
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_capture",
        readiness_spec={"hands": "two_hands", "body": "upper_body"},
    )

    assert session.readiness_spec == {"hands": "none", "body": "none"}
    assert session._hands_needed is True
    assert session._pose_needed is True
    assert session._hands_max == 2
    assert session._yolo_frame_skip == 1


def test_custom_capture_requests_two_poses_only_for_reference_session(monkeypatch):
    constructed = []

    class FakePose:
        def __init__(self, **kwargs):
            constructed.append(kwargs)

        def close(self):
            pass

    monkeypatch.setattr(websocket_api, "PoseDetector", FakePose)
    capture = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    capture._ensure_readiness_detectors()
    assert constructed == [{"max_poses": 2}]
    capture._ensure_detectors()
    assert constructed == [{"max_poses": 2}]
    ordinary = websocket_api.VisionSession("Hand Stall")
    ordinary._sync_landmark_detectors(needs_hands=False, needs_pose=True)
    assert constructed[-1] == {}


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
