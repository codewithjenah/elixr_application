"""Unit tests for camera selection, reuse, discovery, and WS validation."""

from __future__ import annotations

import cv2
import numpy as np
import threading
import time

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
    camera_mod._stop_capture_producer()
    camera_mod._shared_cap = None
    camera_mod._shared_index = None
    camera_mod._shared_device_id = None
    camera_mod._shared_profile = None
    camera_mod._release_timer = None
    camera_mod._release_generation = 0
    camera_mod.reset_discovery_cache()


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


def test_parse_camera_selection_prefers_device_id():
    from api.websocket import parse_camera_selection

    device_id, index, error = parse_camera_selection(
        {"camera_device_id": "\\\\?\\usb#vid_1234", "camera_index": 1}
    )
    assert device_id == "\\\\?\\usb#vid_1234"
    assert index is None
    assert error is None

    device_id, index, error = parse_camera_selection({"camera_device_id": None})
    assert device_id is None
    assert index is None
    assert error is None

    device_id, index, error = parse_camera_selection({"camera_index": 1})
    assert device_id is None
    assert index == 1
    assert error is None

    device_id, index, error = parse_camera_selection({"camera_device_id": ""})
    assert error == "invalid_camera_device_id"


def test_explicit_device_id_resolves_current_index(monkeypatch):
    from vision import camera_devices
    from vision.camera_devices import EnumeratedCamera

    monkeypatch.setattr(
        camera_devices,
        "enumerate_camera_devices",
        lambda: [
            EnumeratedCamera("dev-a", "Integrated Camera", 1, True),
            EnumeratedCamera("dev-b", "HIKVISION", 0, True),
        ],
    )

    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_device_id="dev-b")
    assert capture.open() is True
    assert tried == [0]
    assert camera_mod._shared_index == 0
    assert camera_mod._shared_device_id == "dev-b"

    camera_mod._release_shared_unlocked()


def test_explicit_device_id_missing_does_not_fallback(monkeypatch):
    from vision import camera_devices

    monkeypatch.setattr(camera_devices, "enumerate_camera_devices", lambda: [])
    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_device_id="missing-device")
    assert capture.open() is False
    assert tried == []


def test_device_reorder_keeps_selected_physical_camera(monkeypatch):
    from vision import camera_devices
    from vision.camera_devices import EnumeratedCamera

    # After reorder, HIKVISION (dev-b) is at runtime index 0.
    monkeypatch.setattr(
        camera_devices,
        "enumerate_camera_devices",
        lambda: [
            EnumeratedCamera("dev-b", "HIKVISION", 0, True),
            EnumeratedCamera("dev-a", "Integrated Camera", 1, True),
        ],
    )

    tried = []

    def fake_open(index: int, **_kwargs):
        tried.append(index)
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_device_id="dev-b")
    assert capture.open() is True
    assert camera_mod._shared_index == 0
    assert tried == [0]

    camera_mod._release_shared_unlocked()



def test_discover_cameras_excludes_blank_frames(monkeypatch):
    def open_or_none(index: int, **_kwargs):
        if index == 1:
            return _opened(_FakeCap(usable=True), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", open_or_none)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(
        camera_mod,
        "enumerate_camera_devices",
        lambda: [],
    )
    _reset_shared()

    result = camera_mod.discover_cameras(max_index=2, force_refresh=True)
    assert [c["runtime_index"] for c in result["cameras"]] == [1]
    assert result["cameras"][0]["display_name"] == "Camera 1"
    assert result["cameras"][0]["identity_stable"] is False
    assert result["preferred_index"] == CAMERA_INDEX
    assert result["fallback_index"] == CAMERA_FALLBACK_INDEX
    assert result["active_index"] is None
    assert "active_device_id" in result


