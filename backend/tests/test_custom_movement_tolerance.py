"""Behavior-aware reference authoring and matching tolerance.

Synthetic detector observations only: no webcam, model, or network. Image
coordinates use a 0.4-wide shoulder line, so 0.01 image = 0.025 shoulder widths.
"""

import math
import time
from dataclasses import replace
from types import SimpleNamespace

import pytest

from assessment.custom_movement import FrameSample, Landmark, MovementTemplate, build_template
from assessment.custom_movement.completion import (
    MOVEMENT_COMPLETED,
    evaluate_completion,
)
from assessment.custom_movement.template_engine import (
    MIN_REFERENCE_DURATION_MS,
    ReferenceQualityError,
    check_reference_integrity,
    compare_sequence,
)
from api import websocket as websocket_api
from schemas.protocol import CommandAck


def _noise(index: int, salt: float) -> float:
    """Deterministic pseudo-random value in [-1, 1]."""
    return math.sin(index * 12.9898 + salt * 78.233) * 43758.5453 % 1 * 2 - 1


def _hand(wx, wy, tip_x):
    return {
        "left:0:0": Landmark(wx, wy),
        "left:0:9": Landmark(wx + 0.02, wy - 0.04),
        "left:0:8": Landmark(tip_x, wy - 0.07),
        "left:0:4": Landmark(wx + 0.05, wy - 0.02),
    }


def _pose(wx, wy):
    return {"11": Landmark(0.3, 0.3), "12": Landmark(0.7, 0.3),
            "13": Landmark(0.35, 0.42), "15": Landmark(wx, wy)}


def _grip(count=12, interval=100, *, hand_dx=0.0, tip=0.34, prop_jitter=0.0,
          prop_miss=(), hand_miss=(), drift=0.0, prop=True):
    """A held normal (tip=0.34) or reverse (tip=0.41) grip."""
    frames = []
    for i in range(count):
        dx = hand_dx + drift * i
        wx, wy = 0.36 + dx, 0.50
        prop_point = None if (not prop or i in prop_miss) else Landmark(
            0.38 + dx + prop_jitter * _noise(i, 1), 0.45 + prop_jitter * _noise(i, 2),
        )
        frames.append(FrameSample(
            i * interval, _pose(wx, wy),
            {} if i in hand_miss else _hand(wx, wy, tip + dx),
            prop_point, {"track_id": 1},
        ))
    return tuple(frames)


def _dynamic(count=12, interval=100, *, wrist_step=0.0, tip_step=0.0, prop_step=0.0,
             prop_miss=(), noise=0.0, prop=True, spike_at=None):
    """Per-frame wrist translation, fingertip transition and prop travel."""
    frames = []
    for i in range(count):
        wx = 0.36 + wrist_step * i + 0.3 * noise * _noise(i, 3)
        wy = 0.50 + 0.3 * noise * _noise(i, 4)
        tip = 0.34 + wrist_step * i + tip_step * i + 0.3 * noise * _noise(i, 5)
        px = 0.38 + wrist_step * i + prop_step * i + noise * _noise(i, 6)
        py = 0.45 + noise * _noise(i, 7)
        if spike_at == i:
            px += 0.15
        prop_point = None if (not prop or i in prop_miss) else Landmark(px, py)
        frames.append(FrameSample(
            i * interval, _pose(wx, wy), _hand(wx, wy, tip), prop_point, {"track_id": 1},
        ))
    return tuple(frames)


def _retime(samples, interval):
    return tuple(replace(frame, timestamp_ms=index * interval)
                 for index, frame in enumerate(samples))


def _code(error) -> str:
    return str(error.value)


# --- Static authoring -------------------------------------------------------

def test_one_static_reference_builds_a_loadable_template():
    template = build_template([_grip()], movement_behavior="static")
    assert template.reference_count == 1
    assert template.schema_version == 3
    assert template.movement_behavior == "static"
    assert MovementTemplate.from_dict(template.to_dict()) == template
    assert websocket_api.CustomMovementTemplate.from_dict(template.to_dict()) == template
    assert template.variability_metadata["motion_unit"] == pytest.approx(1.0)


