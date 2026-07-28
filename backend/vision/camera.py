import logging
import sys
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Optional

import cv2
import numpy as np

from config import (
    CAMERA_FALLBACK_INDEX,
    CAMERA_INDEX,
    CAMERA_RELEASE_DEBOUNCE_S,
    DISCOVERY_CACHE_TTL_S,
    DISCOVERY_MAX_INDEX,
    DISCOVERY_PROBE_READ_SLEEP_S,
    DISCOVERY_PROBE_REQUIRED_CONSECUTIVE,
    DISCOVERY_PROBE_TIMEOUT_S,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    TARGET_FPS,
)
from vision.camera_devices import (
    EnumeratedCamera,
    device_id_for_runtime_index,
    display_name_for_runtime_index,
    enumerate_camera_devices,
    is_fallback_device_id,
    lookup_device,
    merge_enumerated_with_usable_indices,
    resolve_device_id_to_index,
)

logger = logging.getLogger(__name__)

_CAMERA_LOCK = threading.Lock()
_DISCOVERY_LOCK = threading.Lock()

_RELEASE_DELAY_S = 0.15
_READ_RETRIES = 5

# Short-lived GET /cameras cache and single-flight scan coordination.
_discovery_cache: dict[str, Any] | None = None
_discovery_cache_at: float = 0.0
_discovery_scan_inflight = False
_discovery_scan_waiters: list[threading.Event] = []

# Phantom DirectShow devices can open but only return black frames.
_MIN_FRAME_MEAN = 8.0
_MIN_FRAME_STD = 4.0

# Startup must see a stable stream, not a single lucky frame.
_STARTUP_TIMEOUT_S = 2.0
_STARTUP_REQUIRED_CONSECUTIVE_FRAMES = 5
_STARTUP_READ_SLEEP_S = 0.05

# Runtime blank-frame recovery.
_MAX_BLANK_FRAME_STREAK = 12
_RECOVERY_COOLDOWN_S = 1.0
_MAX_RECOVERY_ATTEMPTS_PER_READ = 1

_shared_cap: Optional[cv2.VideoCapture] = None
_shared_index: Optional[int] = None
_shared_device_id: Optional[str] = None
_shared_profile: Optional["CaptureProfile"] = None
_release_timer: Optional[threading.Timer] = None
# Bumped every time a pending release is cancelled/superseded so a timer
# callback that already fired (and was blocked on _CAMERA_LOCK) can detect it
# is stale and skip releasing a camera that has since been reused.
_release_generation = 0


class CameraReadStatus(Enum):
    OK = "ok"
    TEMPORARY_MISS = "temporary_miss"
    RECOVERING = "recovering"
    UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class CaptureProfile:
    api: int | None
    backend_label: str
    use_mjpg: bool
    label: str


def _capture_profiles(
    index: int,
    *,
    dshow_only: bool = False,
) -> list[CaptureProfile]:
    """Ordered Windows capture profiles.

    Profile order does not classify built-in vs external from the runtime
    index. Every backend/format combination is still attempted; startup
    probing rejects profiles that open but yield unusable frames.

  When ``dshow_only`` is True, only DirectShow profiles are returned so a
  stable DirectShow ``device_id`` cannot silently open a different physical
  camera through Media Foundation at the same runtime index.

    ``index`` is retained for call-site compatibility only.
    """
    del index  # Runtime index is not a device-class signal.

    if sys.platform == "win32":
        dshow_mjpg = CaptureProfile(
            cv2.CAP_DSHOW, "DirectShow", True, "DirectShow + MJPG"
        )
        dshow_default = CaptureProfile(
            cv2.CAP_DSHOW, "DirectShow", False, "DirectShow + default"
        )
        if dshow_only:
            return [dshow_mjpg, dshow_default]

        msmf_mjpg = CaptureProfile(
            cv2.CAP_MSMF, "Media Foundation", True, "Media Foundation + MJPG"
        )
        msmf_default = CaptureProfile(
            cv2.CAP_MSMF, "Media Foundation", False, "Media Foundation + default"
        )
        # MJPG first helps many USB cameras; others fall through quickly.
        return [dshow_mjpg, msmf_mjpg, dshow_default, msmf_default]

    return [
        CaptureProfile(None, "Default", False, "Default + default"),
        CaptureProfile(None, "Default", True, "Default + MJPG"),
    ]