def test_discover_cameras_includes_active_shared_without_reopen(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 0
    camera_mod._shared_device_id = "opencv:0"
    camera_mod._shared_profile = _default_profile(0)

    opened = []

    def fake_open(index: int, **_kwargs):
        opened.append(index)
        if index == 1:
            return _opened(_FakeCap(), index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "enumerate_camera_devices", lambda: [])

    result = camera_mod.discover_cameras(max_index=1, force_refresh=True)
    assert [c["runtime_index"] for c in result["cameras"]] == [0, 1]
    assert result["active_index"] == 0
    assert result["active_device_id"] == "opencv:0"
    assert 0 not in opened
    assert fake.released is False

    camera_mod._release_shared_unlocked()


def test_cameras_endpoint_structure(monkeypatch):
    import asyncio

    from api import cameras as cameras_api

    monkeypatch.setattr(
        cameras_api,
        "discover_cameras",
        lambda max_index=4, force_refresh=False: {
            "cameras": [
                {
                    "device_id": "opencv:0",
                    "display_name": "Camera 0",
                    "runtime_index": 0,
                    "is_active": False,
                    "identity_stable": False,
                    "index": 0,
                }
            ],
            "active_device_id": None,
            "preferred_index": CAMERA_INDEX,
            "fallback_index": CAMERA_FALLBACK_INDEX,
            "active_index": None,
        },
    )

    body = asyncio.run(cameras_api.list_cameras())
    payload = body.model_dump()
    assert payload["cameras"][0]["display_name"] == "Camera 0"
    assert payload["cameras"][0]["device_id"] == "opencv:0"
    assert "preferred_index" in payload
    assert "fallback_index" in payload
    assert "active_index" in payload
    assert "active_device_id" in payload


def test_cameras_endpoint_plumbs_force_refresh(monkeypatch):
    import asyncio

    from api import cameras as cameras_api

    seen = {}

    def fake_discover(max_index=4, force_refresh=False):
        seen["force_refresh"] = force_refresh
        return {
            "cameras": [],
            "active_device_id": None,
            "preferred_index": CAMERA_INDEX,
            "fallback_index": CAMERA_FALLBACK_INDEX,
            "active_index": None,
        }

    monkeypatch.setattr(cameras_api, "discover_cameras", fake_discover)

    asyncio.run(cameras_api.list_cameras(force_refresh=False))
    assert seen["force_refresh"] is False

    asyncio.run(cameras_api.list_cameras(force_refresh=True))
    assert seen["force_refresh"] is True


# ---------------------------------------------------------------------------
# Discovery enumeration, cache, and backend consistency
# ---------------------------------------------------------------------------


def test_discovery_probes_only_enumerated_indices(monkeypatch):
    from vision.camera_devices import EnumeratedCamera

    probed: list[int] = []

    def fake_probe(index: int, *, enumerated):
        probed.append(index)
        return index in {1, 3}

    monkeypatch.setattr(camera_mod, "_probe_index_for_discovery", fake_probe)
    monkeypatch.setattr(
        camera_mod,
        "enumerate_camera_devices",
        lambda: [
            EnumeratedCamera("dev-a", "Integrated Camera", 1, True),
            EnumeratedCamera("dev-b", "HIKVISION", 3, True),
        ],
    )
    _reset_shared()

    result = camera_mod.discover_cameras(max_index=4, force_refresh=True)
    assert probed == [1, 3]
    assert [c["runtime_index"] for c in result["cameras"]] == [1, 3]


def test_discovery_uses_blind_index_fallback_when_enumeration_empty(monkeypatch):
    probed: list[int] = []

    def fake_probe(index: int, *, enumerated):
        probed.append(index)
        return index == 2

    monkeypatch.setattr(camera_mod, "_probe_index_for_discovery", fake_probe)
    monkeypatch.setattr(camera_mod, "enumerate_camera_devices", lambda: [])
    _reset_shared()

    result = camera_mod.discover_cameras(max_index=2, force_refresh=True)
    assert probed == [0, 1, 2]
    assert [c["runtime_index"] for c in result["cameras"]] == [2]


def test_discovery_probe_uses_bounded_settings(monkeypatch):
    used = {"discovery": False, "startup": False}

    def fake_discovery(*_args, **_kwargs):
        used["discovery"] = True
        return True, _usable_frame()

    def fake_startup(*_args, **_kwargs):
        used["startup"] = True
        return True, _usable_frame()

    monkeypatch.setattr(camera_mod, "_probe_discovery", fake_discovery)
    monkeypatch.setattr(camera_mod, "_probe_stable_startup", fake_startup)
    monkeypatch.setattr(
        camera_mod,
        "_create_capture",
        lambda index, profile: _FakeCap(),
    )
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)

    assert camera_mod._open_video_capture(0, for_discovery=True) is not None
    assert used["discovery"] is True
    assert used["startup"] is False

    used["discovery"] = False
    assert camera_mod._open_video_capture(0, for_discovery=False) is not None
    assert used["discovery"] is False
    assert used["startup"] is True