def test_dynamic_still_requires_two_references():
    with pytest.raises(ReferenceQualityError, match="invalid_reference_count") as error:
        build_template([_dynamic(prop_step=0.006)])
    assert error.value.details["required_reference_count"] == 2
    one_dynamic = build_template(
        [_dynamic(prop_step=0.006)] * 2,
    ).to_dict() | {"reference_count": 1}
    with pytest.raises(ValueError, match="invalid_schema"):
        MovementTemplate.from_dict(one_dynamic)


def test_static_reference_tolerates_yolo_jitter_and_an_isolated_prop_miss():
    assert build_template([_grip(prop_jitter=0.02)], movement_behavior="static")
    assert build_template([_grip(prop_miss={6})], movement_behavior="static")
    assert build_template([_grip(hand_miss={5})], movement_behavior="static")


def test_static_reference_builds_at_low_ai_cadence():
    # 5 Hz used to leave < 8 samples in the 800 ms hold and always failed.
    template = build_template([_grip(count=7, interval=200)], movement_behavior="static")
    assert evaluate_completion(template, _grip(count=7, interval=200)) == MOVEMENT_COMPLETED


def test_static_reference_requires_the_prop_and_the_hand():
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage") as prop:
        build_template([_grip(prop_miss=set(range(0, 12, 2)) | {1, 3})], movement_behavior="static")
    assert prop.value.details["prop_coverage"] < 0.6
    with pytest.raises(ReferenceQualityError, match="insufficient_hand_coverage") as hand:
        build_template([_grip(hand_miss=set(range(1, 12)) - {6})], movement_behavior="static")
    assert hand.value.details["reference_index"] == 0


def test_partial_second_hand_reports_the_hand_that_needs_tracking():
    reference = tuple(replace(frame, hands={
        **frame.hands,
        **({"right:0:0": Landmark(0.6, 0.5)} if index < 5 else {}),
    }) for index, frame in enumerate(_grip()))
    with pytest.raises(ReferenceQualityError, match="insufficient_hand_coverage") as error:
        build_template([reference], movement_behavior="static")
    assert error.value.details["hand_side"] == "right"
    assert error.value.details["hand_coverage"] == pytest.approx(0.3, abs=0.001)


def test_static_reference_rejects_a_moving_final_position():
    with pytest.raises(ReferenceQualityError, match="unstable_static_reference"):
        build_template([_grip(drift=0.02)], movement_behavior="static")


def test_static_reference_needs_enough_hold_samples_not_a_second_example():
    with pytest.raises(ReferenceQualityError, match="insufficient_tracking_samples") as short:
        build_template([_grip(count=6)], movement_behavior="static")  # 500 ms span
    assert short.value.details["required_sample_count"] == 6
    assert short.value.details["hold_sample_count"] == 6
    assert short.value.details["hold_duration_ms"] == 500
    assert short.value.details["required_hold_sample_count"] == 4
    assert short.value.details["required_hold_ms"] == 800


# --- Static assessment ------------------------------------------------------

@pytest.fixture(scope="module")
def static_template():
    return build_template([_grip()], movement_behavior="static")


def test_static_assessment_accepts_position_offset_jitter_and_short_gaps(static_template):
    assert evaluate_completion(static_template, _grip(hand_dx=0.03)) == MOVEMENT_COMPLETED
    assert evaluate_completion(static_template, _grip(prop_jitter=0.02)) == MOVEMENT_COMPLETED
    assert evaluate_completion(static_template, _grip(hand_miss={7})) == MOVEMENT_COMPLETED


def test_static_same_grip_with_arm_offset_completes_with_lower_score(static_template):
    # Same wrist-relative grip, hand placed 0.15 shoulder widths away.
    offset = _grip(hand_dx=0.06, prop_jitter=0.01)
    assert evaluate_completion(static_template, offset) == MOVEMENT_COMPLETED
    exact = compare_sequence(static_template, _grip(), assessment=True).total
    assert compare_sequence(static_template, offset, assessment=True).total < exact
    assert evaluate_completion(static_template, _grip(hand_dx=0.06, tip=0.47)) != MOVEMENT_COMPLETED


def test_static_assessment_rejects_wrong_grip_missing_prop_and_motion(static_template):
    assert evaluate_completion(static_template, _grip(tip=0.41)) != MOVEMENT_COMPLETED
    assert evaluate_completion(static_template, _grip(prop=False)) != MOVEMENT_COMPLETED
    assert evaluate_completion(static_template, _grip(drift=0.02)) != MOVEMENT_COMPLETED
    assert evaluate_completion(static_template, _grip(count=6)) != MOVEMENT_COMPLETED


