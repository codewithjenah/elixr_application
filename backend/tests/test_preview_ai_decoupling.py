"""Preview cadence must stay independent of AI inference and scoring."""

from __future__ import annotations

import asyncio
import json
import threading
import time
from dataclasses import replace
from unittest.mock import MagicMock

import numpy as np
import pytest

from api import websocket as websocket_api
from assessment.rules.base import RuleResult
from assessment.scoring import RubricTracker
from schemas.feedback import PreviewFrameMessage
from test_session_lifecycle import (
    StubBottleDetector,
    StubCamera,
    _patch_vision,
)
from vision.camera import CapturedFrame
from vision.dual_prop_detector import DualPropResult
from vision.overlay_snapshot import freeze_overlay
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection


def _decode(payload: str) -> dict:
    return json.loads(payload)


def test_outbound_mailbox_keeps_latest_preview_only():
    async def _run():
        mailbox = websocket_api._OutboundMailbox()
        stop = asyncio.Event()
        mailbox.put(
            websocket_api._OutboundItem("preview", "old", None)
        )
        mailbox.put(
            websocket_api._OutboundItem("preview", "new", None)
        )
        assert mailbox.preview_replaced == 1
        batch = await mailbox.take_batch(stop)
        assert [item.payload for item in batch] == ["new"]

    asyncio.run(_run())


def test_outbound_mailbox_never_drops_must_deliver_feedback():
    async def _run():
        mailbox = websocket_api._OutboundMailbox()
        stop = asyncio.Event()
        for index in range(websocket_api._FEEDBACK_PENDING_MAX):
            mailbox.put(
                websocket_api._OutboundItem("feedback", f"f{index}", None)
            )
        mailbox.put(
            websocket_api._OutboundItem("feedback", "dropped", None)
        )
        mailbox.put(
            websocket_api._OutboundItem(
                "feedback",
                "hold",
                None,
                must_deliver=True,
            )
        )
        assert mailbox.feedback_replaced == 1
        batch = await mailbox.take_batch(stop)
        payloads = [item.payload for item in batch]
        assert "dropped" not in payloads
        assert "hold" in payloads
        assert len(payloads) == websocket_api._FEEDBACK_PENDING_MAX + 1

    asyncio.run(_run())


def test_preview_frame_message_has_no_scoring_fields():
    dumped = json.loads(
        PreviewFrameMessage(
            frame_jpeg_base64="abcd",
            camera_ready=True,
            session_state="active",
            capture_sequence=3,
        )
        .with_session("session-1")
        .model_dump_json()
    )
    assert dumped["message_type"] == "preview_frame"
    assert dumped["session_id"] == "session-1"
    assert "assessment" not in dumped
    assert "hold_confirmed" not in dumped
    assert "readiness_items" not in dumped
    assert "feedback" not in dumped