def _profiles_starting_after(
    profiles: list[CaptureProfile],
    failed: CaptureProfile | None,
) -> list[CaptureProfile]:
    """Rotate so the next profile after ``failed`` is tried first."""
    if not profiles or failed is None:
        return list(profiles)

    try:
        idx = next(i for i, p in enumerate(profiles) if p.label == failed.label)
    except StopIteration:
        return list(profiles)

    return profiles[idx + 1 :] + profiles[: idx + 1]


def candidate_indices(camera_index: int | None = None) -> list[int]:
    """Return camera indices to try for a session request.

    ``None`` means Auto-select (preferred, then fallback config indices).
    An integer means explicit selection with no silent fallback.

    Prefer resolving ``camera_device_id`` via
    :func:`resolve_camera_device_id` before calling this with a legacy index.
    """
    if camera_index is None:
        indices = [CAMERA_INDEX]
        if CAMERA_FALLBACK_INDEX != CAMERA_INDEX:
            indices.append(CAMERA_FALLBACK_INDEX)
        return indices

    return [camera_index]


def resolve_camera_device_id(device_id: str | None) -> int | None:
    """Resolve a stable device id to the current OpenCV runtime index.

    Returns ``None`` when the device is disconnected or unknown.
    """
    if device_id is None:
        return None
    return resolve_device_id_to_index(device_id)


def camera_display_name(
    *,
    device_id: str | None = None,
    runtime_index: int | None = None,
) -> str:
    """Friendly label from OS identity when available; never invents Default/Webcam."""
    if device_id:
        device = lookup_device(device_id)
        if device is not None:
            return device.display_name
    if runtime_index is not None:
        return display_name_for_runtime_index(runtime_index)
    return "Selected camera"


def _frame_is_usable(frame: np.ndarray) -> bool:
    if frame.size == 0:
        return False

    mean = float(frame.mean())
    std = float(frame.std())

    if mean < _MIN_FRAME_MEAN and std < _MIN_FRAME_STD:
        return False

    return True


def _fourcc_to_str(value: float | int) -> str:
    code = int(value)
    chars = "".join(chr((code >> (8 * i)) & 0xFF) for i in range(4))
    return chars if chars.isprintable() else f"0x{code:08x}"


def _probe_stable_startup(
    cap: cv2.VideoCapture,
    *,
    timeout_s: float = _STARTUP_TIMEOUT_S,
    required_consecutive: int = _STARTUP_REQUIRED_CONSECUTIVE_FRAMES,
    read_sleep_s: float = _STARTUP_READ_SLEEP_S,
) -> tuple[bool, Optional[np.ndarray]]:
    """Require consecutive usable frames before accepting a capture profile."""
    deadline = time.monotonic() + timeout_s
    consecutive = 0
    last_valid: Optional[np.ndarray] = None

    while time.monotonic() < deadline:
        ok, frame = cap.read()
        if ok and frame is not None and _frame_is_usable(frame):
            consecutive += 1
            last_valid = frame
            if consecutive >= required_consecutive:
                return True, last_valid
        else:
            consecutive = 0

        if read_sleep_s > 0:
            time.sleep(read_sleep_s)

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
    cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)


def _cancel_pending_release() -> None:
    global _release_timer, _release_generation

    _release_generation += 1

    if _release_timer is not None:
        _release_timer.cancel()
        _release_timer = None