# --- Dynamic authoring ------------------------------------------------------

@pytest.mark.parametrize("kwargs", (
    {"tip_step": 0.004},                      # small grip transition
    {"wrist_step": 0.003, "prop_step": 0.002},  # arm-led, small prop travel
    {"prop_step": 0.006},                     # prop path, little body motion
))
def test_small_dynamic_movements_build_and_complete(kwargs):
    template = build_template([_dynamic(**kwargs), _dynamic(count=10, interval=120, **kwargs)])
    assert template.movement_behavior == "dynamic"
    assert evaluate_completion(template, _dynamic(**kwargs)) == MOVEMENT_COMPLETED
    slower = _retime(_dynamic(**kwargs), 200)
    faster = _retime(_dynamic(**kwargs), 60)
    assert evaluate_completion(template, slower) == MOVEMENT_COMPLETED
    assert evaluate_completion(template, faster) == MOVEMENT_COMPLETED
    stationary = _dynamic(noise=0.01)
    assert evaluate_completion(template, stationary) != MOVEMENT_COMPLETED
    halfway = _dynamic(**kwargs)[:6] + tuple(
        replace(_dynamic(**kwargs)[5], timestamp_ms=index * 100) for index in range(6, 12)
    )
    assert evaluate_completion(template, halfway) != MOVEMENT_COMPLETED


def _offset(samples, dx):
    """Shift arms, hands and prop sideways; shoulders (the anchor) stay put."""
    move = lambda p: Landmark(p.x + dx, p.y)  # noqa: E731
    return tuple(replace(
        frame,
        pose={k: (p if k in ("11", "12") else move(p)) for k, p in frame.pose.items()},
        hands={k: move(p) for k, p in frame.hands.items()},
        prop=move(frame.prop) if frame.prop else None,
    ) for frame in samples)


@pytest.mark.parametrize("step", ({"prop_step": 0.006}, {"tip_step": 0.004}))
def test_recognizable_near_match_completes_but_scores_below_close_match(step):
    template = build_template([_dynamic(**step), _dynamic(count=10, interval=120, **step)])
    smaller = {key: value * 0.65 for key, value in step.items()}
    near = _offset(_dynamic(noise=0.004, **smaller), 0.04)
    assert evaluate_completion(template, near) == MOVEMENT_COMPLETED
    close = compare_sequence(template, _dynamic(**step), assessment=True)
    assert compare_sequence(template, near, assessment=True).total < close.total
    reversed_ = {key: -value for key, value in step.items()}
    assert evaluate_completion(template, _dynamic(**reversed_)) != MOVEMENT_COMPLETED
    too_small = {key: value * 0.3 for key, value in step.items()}
    assert evaluate_completion(template, _dynamic(**too_small)) != MOVEMENT_COMPLETED


def test_small_dynamic_movement_tolerates_path_noise_and_short_prop_loss():
    template = build_template([_dynamic(prop_step=0.006), _dynamic(prop_step=0.006, count=10)])
    noisy = _dynamic(prop_step=0.006, noise=0.003)
    assert evaluate_completion(template, noisy) == MOVEMENT_COMPLETED
    assert evaluate_completion(
        template, _dynamic(prop_step=0.006, prop_miss={5}),
    ) == MOVEMENT_COMPLETED


def test_small_prop_only_movement_uses_learned_units_to_find_its_start():
    moving = tuple(FrameSample(
        index * 100, prop=Landmark(0.4 + 0.003 * index, 0.5),
        prop_metadata={"track_id": 1},
    ) for index in range(12))
    template = build_template([moving, moving])
    assert evaluate_completion(template, moving) == MOVEMENT_COMPLETED
    stationary = tuple(replace(sample, prop=Landmark(0.4, 0.5)) for sample in moving)
    assert evaluate_completion(template, stationary) != MOVEMENT_COMPLETED


def test_toss_release_catch_builds_from_two_references():
    path = [0, 0, .4, .6, .4, 0, 0, 0]
    heights = [0, 0, -.04, -.10, -.04, 0, 0, 0]
    toss = tuple(FrameSample(
        i * 100, pose={"11": Landmark(.3, .3), "12": Landmark(.7, .3)},
        hands={"left": Landmark(0, 0)}, prop=Landmark(x, heights[i]),
    ) for i, x in enumerate(path))
    template = build_template([toss, _retime(toss, 110)])
    assert template.feature_capabilities["release_catch"] is True