def test_analyze_tick_skips_prepared_lifecycle(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        return (
            RuleResult(
                feedback="should not run",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.analyze_tick() is None
    assert evaluate_calls["n"] == 0
    session.close()


def test_stale_overlay_expires_instead_of_drawing(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic() - 1.0,
            captured_at_monotonic=time.monotonic() - 1.1,
            capture_sequence=1,
            boxes=[PropDetection(1, 2, 3, 4, 0.9)],
            hands=None,
            pose=None,
            feedback="ghost",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    assert session._read_fresh_overlay() is None
    session.close()


def test_fresh_overlay_is_readable(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=time.monotonic(),
            capture_sequence=2,
            boxes=[PropDetection(1, 2, 3, 4, 0.9)],
            hands=None,
            pose=None,
            feedback="ok",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    snapshot = session._read_fresh_overlay()
    assert snapshot is not None
    assert snapshot.capture_sequence == 2
    session.close()


def test_recently_published_overlay_bridges_preview_ai_scheduling_gap(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "OVERLAY_MAX_CAPTURE_AGE_S", 0.1)
    annotate_calls = {"n": 0}
    evaluate_calls = {"n": 0}

    def tracking_annotate(current_frame, *args, **kwargs):
        annotate_calls["n"] += 1
        return current_frame

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("preview overlay rejection must not evaluate")

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)
    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.0,
            capture_sequence=1,
            boxes=[],
            hands=HandsResult(
                hands=[
                    HandLandmarks(
                        points={0: Point2D(0.2, 0.3)},
                        handedness="Right",
                    )
                ]
            ),
            pose=None,
            feedback="old hand",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    session.camera.peek_latest = lambda **kwargs: CapturedFrame(
        frame=np.full((48, 64, 3), 120, dtype=np.uint8),
        captured_at_monotonic=10.2,
        sequence=5,
    )

    message = session.render_preview()

    assert message is not None
    assert annotate_calls["n"] == 1
    assert evaluate_calls["n"] == 0
    summary = session.preview_timings.overlay_alignment_summary()
    assert summary["capture_age_max_ms"] == pytest.approx(200.0)
    assert summary["sequence_gap_max"] == 4
    session.close()


def test_custom_preview_metadata_and_annotation_share_confirmed_prop(monkeypatch):
    """A custom status may say detected only when this JPEG drew the box."""
    _patch_vision(monkeypatch)
    annotate_boxes: list[list[PropDetection]] = []

    def tracking_annotate(current_frame, boxes, *args, **kwargs):
        annotate_boxes.append(list(boxes))
        return current_frame

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture"
    )
    session.start()
    box = PropDetection(1, 2, 20, 40, 0.9, yolo_confirmed=True)
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.0,
            capture_sequence=1,
            boxes=[box],
            hands=None,
            pose=None,
            feedback="Bottle detected",
            feedback_type="positive",
            movement="Custom Movement",
            prop_label="Bottle",
        )
    )
    # Simulate a measured 3.0 FPS AI cadence. This is a normal interval, not
    # an indefinitely stale overlay; the hard cap still bounds it.
    with session._overlay_lock:
        session._overlay_publish_period_s = 1.0 / 3.0
    session.camera.peek_latest = lambda **kwargs: CapturedFrame(
        frame=np.full((48, 64, 3), 120, dtype=np.uint8),
        captured_at_monotonic=10.4,
        sequence=8,
    )

    message = session.render_preview()

    assert message is not None
    assert message.prop_presentation_state == "confirmed"
    assert message.overlay_capture_sequence == 1
    assert annotate_boxes == [[box]]
    session.close()


@pytest.mark.parametrize(
    ("prop_type", "session_mode"),
    [
        ("bottle", None),
        ("shaker", None),
        ("bottle_and_shaker", None),
        ("bottle", "custom_capture"),
    ],
)
def test_yolo_miss_coasts_briefly_without_entering_normalized_observations(
    monkeypatch, prop_type, session_mode
):
    _patch_vision(monkeypatch)
    drawn: list[list[PropDetection]] = []

    def tracking_annotate(current_frame, boxes, *args, **kwargs):
        drawn.append(list(boxes))
        return current_frame

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)
    session = websocket_api.VisionSession(
        "Custom Movement" if session_mode else "Hand Stall",
        prop_type=prop_type,
        session_mode=session_mode,
    )
    session.start()
    bottle = PropDetection(1, 2, 20, 40, 0.9, track_id=1, yolo_confirmed=True)
    shaker = PropDetection(22, 2, 40, 40, 0.9, track_id=2, yolo_confirmed=True)
    live = {
        "bottles": [bottle] if prop_type != "shaker" else [],
        "shakers": [shaker] if prop_type != "bottle" else [],
    }

    class Detector:
        def detect(self, frame):
            if prop_type == "bottle_and_shaker":
                return DualPropResult(**live)
            return live["shakers"] if prop_type == "shaker" else live["bottles"]

        def extrapolate_detections(self, *, bottles, shakers, now):
            return [replace(box, x1=box.x1 + 1) for box in bottles], [
                replace(box, x1=box.x1 + 1) for box in shakers
            ]

    session.prop_detector = Detector()
    frame = np.zeros((48, 64, 3), dtype=np.uint8)
    captured_at = time.monotonic()
    confirmed = session._detect_normalized_props(frame)
    expected = list(confirmed.annotation)
    boxes, _ = session._presentation_boxes(
        captured_at=captured_at, generation=1, run_yolo=True
    )
    assert boxes == expected

    # A deliberately skipped YOLO tick keeps and extrapolates confirmed boxes.
    skipped = session._cached_normalized_props()
    assert len(skipped.annotation) == len(expected)
    boxes, _ = session._presentation_boxes(
        captured_at=captured_at + .05, generation=1, run_yolo=False
    )
    assert len(boxes) == len(expected)
    assert boxes[0].x1 == expected[0].x1 + 1
    assert all(not box.yolo_confirmed for box in boxes)

    # A YOLO miss leaves track identity available for reacquisition.
    missing = shaker if prop_type == "shaker" else bottle
    key = "shakers" if prop_type == "shaker" else "bottles"
    live[key] = [replace(missing, yolo_confirmed=False)]
    normalized = session._detect_normalized_props(frame)
    assert live[key][0].track_id == missing.track_id
    retained = (
        session._last_live_shakers
        if key == "shakers"
        else session._last_live_bottles
    )
    assert retained[0].yolo_confirmed is False
    assert normalized.annotation == (
        (shaker,) if prop_type == "bottle_and_shaker" else ()
    )
    boxes, expires = session._presentation_boxes(
        captured_at=captured_at + .1, generation=1, run_yolo=True
    )
    assert len(boxes) == len(expected)
    assert any(not box.yolo_confirmed for box in boxes)
    assert any(expiry == captured_at + websocket_api.DETECTION_PRESENTATION_GRACE_S
               for expiry in expires)

    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=captured_at + .1,
            capture_sequence=1,
            capture_generation=1,
            boxes=boxes,
            box_expires_at=expires,
            hands=None,
            pose=None,
            feedback="missing",
            feedback_type="warning",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    overlay = session._read_fresh_overlay()
    assert overlay is not None
    assert list(overlay.boxes) == boxes
    session.camera.peek_latest = lambda **kwargs: CapturedFrame(frame, captured_at + .11, 2, 1)
    preview = session.render_preview()
    assert preview is not None
    if session_mode == "custom_capture":
        assert preview.prop_presentation_state == "coasted"
    assert drawn == [boxes]
    expired_boxes, _ = session._presentation_boxes(
        captured_at=captured_at + websocket_api.DETECTION_PRESENTATION_GRACE_S + .01,
        generation=1, run_yolo=True,
    )
    assert expired_boxes == list(normalized.annotation)
    # A still-published snapshot also drops coasted geometry on a later JPEG.
    expired_overlay = session._read_fresh_overlay(
        preview=CapturedFrame(frame, captured_at + .3, 3, 1)
    )
    assert expired_overlay is not None
    assert list(expired_overlay.boxes) == list(normalized.annotation)
    recovered = replace(missing, yolo_confirmed=True)
    live[key] = [recovered]
    session._detect_normalized_props(frame)
    recovered_boxes, _ = session._presentation_boxes(
        captured_at=captured_at + .31, generation=1, run_yolo=True
    )
    assert recovered in recovered_boxes
    session.close()


