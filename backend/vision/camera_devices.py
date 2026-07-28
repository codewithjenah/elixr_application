"""Windows camera identity enumeration and runtime-index mapping.

Isolates DirectShow device discovery from OpenCV capture. Runtime indices are
ephemeral OpenCV/DirectShow positions; ``device_id`` is the persisted identity.
"""

from __future__ import annotations

import logging
import sys
from dataclasses import dataclass

logger = logging.getLogger(__name__)

# Prefix for OpenCV-only fallback identities when native enumeration fails.
_OPENCV_FALLBACK_PREFIX = "opencv:"


@dataclass(frozen=True)
class EnumeratedCamera:
    """One camera as reported by the OS (or OpenCV fallback)."""

    device_id: str
    display_name: str
    runtime_index: int
    identity_stable: bool


def enumerate_camera_devices() -> list[EnumeratedCamera]:
    """Return cameras in DirectShow/OpenCV index order when possible.

    On Windows, uses DirectShow System Device Enumerator (via comtypes) to
    obtain FriendlyName + DevicePath and map them to runtime indices.

    On failure or non-Windows platforms, returns an empty list so callers can
    fall back to OpenCV index probing with neutral ``Camera N`` labels.
    """
    if sys.platform != "win32":
        return []

    try:
        devices = _enumerate_directshow_devices()
        if devices:
            return devices
    except ModuleNotFoundError as exc:
        logger.warning(
            "DirectShow camera enumeration unavailable (%s). "
            "Install backend requirements in the active environment, or start "
            "the server with backend\\.run.ps1 so .venv (with comtypes) is used. "
            "Falling back to OpenCV index labels like 'Camera 0'.",
            exc,
        )
    except Exception:
        logger.exception(
            "DirectShow camera enumeration failed; OpenCV index fallback will be used"
        )

    return []


def fallback_device_for_index(index: int) -> EnumeratedCamera:
    """Neutral OpenCV-only identity when OS enumeration is unavailable."""
    return EnumeratedCamera(
        device_id=f"{_OPENCV_FALLBACK_PREFIX}{index}",
        display_name=f"Camera {index}",
        runtime_index=index,
        identity_stable=False,
    )


def is_fallback_device_id(device_id: str) -> bool:
    return device_id.startswith(_OPENCV_FALLBACK_PREFIX)


def resolve_device_id_to_index(
    device_id: str,
    *,
    devices: list[EnumeratedCamera] | None = None,
) -> int | None:
    """Map a persisted ``device_id`` to the current runtime OpenCV index.

    Re-enumerates when ``devices`` is omitted so callers always resolve against
    the live device list rather than a stale discovery snapshot.
    """
    if not device_id:
        return None

    if is_fallback_device_id(device_id):
        suffix = device_id[len(_OPENCV_FALLBACK_PREFIX) :]
        try:
            index = int(suffix)
        except ValueError:
            return None
        if index < 0:
            return None
        return index

    live = devices if devices is not None else enumerate_camera_devices()
    for device in live:
        if device.device_id == device_id:
            return device.runtime_index

    return None


def lookup_device(
    device_id: str,
    *,
    devices: list[EnumeratedCamera] | None = None,
) -> EnumeratedCamera | None:
    if not device_id:
        return None

    live = devices if devices is not None else enumerate_camera_devices()
    for device in live:
        if device.device_id == device_id:
            return device

    if is_fallback_device_id(device_id):
        index = resolve_device_id_to_index(device_id, devices=live)
        if index is not None:
            return fallback_device_for_index(index)

    return None


def device_id_for_runtime_index(
    index: int,
    *,
    devices: list[EnumeratedCamera] | None = None,
) -> str:
    live = devices if devices is not None else enumerate_camera_devices()
    for device in live:
        if device.runtime_index == index:
            return device.device_id
    return fallback_device_for_index(index).device_id


def display_name_for_runtime_index(
    index: int,
    *,
    devices: list[EnumeratedCamera] | None = None,
) -> str:
    live = devices if devices is not None else enumerate_camera_devices()
    for device in live:
        if device.runtime_index == index:
            return device.display_name
    return fallback_device_for_index(index).display_name


def merge_enumerated_with_usable_indices(
    usable_indices: list[int],
    *,
    enumerated: list[EnumeratedCamera] | None = None,
) -> list[EnumeratedCamera]:
    """Attach OS identity to OpenCV-probed usable indices.

    Indices present in ``usable_indices`` but missing from native enumeration
    receive unstable ``opencv:N`` identities with neutral ``Camera N`` names.
    Enumerated devices whose indices are not usable are omitted.
    """
    live = enumerated if enumerated is not None else enumerate_camera_devices()
    by_index = {device.runtime_index: device for device in live}

    merged: list[EnumeratedCamera] = []
    for index in usable_indices:
        device = by_index.get(index)
        if device is not None:
            merged.append(device)
        else:
            merged.append(fallback_device_for_index(index))
    return merged