def _release_shared_unlocked() -> None:
    global _shared_cap, _shared_index, _shared_device_id, _shared_profile

    _cancel_pending_release()

    if _shared_cap is not None:
        _shared_cap.release()
        _shared_cap = None
        _shared_index = None
        _shared_device_id = None
        _shared_profile = None
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


def _create_capture(index: int, profile: CaptureProfile) -> cv2.VideoCapture:
    if profile.api is not None:
        return cv2.VideoCapture(index, profile.api)
    return cv2.VideoCapture(index)


def _log_opened_capture(index: int, cap: cv2.VideoCapture, profile: CaptureProfile) -> None:
    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = float(cap.get(cv2.CAP_PROP_FPS))
    fourcc = _fourcc_to_str(cap.get(cv2.CAP_PROP_FOURCC))

    logger.info(
        "Camera %s opened using %s. "
        "Requested %sx%s @ %s FPS. "
        "Actual %sx%s @ %s FPS. "
        "FOURCC=%s.",
        index,
        profile.label,
        FRAME_WIDTH,
        FRAME_HEIGHT,
        TARGET_FPS,
        actual_w,
        actual_h,
        actual_fps,
        fourcc,
    )


def _abbreviate_device_id(device_id: str | None) -> str:
    if not device_id:
        return "none"
    if len(device_id) <= 24:
        return device_id
    return f"{device_id[:12]}…{device_id[-8:]}"


def _probe_discovery(
    cap: cv2.VideoCapture,
    *,
    timeout_s: float = DISCOVERY_PROBE_TIMEOUT_S,
    required_consecutive: int = DISCOVERY_PROBE_REQUIRED_CONSECUTIVE,
    read_sleep_s: float = DISCOVERY_PROBE_READ_SLEEP_S,
) -> tuple[bool, Optional[np.ndarray]]:
    """Bounded probe for GET /cameras; not used for practice session startup."""
    return _probe_stable_startup(
        cap,
        timeout_s=timeout_s,
        required_consecutive=required_consecutive,
        read_sleep_s=read_sleep_s,
    )


def _discovery_log_context(
    index: int,
    *,
    enumerated: list[EnumeratedCamera],
) -> tuple[str, str]:
    device = next((d for d in enumerated if d.runtime_index == index), None)
    if device is not None:
        return device.display_name, _abbreviate_device_id(device.device_id)
    return display_name_for_runtime_index(index, devices=enumerated), "unknown"


def _indices_to_probe(
    *,
    max_index: int,
    enumerated: list[EnumeratedCamera],
) -> list[int]:
    if enumerated:
        return sorted({device.runtime_index for device in enumerated})
    return list(range(max_index + 1))


def _explicit_selection_requires_dshow(device_id: str | None) -> bool:
    if device_id is None or is_fallback_device_id(device_id):
        return False
    device = lookup_device(device_id)
    if device is None:
        return True
    return device.identity_stable


def _open_video_capture(
    index: int,
    *,
    prefer_after: CaptureProfile | None = None,
    dshow_only: bool = False,
    for_discovery: bool = False,
) -> Optional[tuple[cv2.VideoCapture, CaptureProfile]]:
    profiles = _profiles_starting_after(
        _capture_profiles(index, dshow_only=dshow_only),
        prefer_after,
    )

    for profile in profiles:
        cap = _create_capture(index, profile)

        if not cap.isOpened():
            cap.release()
            continue

        _apply_capture_settings(cap, use_mjpg=profile.use_mjpg)

        if for_discovery:
            ok, frame = _probe_discovery(cap)
        else:
            ok, frame = _probe_stable_startup(cap)

        if not ok or frame is None:
            logger.debug(
                "Camera %s rejected (%s): no %s usable frames",
                index,
                profile.label,
                "discovery" if for_discovery else "stable",
            )
            cap.release()
            if sys.platform == "win32":
                time.sleep(_RELEASE_DELAY_S)
            continue

        _log_opened_capture(index, cap, profile)
        return cap, profile

    return None


