"""Bounded submission recorder tests. No physical webcam."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from vision.submission_recorder import (
    SUBMISSION_TEMP_DIRNAME,
    SubmissionRecorder,
    SubmissionRecorderError,
    cleanup_orphan_submission_temp_files,
    submission_temp_dir,
)


class FakeWriter:
    def __init__(self, path: Path, *, fail_open: bool = False):
        self.path = path
        self.fail_open = fail_open
        self.frames: list[np.ndarray] = []
        self.released = False
        if not fail_open:
            path.write_bytes(b"")

    def isOpened(self) -> bool:
        return not self.fail_open

    def write(self, frame: np.ndarray) -> bool:
        self.frames.append(np.copy(frame))
        with self.path.open("ab") as handle:
            handle.write(b"frame")
        return True

    def release(self) -> None:
        self.released = True


def _frame(value: int = 40) -> np.ndarray:
    return np.full((16, 20, 3), value, dtype=np.uint8)


def _recorder(tmp_path: Path, *, now: list[float] | None = None, **kwargs):
    clock = now if now is not None else [0.0]

    def monotonic() -> float:
        return clock[0]

    writers: list[FakeWriter] = []

    def factory(path: Path, fps: float, size: tuple[int, int]) -> FakeWriter:
        writer = FakeWriter(path)
        writers.append(writer)
        return writer

    recorder = SubmissionRecorder(
        fps=20,
        max_duration_s=20,
        max_size_bytes=15 * 1024 * 1024,
        writer_factory=factory,
        temp_root=tmp_path,
        monotonic=monotonic,
        **kwargs,
    )
    return recorder, clock, writers


def test_start_stop_returns_metadata_without_bytes(tmp_path: Path):
    recorder, clock, writers = _recorder(tmp_path)
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    clock[0] = 1.5
    recorder.write_frame(_frame(80), captured_at_monotonic=1.5, sequence=2)
    metadata = recorder.stop()
    assert metadata.local_path.endswith(".mp4")
    assert "clip_" in Path(metadata.local_path).name
    assert metadata.video_duration_ms == 1500
    assert metadata.video_size_bytes > 0
    assert metadata.content_type == "video/mp4"
    assert metadata.sha256 is not None
    assert writers[0].released is True
    assert Path(metadata.local_path).exists()


def test_start_at_monotonic_zero_is_not_treated_as_missing(tmp_path: Path):
    recorder, clock, _writers = _recorder(tmp_path)
    assert clock[0] == 0.0
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    clock[0] = 0.25
    recorder.write_frame(_frame(80), captured_at_monotonic=0.25, sequence=2)
    metadata = recorder.stop()
    assert metadata.video_duration_ms == 250


def test_hard_duration_cap_finalizes_without_flutter(tmp_path: Path):
    recorder, clock, _writers = _recorder(tmp_path)
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    clock[0] = 20.0
    still_recording = recorder.write_frame(
        _frame(90), captured_at_monotonic=20.0, sequence=2
    )
    assert still_recording is False
    assert recorder.is_recording is False
    metadata = recorder.stop()
    assert metadata.video_duration_ms == 20000


def test_cap_task_finalize_then_stop_returns_same_metadata(tmp_path: Path):
    recorder, clock, _writers = _recorder(tmp_path)
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    clock[0] = 20.0
    first = recorder.finalize_due_to_cap()
    second = recorder.stop()
    assert first is not None
    assert second.local_path == first.local_path
    assert second.video_duration_ms == first.video_duration_ms


def test_stop_without_start_rejected(tmp_path: Path):
    recorder, _clock, _writers = _recorder(tmp_path)
    with pytest.raises(SubmissionRecorderError) as exc:
        recorder.stop()
    assert exc.value.code == "submission_not_recording"


def test_second_start_while_recording_rejected(tmp_path: Path):
    recorder, _clock, _writers = _recorder(tmp_path)
    recorder.start()
    with pytest.raises(SubmissionRecorderError) as exc:
        recorder.start()
    assert exc.value.code == "submission_already_recording"


def test_cancel_deletes_temp_file_and_is_idempotent(tmp_path: Path):
    recorder, _clock, writers = _recorder(tmp_path)
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    path = Path(tmp_path / SUBMISSION_TEMP_DIRNAME).glob("clip_*.mp4")
    existing = list(path)
    assert existing
    recorder.cancel()
    assert existing[0].exists() is False
    assert writers[0].released is True
    recorder.cancel()
    recorder.cleanup()


def test_writer_init_failure_does_not_leave_corrupt_file(tmp_path: Path):
    def factory(path: Path, fps: float, size: tuple[int, int]) -> FakeWriter:
        return FakeWriter(path, fail_open=True)

    recorder = SubmissionRecorder(
        writer_factory=factory,
        temp_root=tmp_path,
        monotonic=lambda: 0.0,
    )
    recorder.start()
    directory = submission_temp_dir(tmp_path)
    before = list(directory.glob("clip_*.mp4"))
    still = recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    assert still is False
    with pytest.raises(SubmissionRecorderError) as exc:
        recorder.stop()
    assert exc.value.code == "record_failed"
    after = list(directory.glob("clip_*.mp4"))
    assert after == []
    assert before == [] or all(not item.exists() for item in before)


def test_orphan_cleanup_removes_old_clips_only(tmp_path: Path):
    import os

    directory = submission_temp_dir(tmp_path)
    old = directory / "clip_old.mp4"
    recent = directory / "clip_recent.mp4"
    old.write_bytes(b"old")
    recent.write_bytes(b"new")
    now = 10_000.0
    os.utime(old, (now - 7200, now - 7200))
    os.utime(recent, (now - 10, now - 10))
    removed = cleanup_orphan_submission_temp_files(
        max_age_s=3600, root=tmp_path, now=lambda: now
    )
    assert removed == 1
    assert old.exists() is False
    assert recent.exists() is True


def test_temp_names_are_opaque(tmp_path: Path):
    recorder, _clock, _writers = _recorder(tmp_path)
    recorder.start()
    recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    metadata = recorder.stop()
    name = Path(metadata.local_path).name
    assert name.startswith("clip_")
    assert "gmail" not in name.lower()
    assert "@" not in name
    recorder.cancel()
