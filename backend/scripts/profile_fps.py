"""Benchmark CV pipeline FPS. Run from backend/: python scripts/profile_fps.py"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import TARGET_FPS, YOLO_FRAME_SKIP
from vision.bottle_detector import BottleDetector
from vision.camera import CameraCapture
from vision.pose_detector import PoseDetector


def main() -> None:
    camera = CameraCapture()
    if not camera.open():
        print("ERROR: Camera unavailable.")
        sys.exit(1)

    bottle = BottleDetector()
    pose = PoseDetector()
    frame_index = 0
    timings: list[float] = []
    duration = 10.0
    start = time.perf_counter()

    print(f"Profiling for {duration:.0f}s (TARGET_FPS={TARGET_FPS}, YOLO_SKIP={YOLO_FRAME_SKIP})")

    try:
        while time.perf_counter() - start < duration:
            loop_start = time.perf_counter()
            frame = camera.read()
            if frame is None:
                continue

            frame_index += 1
            if frame_index % YOLO_FRAME_SKIP == 0:
                bottle.detect(frame)
            pose.detect(frame)

            elapsed = time.perf_counter() - loop_start
            target = 1.0 / TARGET_FPS
            if elapsed < target:
                time.sleep(target - elapsed)

            timings.append(time.perf_counter() - loop_start)
    finally:
        camera.release()
        pose.close()

    if not timings:
        print("No frames captured.")
        sys.exit(1)

    avg_ms = sum(timings) / len(timings) * 1000
    fps = 1.0 / (sum(timings) / len(timings))
    print(f"Frames: {len(timings)}")
    print(f"Avg loop: {avg_ms:.1f} ms")
    print(f"Effective FPS: {fps:.1f}")
    if fps < 15:
        print("TIP: Increase YOLO_FRAME_SKIP or lower TARGET_FPS in config.py")
    elif fps > 30:
        print("TIP: You can raise TARGET_FPS or decrease YOLO_FRAME_SKIP")


if __name__ == "__main__":
    main()