def test_stationary_jitter_and_single_spikes_are_not_movement():
    for reference in (_dynamic(noise=0.01), _dynamic(noise=0.01, spike_at=6)):
        with pytest.raises(ReferenceQualityError, match="no_meaningful_motion") as error:
            build_template([reference, reference])
        assert error.value.details["movement_signals"] == []
        assert error.value.details["reference_index"] == 0


def test_temporary_prop_loss_keeps_a_hand_led_reference_but_mostly_missing_fails():
    kept = _dynamic(tip_step=0.004, prop_miss={4, 5, 6})
    assert build_template([kept, _dynamic(tip_step=0.004)])
    mostly_missing = _dynamic(tip_step=0.004, prop_miss=set(range(4, 12)))
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage"):
        build_template([mostly_missing, _dynamic(tip_step=0.004)])


def test_inconsistent_dynamic_references_are_rejected_with_guidance():
    with pytest.raises(ReferenceQualityError, match="inconsistent_dynamic_references") as error:
        build_template([_dynamic(prop_step=0.006), _dynamic(prop_step=-0.006)])
    assert error.value.details["reference_index"] == 1
    assert websocket_api._human_error_message("inconsistent_dynamic_references").startswith(
        "The two examples show different movements"
    )


def test_dynamic_builds_at_low_ai_cadence():
    assert build_template([_dynamic(count=6, interval=200, prop_step=0.012)] * 2)


# --- Forgiving dynamic authoring and execution ----------------------------------

def _arc(count=20, interval=100, *, amp=0.12, start=(0.0, 0.0), shift=(0.0, 0.0), noise=0.0,
         reach=1.0, lead=0, tail=0, prop_miss=(), hand_miss=(), pose_miss=(), prop=True):
    """Arm-led out-and-up arc carrying the prop, with optional idle lead/tail.

    ``start`` offsets the arm and prop from their learned position, ``shift``
    moves the whole body in the frame, and ``reach`` stops the path early.
    """
    frames = []
    for k in range(lead + count + tail):
        t = reach * min(max(k - lead, 0), count - 1) / (count - 1)
        sx, sy = shift
        wx = 0.40 + start[0] + amp * t + noise * _noise(k, 1) + sx
        wy = 0.55 + start[1] - 0.8 * amp * math.sin(math.pi * t) + noise * _noise(k, 2) + sy
        pose = {"11": Landmark(0.3 + sx, 0.3 + sy), "12": Landmark(0.7 + sx, 0.3 + sy),
                "13": Landmark(0.35 + sx, 0.42 + sy), "15": Landmark(wx, wy)}
        frames.append(FrameSample(
            k * interval,
            {} if k in pose_miss else pose,
            {} if k in hand_miss else _hand(wx, wy, wx + 0.03),
            None if (not prop or k in prop_miss) else Landmark(
                wx + 0.02 + noise * _noise(k, 3), wy - 0.05 + noise * _noise(k, 4)),
            {"track_id": 1},
        ))
    return tuple(frames)


@pytest.fixture(scope="module")
def arc_template():
    return build_template([_arc(), _arc(count=18, interval=110)])


@pytest.mark.parametrize("first", (
    _arc(hand_miss=set(range(6, 12))),          # 700 ms Hands loss
    _arc(hand_miss=set(range(0, 20, 3))),       # 65% hand coverage, 1-frame drops
    _arc(pose_miss=set(range(6, 12))),          # 700 ms Pose loss on an arm-led move
    _arc(prop_miss=set(range(5, 14))),          # 1 s YOLO loss
    _arc(start=(0.05, 0.04)),                   # different starting position
    _arc(shift=(0.10, 0.05)),                   # different body placement in frame
    _arc(count=26, interval=90),                # slower, different timing
    _arc(noise=0.01),                           # noisy path
    _arc(lead=8, tail=6),                       # idle before and after the move
    _arc(amp=0.07),                             # smaller second demonstration
))
def test_imperfect_dynamic_references_still_build(first):
    template = build_template([first, _arc(count=18, interval=110)])
    assert template.movement_behavior == "dynamic"
    assert "prop_translation" in template.required_modalities


