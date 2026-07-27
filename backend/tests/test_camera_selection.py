"""Unit tests for camera selection, reuse, discovery, and WS validation."""

from __future__ import annotations

import cv2
import numpy as np

from config import CAMERA_FALLBACK_INDEX, CAMERA_INDEX, FRAME_HEIGHT, FRAME_WIDTH, TARGET_FPS
from vision import camera as camera_mod


def _usable_frame(h: int = 48, w: int = 64) -> np.ndarray:
    frame = np.full((h, w, 3), 120, dtype=np.uint8)
    frame[10:20, 10:20] = 200
    return frame


def _blank_frame(h: int = 48, w: int = 64) -> np.ndarray:
    return np.zeros((h, w, 3), dtype=np.uint8)


def _default_profile(index: int = 0) -> camera_mod.CaptureProfile:
    return camera_mod._capture_profiles(index)[0]


class _FakeCap:
    def __init__(self, *, opened: bool = True, usable: bool = True):
        self._opened = opened
        self._usable = usable
        self.released = False
        self.reads = 0
        self.set_calls: list[tuple[int, object]] = []
        self._props: dict[int, float] = {
            cv2.CAP_PROP_FRAME_WIDTH: float(FRAME_WIDTH),
            cv2.CAP_PROP_FRAME_HEIGHT: float(FRAME_HEIGHT),
            cv2.CAP_PROP_FPS: float(TARGET_FPS),
            cv2.CAP_PROP_FOURCC: float(cv2.VideoWriter_fourcc(*"MJPG")),
        }

    def isOpened(self) -> bool:
        return self._opened and not self.released

    def read(self):
        self.reads += 1
        if not self._usable:
            return True, _blank_frame()
        return True, _usable_frame()

    def release(self) -> None:
        self.released = True
        self._opened = False

    def set(self, prop, value) -> bool:
        self.set_calls.append((prop, value))
        self._props[prop] = float(value) if isinstance(value, (int, float)) else 0.0
        return True

    def get(self, prop) -> float:
        return float(self._props.get(prop, 0.0))


class _SequenceCap(_FakeCap):
    """Returns scripted frames; exhausted script yields blank frames."""

    def __init__(self, frames: list[np.ndarray | None], *, fail_ok: bool = False):
        super().__init__()
        self._frames = list(frames)
        self._fail_ok = fail_ok

    def read(self):
        self.reads += 1
        if not self._frames:
            if self._fail_ok:
                return False, None
            return True, _blank_frame()
        frame = self._frames.pop(0)
        if frame is None:
            return False, None
        return True, frame


def _opened(cap: _FakeCap, index: int = 0) -> tuple[_FakeCap, camera_mod.CaptureProfile]:
    return cap, _default_profile(index)


def _reset_shared() -> None:
    camera_mod._shared_cap = None
    camera_mod._shared_index = None
    camera_mod._shared_profile = None
    camera_mod._release_timer = None
    camera_mod._release_generation = 0


# ---------------------------------------------------------------------------
# Selection contracts
# ---------------------------------------------------------------------------


def test_auto_select_candidate_order():
    assert camera_mod.candidate_indices(None) == (
        [CAMERA_INDEX, CAMERA_FALLBACK_INDEX]
        if CAMERA_INDEX != CAMERA_FALLBACK_INDEX
        else [CAMERA_INDEX]
    )


def test_explicit_selection_has_single_candidate():
    assert camera_mod.candidate_indices(0) == [0]
    assert camera_mod.candidate_indices(1) == [1]
    assert camera_mod.candidate_indices(3) == [3]


def test_explicit_selection_never_includes_fallback():
    candidates = camera_mod.candidate_indices(1)
    assert CAMERA_FALLBACK_INDEX not in candidates or CAMERA_FALLBACK_INDEX == 1
    assert candidates == [1]


def test_shared_camera_reused_only_when_index_allowed(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 0
    camera_mod._shared_profile = _default_profile(0)
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=0)
    assert capture.open() is True
    assert opened == []
    assert camera_mod._shared_index == 0

    camera_mod._release_shared_unlocked()


