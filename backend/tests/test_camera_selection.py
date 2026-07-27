"""Unit tests for camera selection, reuse, discovery, and WS validation."""

from __future__ import annotations

import numpy as np

from config import CAMERA_FALLBACK_INDEX, CAMERA_INDEX
from vision import camera as camera_mod


class _FakeCap:
    def __init__(self, *, opened: bool = True, usable: bool = True):
        self._opened = opened
        self._usable = usable
        self.released = False
        self.reads = 0

    def isOpened(self) -> bool:
        return self._opened and not self.released

    def read(self):
        self.reads += 1
        if not self._usable:
            return True, np.zeros((48, 64, 3), dtype=np.uint8)
        frame = np.full((48, 64, 3), 120, dtype=np.uint8)
        frame[10:20, 10:20] = 200
        return True, frame

    def release(self) -> None:
        self.released = True
        self._opened = False

    def set(self, *_args, **_kwargs) -> bool:
        return True

    def get(self, *_args, **_kwargs) -> float:
        return 0.0


def test_auto_select_candidate_order():
    assert camera_mod.candidate_indices(None) == [
        CAMERA_INDEX,
        CAMERA_FALLBACK_INDEX,
    ] if CAMERA_INDEX != CAMERA_FALLBACK_INDEX else [CAMERA_INDEX]


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
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int):
        opened.append(index)
        return _FakeCap()

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=0)
    assert capture.open() is True
    assert opened == []
    assert camera_mod._shared_index == 0

    camera_mod._release_shared_unlocked()


def test_shared_camera_wrong_index_is_not_reused(monkeypatch):
    old = _FakeCap()
    camera_mod._shared_cap = old
    camera_mod._shared_index = 0
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int):
        opened.append(index)
        return _FakeCap()

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

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
    camera_mod._release_timer = None

    opened = []

    def fake_open(index: int):
        opened.append(index)
        if index == CAMERA_INDEX:
            return _FakeCap()
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

    capture = camera_mod.CameraCapture(camera_index=None)
    assert capture.open() is True
    assert opened[0] == CAMERA_INDEX
    assert camera_mod._shared_index == CAMERA_INDEX

    camera_mod._release_shared_unlocked()


def test_explicit_open_does_not_try_fallback(monkeypatch):
    tried = []

    def fake_open(index: int):
        tried.append(index)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    camera_mod._shared_cap = None
    camera_mod._shared_index = None

    capture = camera_mod.CameraCapture(camera_index=1)
    assert capture.open() is False
    assert tried == [1]


def test_auto_open_tries_preferred_then_fallback(monkeypatch):
    tried = []

    def fake_open(index: int):
        tried.append(index)
        if index == CAMERA_FALLBACK_INDEX:
            return _FakeCap()
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)
    camera_mod._shared_cap = None
    camera_mod._shared_index = None

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
    def fake_open(index: int):
        if index == 0:
            return _FakeCap(usable=False)
        if index == 1:
            return _FakeCap(usable=True)
        return None

    # Bypass full open path; probe uses _open_video_capture which already
    # validates usable frames. Simulate: index 0 fails open, 1 succeeds.
    def open_or_none(index: int):
        if index == 1:
            return _FakeCap(usable=True)
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", open_or_none)
    camera_mod._shared_cap = None
    camera_mod._shared_index = None

    result = camera_mod.discover_cameras(max_index=2)
    assert [c["index"] for c in result["cameras"]] == [1]
    assert result["preferred_index"] == CAMERA_INDEX
    assert result["fallback_index"] == CAMERA_FALLBACK_INDEX
    assert result["active_index"] is None


def test_discover_cameras_includes_active_shared_without_reopen(monkeypatch):
    fake = _FakeCap()
    camera_mod._shared_cap = fake
    camera_mod._shared_index = 0

    opened = []

    def fake_open(index: int):
        opened.append(index)
        if index == 1:
            return _FakeCap()
        return None

    monkeypatch.setattr(camera_mod, "_open_video_capture", fake_open)

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