def test_one_landmark_miss_coasts_then_expires_on_the_rendered_jpeg(monkeypatch):
    _patch_vision(monkeypatch)
    drawn = []

    def tracking_annotate(frame, boxes, hands, *args, pose=None, **kwargs):
        drawn.append((list(boxes), hands, pose))
        return frame

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture"
    )
    session.start()
    base = time.monotonic()
    frame = np.zeros((48, 64, 3), dtype=np.uint8)
    hands = HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)}, handedness="Right")])
    pose = PoseLandmarks(points={0: Point2D(.4, .5)}, visibility={0: 1.0})
    session._publish_presentation(
        captured=CapturedFrame(frame, base, 1, 1), run_yolo=True,
        hands=hands, pose=pose, feedback="present", feedback_type="positive",
        prop_label="Bottle",
    )
    # A genuine observation is frozen; a later mutation cannot alter its cache.
    hands.hands[0].points[0] = Point2D(.9, .9)
    pose.points[0] = Point2D(.9, .9)
    session._publish_presentation(
        captured=CapturedFrame(frame, base + .10, 2, 1), run_yolo=True,
        hands=None, pose=None, feedback="missing", feedback_type="warning",
        prop_label="Bottle",
    )
    preview_frame = [CapturedFrame(frame, base + .11, 3, 1)]
    session.camera.peek_latest = lambda **kwargs: preview_frame[0]
    first = session.render_preview()
    assert first is not None
    assert first.hands_presentation_state == "tracking"
    assert first.pose_presentation_state == "tracking"
    assert drawn[-1][1].hands[0].points[0] == Point2D(.2, .3)
    assert drawn[-1][2].points[0] == Point2D(.4, .5)

    # Expiry is checked per JPEG, even if AI has not published another snapshot.
    preview_frame[0] = CapturedFrame(frame, base + .26, 4, 1)
    expired = session.render_preview()
    assert expired is not None
    assert expired.hands_presentation_state == "missing"
    assert expired.pose_presentation_state == "missing"
    assert drawn[-1][1:] == (None, None)

    # One more missing AI result cannot renew the original observation age.
    session._publish_presentation(
        captured=CapturedFrame(frame, base + .27, 5, 1), run_yolo=True,
        hands=None, pose=None, feedback="missing", feedback_type="warning",
        prop_label="Bottle",
    )
    assert session._read_fresh_overlay().hands is None
    assert session._read_fresh_overlay().pose is None
    session.close()


