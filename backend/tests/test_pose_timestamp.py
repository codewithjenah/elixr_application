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


def test_pose_detector_counts_bounded_poses_without_changing_primary(monkeypatch):
    from vision import pose_detector as module

    options_seen = []
    poses = []
    calls = []
    monkeypatch.setattr(module, "ensure_pose_model", lambda: "unused")

    class FakeLandmarker:
        def detect_for_video(self, image, timestamp_ms):
            calls.append(timestamp_ms)
            return SimpleNamespace(pose_landmarks=poses[:])

        def close(self):
            pass

    def create(options):
        options_seen.append(options)
        return FakeLandmarker()

    monkeypatch.setattr(module.vision.PoseLandmarker, "create_from_options", create)
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    default = module.PoseDetector()
    assert options_seen[-1].num_poses == 1
    default.close()
    detector = module.PoseDetector(max_poses=2)
    assert options_seen[-1].num_poses == 2
    assert detector.detect(frame) is None
    assert detector.last_person_count == 0
    first = [SimpleNamespace(x=0.2, y=0.3, visibility=0.9)]
    second = [SimpleNamespace(x=0.8, y=0.7, visibility=0.8)]
    poses.append(first)
    primary = detector.detect(frame)
    assert detector.last_person_count == 1
    assert primary.points[0].x == 0.2
    poses.append(second)
    primary = detector.detect(frame)
    assert detector.last_person_count == 2
    assert primary.points[0].x == 0.2
    assert len(calls) == 3
    detector.close()


def test_duplicate_pose_candidates_are_not_two_people():
    from vision.pose_detector import PosePersonCandidate, distinct_person_count

    primary = PosePersonCandidate(shoulders=(.40, .30, .20), hips=(.41, .58, .17))
    duplicate = PosePersonCandidate(shoulders=(.42, .31, .19), hips=(.43, .59, .18))
    second_person = PosePersonCandidate(shoulders=(.75, .30, .18), hips=(.76, .58, .17))
    close_person = PosePersonCandidate(shoulders=(.55, .30, .30), hips=(.56, .58, .30))
    wide_primary = PosePersonCandidate(shoulders=(.40, .30, .30), hips=(.41, .58, .30))
    uncertain = PosePersonCandidate(shoulders=(.52, .30, .30), hips=(.53, .58, .30))

    assert distinct_person_count((primary,)) == 1
    assert distinct_person_count((primary, duplicate)) == 1
    assert distinct_person_count((primary, second_person)) == 2
    assert distinct_person_count((wide_primary, close_person)) == 2
    assert distinct_person_count((wide_primary, uncertain)) == 0
    assert distinct_person_count((primary, PosePersonCandidate())) == 0
    assert distinct_person_count((PosePersonCandidate(),)) == 0
    assert distinct_person_count((
        PosePersonCandidate(shoulders=(.4, .3, .2)),
        PosePersonCandidate(hips=(.4, .6, .2)),
    )) == 0


def test_pose_detector_exposes_current_frame_distinct_count(monkeypatch):
    from vision import pose_detector as module

    monkeypatch.setattr(module, "ensure_pose_model", lambda: "unused")
    results = []

    class FakeLandmarker:
        def detect_for_video(self, image, timestamp_ms):
            return SimpleNamespace(pose_landmarks=results.pop(0))

        def close(self):
            pass

    monkeypatch.setattr(module.vision.PoseLandmarker, "create_from_options", lambda _: FakeLandmarker())

    def body(x):
        points = [SimpleNamespace(x=x, y=.5, visibility=.1) for _ in range(33)]
        for left, right, y in ((11, 12, .3), (23, 24, .6)):
            points[left] = SimpleNamespace(x=x - .1, y=y, visibility=.9)
            points[right] = SimpleNamespace(x=x + .1, y=y, visibility=.9)
        return points

    results.extend([[body(.4)], [body(.4), body(.42)], [body(.4), body(.75)]])
    detector = module.PoseDetector(max_poses=2)
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    assert [detector.detect(frame) and detector.last_distinct_person_count for _ in range(3)] == [1, 1, 2]
    detector.close()
