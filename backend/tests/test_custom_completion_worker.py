"""Live Custom completion runs off the AI tick on a latest-state worker."""

import threading
import time

import numpy as np
import pytest

from assessment.custom_movement.completion import (
    MOVEMENT_COMPLETED,
    MOVEMENT_DETECTED,
    WAITING_FOR_MOVEMENT,
)
from api import websocket as websocket_api
from vision.camera import CapturedFrame
from test_custom_movement_session import _template


def _job(worker, count=1, **kwargs):
    return websocket_api._CustomCompletionJob(
        generation=worker.generation, recent=(), full=None,
        sample_count=count, need_progress_estimate=False, **kwargs,
    )


class _GatedEvaluate:
    """Evaluation double that blocks until released and tracks concurrency."""

    def __init__(self, progress=MOVEMENT_DETECTED):
        self.progress = progress
        self.release = threading.Event()
        self.started = threading.Event()
        self.lock = threading.Lock()
        self.active = 0
        self.max_active = 0
        self.seen: list[int] = []

    def __call__(self, job):
        with self.lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
            self.seen.append(job.sample_count)
        self.started.set()
        self.release.wait(5)
        with self.lock:
            self.active -= 1
        return websocket_api._CustomCompletionResult(
            job=job, progress=self.progress, attempt_start_ms=None,
            movement_start_index=None, progress_estimate=None,
        )


@pytest.fixture
def gated():
    evaluate = _GatedEvaluate()
    worker = websocket_api._LatestCompletionWorker(evaluate)
    yield evaluate, worker
    evaluate.release.set()
    worker.shutdown()


def test_single_in_flight_and_busy_submissions_collapse_to_newest(gated):
    evaluate, worker = gated
    worker.submit(_job(worker, 1))
    assert evaluate.started.wait(2)
    for count in (2, 3, 4):
        worker.submit(_job(worker, count))
    evaluate.release.set()
    assert worker.drain(2)
    assert evaluate.max_active == 1
    assert evaluate.seen == [1, 4]
    assert worker.take_result().job.sample_count == 4


def test_stale_generation_result_is_dropped(gated):
    evaluate, worker = gated
    worker.submit(_job(worker, 1))
    assert evaluate.started.wait(2)
    worker.submit(_job(worker, 2))
    worker.invalidate()
    evaluate.release.set()
    assert worker.drain(2)
    assert evaluate.seen == [1]
    assert worker.take_result() is None


def test_evaluation_error_does_not_wedge_worker():
    calls = []

    def evaluate(job):
        calls.append(job.sample_count)
        if job.sample_count == 1:
            raise RuntimeError("boom")
        return websocket_api._CustomCompletionResult(
            job=job, progress=MOVEMENT_DETECTED, attempt_start_ms=None,
            movement_start_index=None, progress_estimate=None,
        )

    worker = websocket_api._LatestCompletionWorker(evaluate)
    try:
        worker.submit(_job(worker, 1))
        assert worker.drain(2)
        worker.submit(_job(worker, 2))
        assert worker.drain(2)
        assert calls == [1, 2]
        assert worker.take_result().job.sample_count == 2
    finally:
        worker.shutdown()


def _assessment_session(monkeypatch, evaluate_segment):
    monkeypatch.setattr(
        websocket_api, "evaluate_custom_assessment_segment", evaluate_segment,
    )
    monkeypatch.setattr(
        websocket_api, "find_custom_assessment_start_index", lambda *_: 0,
    )
    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_assessment",
        custom_movement_template=_template().to_dict(),
    )
    session._custom_samples = []
    session._custom_capture_started_at = time.monotonic()
    return session


def _record(session, count, frame=None):
    frame = np.zeros((20, 20, 3), dtype=np.uint8) if frame is None else frame
    normalized = websocket_api._NormalizedFrameDetections(
        primary=(), bottles=(), shakers=(), annotation=(),
        selected_detected=False, selected_count=0,
    )
    for _ in range(count):
        session._custom_assessment_last_evaluated_at = None
        session._record_custom_sample(
            captured=CapturedFrame(frame, time.monotonic(), 1), frame=frame,
            normalized=normalized, hands=None, pose=None, yolo_attempted=True,
        )