def _probe_index_for_discovery(
    index: int,
    *,
    enumerated: list[EnumeratedCamera],
) -> bool:
    display_name, device_id_short = _discovery_log_context(
        index,
        enumerated=enumerated,
    )
    opened = _open_video_capture(index, for_discovery=True)
    if opened is None:
        logger.info(
            "Discovery probe failed: name=%r id=%s index=%s backend=none "
            "reason=no_openable_profile",
            display_name,
            device_id_short,
            index,
        )
        return False

    cap, profile = opened
    cap.release()
    if sys.platform == "win32":
        time.sleep(_RELEASE_DELAY_S)

    logger.info(
        "Discovery probe succeeded: name=%r id=%s index=%s backend=%s",
        display_name,
        device_id_short,
        index,
        profile.label,
    )
    return True


def _try_reuse_shared_capture(
    allowed_indices: list[int],
    *,
    preferred_index: int | None = None,
) -> bool:
    global _shared_cap, _shared_index, _shared_profile

    if _shared_cap is None or not _shared_cap.isOpened():
        return False

    if _shared_profile is None:
        logger.info("Shared camera has no profile metadata; reopening")
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

    ok, _ = _probe_stable_startup(
        _shared_cap,
        timeout_s=min(_STARTUP_TIMEOUT_S, 1.0),
        required_consecutive=_STARTUP_REQUIRED_CONSECUTIVE_FRAMES,
    )
    if ok:
        logger.info(
            "Reusing open camera %s (%s)",
            _shared_index,
            _shared_profile.label if _shared_profile else "unknown",
        )
        return True

    logger.warning("Shared camera %s became unusable; reopening", _shared_index)
    _release_shared_unlocked()
    return False


def _discover_cameras_impl(*, max_index: int = DISCOVERY_MAX_INDEX) -> dict[str, Any]:
    """Probe enumerated (or fallback) indices and return usable cameras."""
    enumerated = enumerate_camera_devices()
    indices = _indices_to_probe(max_index=max_index, enumerated=enumerated)
    usable_indices: list[int] = []

    with _CAMERA_LOCK:
        active_index = (
            _shared_index
            if _shared_cap is not None and _shared_cap.isOpened()
            else None
        )
        active_device_id = _shared_device_id

    for index in indices:
        if active_index is not None and index == active_index:
            usable_indices.append(index)
            continue

        if _probe_index_for_discovery(index, enumerated=enumerated):
            usable_indices.append(index)

    merged = merge_enumerated_with_usable_indices(
        usable_indices,
        enumerated=enumerated,
    )

    if active_device_id is None and active_index is not None:
        active_device_id = device_id_for_runtime_index(
            active_index,
            devices=merged,
        )

    cameras: list[dict[str, Any]] = []
    for device in merged:
        cameras.append(
            {
                "device_id": device.device_id,
                "display_name": device.display_name,
                "runtime_index": device.runtime_index,
                "is_active": (
                    active_index is not None
                    and device.runtime_index == active_index
                ),
                "identity_stable": device.identity_stable,
                # Legacy migration field.
                "index": device.runtime_index,
            }
        )

    return {
        "cameras": cameras,
        "active_device_id": active_device_id,
        # Legacy migration fields.
        "preferred_index": CAMERA_INDEX,
        "fallback_index": CAMERA_FALLBACK_INDEX,
        "active_index": active_index,
    }


def _discovery_cache_fresh(now: float) -> bool:
    if _discovery_cache is None:
        return False
    return (now - _discovery_cache_at) < DISCOVERY_CACHE_TTL_S