def test_shared_camera_wrong_index_is_not_reused(monkeypatch):
    old = _FakeCap()
    camera_mod._shared_cap = old
    camera_mod._shared_index = 0
    camera_mod._shared_profile = _default_profile(0)
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is True
    assert old.released is True
    assert opened == [1]
    assert camera_mod._shared_index == 1

    camera_mod._release_shared_unlocked()


def test_auto_does_not_reuse_sticky_fallback_when_preferred_differs(monkeypatch):
    if CAMERA_INDEX == CAMERA_FALLBACK_INDEX:
        return

    old = _FakeCap()
    camera_mod._shared_cap = old
    camera_mod._shared_index = CAMERA_FALLBACK_INDEX
    camera_mod._shared_profile = _default_profile(CAMERA_FALLBACK_INDEX)
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        if index == CAMERA_INDEX:
            return _opened(_FakeCap(), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=None)
    assert capture.open() is True
    assert opened[0] == CAMERA_INDEX
    assert camera_mod._shared_index == CAMERA_INDEX

    camera_mod._release_shared_unlocked()


def test_explicit_open_does_not_try_fallback(monkeypatch):
    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is False
    assert tried == [1]


def test_auto_open_tries_preferred_then_fallback(monkeypatch):
    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        if index == CAMERA_FALLBACK_INDEX:
            return _opened(_FakeCap(), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_index=None)
    assert capture.open() is True
    assert tried[0] == CAMERA_INDEX
    if CAMERA_INDEX != CAMERA_FALLBACK_INDEX:
        assert CAMERA_FALLBACK_INDEX in tried
    assert camera_mod._shared_index == CAMERA_FALLBACK_INDEX

    camera_mod._release_shared_unlocked()


def test_parse_camera_index_rejects_invalid_values():
    from api.websocket import parse_camera_index

    assert parse_camera_index(None) == (None, None)
    assert parse_camera_index(1) == (1, None)
    assert parse_camera_index(0) == (0, None)

    value, error = parse_camera_index(True)
    assert value is None
    assert error == "invalid_camera_index"

    value, error = parse_camera_index(-1)
    assert value is None
    assert error == "invalid_camera_index"

    value, error = parse_camera_index(11)
    assert value is None
    assert error == "invalid_camera_index"

    value, error = parse_camera_index(1.5)
    assert value is None
    assert error == "invalid_camera_index"


