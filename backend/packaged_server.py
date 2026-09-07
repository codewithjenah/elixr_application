"""Console-free entry point used by the packaged ELIXR backend."""

from __future__ import annotations

import argparse
import ctypes
import sys
import threading
import traceback
from ctypes import wintypes

from runtime_paths import model_dir, writable_data_root


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the local ELIXR backend")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8000, type=int)
    parser.add_argument(
        "--parent-pid",
        default=None,
        type=int,
        help="exit when the owning ELIXR process exits",
    )
    parser.add_argument(
        "--verify-resources",
        action="store_true",
        help="load one bundled MediaPipe model and verify required assets",
    )
    return parser.parse_args()


def verify_resources() -> None:
    required = (
        "best.onnx",
        "best.pt",
        "hand_landmarker.task",
        "pose_landmarker_lite.task",
    )
    missing = [name for name in required if not (model_dir() / name).is_file()]
    if missing:
        raise FileNotFoundError(
            "Missing bundled model assets: " + ", ".join(sorted(missing))
        )

    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision

    landmarker = vision.HandLandmarker.create_from_options(
        vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(
                model_asset_path=str(model_dir() / "hand_landmarker.task")
            ),
            running_mode=vision.RunningMode.IMAGE,
            num_hands=1,
        )
    )
    landmarker.close()


def _record_startup_error(error: Exception) -> None:
    try:
        log_path = writable_data_root() / "logs" / "backend_startup_error.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write("\n--- ELIXR backend startup failure ---\n")
            traceback.print_exception(error, file=handle)
    except OSError:
        # There is no useful fallback for a failure before logging is ready.
        pass


def _watch_parent_process(parent_pid: int, server: object) -> None:
    """Ask Uvicorn to stop when the Flutter owner disappears.

    Flutter normally calls [BackendService.dispose], but a Windows force-close
    or native crash can bypass Dart teardown. Waiting on the owner's process
    handle keeps the packaged sidecar from retaining the camera indefinitely.
    """
    if sys.platform != "win32":
        return

    synchronize = 0x00100000
    wait_object_0 = 0x00000000
    infinite = 0xFFFFFFFF
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.WaitForSingleObject.restype = wintypes.DWORD
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    handle = kernel32.OpenProcess(synchronize, False, parent_pid)
    if not handle:
        server.should_exit = True
        return

    try:
        result = kernel32.WaitForSingleObject(handle, infinite)
        if result == wait_object_0 or result == 0xFFFFFFFF:
            server.should_exit = True
    finally:
        kernel32.CloseHandle(handle)


def main() -> int:
    args = parse_args()
    try:
        import uvicorn

        from main import app

        if args.verify_resources:
            verify_resources()
            return 0
        config = uvicorn.Config(
            app,
            host=args.host,
            port=args.port,
            log_level="info",
            access_log=False,
            # The PyInstaller windowless bootloader does not provide a
            # stderr console for Uvicorn's default color formatter.
            log_config=None,
        )
        server = uvicorn.Server(config)
        if args.parent_pid is not None:
            threading.Thread(
                target=_watch_parent_process,
                args=(args.parent_pid, server),
                daemon=True,
            ).start()
        server.run()
        return 0
    except Exception as error:
        _record_startup_error(error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