def discover_cameras(
    *,
    max_index: int = DISCOVERY_MAX_INDEX,
    force_refresh: bool = False,
) -> dict[str, Any]:
    """Return usable cameras with stable IDs, using cache and single-flight.

    Does not release an already-open shared capture. Blocking OpenCV work must
    be run off the FastAPI event loop by the caller (``asyncio.to_thread``).
    """
    global _discovery_cache, _discovery_cache_at, _discovery_scan_inflight

    now = time.monotonic()

    with _DISCOVERY_LOCK:
        if not force_refresh and _discovery_cache_fresh(now):
            logger.debug("Returning cached camera discovery result")
            return dict(_discovery_cache)

        if _discovery_scan_inflight:
            waiter = threading.Event()
            _discovery_scan_waiters.append(waiter)
            logger.debug("Waiting for in-flight camera discovery scan")
        else:
            _discovery_scan_inflight = True
            waiter = None

    if waiter is not None:
        waiter.wait()
        with _DISCOVERY_LOCK:
            if _discovery_cache is not None:
                return dict(_discovery_cache)
            # Prior scan failed without caching; become the leader.
            _discovery_scan_inflight = True

    try:
        result = _discover_cameras_impl(max_index=max_index)
    except Exception:
        with _DISCOVERY_LOCK:
            waiters = list(_discovery_scan_waiters)
            _discovery_scan_waiters.clear()
            _discovery_scan_inflight = False
        for event in waiters:
            event.set()
        raise

    with _DISCOVERY_LOCK:
        _discovery_cache = result
        _discovery_cache_at = time.monotonic()
        waiters = list(_discovery_scan_waiters)
        _discovery_scan_waiters.clear()
        _discovery_scan_inflight = False

    for event in waiters:
        event.set()

    return dict(result)


def reset_discovery_cache() -> None:
    """Clear cached discovery results (primarily for tests)."""
    global _discovery_cache, _discovery_cache_at

    with _DISCOVERY_LOCK:
        _discovery_cache = None
        _discovery_cache_at = 0.0


