"""macOS port: capture profiles, camera identity, runtime paths, and sidecar
parent watching. Host-independent (sys.platform is patched; no camera)."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import cv2

import packaged_server
import runtime_paths
from config import FRAME_HEIGHT, FRAME_WIDTH, TARGET_FPS
from vision import camera as camera_mod
from vision import camera_devices
from vision.prop_inference import select_prop_runtime


def test_macos_uses_only_avfoundation_without_directshow(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "darwin")
    for dshow_only in (False, True):
        profiles = camera_mod._capture_profiles(0, dshow_only=dshow_only)
        assert [p.api for p in profiles] == [cv2.CAP_AVFOUNDATION]
        assert all(p.api not in (cv2.CAP_DSHOW, cv2.CAP_MSMF) for p in profiles)
        # AVFoundation ignores FOURCC; MJPG is never forced on the camera.
        assert not any(p.use_mjpg for p in profiles)


def test_windows_profiles_are_unchanged(monkeypatch):
    monkeypatch.setattr(camera_mod.sys, "platform", "win32")
    assert [p.label for p in camera_mod._capture_profiles(0)] == [
        "DirectShow + MJPG",
        "Media Foundation + MJPG",
        "DirectShow + default",
        "Media Foundation + default",
    ]


def test_capture_request_stays_640x480_at_30_fps():
    assert (FRAME_WIDTH, FRAME_HEIGHT, TARGET_FPS) == (640, 480, 30)


def test_avfoundation_indices_follow_opencv_uniqueid_ordering():
    devices = camera_devices.avfoundation_devices_from_entries(
        [
            ("0x2100000046d0825", "USB Camera"),
            ("47B4B64B-7067-4B9C-AD2B-AE273A71F4B5", "MacBook Air Camera"),
        ]
    )
    assert [(d.runtime_index, d.display_name) for d in devices] == [
        (0, "USB Camera"),
        (1, "MacBook Air Camera"),
    ]
    assert all(d.identity_stable for d in devices)
    assert devices[1].device_id == (
        "avfoundation:47B4B64B-7067-4B9C-AD2B-AE273A71F4B5"
    )
    assert all(camera_devices.is_stable_device_id(d.device_id) for d in devices)


def test_avfoundation_identity_resolves_after_reindexing():
    built_in = ("47B4B64B-7067-4B9C-AD2B-AE273A71F4B5", "MacBook Air Camera")
    alone = camera_devices.avfoundation_devices_from_entries([built_in])
    with_usb = camera_devices.avfoundation_devices_from_entries(
        [built_in, ("0x2100000046d0825", "USB Camera")]
    )
    device_id = alone[0].device_id
    assert camera_devices.resolve_device_id_to_index(device_id, devices=alone) == 0
    assert camera_devices.resolve_device_id_to_index(device_id, devices=with_usb) == 1


def test_disconnected_avfoundation_selection_is_unresolved():
    assert (
        camera_devices.resolve_device_id_to_index(
            "avfoundation:gone", devices=[]
        )
        is None
    )


def test_macos_enumeration_failure_falls_back_to_opencv_indices(monkeypatch):
    monkeypatch.setattr(camera_devices.sys, "platform", "darwin")

    def boom():
        raise OSError("no objc runtime")

    monkeypatch.setattr(camera_devices, "_enumerate_avfoundation_devices", boom)
    assert camera_devices.enumerate_camera_devices() == []
    merged = camera_devices.merge_enumerated_with_usable_indices([0], enumerated=[])
    assert merged[0].device_id == "opencv:0"
    assert merged[0].identity_stable is False


def test_non_windows_non_macos_hosts_use_opencv_fallback(monkeypatch):
    monkeypatch.setattr(camera_devices.sys, "platform", "linux")
    assert camera_devices.enumerate_camera_devices() == []


def test_macos_auto_runtime_selects_onnx_cpu(tmp_path: Path):
    pt = tmp_path / "best.pt"
    onnx = tmp_path / "best.onnx"
    pt.write_bytes(b"x")
    onnx.write_bytes(b"x")
    selection = select_prop_runtime(
        "auto",
        pytorch_path=pt,
        onnx_path=onnx,
        onnxruntime_available=True,
        dml_available=False,
        is_windows=False,
    )
    assert (selection.runtime, selection.provider) == (
        "onnx_cpu",
        "CPUExecutionProvider",
    )


def test_macos_writable_root_is_application_support(monkeypatch, tmp_path):
    monkeypatch.setattr(runtime_paths.sys, "platform", "darwin")
    monkeypatch.setattr(runtime_paths.Path, "home", lambda: tmp_path)
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "ignored"))
    assert runtime_paths.writable_data_root() == (
        tmp_path / "Library" / "Application Support" / "ELIXR"
    )


def test_posix_parent_watch_stops_server_when_owner_exits(monkeypatch):
    server = SimpleNamespace(should_exit=False)
    alive = iter([True, True, False])
    monkeypatch.setattr(packaged_server, "_posix_parent_alive", lambda _pid: next(alive))
    sleeps = []
    packaged_server._poll_posix_parent(123, server, sleep=sleeps.append)
    assert server.should_exit is True
    assert len(sleeps) == 2


def test_posix_parent_is_dead_after_reparenting(monkeypatch):
    monkeypatch.setattr(packaged_server.os, "getppid", lambda: 1)
    assert packaged_server._posix_parent_alive(4242) is False
