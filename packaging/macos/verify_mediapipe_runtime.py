"""Proves MediaPipe runs natively in the arm64 macOS release venv.

Run by scripts/build_macos_release.sh with the release venv's interpreter.
Constructs ELIXR's Hands and Pose landmarkers from the repository's bundled
task models with the production options (hands_detector.py, pose_detector.py),
runs one VIDEO-mode inference on a synthetic frame, and closes them. No camera
is needed. Any failure exits non-zero and must fail the release.

``--mislabeled-wheel`` additionally proves the one tolerated ``pip check``
complaint is only a metadata defect: the mediapipe 0.10.9 wheel published as
``macosx_11_0_universal2`` declares ``Tag: cp311-cp311-macosx_13_0_x86_64`` in
its WHEEL file, while its native extensions carry arm64 slices.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import platform
import subprocess
import sys
from pathlib import Path

EXPECTED_VERSION = "0.10.9"
MISLABELED_TAG = "cp311-cp311-macosx_13_0_x86_64"
MODEL_DIR = Path(__file__).resolve().parents[2] / "backend" / "models"


def _check_host() -> None:
    assert platform.system() == "Darwin", platform.system()
    assert platform.machine() == "arm64", platform.machine()
    assert sys.version_info[:2] == (3, 11), sys.version
    assert sys.prefix != sys.base_prefix, "not running inside the release venv"


def _check_mislabeled_wheel(dist: importlib.metadata.Distribution) -> None:
    wheel = dist.read_text("WHEEL") or ""
    tags = [line.split(":", 1)[1].strip() for line in wheel.splitlines() if line.startswith("Tag:")]
    assert tags == [MISLABELED_TAG], f"unexpected mediapipe WHEEL tags: {tags}"

    extensions = [
        Path(dist.locate_file(entry))
        for entry in dist.files or []
        if str(entry).endswith((".so", ".dylib"))
    ]
    assert extensions, "mediapipe has no native extensions"
    for extension in extensions:
        archs = subprocess.run(
            ["lipo", "-archs", str(extension)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.split()
        assert "arm64" in archs, f"{extension} has no arm64 slice: {archs}"
        print(f"  {extension.name}: {' '.join(archs)}")


def _smoke_test_tasks() -> None:
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision

    package_dir = Path(mp.__file__).resolve().parent
    assert Path(sys.prefix).resolve() in package_dir.parents, package_dir
    assert mp.__version__ == EXPECTED_VERSION, mp.__version__

    frame = mp.Image(
        image_format=mp.ImageFormat.SRGB,
        data=np.full((480, 640, 3), 127, dtype=np.uint8),
    )

    hands = vision.HandLandmarker.create_from_options(
        vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(
                model_asset_path=str(MODEL_DIR / "hand_landmarker.task")
            ),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    )
    try:
        hands.detect_for_video(frame, 0)
    finally:
        hands.close()

    pose = vision.PoseLandmarker.create_from_options(
        vision.PoseLandmarkerOptions(
            base_options=python.BaseOptions(
                model_asset_path=str(MODEL_DIR / "pose_landmarker_lite.task")
            ),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    )
    try:
        pose.detect_for_video(frame, 0)
    finally:
        pose.close()

    print(f"mediapipe {mp.__version__} Hands + Pose tasks OK from {package_dir}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mislabeled-wheel", action="store_true")
    args = parser.parse_args()

    _check_host()
    dist = importlib.metadata.distribution("mediapipe")
    assert dist.version == EXPECTED_VERSION, dist.version
    if args.mislabeled_wheel:
        _check_mislabeled_wheel(dist)
    _smoke_test_tasks()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
