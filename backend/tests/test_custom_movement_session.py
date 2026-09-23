import time

import numpy as np

from assessment.custom_movement import FrameSample, Landmark, build_template
from api import websocket as websocket_api
from config import YOLO_FRAME_SKIP
from vision.camera import CapturedFrame
from vision.types import PropDetection


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


def test_unconfirmed_prop_is_neither_presented_nor_a_custom_sample():
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
    assert session._presentation_boxes() == []