def _enumerate_directshow_devices() -> list[EnumeratedCamera]:
    """Enumerate video capture devices via DirectShow (comtypes only)."""
    import comtypes
    from comtypes import CLSCTX_INPROC_SERVER, COMMETHOD, GUID, HRESULT, POINTER
    from comtypes import c_int, c_ulong, client
    from comtypes.automation import IUnknown
    from comtypes.persist import IPersist, IPropertyBag
    from ctypes.wintypes import _ULARGE_INTEGER

    # COM may already be initialized on a worker thread; ignore S_FALSE.
    try:
        comtypes.CoInitialize()
    except OSError:
        pass

    class ISequentialStream(IUnknown):
        _case_insensitive_ = True
        _iid_ = GUID("{0C733A30-2A1C-11CE-ADE5-00AA0044773D}")
        _idlflags_ = []

    class IStream(ISequentialStream):
        _case_insensitive_ = True
        _iid_ = GUID("{0000000C-0000-0000-C000-000000000046}")
        _idlflags_ = []

    class IBindCtx(IUnknown):
        _case_insensitive_ = True
        _iid_ = GUID("{0000000E-0000-0000-C000-000000000046}")
        _idlflags_ = []

    class IPersistStream(IPersist):
        _case_insensitive_ = True
        _iid_ = GUID("{00000109-0000-0000-C000-000000000046}")
        _idlflags_ = []

    IPersistStream._methods_ = [
        COMMETHOD([], HRESULT, "IsDirty"),
        COMMETHOD(
            [],
            HRESULT,
            "Load",
            (["in"], POINTER(IStream), "pstm"),
        ),
        COMMETHOD(
            [],
            HRESULT,
            "Save",
            (["in"], POINTER(IStream), "pstm"),
            (["in"], c_int, "fClearDirty"),
        ),
        COMMETHOD(
            [],
            HRESULT,
            "GetSizeMax",
            (["out"], POINTER(_ULARGE_INTEGER), "pcbSize"),
        ),
    ]

    class IMoniker(IPersistStream):
        _case_insensitive_ = True
        _iid_ = GUID("{0000000F-0000-0000-C000-000000000046}")
        _idlflags_ = []

    IMoniker._methods_ = [
        COMMETHOD(
            [],
            HRESULT,
            "BindToObject",
            (["in"], POINTER(IBindCtx), "pbc"),
            (["in"], POINTER(IMoniker), "pmkToLeft"),
            (["in"], POINTER(GUID), "riidResult"),
            (["out"], POINTER(POINTER(IUnknown)), "ppvResult"),
        ),
        COMMETHOD(
            [],
            HRESULT,
            "BindToStorage",
            (["in"], POINTER(IBindCtx), "pbc"),
            (["in"], POINTER(IMoniker), "pmkToLeft"),
            (["in"], POINTER(GUID), "riid"),
            (["out"], POINTER(POINTER(IUnknown)), "ppvObj"),
        ),
    ]

    class IEnumMoniker(IUnknown):
        _case_insensitive_ = True
        _iid_ = GUID("{00000102-0000-0000-C000-000000000046}")
        _idlflags_ = []

    IEnumMoniker._methods_ = [
        COMMETHOD(
            [],
            HRESULT,
            "Next",
            (["in"], c_ulong, "celt"),
            (["out"], POINTER(POINTER(IMoniker)), "rgelt"),
            (["out"], POINTER(c_ulong), "pceltFetched"),
        ),
        COMMETHOD([], HRESULT, "Skip", (["in"], c_ulong, "celt")),
        COMMETHOD([], HRESULT, "Reset"),
        COMMETHOD(
            [],
            HRESULT,
            "Clone",
            (["out"], POINTER(POINTER(IMoniker)), "ppenum"),
        ),
    ]

    class ICreateDevEnum(IUnknown):
        _case_insensitive_ = True
        _iid_ = GUID("{29840822-5B84-11D0-BD3B-00A0C911CE86}")
        _idlflags_ = []

    ICreateDevEnum._methods_ = [
        COMMETHOD(
            [],
            HRESULT,
            "CreateClassEnumerator",
            (["in"], POINTER(GUID), "clsidDeviceClass"),
            (["out"], POINTER(POINTER(IEnumMoniker)), "ppEnumMoniker"),
            (["in"], c_int, "dwFlags"),
        )
    ]

    clsid_system_device_enum = GUID("{62BE5D10-60EB-11d0-BD3B-00A0C911CE86}")
    clsid_video_input = GUID("{860BB310-5D01-11d0-BD3B-00A0C911CE86}")

    device_enumerator = client.CreateObject(
        clsid_system_device_enum,
        clsctx=CLSCTX_INPROC_SERVER,
        interface=ICreateDevEnum,
    )
    moniker_enumerator = device_enumerator.CreateClassEnumerator(
        clsid_video_input, 0
    )

    result: list[EnumeratedCamera] = []
    try:
        moniker, count = moniker_enumerator.Next(1)
    except ValueError:
        return result

    index = 0
    while count > 0:
        property_bag = moniker.BindToStorage(0, 0, IPropertyBag._iid_).QueryInterface(
            IPropertyBag
        )
        friendly_name = str(property_bag.Read("FriendlyName", pErrorLog=None))

        device_path = ""
        try:
            device_path = str(property_bag.Read("DevicePath", pErrorLog=None))
        except Exception:
            device_path = ""

        if device_path:
            device_id = device_path
            identity_stable = True
        else:
            # No DevicePath (rare). Keep a usable but unstable identity.
            device_id = f"dshow-name:{friendly_name}:{index}"
            identity_stable = False

        result.append(
            EnumeratedCamera(
                device_id=device_id,
                display_name=friendly_name or f"Camera {index}",
                runtime_index=index,
                identity_stable=identity_stable,
            )
        )

        moniker, count = moniker_enumerator.Next(1)
        index += 1

    return result
