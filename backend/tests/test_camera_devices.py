"""Unit tests for Windows camera identity mapping."""

from __future__ import annotations

from vision.camera_devices import (
    EnumeratedCamera,
    fallback_device_for_index,
    merge_enumerated_with_usable_indices,
    resolve_device_id_to_index,
)


def test_resolve_device_id_after_reorder():
    first = [
        EnumeratedCamera("dev-a", "Integrated Camera", 0, True),
        EnumeratedCamera("dev-b", "HIKVISION", 1, True),
    ]
    second = [
        EnumeratedCamera("dev-b", "HIKVISION", 0, True),
        EnumeratedCamera("dev-a", "Integrated Camera", 1, True),
    ]

    assert resolve_device_id_to_index("dev-b", devices=first) == 1
    assert resolve_device_id_to_index("dev-b", devices=second) == 0
    assert resolve_device_id_to_index("dev-a", devices=second) == 1


def test_duplicate_friendly_names_keep_distinct_ids():
    devices = [
        EnumeratedCamera("path-1", "USB Camera", 0, True),
        EnumeratedCamera("path-2", "USB Camera", 1, True),
    ]
    assert devices[0].display_name == devices[1].display_name
    assert devices[0].device_id != devices[1].device_id
    assert resolve_device_id_to_index("path-2", devices=devices) == 1


def test_missing_device_id_returns_none():
    devices = [
        EnumeratedCamera("dev-a", "Integrated Camera", 0, True),
    ]
    assert resolve_device_id_to_index("missing", devices=devices) is None


def test_fallback_opencv_identity_is_unstable():
    device = fallback_device_for_index(2)
    assert device.device_id == "opencv:2"
    assert device.display_name == "Camera 2"
    assert device.identity_stable is False
    assert resolve_device_id_to_index("opencv:2", devices=[]) == 2


def test_merge_enumerated_with_usable_indices():
    enumerated = [
        EnumeratedCamera("dev-a", "Integrated Camera", 0, True),
        EnumeratedCamera("dev-b", "HIKVISION", 1, True),
        EnumeratedCamera("dev-c", "Ghost", 3, True),
    ]
    merged = merge_enumerated_with_usable_indices(
        [1, 2],
        enumerated=enumerated,
    )
    assert [d.device_id for d in merged] == ["dev-b", "opencv:2"]
    assert merged[0].identity_stable is True
    assert merged[1].identity_stable is False
    assert merged[1].display_name == "Camera 2"