def test_dynamic_references_still_reject_stationary_missing_prop_and_mostly_lost_hand():
    still = _arc(amp=0.0, noise=0.004)
    with pytest.raises(ReferenceQualityError, match="no_meaningful_motion"):
        build_template([still, still])
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage"):
        build_template([_arc(prop=False), _arc()])
    with pytest.raises(ReferenceQualityError, match="insufficient_hand_coverage"):
        build_template([_arc(hand_miss=set(range(3, 20))), _arc()], ("hands",))


@pytest.mark.parametrize("attempt", (
    _arc(reach=0.8),                            # stops before the learned end
    _arc(start=(0.06, 0.05)),                   # starts somewhere else
    _arc(amp=0.084, noise=0.004),               # 70% size, slightly noisy
    _arc(noise=0.015),                          # noisy path
    _arc(lead=10, tail=8),                      # idle before and after
    _arc(hand_miss=set(range(6, 11))),          # 600 ms Hands loss
    _arc(prop_miss=set(range(6, 12))),          # 700 ms YOLO loss
    _retime(_arc(), 60),                        # faster
    _retime(_arc(), 180),                       # slower
))
def test_approximately_correct_dynamic_attempts_complete(arc_template, attempt):
    assert evaluate_completion(arc_template, attempt) == MOVEMENT_COMPLETED
    assert compare_sequence(arc_template, attempt, assessment=True).validation.valid


def test_incorrect_dynamic_attempts_still_do_not_complete(arc_template):
    backwards = _arc()
    backwards = tuple(replace(frame, timestamp_ms=index * 100)
                      for index, frame in enumerate(reversed(backwards)))
    assert evaluate_completion(arc_template, backwards) != MOVEMENT_COMPLETED
    assert evaluate_completion(arc_template, _arc(amp=0.0, noise=0.004)) != MOVEMENT_COMPLETED
    assert evaluate_completion(arc_template, _arc(reach=0.35)) != MOVEMENT_COMPLETED
    # Arm and hand perform the arc while the prop is set down and never moves.
    set_down = tuple(replace(frame, prop=Landmark(0.42, 0.50)) for frame in _arc())
    assert evaluate_completion(arc_template, set_down) != MOVEMENT_COMPLETED


def test_similarity_sets_the_dynamic_score_not_whether_it_completes(arc_template):
    close = _arc()
    weaker = _arc(start=(0.06, 0.05))
    assert evaluate_completion(arc_template, close) == MOVEMENT_COMPLETED
    assert evaluate_completion(arc_template, weaker) == MOVEMENT_COMPLETED
    high = compare_sequence(arc_template, close, assessment=True).total
    low = compare_sequence(arc_template, weaker, assessment=True).total
    assert 0 < low < high <= 12


def test_live_completion_window_drops_idle_prefix_but_keeps_the_movement(arc_template):
    from assessment.custom_movement.completion import live_completion_window

    idle_then_move = _arc(lead=250, tail=5)          # 25 s idle, then the arc
    window = live_completion_window(arc_template, idle_then_move)
    assert len(window) < 80
    assert window[-1] is idle_then_move[-1]
    assert evaluate_completion(arc_template, window) == MOVEMENT_COMPLETED
    static = build_template([_grip()], movement_behavior="static")
    assert live_completion_window(static, _grip()) == _grip()


def _assessment_session(template, samples, progress):
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=template.to_dict(),
    )
    session._custom_samples = list(samples)
    session._custom_assessment_progress = progress
    return session


def test_every_usable_dynamic_attempt_produces_a_score_payload(arc_template):
    totals = {}
    for name, attempt in (("close", _arc()), ("weaker", _arc(start=(0.06, 0.05)))):
        session = _assessment_session(arc_template, attempt, MOVEMENT_COMPLETED)
        payload = session.finish_custom_assessment()
        session.close()
        assert payload["movement_completed"] is True
        assert payload["max_total"] == 12
        totals[name] = payload["total"]
    assert 0 < totals["weaker"] < totals["close"]
    # A timed-out attempt with a temporary Hands loss is still scored, not
    # rejected as track loss.
    from assessment.custom_movement.completion import MOVEMENT_DETECTED

    partial = _arc(reach=0.35, hand_miss=set(range(6, 11)))
    session = _assessment_session(arc_template, partial, MOVEMENT_DETECTED)
    payload = session.finish_custom_assessment()
    session.close()
    assert payload["movement_completed"] is False
    assert 0 < payload["total"] <= websocket_api._CUSTOM_INCOMPLETE_MAX_TOTAL


