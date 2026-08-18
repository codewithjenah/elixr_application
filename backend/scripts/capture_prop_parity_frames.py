"""Capture real camera frames for ONNX vs PyTorch prop-parity validation.

This script is opt-in only. It does not run during practice sessions and does
not change production camera behavior.

Run from backend/ (interactive capture is the recommended workflow):

    python scripts/capture_prop_parity_frames.py --output parity_frames

Console:

    Press ENTER to capture frame
    Type q + ENTER to finish

Each ENTER saves exactly one NEW camera frame, so you can reposition props
between captures. Existing numbered JPEGs are kept; the next file continues
after the highest index (001.jpg ... 020.jpg -> 021.jpg).

Optional explicit camera (from GET /cameras / discover_cameras device_id):

    python scripts/capture_prop_parity_frames.py --output parity_frames --camera-device-id "<device_id>"

Optional timed burst (not recommended for the production set):

    python scripts/capture_prop_parity_frames.py --mode timed --count 20 --output parity_frames

Then validate:

    python scripts/validate_prop_parity.py --images parity_frames

Do not commit captured frames; they may contain private webcam images.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from vision.camera import CameraCapture, discover_cameras
from vision.prop_parity import (
    capture_parity_frames,
    capture_parity_frames_interactive,
)

_PEEK_TIMEOUT_S = 2.0


def _print_cameras(payload: dict) -> None:
    cameras = payload.get("cameras") or []
    if not cameras:
        print("No usable cameras discovered.")
        return
    print("Discovered cameras:")
    for camera in cameras:
        stable = "stable" if camera.get("identity_stable") else "ephemeral"
        active = " active" if camera.get("is_active") else ""
        print(
            f"  device_id={camera.get('device_id')!r} "
            f"name={camera.get('display_name')!r} "
            f"runtime_index={camera.get('runtime_index')} "
            f"identity={stable}{active}"
        )


def _prompt_capture(prompt: str = "") -> str:
    return input(prompt)


def _peek_latest(camera: CameraCapture, newer_than: int | None):
    return camera.peek_latest(newer_than=newer_than, timeout=_PEEK_TIMEOUT_S)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("parity_frames"),
        help="Directory to write 001.jpg, 002.jpg, ... (appends by default).",
    )
    parser.add_argument(
        "--mode",
        choices=("interactive", "timed"),
        default="interactive",
        help="interactive (recommended) waits for ENTER; timed captures --count frames.",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=12,
        help="Frames to capture in --mode timed. Ignored in interactive mode.",
    )
    parser.add_argument(
        "--camera-device-id",
        default=None,
        help="Explicit discovered camera_device_id. Omit for Auto-select.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow replacing existing numbered JPEGs instead of appending.",
    )
    parser.add_argument(
        "--list-only",
        action="store_true",
        help="Print discovered cameras and exit without capturing.",
    )
    args = parser.parse_args(argv)

    if args.mode == "timed" and args.count <= 0:
        print("count must be >= 1")
        return 2

    if args.list_only:
        discovery = discover_cameras()
        _print_cameras(discovery)
        return 0

    if args.camera_device_id:
        print("Opening selected camera...")
        print(f"device_id={args.camera_device_id}")

    camera = CameraCapture(camera_device_id=args.camera_device_id)
    if not camera.open():
        if args.camera_device_id:
            print("ERROR: Selected camera is unavailable or could not be opened.")
        else:
            print("ERROR: Camera unavailable.")
        return 1
    try:
        if args.mode == "interactive":
            saved = capture_parity_frames_interactive(
                peek_frame=lambda newer_than: _peek_latest(camera, newer_than),
                output_dir=args.output,
                input_fn=_prompt_capture,
                print_fn=print,
                overwrite=args.overwrite,
            )
        else:
            last_sequence: dict[str, int | None] = {"value": None}

            def read_fresh_frame():
                captured = _peek_latest(camera, last_sequence["value"])
                if captured is None:
                    return None
                last_sequence["value"] = captured.sequence
                return captured.frame

            saved = capture_parity_frames(
                read_frame=read_fresh_frame,
                output_dir=args.output,
                count=args.count,
                start_index=1 if args.overwrite else None,
                overwrite=args.overwrite,
            )
    except (RuntimeError, FileExistsError) as exc:
        print(f"ERROR: {exc}")
        return 1
    finally:
        camera.release()

    print(f"Saved {len(saved)} frames to {args.output.resolve()}")
    print("Next: python scripts/validate_prop_parity.py --images " + str(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
