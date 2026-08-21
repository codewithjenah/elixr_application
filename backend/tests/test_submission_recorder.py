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

    def write(self, frame: np.ndarray) -> None:
        self.frames.append(np.copy(frame))
        with self.path.open("ab") as handle:
            handle.write(b"frame")
        return None

    def release(self) -> None:
        self.released = True


class InflatingOnReleaseWriter(FakeWriter):
    def __init__(self, path: Path, *, final_size: int):
        super().__init__(path)
        self.final_size = final_size

    def release(self) -> None:
        self.path.write_bytes(b"x" * self.final_size)
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


def test_writer_write_returning_none_finalizes_metadata(tmp_path: Path):
    probe = FakeWriter(tmp_path / "none_probe.mp4")
    assert probe.write(_frame()) is None
    recorder, clock, writers = _recorder(tmp_path)
    recorder.start()
    still = recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    assert still is True
    clock[0] = 0.5
    recorder.write_frame(_frame(90), captured_at_monotonic=0.5, sequence=2)
    metadata = recorder.stop()
    assert writers[0].released is True
    assert metadata.video_size_bytes > 0
    assert metadata.video_duration_ms == 500
    assert Path(metadata.local_path).exists()
    assert metadata.content_type == "video/mp4"


def test_oversized_file_after_release_is_rejected_and_deleted(tmp_path: Path):
    writers: list[InflatingOnReleaseWriter] = []

    def factory(path: Path, fps: float, size: tuple[int, int]) -> InflatingOnReleaseWriter:
        writer = InflatingOnReleaseWriter(path, final_size=64)
        writers.append(writer)
        return writer

    recorder = SubmissionRecorder(
        fps=20,
        max_duration_s=20,
        max_size_bytes=16,
        writer_factory=factory,
        temp_root=tmp_path,
        monotonic=lambda: 0.0,
    )
    recorder.start()
    still = recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    assert still is True
    with pytest.raises(SubmissionRecorderError) as exc:
        recorder.stop()
    assert exc.value.code == "record_failed"
    assert writers[0].released is True
    directory = submission_temp_dir(tmp_path)
    assert list(directory.glob("clip_*.mp4")) == []


def test_writer_exception_is_a_bounded_recording_failure(tmp_path: Path):
    class RaisingWriter(FakeWriter):
        def write(self, frame: np.ndarray) -> None:
            raise RuntimeError("encoder failed")

    def factory(path: Path, fps: float, size: tuple[int, int]) -> RaisingWriter:
        return RaisingWriter(path)

    recorder = SubmissionRecorder(
        writer_factory=factory,
        temp_root=tmp_path,
        monotonic=lambda: 0.0,
    )
    recorder.start()
    still = recorder.write_frame(_frame(), captured_at_monotonic=0.0, sequence=1)
    assert still is False
    with pytest.raises(SubmissionRecorderError) as exc:
        recorder.stop()
    assert exc.value.code == "record_failed"


def test_real_opencv_write_return_is_ignored_and_synthetic_clip_finalizes(
    tmp_path: Path,
):
    cv2 = pytest.importorskip("cv2")
    probe = tmp_path / "probe.mp4"
    writer = cv2.VideoWriter(
        str(probe), cv2.VideoWriter_fourcc(*"mp4v"), 10.0, (16, 16)
    )
    if writer is None or not writer.isOpened():
        pytest.skip("OpenCV could not open an mp4v writer")
    frame = np.zeros((16, 16, 3), dtype=np.uint8)
    write_return = writer.write(frame)
    writer.release()
    # OpenCV 5 returns bool; older Python bindings returned None. Either is
    # success for this recorder as long as the value is not interpreted.
    assert write_return is None or write_return is True or write_return is False

    recorder = SubmissionRecorder(
        fps=10,
        max_duration_s=20,
        temp_root=tmp_path,
        monotonic=lambda: 0.0,
    )
    recorder.start()
    clock = 0.0
    for index in range(8):
        clock = index * 0.1
        tinted = np.full((48, 64, 3), min(index * 20, 255), dtype=np.uint8)
        recorder.write_frame(
            tinted, captured_at_monotonic=clock, sequence=index + 1
        )
    metadata = recorder.stop()
    path = Path(metadata.local_path)
    assert path.exists()
    assert path.stat().st_size > 0
    assert metadata.content_type == "video/mp4"
    assert metadata.video_duration_ms > 0
    recorder.cancel()


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
