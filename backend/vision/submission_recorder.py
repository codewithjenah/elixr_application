"""Bounded assignment-submission recorder.

Consumes copies of frames from the existing Python-owned camera/session flow.
Does not open a second ``cv2.VideoCapture``.
"""

from __future__ import annotations

import hashlib
import logging
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Protocol

import numpy as np

from config import (
    FRAME_HEIGHT,
    FRAME_WIDTH,
    MAX_SUBMISSION_DURATION_SECONDS,
    MAX_SUBMISSION_SIZE_BYTES,
    SUBMISSION_CONTENT_TYPE,
    SUBMISSION_TEMP_DIRNAME,
    TARGET_FPS,
)

logger = logging.getLogger(__name__)

# Prefer H.264 when the local OpenCV/FFmpeg build can open it; mp4v remains
# the practical Windows OpenCV fallback. These are tried in order.
_WRITER_FOURCC_CANDIDATES = ("avc1", "H264", "mp4v")


class SubmissionRecorderError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class VideoWriterLike(Protocol):
    def isOpened(self) -> bool: ...

    def write(self, frame: np.ndarray) -> None: ...

    def release(self) -> None: ...


WriterFactory = Callable[[Path, float, tuple[int, int]], VideoWriterLike]


@dataclass(frozen=True)
class SubmissionClipMetadata:
    local_path: str
    video_duration_ms: int
    video_size_bytes: int
    content_type: str = SUBMISSION_CONTENT_TYPE
    sha256: str | None = None


def submission_temp_dir(root: Path | None = None) -> Path:
    base = Path(root) if root is not None else Path(_default_temp_root())
    path = base / SUBMISSION_TEMP_DIRNAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def _default_temp_root() -> str:
    import tempfile

    return tempfile.gettempdir()


def cleanup_orphan_submission_temp_files(
    *,
    max_age_s: float = 3600.0,
    root: Path | None = None,
    now: Callable[[], float] | None = None,
) -> int:
    """Delete leftover ELIXR submission temp clips older than ``max_age_s``.

    Filenames are opaque ``clip_*.mp4`` ids. Does not log full paths.
    """
    clock = now or time.time
    directory = submission_temp_dir(root)
    removed = 0
    cutoff = clock() - max_age_s
    for path in directory.glob("clip_*.mp4"):
        try:
            if path.stat().st_mtime <= cutoff:
                path.unlink(missing_ok=True)
                removed += 1
        except OSError:
            logger.warning("Failed to remove orphan submission temp clip")
    return removed


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _open_opencv_writer(
    path: Path, fps: float, size: tuple[int, int]
) -> VideoWriterLike:
    import cv2

    last_error = "no writer candidates"
    for fourcc_name in _WRITER_FOURCC_CANDIDATES:
        fourcc = cv2.VideoWriter_fourcc(*fourcc_name)
        writer = cv2.VideoWriter(str(path), fourcc, float(fps), size)
        if writer is not None and writer.isOpened():
            return writer
        last_error = fourcc_name
        if writer is not None:
            writer.release()
    raise SubmissionRecorderError(
        "record_failed",
        f"Could not initialize a Windows-compatible MP4 writer ({last_error}).",
    )