def test_discover_cameras_reuses_cache(monkeypatch):
    calls = {"n": 0}

    def fake_impl(**_kwargs):
        calls["n"] += 1
        return {
            "cameras": [],
            "active_device_id": None,
            "preferred_index": CAMERA_INDEX,
            "fallback_index": CAMERA_FALLBACK_INDEX,
            "active_index": None,
        }

    monkeypatch.setattr(camera_mod, "_discover_cameras_impl", fake_impl)
    _reset_shared()

    first = camera_mod.discover_cameras(force_refresh=True)
    second = camera_mod.discover_cameras()
    assert calls["n"] == 1
    assert first == second


def test_overlapping_discovery_scans_share_single_flight(monkeypatch):
    import threading

    calls = {"n": 0}
    started = threading.Event()
    release = threading.Event()

    def slow_impl(**_kwargs):
        calls["n"] += 1
        started.set()
        release.wait(timeout=2.0)
        return {
            "cameras": [],
            "active_device_id": None,
            "preferred_index": CAMERA_INDEX,
            "fallback_index": CAMERA_FALLBACK_INDEX,
            "active_index": None,
        }

    monkeypatch.setattr(camera_mod, "_discover_cameras_impl", slow_impl)
    _reset_shared()

    results: list[dict] = []

    def worker():
        results.append(camera_mod.discover_cameras(force_refresh=True))

    first = threading.Thread(target=worker)
    second = threading.Thread(target=worker)
    first.start()
    assert started.wait(timeout=2.0)
    second.start()
    release.set()
    first.join(timeout=2.0)
    second.join(timeout=2.0)

    assert calls["n"] == 1
    assert len(results) == 2


