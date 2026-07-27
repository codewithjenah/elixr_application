import logging
import sys
import threading
import time
from typing import Any, Optional

import cv2
import numpy as np

from config import (
    CAMERA_FALLBACK_INDEX,
    CAMERA_INDEX,
    CAMERA_RELEASE_DEBOUNCE_S,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    TARGET_FPS,
)

logger = logging.getLogger(__name__)

_CAMERA_LOCK = threading.Lock()

_WARMUP_FRAMES = 3
_WARMUP_SLEEP_S = 0.08
_RELEASE_DELAY_S = 0.15
_READ_RETRIES = 5
_DISCOVERY_MAX_INDEX = 4

# Phantom DirectShow devices can open but only return black frames.
_MIN_FRAME_MEAN = 8.0
_MIN_FRAME_STD = 4.0

_shared_cap: Optional[cv2.VideoCapture] = None
_shared_index: Optional[int] = None
_release_timer: Optional[threading.Timer] = None
# Bumped every time a pending release is cancelled/superseded so a timer
# callback that already fired (and was blocked on _CAMERA_LOCK) can detect it
# is stale and skip releasing a camera that has since been reused.
_release_generation = 0


def _backends() -> list[int | None]:
    if sys.platform == "win32":
        return [cv2.CAP_DSHOW, cv2.CAP_MSMF]

    return [None]


def candidate_indices(camera_index: int | None = None) -> list[int]:
    """Return camera indices to try for a session request.

    ``None`` means Auto-select (preferred, then fallback).
    An integer means explicit selection with no silent fallback.
    """
    if camera_index is None:
        indices = [CAMERA_INDEX]
        if CAMERA_FALLBACK_INDEX != CAMERA_INDEX:
            indices.append(CAMERA_FALLBACK_INDEX)
        return indices

    return [camera_index]


def camera_display_name(index: int) -> str:
    """Friendly label for a camera index. Selection still uses the numeric index."""
    if index == CAMERA_INDEX:
        return "Default camera"
    if index == CAMERA_FALLBACK_INDEX:
        return "Webcam"
    return f"Webcam {index}"


def _frame_is_usable(frame: np.ndarray) -> bool:
    if frame.size == 0:
        return False

    mean = float(frame.mean())
    std = float(frame.std())

    if mean < _MIN_FRAME_MEAN and std < _MIN_FRAME_STD:
        return False

    return True


def _mjpg_attempts(index: int) -> tuple[bool, ...]:
    # USB webcams on Windows often return black frames with MJPG via DirectShow.
    if sys.platform == "win32" and index > 0:
        return (False,)

    return (False, True)


def _read_usable_frame(
    cap: cv2.VideoCapture,
    *,
    warmup_frames: int = _WARMUP_FRAMES,
) -> tuple[bool, Optional[np.ndarray]]:
    for _ in range(warmup_frames + 1):
        ok, frame = cap.read()
        if ok and frame is not None and _frame_is_usable(frame):
            return True, frame

        if _WARMUP_SLEEP_S > 0:
            time.sleep(_WARMUP_SLEEP_S)

    return False, None


def _apply_capture_settings(
    cap: cv2.VideoCapture,
    *,
    use_mjpg: bool,
) -> None:
    if use_mjpg:
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)


def _cancel_pending_release() -> None:
    global _release_timer, _release_generation

    _release_generation += 1

    if _release_timer is not None:
        _release_timer.cancel()
        _release_timer = None


def _release_shared_unlocked() -> None:
    global _shared_cap, _shared_index

    _cancel_pending_release()

    if _shared_cap is not None:
        _shared_cap.release()
        _shared_cap = None
        _shared_index = None
        logger.info("Camera released")

        if sys.platform == "win32":
            time.sleep(_RELEASE_DELAY_S)


def _release_shared() -> None:
    with _CAMERA_LOCK:
        _release_shared_unlocked()


def release_shared_camera() -> None:
    """Immediately release the shared webcam (e.g. when the client disconnects)."""
    _release_shared()


def _run_scheduled_release(generation: int) -> None:
    with _CAMERA_LOCK:
        # A newer open()/release() superseded this timer while it was waiting
        # on the lock; releasing now would kill an in-use camera.
        if generation != _release_generation:
            return
        _release_shared_unlocked()


