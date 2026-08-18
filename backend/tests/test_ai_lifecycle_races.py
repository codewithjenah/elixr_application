"""Lifecycle transitions must not mutate VisionSession state during AI analysis."""

from __future__ import annotations

import asyncio
import json
import threading
import time
from unittest.mock import MagicMock

import pytest

from assessment.hold_validator import HoldValidator
from assessment.rules.base import RuleResult
from assessment.scoring import RubricTracker
from api import websocket as websocket_api
from test_session_lifecycle import (
    StubCamera,
    StubHandsDetector,
    StubPoseDetector,
    _confirm_session_readiness,
    _patch_vision,
    _stable_readiness_snapshot,
)


_WAIT_S = 2.0
_STILL_BLOCKED_S = 0.2


class GatedHands(StubHandsDetector):
    """Hands detector that blocks in detect() until ``release`` is set."""

    instances: list["GatedHands"] = []

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.closed = False
        self.closed_during_detect = False
        self.in_detect = 0
        self.max_in_detect = 0
        self.entered = threading.Event()
        self.release = threading.Event()
        self.close_entered = threading.Event()
        GatedHands.instances.append(self)

    def detect(self, current_frame, bottle=None):
        self.detect_calls += 1
        self.in_detect += 1
        self.max_in_detect = max(self.max_in_detect, self.in_detect)
        try:
            self.entered.set()
            self.release.wait(timeout=_WAIT_S)
            if self.closed:
                self.closed_during_detect = True
            return None
        finally:
            self.in_detect -= 1

    def close(self):
        self.close_entered.set()
        self.closed = True


class GatedPose(StubPoseDetector):
    instances: list["GatedPose"] = []

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.closed = False
        self.closed_during_detect = False
        self.entered = threading.Event()
        self.release = threading.Event()
        GatedPose.instances.append(self)

    def detect(self, current_frame):
        self.detect_calls += 1
        self.entered.set()
        self.release.wait(timeout=_WAIT_S)
        if self.closed:
            self.closed_during_detect = True
        return None

    def close(self):
        self.closed = True


def _patch_gated_vision(monkeypatch):
    _patch_vision(monkeypatch)
    GatedHands.instances = []
    GatedPose.instances = []
    monkeypatch.setattr(websocket_api, "HandsDetector", GatedHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", GatedPose)
    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(
                feedback="ok",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        ),
    )


def _start_analyze(session: websocket_api.VisionSession) -> tuple[threading.Thread, list]:
    result: list = []

    def _run():
        result.append(session.analyze_tick())

    thread = threading.Thread(target=_run, name="elixr-test-analyze")
    thread.start()
    return thread, result


def _join(thread: threading.Thread) -> None:
    thread.join(timeout=_WAIT_S)
    assert not thread.is_alive(), f"{thread.name} did not finish"


def _release_all_gates() -> None:
    for hands in GatedHands.instances:
        hands.release.set()
    for pose in GatedPose.instances:
        pose.release.set()


@pytest.fixture(autouse=True)
def _ungate_detectors():
    yield
    _release_all_gates()