class SubmissionRecorder:
    """Owns at most one temp MP4 per WebSocket/session."""

    def __init__(
        self,
        *,
        fps: float = TARGET_FPS,
        max_duration_s: float = MAX_SUBMISSION_DURATION_SECONDS,
        max_size_bytes: int = MAX_SUBMISSION_SIZE_BYTES,
        frame_width: int = FRAME_WIDTH,
        frame_height: int = FRAME_HEIGHT,
        writer_factory: WriterFactory | None = None,
        temp_root: Path | None = None,
        monotonic: Callable[[], float] | None = None,
    ) -> None:
        self._fps = float(fps)
        self._max_duration_s = float(max_duration_s)
        self._max_size_bytes = int(max_size_bytes)
        self._default_size = (int(frame_width), int(frame_height))
        self._writer_factory = writer_factory or _open_opencv_writer
        self._temp_root = temp_root
        self._monotonic = monotonic or time.monotonic
        self._lock = threading.Lock()
        self._state = "idle"
        self._path: Path | None = None
        self._writer: VideoWriterLike | None = None
        self._started_at: float | None = None
        self._last_frame_at: float | None = None
        self._frames_written = 0
        self._failed_code: str | None = None
        self._failed_message: str | None = None
        self._final_metadata: SubmissionClipMetadata | None = None
        self._last_sequence: int | None = None

    @property
    def is_recording(self) -> bool:
        with self._lock:
            return self._state == "recording"

    @property
    def has_clip(self) -> bool:
        with self._lock:
            return self._final_metadata is not None or (
                self._state == "recording" and self._path is not None
            )

    @property
    def failed_code(self) -> str | None:
        with self._lock:
            return self._failed_code

    def start(self) -> None:
        with self._lock:
            if self._state == "recording":
                raise SubmissionRecorderError(
                    "submission_already_recording",
                    "A submission clip is already being recorded.",
                )
            if self._state == "finalized" and self._path is not None:
                raise SubmissionRecorderError(
                    "submission_already_recording",
                    "A submission clip is waiting. Cancel it before recording again.",
                )
            self._reset_unlocked(delete_file=True)
            directory = submission_temp_dir(self._temp_root)
            self._path = directory / f"clip_{uuid.uuid4().hex}.mp4"
            self._started_at = self._monotonic()
            self._last_frame_at = self._started_at
            self._state = "recording"
            self._frames_written = 0
            self._final_metadata = None
            self._failed_code = None
            self._failed_message = None
            self._last_sequence = None

    def write_frame(
        self,
        frame: np.ndarray,
        *,
        captured_at_monotonic: float | None = None,
        sequence: int | None = None,
    ) -> bool:
        """Copy ``frame`` into the active writer. Returns False if recording ended."""
        if frame is None:
            return False
        captured_at = (
            float(captured_at_monotonic)
            if captured_at_monotonic is not None
            else self._monotonic()
        )
        with self._lock:
            if self._state != "recording":
                return False
            if sequence is not None and sequence == self._last_sequence:
                return True
            started_at = (
                self._started_at
                if self._started_at is not None
                else captured_at
            )
            elapsed = max(0.0, captured_at - started_at)
            if elapsed >= self._max_duration_s:
                self._last_frame_at = started_at + self._max_duration_s
                self._finalize_unlocked(reason="cap")
                return False
            try:
                owned = np.copy(frame, order="C")
                self._ensure_writer_unlocked(owned)
                writer = self._writer
                if writer is None or not writer.isOpened():
                    self._fail_unlocked("record_failed", "Video writer is not open.")
                    return False
                # OpenCV 4/5 may return bool; older Python bindings returned
                # None on success. Never treat a falsey return as failure.
                writer.write(owned)
                self._frames_written += 1
                self._last_frame_at = captured_at
                self._last_sequence = sequence
                if self._path is not None:
                    try:
                        size = self._path.stat().st_size
                    except OSError:
                        size = 0
                    if size > self._max_size_bytes:
                        self._fail_unlocked(
                            "record_failed",
                            "Submission clip exceeded the maximum size.",
                        )
                        return False
                remaining = self._max_duration_s - elapsed
                if remaining <= 0:
                    self._last_frame_at = started_at + self._max_duration_s
                    self._finalize_unlocked(reason="cap")
                    return False
            except SubmissionRecorderError as exc:
                self._fail_unlocked(exc.code, exc.message)
                return False
            except Exception:
                logger.exception("Submission recorder write failed")
                self._fail_unlocked("record_failed", "Submission recording failed.")
                return False
            return True

    def finalize_due_to_cap(self) -> SubmissionClipMetadata | None:
        with self._lock:
            if self._state == "finalized":
                return self._final_metadata
            if self._state != "recording":
                return None
            if self._started_at is not None:
                self._last_frame_at = self._started_at + self._max_duration_s
            return self._finalize_unlocked(reason="cap")

    def stop(self) -> SubmissionClipMetadata:
        with self._lock:
            if self._failed_code is not None:
                code = self._failed_code
                message = self._failed_message or "Submission recording failed."
                self._reset_unlocked(delete_file=True)
                raise SubmissionRecorderError(code, message)
            if self._state == "finalized" and self._final_metadata is not None:
                return self._final_metadata
            if self._state != "recording":
                raise SubmissionRecorderError(
                    "submission_not_recording",
                    "No submission clip is being recorded.",
                )
            metadata = self._finalize_unlocked(reason="stop")
            if metadata is None:
                raise SubmissionRecorderError(
                    "record_failed",
                    "Submission recording produced no usable clip.",
                )
            return metadata

    def cancel(self) -> None:
        with self._lock:
            self._reset_unlocked(delete_file=True)

    def cleanup(self) -> None:
        self.cancel()

    def _ensure_writer_unlocked(self, frame: np.ndarray) -> None:
        if self._writer is not None:
            return
        if self._path is None:
            raise SubmissionRecorderError("record_failed", "Missing temp path.")
        height, width = int(frame.shape[0]), int(frame.shape[1])
        if height <= 0 or width <= 0:
            height, width = self._default_size[1], self._default_size[0]
        size = (width, height)
        writer = self._writer_factory(self._path, self._fps, size)
        if writer is None or not writer.isOpened():
            raise SubmissionRecorderError(
                "record_failed",
                "Could not initialize a Windows-compatible MP4 writer.",
            )
        self._writer = writer

    def _finalize_unlocked(self, *, reason: str) -> SubmissionClipMetadata | None:
        path = self._path
        writer = self._writer
        self._writer = None
        if writer is not None:
            try:
                writer.release()
            except Exception:
                logger.exception("Submission writer release failed")
        if path is None or not path.exists():
            self._fail_unlocked("record_failed", "Submission clip was not written.")
            return None
        try:
            size = path.stat().st_size
        except OSError:
            size = 0
        if size <= 0 or self._frames_written <= 0:
            self._fail_unlocked("record_failed", "Submission clip was empty.")
            return None
        if size > self._max_size_bytes:
            self._fail_unlocked(
                "record_failed",
                "Submission clip exceeded the maximum size.",
            )
            return None
        started = (
            self._started_at
            if self._started_at is not None
            else self._monotonic()
        )
        ended = (
            self._last_frame_at
            if self._last_frame_at is not None
            else self._monotonic()
        )
        duration_ms = int(round(max(0.0, ended - started) * 1000.0))
        max_ms = int(round(self._max_duration_s * 1000.0))
        if reason == "cap":
            duration_ms = max_ms
        elif duration_ms > max_ms:
            duration_ms = max_ms
        if duration_ms <= 0:
            duration_ms = int(
                round((self._frames_written / max(self._fps, 1.0)) * 1000.0)
            )
        if duration_ms <= 0:
            self._fail_unlocked("record_failed", "Submission clip duration was empty.")
            return None
        if duration_ms > max_ms:
            duration_ms = max_ms
        sha256 = None
        try:
            sha256 = _sha256_file(path)
        except OSError:
            logger.warning("Could not hash submission clip")
        metadata = SubmissionClipMetadata(
            local_path=str(path),
            video_duration_ms=duration_ms,
            video_size_bytes=size,
            content_type=SUBMISSION_CONTENT_TYPE,
            sha256=sha256,
        )
        self._state = "finalized"
        self._final_metadata = metadata
        self._failed_code = None
        logger.info(
            "Submission recording finalized reason=%s duration_ms=%s size_bytes=%s",
            reason,
            duration_ms,
            size,
        )
        return metadata

    def _fail_unlocked(self, code: str, message: str) -> None:
        self._failed_code = code
        self._failed_message = message
        self._state = "failed"
        self._release_writer_unlocked()
        self._delete_path_unlocked()
        self._final_metadata = None
        logger.warning("Submission recording failed code=%s", code)

    def _release_writer_unlocked(self) -> None:
        writer = self._writer
        self._writer = None
        if writer is not None:
            try:
                writer.release()
            except Exception:
                logger.exception("Submission writer release failed")

    def _delete_path_unlocked(self) -> None:
        path = self._path
        self._path = None
        if path is None:
            return
        try:
            path.unlink(missing_ok=True)
        except OSError:
            logger.warning("Failed to delete submission temp clip")

    def _reset_unlocked(self, *, delete_file: bool) -> None:
        self._release_writer_unlocked()
        if delete_file:
            self._delete_path_unlocked()
        else:
            self._path = None
        self._state = "idle"
        self._started_at = None
        self._last_frame_at = None
        self._frames_written = 0
        self._failed_code = None
        self._failed_message = None
        self._final_metadata = None
        self._last_sequence = None