def test_explicit_stable_device_uses_directshow_only(monkeypatch):
    from vision import camera_devices
    from vision.camera_devices import EnumeratedCamera

    monkeypatch.setattr(
        camera_devices,
        "enumerate_camera_devices",
        lambda: [EnumeratedCamera("dev-a", "Integrated Camera", 1, True)],
    )

    seen: list[bool] = []

    def fake_open(index: int, **kwargs):
        seen.append(kwargs.get("dshow_only", False))
        return _opened(_FakeCap(), index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    _reset_shared()

    capture = camera_mod.CameraCapture(camera_device_id="dev-a")
    assert capture.open() is True
    assert seen == [True]

    camera_mod._release_shared_unlocked()


def test_explicit_device_open_never_uses_msmf_profile(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    profiles = camera_mod._capture_profiles(0, dshow_only=True)
    assert profiles
    assert all(profile.api == camera_mod.cv2.CAP_DSHOW for profile in profiles)
    assert all(profile.api != camera_mod.cv2.CAP_MSMF for profile in profiles)


# ---------------------------------------------------------------------------
# Capture profile ordering
# ---------------------------------------------------------------------------


def test_windows_profiles_prefer_mjpg_first_for_all_indices(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    for index in (0, 1, 2):
        profiles = camera_mod._capture_profiles(index)
        assert len(profiles) == 4
        assert [p.use_mjpg for p in profiles] == [True, True, False, False]
        assert profiles[0].api == cv2.CAP_DSHOW
        assert profiles[0].label == "DirectShow + MJPG"
        assert profiles[1].api == cv2.CAP_MSMF
        assert profiles[1].label == "Media Foundation + MJPG"
        assert profiles[2].label == "DirectShow + default"
        assert profiles[3].label == "Media Foundation + default"


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

# ---------------------------------------------------------------------------
# Latest-frame capture producer
# ---------------------------------------------------------------------------


class _SlowSequenceCap(_FakeCap):
    """Yields marked frames; tracks reads after release."""

    def __init__(self, frames: list[np.ndarray], *, read_delay_s: float = 0.0):
        super().__init__()
        self._frames = list(frames)
        self._read_delay_s = read_delay_s
        self.reads_after_release = 0

    def read(self):
        if self.released:
            self.reads_after_release += 1
            return False, None
        if self._read_delay_s > 0:
            time.sleep(self._read_delay_s)
        self.reads += 1
        if not self._frames:
            return True, _usable_frame()
        return True, self._frames.pop(0)


def test_latest_frame_slot_overwrites_unconsumed_frame():
    slot = camera_mod._LatestFrameSlot()
    first = camera_mod.CapturedFrame(_usable_frame(), 1.0, 1)
    second = camera_mod.CapturedFrame(_usable_frame(h=64, w=80), 2.0, 2)
    slot.publish(first)
    slot.publish(second)
    assert slot.overwrite_count == 1
    taken = slot.take(timeout=0)
    assert taken is not None
    assert taken.sequence == 2
    assert taken.frame.shape[0] == 64
    assert slot.take(timeout=0) is None


def test_capture_producer_keeps_only_newest_frame(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    _reset_shared()

    frames = [_usable_frame() for _ in range(8)]
    for i, frame in enumerate(frames):
        frame[0, 0] = i + 1
    cap = _SlowSequenceCap(frames)
    camera_mod._start_capture_producer(cap, width=64, height=48)

    deadline = time.monotonic() + 2.0
    while camera_mod.latest_frame_overwrite_count() < 3 and time.monotonic() < deadline:
        time.sleep(0.01)

    assert camera_mod.latest_frame_overwrite_count() >= 1
    assert camera_mod.capture_producer_is_alive()

    capture = camera_mod.CameraCapture(camera_index=1)
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)

    got = capture.read()
    assert got is not None
    # Newest published marker should be greater than the first frame's marker.
    assert int(got[0, 0, 0]) >= 2

    camera_mod._release_shared_unlocked()
    assert camera_mod.capture_producer_is_alive() is False
    assert cap.released is True
    time.sleep(0.05)
    assert cap.reads_after_release == 0


def test_blocked_producer_release_does_not_race_with_read(monkeypatch):
    """Release must not call VideoCapture.release while read() is in flight."""
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod, "_PRODUCER_JOIN_TIMEOUT_S", 0.15)
    _reset_shared()

    join_timeout = camera_mod._PRODUCER_JOIN_TIMEOUT_S
    block_s = join_timeout + 0.35
    # Use Event.wait so monkeypatched time.sleep cannot shorten the block.
    block_gate = threading.Event()

    class _BlockingCap(_FakeCap):
        def __init__(self):
            super().__init__()
            self.read_entered = threading.Event()
            self.release_while_reading = False

        def read(self):
            self.read_entered.set()
            block_gate.wait(timeout=block_s)
            if self.released:
                self.release_while_reading = True
                return False, None
            self.reads += 1
            return True, _usable_frame()

    cap = _BlockingCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    assert camera_mod._start_capture_producer(cap, width=64, height=48)

    assert cap.read_entered.wait(timeout=2.0)
    # Release while producer is blocked in read() longer than join timeout.
    camera_mod._release_shared_unlocked()

    assert camera_mod.capture_producer_shutdown_completed()
    assert camera_mod.capture_producer_is_alive() is False
    # Must not have released during the blocked read.
    assert cap.release_while_reading is False
    assert cap.released is False

    block_gate.set()
    deadline = time.monotonic() + 2.0
    while not cap.released and time.monotonic() < deadline:
        time.sleep(0.02)
    assert cap.released is True
    assert cap.release_while_reading is False


def test_blocked_producer_cannot_publish_into_replacement_slot(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    monkeypatch.setattr(camera_mod, "_PRODUCER_JOIN_TIMEOUT_S", 0.1)
    _reset_shared()

    allow_first = threading.Event()
    entered_first = threading.Event()

    class _GatedCap(_FakeCap):
        def __init__(self, marker: int):
            super().__init__()
            self.marker = marker
            self._first = True

        def read(self):
            if self._first:
                self._first = False
                entered_first.set()
                allow_first.wait(timeout=2.0)
            self.reads += 1
            frame = _usable_frame()
            frame[0, 0] = self.marker
            return True, frame

    old = _GatedCap(marker=11)
    new = _FakeCap(usable=True)
    camera_mod._shared_cap = old
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(old, width=64, height=48)
    assert entered_first.wait(timeout=2.0)

    old_slot = camera_mod._latest_frame_slot
    # Replacement while old producer is blocked.
    camera_mod._release_shared_unlocked()
    camera_mod._shared_cap = new
    camera_mod._shared_index = 2
    camera_mod._shared_profile = _default_profile(2)
    assert camera_mod._start_capture_producer(new, width=64, height=48)
    new_slot = camera_mod._latest_frame_slot
    assert new_slot is not old_slot

    allow_first.set()
    deadline = time.monotonic() + 2.0
    while not old.released and time.monotonic() < deadline:
        time.sleep(0.02)
    assert old.released is True

    # New slot must never receive the old producer's marker frame.
    taken = new_slot.take(timeout=0.2) if new_slot is not None else None
    if taken is not None:
        assert int(taken.frame[0, 0, 0]) != 11


def test_published_frame_is_independent_of_camera_buffer(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    _reset_shared()

    class _MutatingCap(_FakeCap):
        def __init__(self):
            super().__init__()
            self._buf = _usable_frame()
            self._marker = 1

        def read(self):
            self.reads += 1
            self._buf[:] = 120
            self._buf[10:20, 10:20] = 200
            self._buf[0, 0] = self._marker
            self._marker += 1
            # Contiguous buffer: ascontiguousarray would not copy.
            assert self._buf.flags["C_CONTIGUOUS"]
            return True, self._buf

    cap = _MutatingCap()
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(cap, width=64, height=48)

    slot = camera_mod._latest_frame_slot
    assert slot is not None
    captured = None
    deadline = time.monotonic() + 2.0
    while captured is None and time.monotonic() < deadline:
        captured = slot.take(timeout=0.05)
    assert captured is not None
    published_marker = int(captured.frame[0, 0, 0])
    # Mutate the camera's reused buffer after publish.
    cap._buf[:] = 0
    assert int(captured.frame[0, 0, 0]) == published_marker
    assert captured.frame.flags["C_CONTIGUOUS"]

    camera_mod._release_shared_unlocked()


def test_capture_producer_stops_before_release_and_recovery(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_MAX_BLANK_FRAME_STREAK", 2)
    monkeypatch.setattr(camera_mod, "_RECOVERY_COOLDOWN_S", 0.0)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    _reset_shared()

    blank = _FakeCap(usable=False)
    healthy = _FakeCap(usable=True)
    camera_mod._shared_cap = blank
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(blank, width=64, height=48)
    assert camera_mod.capture_producer_is_alive()

    def fake_open(index: int, **_kwargs):
        return _opened(healthy, index)

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=1)
    deadline = time.monotonic() + 2.0
    while camera_mod._producer_blank_streak < 2 and time.monotonic() < deadline:
        time.sleep(0.01)

    frame = capture.read()
    assert frame is not None
    assert blank.released is True
    assert camera_mod._shared_cap is healthy
    assert camera_mod.capture_producer_is_alive()
    assert camera_mod._capture_producer._cap is healthy

    camera_mod._release_shared_unlocked()
    assert camera_mod.capture_producer_is_alive() is False


def test_stop_and_recovery_do_not_deadlock_with_producer(monkeypatch):
    monkeypatch.setattr(camera_mod.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(camera_mod, "_STARTUP_READ_SLEEP_S", 0.0)
    _reset_shared()

    cap = _FakeCap(usable=True)
    camera_mod._shared_cap = cap
    camera_mod._shared_index = 1
    camera_mod._shared_profile = _default_profile(1)
    camera_mod._start_capture_producer(cap, width=64, height=48)

    capture = camera_mod.CameraCapture(camera_index=1)
    frame = None
    deadline = time.monotonic() + 2.0
    while frame is None and time.monotonic() < deadline:
        frame = capture.read()
        if frame is None:
            time.sleep(0.01)
    assert frame is not None
    capture.release()
    # Scheduled release path joins the producer under the camera lock.
    camera_mod._run_scheduled_release(camera_mod._release_generation)
    assert camera_mod.capture_producer_is_alive() is False
    assert cap.released is True