def _schedule_shared_release() -> None:
    global _release_timer

    _cancel_pending_release()
    _release_timer = threading.Timer(
        CAMERA_RELEASE_DEBOUNCE_S,
        _run_scheduled_release,
        args=(_release_generation,),
    )
    _release_timer.daemon = True
    _release_timer.start()


def _open_video_capture(index: int) -> Optional[cv2.VideoCapture]:
    warmup_frames = _WARMUP_FRAMES + (2 if index > 0 else 0)

    for api in _backends():
        for use_mjpg in _mjpg_attempts(index):
            cap = (
                cv2.VideoCapture(index, api)
                if api is not None
                else cv2.VideoCapture(index)
            )

            if not cap.isOpened():
                cap.release()
                continue

            _apply_capture_settings(cap, use_mjpg=use_mjpg)

            ok, frame = _read_usable_frame(cap, warmup_frames=warmup_frames)
            if not ok or frame is None:
                logger.debug(
                    "Camera %s rejected (backend=%s, mjpg=%s): no usable frames",
                    index,
                    api,
                    use_mjpg,
                )
                cap.release()
                if sys.platform == "win32":
                    time.sleep(_RELEASE_DELAY_S)
                continue

            actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            actual_fps = int(cap.get(cv2.CAP_PROP_FPS))

            logger.info(
                "Camera %s opened (backend=%s, mjpg=%s). "
                "Requested %sx%s @ %s FPS, actual %sx%s @ %s FPS",
                index,
                api,
                use_mjpg,
                FRAME_WIDTH,
                FRAME_HEIGHT,
                TARGET_FPS,
                actual_w,
                actual_h,
                actual_fps,
            )

            return cap

    return None


def _try_reuse_shared_capture(
    allowed_indices: list[int],
    *,
    preferred_index: int | None = None,
) -> bool:
    global _shared_cap, _shared_index

    if _shared_cap is None or not _shared_cap.isOpened():
        return False

    if _shared_index not in allowed_indices:
        logger.info(
            "Shared camera %s is not in allowed indices %s; reopening",
            _shared_index,
            allowed_indices,
        )
        return False

    # Auto-select must still prefer CAMERA_INDEX over a sticky fallback capture.
    if (
        preferred_index is not None
        and _shared_index != preferred_index
        and preferred_index in allowed_indices
    ):
        logger.info(
            "Shared camera %s is allowed but preferred index is %s; reopening",
            _shared_index,
            preferred_index,
        )
        return False

    ok, _ = _read_usable_frame(_shared_cap, warmup_frames=1)
    if ok:
        logger.info("Reusing open camera %s", _shared_index)
        return True

    logger.warning("Shared camera %s became unusable; reopening", _shared_index)
    _release_shared_unlocked()
    return False


def discover_cameras(*, max_index: int = _DISCOVERY_MAX_INDEX) -> dict[str, Any]:
    """Probe a bounded index range and return usable cameras.

    Does not release an already-open shared capture. The active shared index is
    listed without reopening it. Blocking OpenCV work must be run off the
    FastAPI event loop by the caller (``asyncio.to_thread``).
    """
    cameras: list[dict[str, Any]] = []

    with _CAMERA_LOCK:
        active_index = (
            _shared_index
            if _shared_cap is not None and _shared_cap.isOpened()
            else None
        )

        for index in range(max_index + 1):
            if active_index is not None and index == active_index:
                cameras.append(
                    {
                        "index": index,
                        "display_name": camera_display_name(index),
                    }
                )
                continue

            cap = _open_video_capture(index)
            if cap is None:
                continue

            cameras.append(
                {
                    "index": index,
                    "display_name": camera_display_name(index),
                }
            )
            cap.release()
            if sys.platform == "win32":
                time.sleep(_RELEASE_DELAY_S)

    return {
        "cameras": cameras,
        "preferred_index": CAMERA_INDEX,
        "fallback_index": CAMERA_FALLBACK_INDEX,
        "active_index": active_index,
    }