def test_repeated_landmark_misses_expire_by_observation_age(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session.start()
    base = time.monotonic()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    hands = HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})])
    pose = PoseLandmarks(points={0: Point2D(.4, .5)})
    def publish(sequence, dt, current_hands, current_pose):
        return session._publish_presentation(
            captured=CapturedFrame(frame, base + dt, sequence, 1),
            run_yolo=True, hands=current_hands, pose=current_pose,
            feedback="test", feedback_type="positive", prop_label="Bottle",
        )

    publish(1, 0, hands, pose)
    first_miss = publish(2, .05, None, None)
    assert first_miss.hands is not None and first_miss.pose is not None
    second_miss = publish(3, .10, None, None)
    assert second_miss.hands is not None and second_miss.pose is not None
    assert session._presented_hands[1] == base
    assert session._presented_pose[1] == base
    expired = publish(4, .26, None, None)
    assert expired.hands is None and expired.pose is None
    recovered = publish(5, .30, hands, pose)
    assert recovered.hands is not None and recovered.pose is not None
    session.close()


def test_presentation_cache_clears_on_generation_activation_and_close(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session.start()
    base = time.monotonic()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    hands = HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})])
    pose = PoseLandmarks(points={0: Point2D(.4, .5)})
    def publish(sequence, generation, current_hands, current_pose):
        return session._publish_presentation(
            captured=CapturedFrame(frame, base + sequence * .01, sequence, generation),
            run_yolo=True, hands=current_hands, pose=current_pose,
            feedback="test", feedback_type="positive", prop_label="Bottle",
        )

    publish(1, 1, hands, pose)
    switched = publish(2, 2, None, None)
    assert switched.hands is None and switched.pose is None
    publish(3, 2, hands, pose)
    assert session.activate() == (True, None)
    after_activation = publish(4, 2, None, None)
    assert after_activation.hands is None and after_activation.pose is None
    publish(5, 2, hands, pose)
    session.close()
    assert session._read_fresh_overlay() is None
    assert session._presented_hands is None and session._presented_pose is None