def test_begin_readiness_waits_for_in_flight_readiness_worker(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    hands = GatedHands.instances[-1]
    detector_id = id(hands)

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    done = threading.Event()

    def _begin_again():
        assert session.begin_readiness() is True
        done.set()

    begin_thread = threading.Thread(target=_begin_again, name="elixr-test-begin")
    begin_thread.start()
    assert not done.wait(_STILL_BLOCKED_S)
    assert not hands.closed
    assert id(session.hands_detector) == detector_id
    assert len(GatedHands.instances) == 1

    hands.release.set()
    _join(analyze_thread)
    _join(begin_thread)
    assert done.is_set()
    assert len(GatedHands.instances) == 1
    assert not hands.closed_during_detect
    session.close()


def test_confirm_readiness_waits_until_in_flight_ai_finishes(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    session._latest_readiness_snapshot = _stable_readiness_snapshot()
    session._latest_readiness_observed_at = time.monotonic()
    session._readiness_tracker.update = lambda _obs: _stable_readiness_snapshot()

    hands = GatedHands.instances[-1]
    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    result: list[tuple[bool, str | None]] = []
    done = threading.Event()

    def _confirm():
        result.append(session.confirm_readiness())
        done.set()

    confirm_thread = threading.Thread(target=_confirm, name="elixr-test-confirm")
    confirm_thread.start()
    assert not done.wait(_STILL_BLOCKED_S)
    assert session.readiness_confirmed is False

    hands.release.set()
    _join(analyze_thread)
    _join(confirm_thread)
    assert done.is_set()
    assert result == [(True, None)]
    assert session.readiness_confirmed is True
    session.close()


def test_activate_waits_and_does_not_reset_state_mid_analysis(monkeypatch):
    _patch_gated_vision(monkeypatch)
    record_calls = {"n": 0}
    hold_calls = {"n": 0}
    real_record = RubricTracker.record
    real_hold = HoldValidator.update

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    def tracking_hold(self, *args, **kwargs):
        hold_calls["n"] += 1
        return real_hold(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    monkeypatch.setattr(HoldValidator, "update", tracking_hold)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)
    tracker_before = session._readiness_tracker
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)
    assert session._frame_index == 1
    assert session.lifecycle == websocket_api.SESSION_READYING

    done = threading.Event()
    activate_result: list[tuple[bool, str | None]] = []

    def _activate():
        activate_result.append(session.activate())
        done.set()

    activate_thread = threading.Thread(target=_activate, name="elixr-test-activate")
    activate_thread.start()
    assert not done.wait(_STILL_BLOCKED_S)
    assert session.lifecycle == websocket_api.SESSION_READYING
    assert session._frame_index == 1
    assert session._readiness_tracker is tracker_before
    assert record_calls["n"] == 0
    assert hold_calls["n"] == 0

    hands.release.set()
    _join(analyze_thread)
    _join(activate_thread)
    assert done.is_set()
    assert activate_result == [(True, None)]
    assert session.lifecycle == websocket_api.SESSION_ACTIVE
    assert session._frame_index == 0
    assert session._readiness_tracker is None
    assert record_calls["n"] == 0
    assert hold_calls["n"] == 0
    session.close()


def test_detector_close_waits_until_detect_returns(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    close_done = threading.Event()

    def _close():
        session.close()
        close_done.set()

    close_thread = threading.Thread(target=_close, name="elixr-test-close")
    close_thread.start()
    assert not close_done.wait(_STILL_BLOCKED_S)
    assert not hands.closed
    assert not hands.close_entered.is_set()

    hands.release.set()
    _join(analyze_thread)
    _join(close_thread)
    assert close_done.is_set()
    assert hands.closed is True
    assert hands.closed_during_detect is False
    assert session.hands_detector is None


def test_second_analyze_tick_is_rejected_while_first_is_in_detect(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    hands = GatedHands.instances[-1]

    first_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    errors: list[BaseException] = []

    def _second():
        try:
            session.analyze_tick()
        except BaseException as exc:  # noqa: BLE001 — capture exact worker failure
            errors.append(exc)

    second_thread = threading.Thread(target=_second, name="elixr-test-analyze-2")
    second_thread.start()
    _join(second_thread)
    assert len(errors) == 1
    assert isinstance(errors[0], RuntimeError)
    assert "single in-flight" in str(errors[0])
    assert hands.max_in_detect == 1
    assert hands.detect_calls == 1

    hands.release.set()
    _join(first_thread)
    session.close()


def test_preview_continues_while_lifecycle_waits_for_ai(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    activate_done = threading.Event()

    def _activate():
        session.activate()
        activate_done.set()

    activate_thread = threading.Thread(target=_activate, name="elixr-test-activate")
    activate_thread.start()
    assert not activate_done.wait(_STILL_BLOCKED_S)

    previews = []
    for _ in range(3):
        previews.append(session.render_preview())
    assert any(message is not None for message in previews)
    assert not activate_done.is_set()
    assert session.lifecycle == websocket_api.SESSION_READYING

    hands.release.set()
    _join(analyze_thread)
    _join(activate_thread)
    assert activate_done.is_set()
    session.close()


def test_lifecycle_wait_does_not_block_asyncio_event_loop(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    async def _run():
        heartbeats: list[int] = []

        async def _beat():
            for index in range(8):
                heartbeats.append(index)
                await asyncio.sleep(0)

        beat_task = asyncio.create_task(_beat())
        activate_task = asyncio.create_task(asyncio.to_thread(session.activate))
        await asyncio.wait_for(beat_task, timeout=_WAIT_S)
        assert heartbeats == list(range(8))
        assert not activate_task.done()
        hands.release.set()
        await asyncio.wait_for(activate_task, timeout=_WAIT_S)
        assert activate_task.result() == (True, None)

    asyncio.run(_run())
    _join(analyze_thread)
    session.close()


def test_active_analysis_is_not_reset_by_idempotent_activate(monkeypatch):
    _patch_gated_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)
    assert session._frame_index == 1

    done = threading.Event()

    def _activate_again():
        again_ok, again_error = session.activate()
        assert (again_ok, again_error) == (True, None)
        done.set()

    activate_thread = threading.Thread(target=_activate_again, name="elixr-test-activate-id")
    activate_thread.start()
    assert not done.wait(_STILL_BLOCKED_S)
    assert session._frame_index == 1
    assert session._movement_state is None

    hands.release.set()
    _join(analyze_thread)
    _join(activate_thread)
    assert done.is_set()
    assert session._frame_index == 1
    session.close()


def test_stop_during_slow_inference_waits_and_does_not_leak(monkeypatch):
    _patch_gated_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

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
        deadline = time.monotonic() + _WAIT_S
        hands = None
        while time.monotonic() < deadline:
            session = session_ref.get("session")
            if session is not None and isinstance(session.hands_detector, GatedHands):
                hands = session.hands_detector
                if hands.entered.is_set():
                    break
            await asyncio.sleep(0)
        assert hands is not None
        assert hands.entered.is_set()

        stop_task = asyncio.create_task(websocket_api._stop_session_task(task))
        await asyncio.sleep(0)
        assert not stop_task.done()
        assert not hands.closed

        hands.release.set()
        await asyncio.wait_for(stop_task, timeout=_WAIT_S)
        await asyncio.sleep(0)
        leftover = [
            leftover_task
            for leftover_task in asyncio.all_tasks()
            if id(leftover_task) not in before and leftover_task is not asyncio.current_task()
        ]
        assert leftover == []
        assert StubCamera.instances[-1].released is True
        assert session_ref.get("session") is None
        assert hands.closed is True
        assert hands.closed_during_detect is False

    asyncio.run(_run())


def test_readying_to_active_does_not_duplicate_score_or_hold_samples(monkeypatch):
    _patch_gated_vision(monkeypatch)
    record_calls = {"n": 0}
    hold_calls = {"n": 0}
    real_record = RubricTracker.record
    real_hold = HoldValidator.update

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    def tracking_hold(self, *args, **kwargs):
        hold_calls["n"] += 1
        return real_hold(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    monkeypatch.setattr(HoldValidator, "update", tracking_hold)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)
    hands = GatedHands.instances[-1]

    analyze_thread, _ = _start_analyze(session)
    assert hands.entered.wait(timeout=_WAIT_S)

    activate_thread = threading.Thread(target=lambda: session.activate())
    activate_thread.start()
    hands.release.set()
    _join(analyze_thread)
    _join(activate_thread)
    assert record_calls["n"] == 0
    assert hold_calls["n"] == 0

    hands.release.set()
    message = session.analyze_tick()
    assert message is not None
    assert message.session_state == "active"
    assert record_calls["n"] == 1
    assert hold_calls["n"] == 1
    session.close()


def _install_lifecycle_state_gate(monkeypatch):
    """Hold the AI/lifecycle state lock after a lifecycle method acquires it.

    The reverse of the existing tests: lifecycle owns the lock first, then
    analyze_tick is attempted. That must be contention, not a duplicate AI
    worker.
    """
    entered = threading.Event()
    release = threading.Event()
    original = websocket_api.VisionSession._acquire_ai_state

    def gated(self, *, blocking):
        acquired = original(self, blocking=blocking)
        if blocking:
            entered.set()
            if not release.wait(timeout=_WAIT_S):
                self._release_ai_state()
                raise AssertionError("lifecycle state-lock gate was not released")
        return acquired

    monkeypatch.setattr(websocket_api.VisionSession, "_acquire_ai_state", gated)
    return entered, release


def _analyze_tick_outcome(session: websocket_api.VisionSession):
    try:
        return ("ok", session.analyze_tick())
    except BaseException as exc:  # noqa: BLE001 — the regression is this exception
        return ("err", exc)


def _run_lifecycle_while_holding_state_lock(
    monkeypatch,
    *,
    target,
    thread_name: str,
):
    entered, release = _install_lifecycle_state_gate(monkeypatch)
    result: list = []

    def _run():
        result.append(target())

    thread = threading.Thread(target=_run, name=thread_name)
    thread.start()
    return entered, release, thread, result


def test_analyze_tick_skips_when_activate_holds_state_lock(monkeypatch):
    _patch_vision(monkeypatch)
    record_calls = {"n": 0}
    hold_calls = {"n": 0}
    real_record = RubricTracker.record
    real_hold = HoldValidator.update

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    def tracking_hold(self, *args, **kwargs):
        hold_calls["n"] += 1
        return real_hold(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    monkeypatch.setattr(HoldValidator, "update", tracking_hold)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)
    detect_before = session.hands_detector.detect_calls

    entered, release, activate_thread, activate_result = (
        _run_lifecycle_while_holding_state_lock(
            monkeypatch,
            target=session.activate,
            thread_name="elixr-test-activate-owns-lock",
        )
    )
    try:
        assert entered.wait(timeout=_WAIT_S)
        assert session.lifecycle == websocket_api.SESSION_READYING

        outcome = _analyze_tick_outcome(session)
        assert outcome[0] == "ok", outcome[1]
        assert outcome[1] is None
        assert session.lifecycle == websocket_api.SESSION_READYING
        assert record_calls["n"] == 0
        assert hold_calls["n"] == 0
        assert session.hands_detector.detect_calls == detect_before
        assert session._ai_inflight == 0
        assert session._ai_lifecycle_skips >= 1

        previews = [session.render_preview() for _ in range(3)]
        assert any(message is not None for message in previews)
        assert session.lifecycle == websocket_api.SESSION_READYING
    finally:
        release.set()
        _join(activate_thread)

    assert activate_result == [(True, None)]
    assert session.lifecycle == websocket_api.SESSION_ACTIVE

    message = session.analyze_tick()
    assert message is not None
    assert message.session_state == "active"
    assert record_calls["n"] == 1
    assert hold_calls["n"] == 1
    session.close()


def test_analyze_tick_skips_when_confirm_readiness_holds_state_lock(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    session._latest_readiness_snapshot = _stable_readiness_snapshot()
    session._latest_readiness_observed_at = time.monotonic()
    session._readiness_tracker.update = lambda _obs: _stable_readiness_snapshot()
    detect_before = session.hands_detector.detect_calls

    entered, release, confirm_thread, confirm_result = (
        _run_lifecycle_while_holding_state_lock(
            monkeypatch,
            target=session.confirm_readiness,
            thread_name="elixr-test-confirm-owns-lock",
        )
    )
    try:
        assert entered.wait(timeout=_WAIT_S)
        assert session.readiness_confirmed is False

        outcome = _analyze_tick_outcome(session)
        assert outcome[0] == "ok", outcome[1]
        assert outcome[1] is None
        assert session.readiness_confirmed is False
        assert session.hands_detector.detect_calls == detect_before
    finally:
        release.set()
        _join(confirm_thread)

    assert confirm_result == [(True, None)]
    assert session.readiness_confirmed is True
    assert session.lifecycle == websocket_api.SESSION_READYING

    message = session.analyze_tick()
    assert message is not None
    assert message.session_state == "readying"
    session.close()


def test_analyze_tick_skips_when_begin_readiness_holds_state_lock(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.lifecycle == websocket_api.SESSION_PREPARED

    entered, release, begin_thread, begin_result = (
        _run_lifecycle_while_holding_state_lock(
            monkeypatch,
            target=session.begin_readiness,
            thread_name="elixr-test-begin-owns-lock",
        )
    )
    try:
        assert entered.wait(timeout=_WAIT_S)
        assert session.lifecycle == websocket_api.SESSION_PREPARED
        assert session.hands_detector is None

        outcome = _analyze_tick_outcome(session)
        assert outcome[0] == "ok", outcome[1]
        assert outcome[1] is None
        assert session.lifecycle == websocket_api.SESSION_PREPARED
        assert session.hands_detector is None
    finally:
        release.set()
        _join(begin_thread)

    assert begin_result == [True]
    assert session.lifecycle == websocket_api.SESSION_READYING
    assert session.hands_detector is not None

    message = session.analyze_tick()
    assert message is not None
    assert message.session_state == "readying"
    session.close()


def test_analyze_tick_skips_when_close_holds_state_lock(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    detector = session.hands_detector
    detect_before = detector.detect_calls
    close_done = threading.Event()

    entered, release, close_thread, _close_result = (
        _run_lifecycle_while_holding_state_lock(
            monkeypatch,
            target=lambda: (session.close(), close_done.set())[0],
            thread_name="elixr-test-close-owns-lock",
        )
    )
    try:
        assert entered.wait(timeout=_WAIT_S)
        assert session.lifecycle == websocket_api.SESSION_READYING
        assert session.hands_detector is detector

        outcome = _analyze_tick_outcome(session)
        assert outcome[0] == "ok", outcome[1]
        assert outcome[1] is None
        assert not close_done.is_set()
        assert detector.detect_calls == detect_before
        assert session.hands_detector is detector
    finally:
        release.set()
        _join(close_thread)

    assert close_done.is_set()
    assert session.lifecycle == websocket_api.SESSION_CLOSED
    assert session.hands_detector is None

    closed_outcome = _analyze_tick_outcome(session)
    assert closed_outcome == ("ok", None)


def test_lifecycle_state_lock_skip_does_not_deadlock_with_preview(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.begin_readiness() is True
    _confirm_session_readiness(session)

    entered, release, activate_thread, _activate_result = (
        _run_lifecycle_while_holding_state_lock(
            monkeypatch,
            target=session.activate,
            thread_name="elixr-test-activate-preview",
        )
    )
    try:
        assert entered.wait(timeout=_WAIT_S)

        preview_thread_result: list = []

        def _preview():
            preview_thread_result.append(session.render_preview())

        preview_thread = threading.Thread(target=_preview, name="elixr-test-preview")
        preview_thread.start()
        _join(preview_thread)
        assert any(item is not None for item in preview_thread_result)

        outcome = _analyze_tick_outcome(session)
        assert outcome == ("ok", None)
    finally:
        release.set()
        _join(activate_thread)

    assert session.lifecycle == websocket_api.SESSION_ACTIVE
    session.close()


def test_ai_loop_survives_activate_holding_state_lock(monkeypatch):
    """Production READYING→ACTIVE race: ai_loop tick during activate must not die."""
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    original = websocket_api.VisionSession.analyze_tick
    ai_may_run = threading.Event()
    ai_may_run.set()
    during_hold = threading.Event()
    tick_during_hold = threading.Event()
    hold_outcomes: list[tuple[str, object]] = []

    def wrapped_analyze(self):
        if not ai_may_run.wait(timeout=_WAIT_S):
            raise AssertionError("AI tick remained paused")
        observing = during_hold.is_set()
        try:
            result = original(self)
        except BaseException as exc:  # noqa: BLE001 — capture worker death
            if observing:
                hold_outcomes.append(("err", exc))
                tick_during_hold.set()
            raise
        if observing:
            hold_outcomes.append(("ok", result))
            tick_during_hold.set()
        return result

    monkeypatch.setattr(websocket_api.VisionSession, "analyze_tick", wrapped_analyze)

    original_ensure = websocket_api.VisionSession._ensure_detectors
    ensure_entered = threading.Event()
    ensure_release = threading.Event()

    def gated_ensure(self):
        ensure_entered.set()
        if not ensure_release.wait(timeout=_WAIT_S):
            raise AssertionError("activate ensure_detectors gate was not released")
        return original_ensure(self)

    async def _run():
        before = {id(task) for task in asyncio.all_tasks()}
        sent: list[str] = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        session_ref: dict = {"session": None}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=False,
                send_text=fake_send,
            )
        )
        deadline = time.monotonic() + _WAIT_S
        session = None
        while time.monotonic() < deadline:
            session = session_ref.get("session")
            if session is not None:
                break
            await asyncio.sleep(0)
        assert session is not None

        assert session.begin_readiness() is True
        _confirm_session_readiness(session)

        ai_may_run.clear()
        idle_deadline = time.monotonic() + _WAIT_S
        while time.monotonic() < idle_deadline:
            if session._ai_inflight == 0:
                break
            await asyncio.sleep(0)
        assert session._ai_inflight == 0

        monkeypatch.setattr(
            websocket_api.VisionSession,
            "_ensure_detectors",
            gated_ensure,
        )
        activate_task = asyncio.create_task(asyncio.to_thread(session.activate))
        try:
            assert await asyncio.to_thread(ensure_entered.wait, _WAIT_S)
            assert session.lifecycle == websocket_api.SESSION_READYING
            during_hold.set()
            ai_may_run.set()
            assert await asyncio.to_thread(tick_during_hold.wait, _WAIT_S)
            assert not loop_task.done()
            assert hold_outcomes
            assert all(kind == "ok" for kind, _value in hold_outcomes), hold_outcomes
            assert all(value is None for _kind, value in hold_outcomes)
            assert not any("pipeline_error" in payload for payload in sent)

            def _preview_count() -> int:
                count = 0
                for payload in sent:
                    try:
                        data = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    if data.get("message_type") == "preview_frame":
                        count += 1
                return count

            previews_before = _preview_count()
            preview_deadline = time.monotonic() + _WAIT_S
            while time.monotonic() < preview_deadline:
                if _preview_count() > previews_before:
                    break
                await asyncio.sleep(0)
            assert _preview_count() > previews_before
            assert not loop_task.done()
        finally:
            ensure_release.set()

        await asyncio.wait_for(activate_task, timeout=_WAIT_S)
        assert activate_task.result() == (True, None)
        assert session.lifecycle == websocket_api.SESSION_ACTIVE

        active_deadline = time.monotonic() + _WAIT_S
        saw_active = False
        while time.monotonic() < active_deadline:
            for payload in sent:
                try:
                    data = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                if data.get("session_state") == "active":
                    saw_active = True
                    break
            if saw_active:
                break
            await asyncio.sleep(0)
        assert saw_active
        assert not loop_task.done()

        await websocket_api._stop_session_task(loop_task)
        await asyncio.sleep(0)
        leftover = [
            leftover_task
            for leftover_task in asyncio.all_tasks()
            if id(leftover_task) not in before
            and leftover_task is not asyncio.current_task()
        ]
        assert leftover == []
        assert session_ref.get("session") is None
        assert not any("pipeline_error" in payload for payload in sent)

    asyncio.run(_run())