# --- Duration / sample diagnostics ---------------------------------------------

def test_integrity_separates_duration_samples_prop_and_gaps():
    with pytest.raises(ReferenceQualityError, match="reference_duration_too_short") as short:
        check_reference_integrity(_grip(count=7), clip_duration_ms=600)
    assert (short.value.details["duration_ms"], short.value.details["required_duration_ms"]) == (
        600, MIN_REFERENCE_DURATION_MS,
    )
    with pytest.raises(ReferenceQualityError, match="insufficient_tracking_samples") as sparse:
        check_reference_integrity(_grip(count=4, interval=1300), clip_duration_ms=5200)
    assert sparse.value.details["duration_ms"] == 5200
    assert (sparse.value.details["sample_count"], sparse.value.details["required_sample_count"]) == (4, 6)
    half_prop = _grip(prop_miss=set(range(6)))
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage"):
        check_reference_integrity(half_prop, clip_duration_ms=1200, movement_behavior="static")
    one_second_miss = _grip(count=24, prop_miss=set(range(8, 17)))
    with pytest.raises(ReferenceQualityError, match="excessive_tracking_gap") as gap:
        check_reference_integrity(one_second_miss, clip_duration_ms=2400, movement_behavior="static")
    assert gap.value.details["longest_tracking_gap_ms"] == 1000
    # Dynamic references tolerate these temporary YOLO losses ...
    assert check_reference_integrity(half_prop, clip_duration_ms=1200)["required_prop_coverage"] == 0.4
    assert check_reference_integrity(one_second_miss, clip_duration_ms=2400)
    # ... but not a mostly or completely missing prop.
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage"):
        check_reference_integrity(_grip(prop_miss=set(range(8))), clip_duration_ms=1200)
    with pytest.raises(ReferenceQualityError, match="insufficient_prop_coverage"):
        check_reference_integrity(_grip(prop=False), clip_duration_ms=1200)
    quality = check_reference_integrity(_grip(), clip_duration_ms=1200)
    assert quality["sample_count"] == 12 and quality["prop_coverage"] == 1.0


def _session_with_clip(frame_count: int):
    session = websocket_api.VisionSession("Custom Movement", session_mode="custom_capture")
    session._lifecycle = websocket_api.SESSION_ACTIVE
    session._custom_person_count = 1
    session._custom_person_observed_at = time.monotonic()
    session._custom_capture_visible = (True, True, True)
    session._custom_capture_observed_at = time.monotonic()
    assert session.start_custom_capture(duration_seconds=15) == (True, None)
    recorder = session._custom_video_recorder
    started = recorder.started
    recorder.path.write_bytes(b"test video")
    recorder.stop = lambda: SimpleNamespace(
        local_path=str(recorder.path),
        frame_capture_times=tuple(started + i * .1 for i in range(frame_count)),
        fps=10.0,
        encoded_duration_ms=frame_count * 100,
        video_ms_for_capture=lambda observed: max(0, round((observed - started) * 1000)),
    )
    return session, started


@pytest.fixture(autouse=True)
def _fake_recorder(monkeypatch, tmp_path):
    class FakeRecorder:
        def __init__(self, **kwargs):
            self.started = time.monotonic()
            self.path = tmp_path / f"reference_{id(self)}.mp4"

        def start(self):
            pass

        def cancel(self):
            self.path.unlink(missing_ok=True)

    monkeypatch.setattr(websocket_api, "SubmissionRecorder", FakeRecorder)


def _stop_with(session, started, samples):
    session._custom_samples = list(samples)
    session._custom_sample_capture_times = [started + s.timestamp_ms / 1000 for s in samples]
    return session.stop_custom_capture()


def test_long_clip_with_few_samples_is_a_tracking_problem_not_too_short():
    session, started = _session_with_clip(52)
    accepted, code, quality = _stop_with(session, started, _grip(count=4, interval=1300))
    assert (accepted, code) == (False, "insufficient_tracking_samples")
    assert quality["duration_ms"] == 5200
    assert quality["sample_count"] == 4
    assert "too short" not in websocket_api._human_error_message(code)
    session.close()


def test_short_clip_reports_duration_and_static_hold_guidance():
    session, started = _session_with_clip(6)
    accepted, code, quality = _stop_with(session, started, _grip(count=6))
    assert (accepted, code) == (False, "reference_duration_too_short")
    assert (quality["duration_ms"], quality["required_duration_ms"]) == (600, 1000)
    assert "0.8 seconds" in websocket_api._human_error_message(code)
    session.close()