def test_discover_cameras_excludes_blank_frames(monkeypatch):
    def open_or_none(index: int, **_kwargs):
        if index == 1:
            return _opened(_FakeCap(usable=True), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", open_or_none)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    result = camera_mod.discover_cameras(max_index=2)
    assert [c["index"] for c in result["cameras"]] == [1]
    assert result["preferred_index"] == CAMERA_INDEX
    assert result["fallback_index"] == CAMERA_FALLBACK_INDEX
    assert result["active_index"] is None


def test_discover_cameras_includes_active_shared_without_reopen(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 0
    camera_mod._shared_profile = _default_profile(0)

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        if index == 1:
            return _opened(_FakeCap(), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    result = camera_mod.discover_cameras(max_index=1)
    assert [c["index"] for c in result["cameras"]] == [0, 1]
    assert result["active_index"] == 0
    assert 0 not in opened
    assert fake.released is False

    camera_mod._release_shared_unlocked()


def test_cameras_endpoint_structure(monkeypatch):
    import asyncio

    from api import cameras as cameras_api

    monkeypatch.setattr(
        cameras_api,
        "discover_cameras",
        lambda max_index=4: {
            "cameras": [
                {
                    "index": 0,
                    "display_name": camera_mod.camera_display_name(0),
                }
            ],
            "preferred_index": CAMERA_INDEX,
            "fallback_index": CAMERA_FALLBACK_INDEX,
            "active_index": None,
        },
    )

    body = asyncio.run(cameras_api.list_cameras())
    payload = body.model_dump()
    assert payload["cameras"][0]["display_name"] == camera_mod.camera_display_name(0)
    assert "preferred_index" in payload
    assert "fallback_index" in payload
    assert "active_index" in payload


# ---------------------------------------------------------------------------
# Capture profile ordering
# ---------------------------------------------------------------------------


def test_external_windows_profiles_prefer_mjpg_first(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    profiles = camera_mod._capture_profiles(1)
    assert len(profiles) == 4
    assert [p.use_mjpg for p in profiles] == [True, True, False, False]
    assert profiles[0].api == cv2.CAP_DSHOW
    assert profiles[0].label == "DirectShow + MJPG"
    assert profiles[1].api == cv2.CAP_MSMF
    assert profiles[1].label == "Media Foundation + MJPG"
    assert profiles[2].label == "DirectShow + default"
    assert profiles[3].label == "Media Foundation + default"


def test_builtin_windows_profiles_prefer_default_first(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    profiles = camera_mod._capture_profiles(0)
    assert len(profiles) == 4
    assert [p.use_mjpg for p in profiles] == [False, False, True, True]
    assert profiles[0].label == "DirectShow + default"
    assert profiles[1].label == "Media Foundation + default"
    assert profiles[2].label == "DirectShow + MJPG"
    assert profiles[3].label == "Media Foundation + MJPG"


def test_windows_profiles_include_both_mjpg_and_default(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    for index in (0, 1, 2):
        flags = {p.use_mjpg for p in camera_mod._capture_profiles(index)}
        assert flags == {True, False}
        apis = {p.api for p in camera_mod._capture_profiles(index)}
        assert apis == {cv2.CAP_DSHOW, cv2.CAP_MSMF}


def test_rotate_profiles_starts_after_failed():
    monkeypatch_profiles = [
        camera_mod.CaptureProfile(cv2.CAP_DSHOW, "DirectShow", True, "DirectShow + MJPG"),
        camera_mod.CaptureProfile(cv2.CAP_MSMF, "Media Foundation", True, "Media Foundation + MJPG"),
        camera_mod.CaptureProfile(cv2.CAP_DSHOW, "DirectShow", False, "DirectShow + default"),
        camera_mod.CaptureProfile(cv2.CAP_MSMF, "Media Foundation", False, "Media Foundation + default"),
    ]
    rotated = camera_mod._profiles_starting_after(
        monkeypatch_profiles,
        monkeypatch_profiles[0],
    )
    assert rotated[0].label == "Media Foundation + MJPG"
    assert rotated[-1].label == "DirectShow + MJPG"


# ---------------------------------------------------------------------------
# FPS / capture settings
# ---------------------------------------------------------------------------


def test_apply_capture_settings_sets_fps():
    cap = _FakeCap()
    camera_mod._apply_capture_settings(cap, use_mjpg=False)
    props = [p for p, _ in cap.set_calls]
    assert cv2.CAP_PROP_FPS in props
    fps_value = next(v for p, v in cap.set_calls if p == cv2.CAP_PROP_FPS)
    assert fps_value == TARGET_FPS
    assert cv2.CAP_PROP_FRAME_WIDTH in props
    assert cv2.CAP_PROP_FRAME_HEIGHT in props
    assert cv2.CAP_PROP_BUFFERSIZE in props


def test_apply_capture_settings_sets_mjpg_before_dimensions_and_fps():
    cap = _FakeCap()
    camera_mod._apply_capture_settings(cap, use_mjpg=True)
    props = [p for p, _ in cap.set_calls]
    assert props[0] == cv2.CAP_PROP_FOURCC
    assert props.index(cv2.CAP_PROP_FOURCC) < props.index(cv2.CAP_PROP_FRAME_WIDTH)
    assert props.index(cv2.CAP_PROP_FOURCC) < props.index(cv2.CAP_PROP_FPS)


# ---------------------------------------------------------------------------
# Startup validation
# ---------------------------------------------------------------------------


def test_startup_one_valid_frame_is_not_enough(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    frames = [_usable_frame()] + [_blank_frame()] * 40
    cap = _SequenceCap(frames)
    ok, _ = camera_mod._probe_stable_startup(cap)
    assert ok is False


def test_startup_required_consecutive_usable_frames_succeed(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    needed = camera_mod._STARTUP_REQUIRED_CONSECUTIVE_FRAMES
    cap = _SequenceCap([_usable_frame() for _ in range(needed)])
    ok, frame = camera_mod._probe_stable_startup(cap)
    assert ok is True
    assert frame is not None
    assert camera_mod._frame_is_usable(frame)


def test_startup_blank_frame_resets_consecutive_counter(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    needed = camera_mod._STARTUP_REQUIRED_CONSECUTIVE_FRAMES
    # Almost enough, then blank, then almost enough again — never reaches N consecutive.
    frames = (
        [_usable_frame() for _ in range(needed - 1)]
        + [_blank_frame()]
        + [_usable_frame() for _ in range(needed - 1)]
        + [_blank_frame()] * 30
    )
    cap = _SequenceCap(frames)
    ok, _ = camera_mod._probe_stable_startup(cap)
    assert ok is False


def test_startup_timeout_rejects_unstable_profile(monkeypatch):
    clock = {"t": 0.0}

    def fake_monotonic():
        return clock["t"]

    def fake_sleep(seconds=0):
        clock["t"] += float(seconds) if seconds else camera_mod._STARTUP_READ_SLEEP_S
        if clock["t"] < camera_mod._STARTUP_TIMEOUT_S:
            clock["t"] = camera_mod._STARTUP_TIMEOUT_S + 0.01

    monkeypatch.setattr(camera_mod.time, "monotonic", fake_monotonic)
    monkeypatch.setattr(camera_mod.time, "sleep", fake_sleep)

    cap = _SequenceCap([_usable_frame(), _blank_frame()] * 5)
    ok, _ = camera_mod._probe_stable_startup(cap)
    assert ok is False


# ---------------------------------------------------------------------------
# Shared-camera reuse
# ---------------------------------------------------------------------------


def test_healthy_shared_capture_is_reused(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._release_timer = None
    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is True
    assert opened == []
    assert fake.released is False
    assert camera_mod._shared_index == 1

    camera_mod._release_shared_unlocked()


def test_unstable_shared_capture_is_released_and_reopened(monkeypatch):
    needed = camera_mod._STARTUP_REQUIRED_CONSECUTIVE_FRAMES
    # Only two usable frames — not enough consecutive stability for reuse.
    unstable = _SequenceCap(
        [_usable_frame(), _usable_frame()] + [_blank_frame()] * (needed + 5)
    )
    camera_mod._shared_cap = unstable
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is True
    assert unstable.released is True
    assert opened == [1]
    assert camera_mod._shared_index == 1

    camera_mod._release_shared_unlocked()


def test_shared_reuse_requires_profile_metadata(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 1
    camera_mod._shared_profile = None
    camera_mod._release_timer = None
    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is True
    assert fake.released is True
    assert opened == [1]

    camera_mod._release_shared_unlocked()


def test_stale_release_timer_cannot_close_recovered_capture(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    first = _FakeCap()
    second = _FakeCap()
    opens = {"n": 0}

    def fake_open(index: int, **_kwargs):
        opens["n"] += 1
        return _opened(first if opens["n"] == 1 else second, index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is True
    assert camera_mod._shared_cap is first

    # Schedule a delayed release, then open again (cancels / bumps generation).
    capture.release()
    stale_generation = camera_mod._release_generation
    assert capture.open() is True
    assert camera_mod._shared_cap is first  # reused healthy capture

    # Simulate the stale timer callback that was already waiting on the lock.
    camera_mod._run_scheduled_release(stale_generation)
    assert first.released is False
    assert camera_mod._shared_cap is first

    camera_mod._release_shared_unlocked()


# ---------------------------------------------------------------------------
# Runtime recovery
# ---------------------------------------------------------------------------


def test_persistent_blank_frames_trigger_same_index_recovery(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 3)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    _reset_shared()

    blank = _FakeCap(usable=False)
    healthy = _FakeCap(usable=True)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)

    recovered = []

    def fake_open(index: int, **kwargs):
        recovered.append((index, kwargs.get("prefer_after")))
        return _opened(healthy, index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    # Drive blank streak just below the recovery threshold.
    for _ in range(2):
        assert capture.read() is None

    # Third blank reaches the threshold and recovers on the same read().
    frame = capture.read()
    assert frame is not None
    assert blank.released is True
    assert camera_mod._shared_cap is healthy
    assert camera_mod._shared_index == 1
    assert all(idx == 1 for idx, _ in recovered)
    assert capture._blank_frame_streak == 0

    camera_mod._release_shared_unlocked()


def test_explicit_recovery_never_switches_to_fallback(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 2)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    _reset_shared()

    blank = _FakeCap(usable=False)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)

    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.read() is None
    assert capture.read() is None

    assert tried
    assert all(i == 1 for i in tried)
    assert CAMERA_FALLBACK_INDEX not in tried or CAMERA_FALLBACK_INDEX == 1
    assert capture.last_read_status == camera_mod.CameraReadStatus.UNAVAILABLE

    camera_mod._release_shared_unlocked()


def test_auto_select_fallback_only_after_preferred_recovery_fails(monkeypatch):
    if CAMERA_INDEX == CAMERA_FALLBACK_INDEX:
        return

    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 2)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    _reset_shared()

    blank = _FakeCap(usable=False)
    fallback = _FakeCap(usable=True)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = CAMERA_INDEX
    camera_mod._shared_profile = _default_profile(CAMERA_INDEX)

    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        if index == CAMERA_FALLBACK_INDEX:
            return _opened(fallback, index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=None)
    assert capture.read() is None

    frame = capture.read()
    assert frame is not None
    assert tried[0] == CAMERA_INDEX
    assert CAMERA_FALLBACK_INDEX in tried
    assert tried.index(CAMERA_INDEX) < tried.index(CAMERA_FALLBACK_INDEX)
    assert camera_mod._shared_index == CAMERA_FALLBACK_INDEX
    assert capture.used_fallback is True

    camera_mod._release_shared_unlocked()


def test_successful_recovery_resets_blank_streak(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 2)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    _reset_shared()

    blank = _FakeCap(usable=False)
    healthy = _FakeCap(usable=True)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)

    def fake_open(index: int, **_kwargs):
        return _opened(healthy, index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    capture._blank_frame_streak = 2
    frame = capture.read()
    assert frame is not None
    assert capture._blank_frame_streak == 0

    camera_mod._release_shared_unlocked()


def test_failed_recovery_returns_none_without_deadlock(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 1)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    monkeypatch.setattr(camera_mod, "_MAX_RECOVERY_ATTEMPTS_PER_READ", 1)
    _reset_shared()

    blank = _FakeCap(usable=False)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)

    monkeypatch.setattr(camera_mod, "_open_video_capture", lambda *a, **k: None)

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.read() is None
    assert capture.last_read_status == camera_mod.CameraReadStatus.UNAVAILABLE
    # Second call still returns promptly (cooldown / no hang).
    assert capture.read() is None

    camera_mod._release_shared_unlocked()


def test_recovery_passes_prefer_after_failed_profile(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 1)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_READ_RETRIES", 1)
    _reset_shared()

    failed_profile = _default_profile(1)
    blank = _FakeCap(usable=False)
    healthy = _FakeCap(usable=True)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = failed_profile

    seen = {}

    def fake_open(index: int, **kwargs):
        seen["prefer_after"] = kwargs.get("prefer_after")
        return _opened(healthy, index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    capture._blank_frame_streak = 1
    assert capture.read() is not None
    assert seen["prefer_after"] == failed_profile

    camera_mod._release_shared_unlocked()