def test_new_camera_generation_resets_prop_skip_cache_before_next_ai_tick(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    box = PropDetection(1, 2, 5, 6, .9, track_id=1)
    session._last_ai_generation = 1
    session._frame_index = 1
    session._last_live_bottles = [box]
    session._presentation_boxes(
        captured_at=time.monotonic(), generation=1, run_yolo=True
    )
    session.prop_detector = MagicMock()
    session._accept_capture_generation(CapturedFrame(frame, time.monotonic(), 2, 2))
    assert session._frame_index == 0
    assert session._last_live_bottles == []
    assert session._prop_confirmed_at == {}
    session.prop_detector.reset_cache.assert_called_once()
    session.close()


def test_multiple_people_never_reuses_old_pose_for_presentation(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session.start()
    base = time.monotonic()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    pose = PoseLandmarks(points={0: Point2D(.4, .5)})
    session._publish_presentation(
        captured=CapturedFrame(frame, base, 1, 1), run_yolo=True,
        hands=None, pose=pose, feedback="test", feedback_type="positive",
        prop_label="Bottle",
    )
    session.pose_detector = MagicMock(last_distinct_person_count=2)
    session._custom_samples = []
    session._observe_custom_people(None, captured_at_monotonic=base)
    session._observe_custom_people(None, captured_at_monotonic=base + .05)
    session._observe_custom_people(None, captured_at_monotonic=base + .11)
    snapshot = session._publish_presentation(
        captured=CapturedFrame(frame, base + .05, 2, 1), run_yolo=True,
        hands=None, pose=None, feedback="test", feedback_type="warning",
        prop_label="Bottle",
    )
    assert snapshot.pose is None
    assert session._custom_person_count == 2
    assert session._custom_multiple_invalid is True
    with_current_pose = session._publish_presentation(
        captured=CapturedFrame(frame, base + .10, 3, 1), run_yolo=True,
        hands=None, pose=pose, feedback="multiple", feedback_type="warning",
        prop_label="Bottle",
    )
    assert with_current_pose.pose is None
    session.close()


def test_duplicate_raw_pose_candidate_keeps_current_body_overlay(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session.start()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    pose = PoseLandmarks(points={11: Point2D(.4, .3), 12: Point2D(.6, .3)})
    session.pose_detector = MagicMock(last_person_count=2, last_distinct_person_count=1)
    session._observe_custom_people(pose)
    snapshot = session._publish_presentation(
        captured=CapturedFrame(frame, time.monotonic(), 1, 1), run_yolo=True,
        hands=None, pose=pose, feedback="ready", feedback_type="positive",
        prop_label="Bottle",
    )
    assert snapshot.pose is not None
    assert session._preview_presentation_metadata(snapshot)["pose_presentation_state"] == "tracking"
    assert session._custom_multiple_invalid is False
    session.close()


def test_dead_ai_watchdog_clears_custom_presentation(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture"
    )
    session.start()
    session._presented_hands = (
        HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})]),
        10.0, 0,
    )
    session._presented_pose = (
        PoseLandmarks(points={0: Point2D(.4, .5)}), 10.0, 0,
    )
    session._prop_confirmed_at[("bottle", 1)] = 10.0
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=10.0,
            captured_at_monotonic=10.0,
            capture_sequence=1,
            boxes=[PropDetection(1, 2, 20, 40, 0.9, yolo_confirmed=True)],
            hands=None,
            pose=None,
            feedback="present",
            feedback_type="positive",
            movement="Custom Movement",
            prop_label="Bottle",
        )
    )

    overlay = session._read_fresh_overlay(now=10.0 + websocket_api.OVERLAY_DEAD_WORKER_TIMEOUT_S + .01)

    assert overlay is None
    assert session._preview_presentation_metadata(overlay)["prop_presentation_state"] == "missing"
    assert session._presented_hands is None and session._presented_pose is None
    assert session._prop_confirmed_at == {}
    session.close()


def test_recent_capture_overlay_is_drawn(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "OVERLAY_MAX_CAPTURE_AGE_S", 0.1)
    annotate_calls = {"n": 0}

    def tracking_annotate(current_frame, *args, **kwargs):
        annotate_calls["n"] += 1
        return current_frame

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.0,
            capture_sequence=3,
            boxes=[],
            hands=None,
            pose=None,
            feedback="current",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    session.camera.peek_latest = lambda **kwargs: CapturedFrame(
        frame=np.full((48, 64, 3), 120, dtype=np.uint8),
        captured_at_monotonic=10.05,
        sequence=4,
    )

    message = session.render_preview()

    assert message is not None
    assert annotate_calls["n"] == 1
    session.close()


