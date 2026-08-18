"""Capture real camera frames for ONNX vs PyTorch prop-parity validation.

This script is opt-in only. It does not run during practice sessions and does
not change production camera behavior.

Run from backend/:

    python scripts/capture_prop_parity_frames.py --output parity_frames --count 20

Optional explicit camera (from GET /cameras / discover_cameras device_id):

    python scripts/capture_prop_parity_frames.py --output parity_frames --count 20 --camera-device-id "<device_id>"

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
from vision.prop_parity import capture_parity_frames


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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("parity_frames"),
        help="Directory to write 001.jpg, 002.jpg, ...",
    )
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument(
        "--camera-device-id",
        default=None,
        help="Explicit discovered camera_device_id. Omit for Auto-select.",
    )
    parser.add_argument(
        "--list-only",
        action="store_true",
        help="Print discovered cameras and exit without capturing.",
    )
    args = parser.parse_args(argv)

    if args.count <= 0:
        print("count must be >= 1")
        return 2

    discovery = discover_cameras()
    _print_cameras(discovery)
    if args.list_only:
        return 0

    camera = CameraCapture(camera_device_id=args.camera_device_id)
    if not camera.open():
        print("ERROR: Camera unavailable.")
        return 1
    try:
        saved = capture_parity_frames(
            read_frame=camera.read,
            output_dir=args.output,
            count=args.count,
        )
    except RuntimeError as exc:
        print(f"ERROR: {exc}")
        return 1
    finally:
        camera.release()

    print(f"Saved {len(saved)} frames to {args.output.resolve()}")
    print("Next: python scripts/validate_prop_parity.py --images " + str(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