class CameraCapture:
    def __init__(
        self,
        index: int = CAMERA_INDEX,
        width: int = FRAME_WIDTH,
        height: int = FRAME_HEIGHT,
        *,
        camera_index: int | None = None,
        camera_device_id: str | None = None,
    ):
        """Open a webcam for a vision session.

        Keyword ``camera_device_id``:
        - ``None`` with ``camera_index is None`` → Auto-select
        - non-null string → explicit physical camera (resolved at open time)

        Keyword ``camera_index`` (legacy migration):
        - ``None`` → Auto-select when device id is also None
        - ``N`` → explicit index N with no silent fallback

        Legacy positional ``index`` remains the preferred Auto-select index when
        both keywords are omitted/None (scripts and profile tools).
        """
        self._width = width
        self._height = height
        self._blank_frame_streak = 0
        self._used_fallback = False
        self._last_read_status = CameraReadStatus.OK
        self._last_recovery_at = 0.0
        self._requested_device_id = camera_device_id
        self._active_device_id: str | None = None

        if camera_device_id is not None:
            self._auto = False
            self._selection = None
            self._auto_preferred = CAMERA_INDEX
        elif camera_index is not None:
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
    def active_device_id(self) -> str | None:
        with _CAMERA_LOCK:
            return _shared_device_id

    @property
    def used_fallback(self) -> bool:
        return self._used_fallback

    @property
    def last_read_status(self) -> CameraReadStatus:
        return self._last_read_status

    def _resolve_allowed_indices(self) -> list[int] | None:
        """Return candidate indices, or ``None`` when explicit device is missing."""
        if self._requested_device_id is not None:
            resolved = resolve_device_id_to_index(self._requested_device_id)
            if resolved is None:
                return None
            return [resolved]

        if not self._auto:
            return candidate_indices(self._selection)

        preferred = getattr(self, "_auto_preferred", CAMERA_INDEX)
        indices = [preferred]
        if CAMERA_FALLBACK_INDEX != preferred:
            indices.append(CAMERA_FALLBACK_INDEX)
        return indices

    def _adopt_opened(
        self,
        index: int,
        cap: cv2.VideoCapture,
        profile: CaptureProfile,
        *,
        device_id: str | None = None,
    ) -> None:
        global _shared_cap, _shared_index, _shared_device_id, _shared_profile

        resolved_id = device_id
        if resolved_id is None:
            if self._requested_device_id is not None:
                resolved_id = self._requested_device_id
            else:
                resolved_id = device_id_for_runtime_index(index)

        _shared_cap = cap
        _shared_index = index
        _shared_device_id = resolved_id
        _shared_profile = profile
        self._active_device_id = resolved_id
        self._blank_frame_streak = 0
        preferred = getattr(self, "_auto_preferred", CAMERA_INDEX)
        self._used_fallback = self._auto and index != preferred

    def open(self) -> bool:
        allowed = self._resolve_allowed_indices()
        mode = "auto-select" if self._auto else "explicit"
        if self._requested_device_id is not None:
            requested = self._requested_device_id
        elif self._auto:
            requested = "auto"
        else:
            requested = str(self._selection)

        if allowed is None:
            logger.error(
                "Failed to resolve selected camera_device_id=%s (disconnected or unknown)",
                self._requested_device_id,
            )
            self._last_read_status = CameraReadStatus.UNAVAILABLE
            return False

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
                self._active_device_id = _shared_device_id
                self._used_fallback = (
                    self._auto
                    and _shared_index is not None
                    and _shared_index != getattr(self, "_auto_preferred", CAMERA_INDEX)
                )
                self._last_read_status = CameraReadStatus.OK
                logger.info(
                    "Camera ready (reused): active_index=%s device_id=%s "
                    "profile=%s used_fallback=%s",
                    _shared_index,
                    _shared_device_id,
                    _shared_profile.label if _shared_profile else "unknown",
                    self._used_fallback,
                )
                return True

            _release_shared_unlocked()

            dshow_only = _explicit_selection_requires_dshow(self._requested_device_id)

            for candidate in allowed:
                opened = _open_video_capture(
                    candidate,
                    dshow_only=dshow_only and self._requested_device_id is not None,
                )

                if opened is not None:
                    cap, profile = opened
                    self._adopt_opened(candidate, cap, profile)

                    if self._used_fallback:
                        logger.warning(
                            "Camera index %s unavailable; using fallback index %s",
                            preferred,
                            candidate,
                        )

                    self._last_read_status = CameraReadStatus.OK
                    logger.info(
                        "Camera ready: active_index=%s device_id=%s profile=%s "
                        "used_fallback=%s size=%sx%s",
                        _shared_index,
                        _shared_device_id,
                        profile.label,
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
            elif self._requested_device_id is not None:
                logger.error(
                    "Failed to open selected camera_device_id=%s (no fallback).",
                    self._requested_device_id,
                )
            else:
                logger.error(
                    "Failed to open selected camera index %s (no fallback).",
                    self._selection,
                )

            self._last_read_status = CameraReadStatus.UNAVAILABLE
            return False

    def _recovery_allowed(self) -> bool:
        if _RECOVERY_COOLDOWN_S <= 0:
            return True
        return (time.monotonic() - self._last_recovery_at) >= _RECOVERY_COOLDOWN_S

    def _recover_unlocked(self) -> bool:
        """Rebuild the capture under ``_CAMERA_LOCK``. Never calls ``read()``."""
        global _shared_cap, _shared_index, _shared_profile

        failed_index = _shared_index
        failed_profile = _shared_profile
        if failed_index is None:
            return False

        self._last_read_status = CameraReadStatus.RECOVERING
        self._last_recovery_at = time.monotonic()

        logger.warning(
            "Camera recovery starting: index=%s failed_profile=%s blank_streak=%s auto=%s",
            failed_index,
            failed_profile.label if failed_profile else "unknown",
            self._blank_frame_streak,
            self._auto,
        )

        _release_shared_unlocked()

        # Same-index recovery with rotated capture profiles.
        # Re-resolve explicit device id in case the runtime index changed.
        recover_index = failed_index
        if self._requested_device_id is not None:
            resolved = resolve_device_id_to_index(self._requested_device_id)
            if resolved is None:
                logger.error(
                    "Camera recovery failed: selected device_id=%s no longer present",
                    self._requested_device_id,
                )
                self._last_read_status = CameraReadStatus.UNAVAILABLE
                return False
            recover_index = resolved

        opened = _open_video_capture(
            recover_index,
            prefer_after=failed_profile,
            dshow_only=_explicit_selection_requires_dshow(self._requested_device_id),
        )
        if opened is not None:
            cap, profile = opened
            self._adopt_opened(recover_index, cap, profile)
            logger.info(
                "Camera recovery succeeded on index %s using %s",
                recover_index,
                profile.label,
            )
            self._last_read_status = CameraReadStatus.OK
            return True

        # Auto-select may fall back only after preferred-index recovery fails.
        if self._auto:
            preferred = getattr(self, "_auto_preferred", CAMERA_INDEX)
            for candidate in self._resolve_allowed_indices() or []:
                if candidate == recover_index:
                    continue
                opened = _open_video_capture(candidate)
                if opened is not None:
                    cap, profile = opened
                    self._adopt_opened(candidate, cap, profile)
                    logger.warning(
                        "Camera recovery fell back from index %s to %s using %s",
                        preferred,
                        candidate,
                        profile.label,
                    )
                    self._last_read_status = CameraReadStatus.OK
                    return True

        logger.error(
            "Camera recovery failed for index %s (auto=%s)",
            recover_index,
            self._auto,
        )
        self._last_read_status = CameraReadStatus.UNAVAILABLE
        return False

    def _read_frame_once_unlocked(self) -> Optional[np.ndarray]:
        """Attempt a short read loop. Does not trigger recovery."""
        if _shared_cap is None or not _shared_cap.isOpened():
            return None

        for _ in range(_READ_RETRIES):
            ok, frame = _shared_cap.read()

            if not ok or frame is None:
                self._blank_frame_streak += 1
                if _STARTUP_READ_SLEEP_S > 0:
                    time.sleep(_STARTUP_READ_SLEEP_S)
                continue

            if not _frame_is_usable(frame):
                self._blank_frame_streak += 1
                if self._blank_frame_streak == 1 or self._blank_frame_streak % 30 == 0:
                    logger.warning(
                        "Camera %s returned a blank frame (streak=%s profile=%s)",
                        _shared_index,
                        self._blank_frame_streak,
                        _shared_profile.label if _shared_profile else "unknown",
                    )
                if _STARTUP_READ_SLEEP_S > 0:
                    time.sleep(_STARTUP_READ_SLEEP_S)
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

    def read(self) -> Optional[np.ndarray]:
        with _CAMERA_LOCK:
            recoveries = 0

            while True:
                frame = self._read_frame_once_unlocked()
                if frame is not None:
                    self._last_read_status = CameraReadStatus.OK
                    return frame

                if (
                    self._blank_frame_streak >= _MAX_BLANK_FRAME_STREAK
                    and recoveries < _MAX_RECOVERY_ATTEMPTS_PER_READ
                    and self._recovery_allowed()
                ):
                    if self._recover_unlocked():
                        recoveries += 1
                        continue

                    self._last_read_status = CameraReadStatus.UNAVAILABLE
                    return None

                if (
                    _shared_cap is None
                    or not _shared_cap.isOpened()
                    or self._last_read_status == CameraReadStatus.UNAVAILABLE
                ):
                    self._last_read_status = CameraReadStatus.UNAVAILABLE
                else:
                    self._last_read_status = CameraReadStatus.TEMPORARY_MISS
                return None

    def release(self) -> None:
        with _CAMERA_LOCK:
            _schedule_shared_release()