def test_overlay_from_previous_camera_generation_is_rejected(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.0,
            capture_sequence=20,
            capture_generation=1,
            boxes=[],
            hands=None,
            pose=None,
            feedback="old camera",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    preview = CapturedFrame(
        frame=np.full((48, 64, 3), 120, dtype=np.uint8),
        captured_at_monotonic=10.01,
        sequence=21,
        generation=2,
    )

    assert session._read_fresh_overlay(preview=preview) is None
    summary = session.preview_timings.overlay_alignment_summary()
    assert summary["count"] == 0
    assert summary["generation_rejections"] == 1

    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.02,
            capture_sequence=22,
            capture_generation=2,
            boxes=[],
            hands=None,
            pose=None,
            feedback="newer than preview",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    assert session._read_fresh_overlay(preview=preview) is None
    summary = session.preview_timings.overlay_alignment_summary()
    assert summary["count"] == 0
    assert summary["ahead_rejections"] == 1
    session.close()


def test_overlay_past_presentation_grace_counts_stale_rejection(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=10.0,
            capture_sequence=20,
            capture_generation=2,
            boxes=[],
            hands=None,
            pose=None,
            feedback="stale geometry",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    preview = CapturedFrame(
        frame=np.full((48, 64, 3), 120, dtype=np.uint8),
        captured_at_monotonic=10.0 + websocket_api.OVERLAY_PRESENTATION_BASE_GRACE_S + 0.001,
        sequence=24,
        generation=2,
    )

    assert session._read_fresh_overlay(preview=preview) is None
    summary = session.preview_timings.overlay_alignment_summary()
    assert summary["count"] == 1
    assert summary["stale_age_rejections"] == 1
    assert summary["ahead_rejections"] == 0
    assert summary["generation_rejections"] == 0
    session.close()


def test_expired_whole_overlay_makes_all_custom_preview_states_missing(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session.start()
    now = time.monotonic()
    frame = np.zeros((48, 64, 3), dtype=np.uint8)
    session._publish_overlay(freeze_overlay(
        published_at_monotonic=now,
        captured_at_monotonic=now - .4,
        capture_sequence=1,
        capture_generation=1,
        boxes=[PropDetection(1, 2, 20, 40, .9)],
        hands=HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})]),
        pose=PoseLandmarks(points={0: Point2D(.4, .5)}),
        feedback="present", feedback_type="positive", movement="Custom Movement",
        prop_label="Bottle",
    ))
    session.camera.peek_latest = lambda **kwargs: CapturedFrame(frame, now, 2, 1)
    preview = session.render_preview()
    assert preview is not None
    assert preview.vision_overlay_present is False
    assert preview.prop_presentation_state == "missing"
    assert preview.hands_presentation_state == "missing"
    assert preview.pose_presentation_state == "missing"
    session.close()


def test_new_ai_absence_keeps_hand_overlay_only_within_real_age(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    base = time.monotonic()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    def publish(sequence, dt, hands):
        return session._publish_presentation(
            captured=CapturedFrame(frame, base + dt, sequence), run_yolo=True,
            hands=hands, pose=None, feedback="hand", feedback_type="positive",
            prop_label="Bottle",
        )

    publish(1, 0, HandsResult(hands=[HandLandmarks(points={0: Point2D(.2, .3)})]))
    assert publish(2, .05, None).hands is not None
    assert publish(3, .10, None).hands is not None
    assert session._read_fresh_overlay(
        preview=CapturedFrame(frame, base + .11, 4)
    ).hands is not None
    assert publish(4, .26, None).hands is None
    session.close()


def test_render_preview_does_not_evaluate_or_score(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}
    real_record = RubricTracker.record

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("preview must not evaluate movement")

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)
    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    message = session.render_preview()
    assert message is not None
    assert message.message_type == "preview_frame"
    assert message.frame_jpeg_base64
    assert evaluate_calls["n"] == 0
    assert record_calls["n"] == 0
    session.close()