class CameraCapture:
    def __init__(
        self,
        index: int = CAMERA_INDEX,
        width: int = FRAME_WIDTH,
        height: int = FRAME_HEIGHT,
        *,
        camera_index: int | None = None,
    ):
        """Open a webcam for a vision session.

        Keyword ``camera_index``:
        - ``None`` → Auto-select (preferred ``index``/CAMERA_INDEX, then fallback)
        - ``N`` → explicit index N with no silent fallback

        Legacy positional ``index`` remains the preferred Auto-select index when
        ``camera_index`` is omitted/None (scripts and profile tools).
        """
        self._width = width
        self._height = height
        self._blank_frame_streak = 0
        self._used_fallback = False

        if camera_index is not None:
            self._auto = False
            self._selection = camera_index
            self._auto_preferred = CAMERA_INDEX
        else:
            self._auto = True
            self._selection = None
            self._auto_preferred = index
    @property
    def is_open(self) -> bool:
        with _CAMERA_LOCK:
            return _shared_cap is not None and _shared_cap.isOpened()

    @property
    def active_index(self) -> int | None:
        with _CAMERA_LOCK:
            return _shared_index

    @property
    def used_fallback(self) -> bool:
        return self._used_fallback

    def _allowed_indices(self) -> list[int]:
        if not self._auto:
            return candidate_indices(self._selection)
        preferred = getattr(self, "_auto_preferred", CAMERA_INDEX)
        indices = [preferred]
        if CAMERA_FALLBACK_INDEX != preferred:
            indices.append(CAMERA_FALLBACK_INDEX)
        return indices

    def open(self) -> bool:
        global _shared_cap, _shared_index

        allowed = self._allowed_indices()
        mode = "auto-select" if self._auto else "explicit"
        requested = "auto" if self._auto else str(self._selection)

        logger.info(
            "Camera open requested: mode=%s requested=%s candidates=%s",
            mode,
            requested,
            allowed,
        )

        with _CAMERA_LOCK:
            _cancel_pending_release()

            preferred = allowed[0] if allowed else None
            if _try_reuse_shared_capture(allowed, preferred_index=preferred):
                self._blank_frame_streak = 0
                self._used_fallback = (
                    self._auto
                    and _shared_index is not None
                    and _shared_index != getattr(self, "_auto_preferred", CAMERA_INDEX)
                )
                logger.info(
                    "Camera ready (reused): active_index=%s used_fallback=%s",
                    _shared_index,
                    self._used_fallback,
                )
                return True

            _release_shared_unlocked()

            for candidate in allowed:
                cap = _open_video_capture(candidate)

                if cap is not None:
                    _shared_cap = cap
                    _shared_index = candidate
                    self._blank_frame_streak = 0
                    preferred = getattr(self, "_auto_preferred", CAMERA_INDEX)
                    self._used_fallback = self._auto and candidate != preferred

                    if self._used_fallback:
                        logger.warning(
                            "Camera index %s unavailable; using fallback index %s",
                            preferred,
                            candidate,
                        )

                    logger.info(
                        "Camera ready: active_index=%s used_fallback=%s size=%sx%s",
                        _shared_index,
                        self._used_fallback,
                        self._width,
                        self._height,
                    )

                    return True

            if self._auto:
                logger.error(
                    "Failed to open camera index %s. Fallback index %s also failed.",
                    getattr(self, "_auto_preferred", CAMERA_INDEX),
                    CAMERA_FALLBACK_INDEX,
                )
            else:
                logger.error(
                    "Failed to open selected camera index %s (no fallback).",
                    self._selection,
                )

            return False

    def read(self) -> Optional[np.ndarray]:
        with _CAMERA_LOCK:
            if _shared_cap is None or not _shared_cap.isOpened():
                return None

            for _ in range(_READ_RETRIES):
                ok, frame = _shared_cap.read()

                if not ok or frame is None:
                    if _WARMUP_SLEEP_S > 0:
                        time.sleep(_WARMUP_SLEEP_S)
                    continue

                if not _frame_is_usable(frame):
                    self._blank_frame_streak += 1
                    if self._blank_frame_streak == 1 or self._blank_frame_streak % 30 == 0:
                        logger.warning(
                            "Camera %s returned a blank frame (streak=%s)",
                            _shared_index,
                            self._blank_frame_streak,
                        )
                    if _WARMUP_SLEEP_S > 0:
                        time.sleep(_WARMUP_SLEEP_S)
                    continue

                self._blank_frame_streak = 0

                if frame.shape[1] != self._width or frame.shape[0] != self._height:
                    frame = cv2.resize(
                        frame,
                        (self._width, self._height),
                        interpolation=cv2.INTER_AREA,
                    )

                return frame

            return None

    def release(self) -> None:
        with _CAMERA_LOCK:
            _schedule_shared_release()