def test_one_static_reference_session_builds_and_diagnostics_travel_in_ack():
    session, started = _session_with_clip(12)
    accepted, code, quality = _stop_with(session, started, _grip())
    assert (accepted, code) == (True, None)
    assert quality["duration_ms"] == 1200 and quality["hand_coverage"] == 1.0
    with pytest.raises(ReferenceQualityError, match="invalid_reference_count") as dynamic:
        session.build_custom_template("dynamic")
    assert dynamic.value.details == {
        "reason": "invalid_reference_count", "reference_count": 1, "required_reference_count": 2,
    }
    ack = CommandAck(request_id="r", action="build_custom_template", accepted=False,
                     error_code=dynamic.value.code, reference_quality=dynamic.value.details)
    assert ack.model_dump()["reference_quality"]["required_reference_count"] == 2
    template = session.build_custom_template("static")
    assert template["reference_count"] == 1 and template["movement_behavior"] == "static"
    session.close()


@pytest.mark.parametrize("code", (
    "reference_duration_too_short", "insufficient_tracking_samples", "insufficient_prop_coverage",
    "excessive_tracking_gap", "no_meaningful_motion", "inconsistent_dynamic_references",
    "invalid_trim_range", "invalid_reference_count",
))
def test_every_authoring_code_has_specific_guidance(code):
    assert websocket_api._human_error_message(code) != "The WebSocket command was rejected."


def test_one_long_prop_gap_does_not_discard_a_timed_out_dynamic_attempt(arc_template):
    # Field case: 30 s at ~9 FPS, good overall coverage, one 1.4 s YOLO loss.
    from assessment.custom_movement.completion import MOVEMENT_DETECTED

    attempt = _arc(reach=0.35, tail=40, prop_miss=set(range(30, 44)))
    session = _assessment_session(arc_template, attempt, MOVEMENT_DETECTED)
    payload = session.finish_custom_assessment()
    session.close()
    assert payload["movement_completed"] is False
    assert 0 < payload["total"] <= websocket_api._CUSTOM_INCOMPLETE_MAX_TOTAL


def test_attempt_where_the_prop_is_never_seen_reports_prop_not_detected(arc_template):
    # Field case: the bottle stayed out of view (0% YOLO confirmation).
    from assessment.custom_movement.completion import MOVEMENT_DETECTED

    session = _assessment_session(arc_template, _arc(prop=False, tail=40), MOVEMENT_DETECTED)
    with pytest.raises(ValueError, match="prop_not_detected"):
        session.finish_custom_assessment()
    session.close()
    assert "prop was not detected" in websocket_api._human_error_message("prop_not_detected")


def _two_hand(samples):
    """Add a mirrored right hand to each frame that has a left hand."""
    return tuple(replace(frame, hands={
        **frame.hands,
        **{key.replace("left", "right"): Landmark(point.x + 0.2, point.y)
           for key, point in frame.hands.items()},
    }) for frame in samples)


def test_one_hand_attempt_of_a_two_hand_movement_is_scored_not_rejected():
    # Field case: template learned both hands; the left hand was seen 3%.
    from assessment.custom_movement.completion import MOVEMENT_DETECTED

    template = build_template([_two_hand(_arc()), _two_hand(_arc(count=18, interval=110))])
    assert template.required_hand_sides == ("left", "right")
    right_only = tuple(replace(frame, hands={k: p for k, p in frame.hands.items()
                                             if k.startswith("right")})
                       for frame in _two_hand(_arc(tail=20)))
    session = _assessment_session(template, right_only, MOVEMENT_DETECTED)
    payload = session.finish_custom_assessment()
    session.close()
    assert payload["movement_completed"] is False
    assert 0 < payload["total"] <= websocket_api._CUSTOM_INCOMPLETE_MAX_TOTAL
    assert any("left hand was not visible" in line for line in payload["feedback"])
    # With no hand at all it is still unassessable.
    no_hands = tuple(replace(frame, hands={}) for frame in right_only)
    session = _assessment_session(template, no_hands, MOVEMENT_DETECTED)
    with pytest.raises(ValueError, match="missing_modality|track_loss"):
        session.finish_custom_assessment()
    session.close()