def test_render_preview_skips_duplicate_capture_sequence(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    def peek_latest(*, newer_than=None, timeout=None):
        frame = np.full((48, 64, 3), 120, dtype=np.uint8)
        sequence = 7
        if newer_than is not None and sequence <= newer_than:
            return None
        return CapturedFrame(
            frame=frame,
            captured_at_monotonic=time.monotonic(),
            sequence=sequence,
        )

    session.camera.peek_latest = peek_latest
    first = session.render_preview()
    second = session.render_preview()
    assert first is not None
    assert first.capture_sequence == 7
    assert second is None
    session.close()


def test_analyze_tick_rejects_second_in_flight_call(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    assert session._ai_tick_lock.acquire(blocking=False)
    try:
        with pytest.raises(RuntimeError, match="single in-flight"):
            session.analyze_tick()
    finally:
        session._ai_tick_lock.release()
    assert session._ai_state_lock.acquire(blocking=False)
    try:
        assert session.analyze_tick() is None
    finally:
        session._ai_state_lock.release()
    session.close()


def test_ai_worker_single_in_flight_and_preview_continues(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    in_flight = {"count": 0, "max": 0}
    original = websocket_api.VisionSession.analyze_tick

    def slow_analyze(self):
        in_flight["count"] += 1
        in_flight["max"] = max(in_flight["max"], in_flight["count"])
        time.sleep(0.18)
        try:
            return original(self)
        finally:
            in_flight["count"] -= 1

    monkeypatch.setattr(websocket_api.VisionSession, "analyze_tick", slow_analyze)

    evaluate_calls = {"n": 0}
    real_evaluate = websocket_api.evaluate_movement

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        return real_evaluate(*args, **kwargs)

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    async def _run():
        sent: list[str] = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )

        deadline = time.monotonic() + 3.0
        preview_n = 0
        feedback_n = 0
        while time.monotonic() < deadline:
            preview_n = sum(
                1
                for payload in sent
                if _decode(payload).get("message_type") == "preview_frame"
            )
            feedback_n = sum(
                1
                for payload in sent
                if _decode(payload).get("message_type") == "feedback"
            )
            if (
                preview_n >= 3
                and feedback_n >= 1
                and evaluate_calls["n"] >= 1
            ):
                break
            await asyncio.sleep(0.02)

        await websocket_api._stop_session_task(task)
        preview_n = sum(
            1
            for payload in sent
            if _decode(payload).get("message_type") == "preview_frame"
        )
        feedback_n = sum(
            1
            for payload in sent
            if _decode(payload).get("message_type") == "feedback"
        )
        sequences = [
            _decode(payload).get("capture_sequence")
            for payload in sent
            if _decode(payload).get("message_type") == "preview_frame"
        ]
        assert in_flight["max"] == 1
        assert preview_n >= 3
        assert preview_n > evaluate_calls["n"]
        assert evaluate_calls["n"] >= 1
        assert feedback_n >= 1
        assert sequences == sorted(sequences)
        assert len(set(sequences)) == len(sequences)

    asyncio.run(_run())


def test_slow_readiness_warmup_finishes_before_live_preview(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 40)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    entered = threading.Event()
    release = threading.Event()
    original_warm = websocket_api.VisionSession.warm_readiness

    def slow_warm(self):
        entered.set()
        assert release.wait(timeout=2)
        return original_warm(self)

    monkeypatch.setattr(websocket_api.VisionSession, "warm_readiness", slow_warm)

    async def run():
        previews: list[float] = []

        async def fake_send(payload):
            if _decode(payload).get("message_type") == "preview_frame":
                previews.append(time.perf_counter())

        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                MagicMock(), "Hand Stall", send_text=fake_send
            )
        )
        try:
            assert await asyncio.to_thread(entered.wait, 1)
            await asyncio.sleep(0.1)
            assert previews == []
            release.set()
            deadline = time.monotonic() + 1
            while len(previews) < 4 and time.monotonic() < deadline:
                await asyncio.sleep(0.01)
            assert len(previews) >= 4
            assert max(b - a for a, b in zip(previews, previews[1:])) < 0.15
        finally:
            release.set()
            await websocket_api._stop_session_task(task)

    asyncio.run(run())