def test_slow_completion_does_not_block_sample_recording(monkeypatch):
    release = threading.Event()
    started = threading.Event()

    def slow(template, samples):
        started.set()
        release.wait(5)
        return MOVEMENT_COMPLETED, samples[0].timestamp_ms

    session = _assessment_session(monkeypatch, slow)
    try:
        began = time.perf_counter()
        _record(session, 8)
        assert started.wait(2)
        _record(session, 4)
        # The AI path returned while evaluation is still blocked.
        assert time.perf_counter() - began < 1.0
        assert session._custom_assessment_progress == WAITING_FOR_MOVEMENT
        assert len(session._custom_samples) == 12
        release.set()
        assert session._custom_completion_worker.drain(2)
        job = session._apply_custom_completion_result()
        assert job is not None
        # The newest collapsed snapshot completed: the recording ends at its
        # confirming sample, and evidence comes from that job's own frame.
        assert session._custom_assessment_progress == MOVEMENT_COMPLETED
        assert len(session._custom_samples) == job.sample_count
        assert len(session._custom_sample_capture_times) == job.sample_count
        assert job.frame is not None
    finally:
        release.set()
        session.close()


def test_completed_state_never_regresses_and_retry_evaluates(monkeypatch):
    progress = [MOVEMENT_COMPLETED]
    session = _assessment_session(
        monkeypatch, lambda template, samples: (progress[0], None),
    )
    try:
        _record(session, 8)
        assert session._custom_completion_worker.drain(2)
        assert session._apply_custom_completion_result() is not None
        assert session._custom_assessment_progress == MOVEMENT_COMPLETED

        # A later, slower result for the same attempt cannot regress it.
        progress[0] = WAITING_FOR_MOVEMENT
        worker = session._custom_completion_worker
        worker.submit(websocket_api._CustomCompletionJob(
            generation=worker.generation,
            recent=tuple(session._custom_samples), full=None,
            sample_count=len(session._custom_samples),
            need_progress_estimate=False,
        ))
        assert worker.drain(2)
        assert session._apply_custom_completion_result() is None
        assert session._custom_assessment_progress == MOVEMENT_COMPLETED

        # A retry starts a new generation that evaluates normally.
        session._custom_samples = None
        session._custom_capture_started_at = None
        session._lifecycle = websocket_api.SESSION_ACTIVE
        ok, _ = session.start_custom_capture(duration_seconds=30)
        assert ok
        progress[0] = MOVEMENT_DETECTED
        _record(session, 8)
        assert worker.drain(2)
        session._apply_custom_completion_result()
        assert session._custom_assessment_progress == MOVEMENT_DETECTED
    finally:
        session.close()


def test_result_from_previous_attempt_never_applies_to_retry(monkeypatch):
    release = threading.Event()
    started = threading.Event()

    def slow(template, samples):
        started.set()
        release.wait(5)
        return MOVEMENT_COMPLETED, None

    session = _assessment_session(monkeypatch, slow)
    try:
        _record(session, 8)
        assert started.wait(2)
        session._custom_samples = None
        session._custom_capture_started_at = None
        session._lifecycle = websocket_api.SESSION_ACTIVE
        ok, _ = session.start_custom_capture(duration_seconds=30)
        assert ok
        release.set()
        assert session._custom_completion_worker.drain(2)
        assert session._apply_custom_completion_result() is None
        assert session._custom_assessment_progress == WAITING_FOR_MOVEMENT
    finally:
        release.set()
        session.close()


def test_stop_waits_briefly_then_invalidates_pending_work(monkeypatch):
    session = _assessment_session(
        monkeypatch, lambda template, samples: (MOVEMENT_DETECTED, None),
    )
    try:
        _record(session, 8)
        session.stop_custom_capture()
        worker = session._custom_completion_worker
        assert not worker.busy
        assert worker.take_result() is None
        # A job from the stopped generation is refused outright.
        stale = websocket_api._CustomCompletionJob(
            generation=worker.generation - 1, recent=(), full=None,
            sample_count=1, need_progress_estimate=False,
        )
        worker.submit(stale)
        assert not worker.busy
    finally:
        session.close()


def test_close_shuts_worker_down_without_waiting(monkeypatch):
    release = threading.Event()
    started = threading.Event()

    def slow(template, samples):
        started.set()
        release.wait(5)
        return MOVEMENT_COMPLETED, None

    session = _assessment_session(monkeypatch, slow)
    _record(session, 8)
    assert started.wait(2)
    began = time.perf_counter()
    session.close()
    assert time.perf_counter() - began < 1.0
    release.set()
    worker = session._custom_completion_worker
    assert worker.drain(2)
    assert worker.take_result() is None
