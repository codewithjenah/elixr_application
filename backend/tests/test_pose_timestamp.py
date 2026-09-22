"""Capture-aware VIDEO timestamps for PoseDetector."""

from types import SimpleNamespace

import numpy as np


def _patch_pose(monkeypatch, timestamps: list[int]):
    from vision import pose_detector as module

    monkeypatch.setattr(module, "ensure_pose_model", lambda: "unused")

    class FakeLandmarker:
        def detect_for_video(self, image, timestamp_ms):
            timestamps.append(timestamp_ms)
            return SimpleNamespace(pose_landmarks=[])

        def close(self):
            pass

    monkeypatch.setattr(
        module.vision.PoseLandmarker,
        "create_from_options",
        lambda options: FakeLandmarker(),
    )
    return module.PoseDetector


def test_pose_detector_uses_capture_timestamps_and_strictly_increases(monkeypatch):
    timestamps: list[int] = []
    PoseDetector = _patch_pose(monkeypatch, timestamps)
    detector = PoseDetector()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    detector.detect(frame, captured_at_monotonic=10.0)
    detector.detect(frame, captured_at_monotonic=10.0004)
    detector.detect(frame, captured_at_monotonic=9.9)
    assert timestamps == [0, 1, 2]
    detector.close()


def test_new_pose_detector_resets_capture_timestamp_lifecycle(monkeypatch):
    timestamps: list[int] = []
    PoseDetector = _patch_pose(monkeypatch, timestamps)
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    first = PoseDetector()
    first.detect(frame, captured_at_monotonic=100.0)
    first.close()
    second = PoseDetector()
    second.detect(frame, captured_at_monotonic=500.0)
    assert timestamps == [0, 0]
    second.close()