def test_warmup_model_failure_is_delivered_without_preview(monkeypatch):
    _patch_vision(monkeypatch)

    class FailingDetector(StubBottleDetector):
        def ensure_ready(self):
            raise websocket_api.ModelLoadError("test failure")

    monkeypatch.setattr(websocket_api, "BottleDetector", FailingDetector)

    async def run():
        sent: list[dict] = []

        async def fake_send(payload):
            sent.append(_decode(payload))

        await asyncio.wait_for(
            websocket_api._cv_session_loop(
                MagicMock(), "Hand Stall", send_text=fake_send
            ),
            timeout=2,
        )
        assert [message["message_type"] for message in sent] == ["feedback"]
        assert sent[0]["error_code"] == "model_load_failed"

    asyncio.run(run())


def test_stop_during_warmup_waits_for_worker_before_camera_release(monkeypatch):
    _patch_vision(monkeypatch)
    entered = threading.Event()
    release = threading.Event()
    camera_releases = []

    class CountingCamera(StubCamera):
        def release(self):
            camera_releases.append(time.perf_counter())
            super().release()

    monkeypatch.setattr(websocket_api, "CameraCapture", CountingCamera)
    original_warm = websocket_api.VisionSession.warm_readiness

    def slow_warm(self):
        entered.set()
        assert release.wait(timeout=2)
        return original_warm(self)

    monkeypatch.setattr(websocket_api.VisionSession, "warm_readiness", slow_warm)

    async def run():
        sent = []

        async def fake_send(payload):
            sent.append(_decode(payload))

        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                MagicMock(), "Hand Stall", send_text=fake_send
            )
        )
        try:
            assert await asyncio.to_thread(entered.wait, 1)
            stopping = asyncio.create_task(websocket_api._stop_session_task(task))
            await asyncio.sleep(0.05)
            assert not stopping.done()
            assert camera_releases == []
            release.set()
            await asyncio.wait_for(stopping, timeout=1)
            assert len(camera_releases) == 1
            assert sent == []
        finally:
            release.set()
            if not task.done():
                await websocket_api._stop_session_task(task)

    asyncio.run(run())


def test_serialized_websocket_sends_never_overlap(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    original = websocket_api.VisionSession.analyze_tick

    def slow_analyze(self):
        time.sleep(0.05)
        return original(self)

    monkeypatch.setattr(websocket_api.VisionSession, "analyze_tick", slow_analyze)

    in_send = {"n": 0, "max": 0}

    async def _run():
        async def fake_send(_text):
            in_send["n"] += 1
            in_send["max"] = max(in_send["max"], in_send["n"])
            await asyncio.sleep(0.03)
            in_send["n"] -= 1

        ws = MagicMock()
        session_ref: dict = {"session": None, "mailbox": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )
        for _ in range(80):
            mailbox = session_ref.get("mailbox")
            if mailbox is not None and mailbox.max_sends_in_flight >= 1:
                break
            await asyncio.sleep(0.02)

        mailbox = session_ref.get("mailbox")
        await websocket_api._stop_session_task(task)
        assert in_send["max"] == 1
        assert mailbox is not None
        assert mailbox.max_sends_in_flight == 1

    asyncio.run(_run())


def test_stop_cancels_preview_and_ai_without_task_leak(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    async def _run():
        before = {id(task) for task in asyncio.all_tasks()}

        async def fake_send(_text):
            return None

        ws = MagicMock()
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )
        for _ in range(50):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        await websocket_api._stop_session_task(task)
        await asyncio.sleep(0)
        leftover = [
            t
            for t in asyncio.all_tasks()
            if id(t) not in before and t is not asyncio.current_task()
        ]
        assert leftover == []
        assert StubCamera.instances[-1].released is True
        assert session_ref.get("session") is None

    asyncio.run(_run())


def test_active_analysis_without_preview_jpeg_still_scores_once(monkeypatch):
    _patch_vision(monkeypatch)
    record_calls = {"n": 0}
    real_record = RubricTracker.record

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    message = session.process_frame(emit_preview_jpeg=False)
    assert message is not None
    assert message.frame_jpeg_base64 is None
    assert message.message_type == "feedback"
    assert message.session_state == "active"
    assert record_calls["n"] == 1
    session.close()
