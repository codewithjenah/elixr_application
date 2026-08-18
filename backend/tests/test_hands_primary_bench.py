"""Benchmark-only two-hand primary Hands diagnosis. Production detectors unchanged."""

from __future__ import annotations

import ast
import inspect
from pathlib import Path

import numpy as np

from assessment.hands_profile import hands_profile_for
from assessment.rule_engine import movement_max_hands
from config import (
    CAMERA_RELEASE_DEBOUNCE_S,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
)
from vision.hands_benchmark import continuity_metrics, production_hands_defaults
from vision.hands_detector import HandsDetector
from vision.hands_primary_bench import (
    BASELINE_A_NAME,
    LOWER_BOUND_NUM_HANDS_1_NAME,
    PRODUCTION_HAND_CONFIDENCE,
    candidate_is_production_default,
    inspect_mediapipe_hands_runtime,
    inspect_primary_python_work,
    landmark_coordinate_deviation,
    production_primary_config,
    resize_keep_aspect,
    restore_normalized_after_full_frame_resize,
    reuse_same_frames,
    scale_targets_for,
    stage_share_pct,
    summarize_stage_timings,
    time_primary_stages,
    two_hand_quality,
)
from vision.hands_timestamp import Synthetic33TimestampClock
from vision.types import HandLandmarks, HandsResult, Point2D


BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent


def _hand(cx: float, cy: float, label: str = "Right") -> HandLandmarks:
    return HandLandmarks(
        points={0: Point2D(cx, cy + 0.04), 9: Point2D(cx, cy)},
        handedness=label,
    )


def _result(*hands: HandLandmarks) -> HandsResult:
    return HandsResult(hands=list(hands))


def test_production_hands_detector_behavior_defaults_unchanged():
    defaults = production_hands_defaults()
    assert defaults["max_num_hands"] == 2
    assert defaults["rotated_fallback"] is False
    assert defaults["bartender_roi_fallback"] is False
    assert defaults["timestamp_clock"] is None
    source = inspect.getsource(HandsDetector._detect_primary)
    assert "detect_for_video" in source
    assert ".copy(" not in source
    to_image = inspect.getsource(HandsDetector._to_mp_image)
    assert to_image.count("cvtColor") == 1
    assert "COLOR_BGR2RGB" in to_image


def test_double_hand_stall_still_resolves_max_num_hands_2():
    assert movement_max_hands("Double Hand Stall") == 2
    profile = hands_profile_for("Double Hand Stall")
    assert profile.semantic_max_hands == 2
    assert profile.active_scheduled_hands is True
    assert profile.rotated_fallback is False
    assert profile.bartender_roi_fallback is False


def test_benchmark_a_matches_production_configuration():
    config = production_primary_config()
    assert config["name"] == BASELINE_A_NAME
    assert config["max_num_hands"] == 2
    assert config["running_mode"] == "VIDEO"
    assert config["min_hand_detection_confidence"] == PRODUCTION_HAND_CONFIDENCE
    assert config["min_hand_presence_confidence"] == PRODUCTION_HAND_CONFIDENCE
    assert config["min_tracking_confidence"] == PRODUCTION_HAND_CONFIDENCE
    assert config["rotated_fallback"] is False
    assert config["bartender_roi_fallback"] is False
    assert config["timestamp_clock"] is Synthetic33TimestampClock
    assert config["model_name"] == "hand_landmarker.task"
    assert config["input_width"] == FRAME_WIDTH
    assert config["input_height"] == FRAME_HEIGHT
    detector_source = inspect.getsource(HandsDetector._create_landmarker)
    assert "num_hands=self._max_num_hands" in detector_source
    assert "min_hand_detection_confidence=0.5" in detector_source
    assert "RunningMode.VIDEO" in inspect.getsource(HandsDetector.__init__)


def test_same_frames_are_reused_across_candidates():
    frames = [np.zeros((8, 8, 3), dtype=np.uint8), np.ones((8, 8, 3), dtype=np.uint8)]
    a, b, c = reuse_same_frames(frames, copies=3)
    assert a is frames
    assert b is frames
    assert c is frames
    assert a[0] is frames[0]
    assert b[1] is frames[1]


def test_timing_sub_stages_are_measured_correctly():
    frame = np.zeros((4, 4, 3), dtype=np.uint8)
    order: list[str] = []

    def prep(src):
        order.append("prep")
        return src

    def image(rgb):
        order.append("image")
        return rgb

    def detect(mp_image, timestamp_ms):
        order.append("detect")
        assert timestamp_ms == 33
        return {"hands": 2}

    def extract(raw):
        order.append("extract")
        return _result(_hand(0.2, 0.3), _hand(0.8, 0.3, "Left"))

    sample = time_primary_stages(
        frame,
        convert_fn=prep,
        image_fn=image,
        detect_fn=detect,
        result_fn=extract,
        timestamp_ms=33,
    )
    assert order == ["prep", "image", "detect", "extract"]
    assert sample.hand_count == 2
    assert sample.preprocess_s >= 0
    assert sample.mp_image_s >= 0
    assert sample.detect_for_video_s >= 0
    assert sample.result_s >= 0
    assert sample.other_s >= 0
    total = (
        sample.preprocess_s
        + sample.mp_image_s
        + sample.detect_for_video_s
        + sample.result_s
        + sample.other_s
    )
    assert abs(sample.total_s - total) < 1e-6
    summary = summarize_stage_timings([sample])
    assert abs(summary["detect_for_video"]["mean_ms"] - sample.detect_for_video_s * 1000) < 1e-6
    shares = stage_share_pct(summary)
    assert abs(sum(shares.values()) - 100.0) < 1e-6


def test_coordinate_restoration_for_scaled_input_is_identity_on_full_frame_resize():
    point = Point2D(x=0.25, y=0.80)
    restored = restore_normalized_after_full_frame_resize(
        point,
        source_size=(640, 480),
        infer_size=(448, 336),
    )
    assert restored == point
    src = np.arange(640 * 480 * 3, dtype=np.uint8).reshape(480, 640, 3)
    scaled = resize_keep_aspect(src, 512, 384)
    assert scaled.shape == (384, 512, 3)
    assert src.shape == (480, 640, 3)
    assert src[0, 0, 0] == 0


def test_source_frames_are_not_modified_during_prep_or_resize():
    frame = np.full((32, 40, 3), 7, dtype=np.uint8)
    original = frame.copy()
    converted = np.empty_like(frame)

    def convert_fn(src):
        converted[:] = src
        converted[:, :, 0] = 99
        return converted

    sample = time_primary_stages(
        frame,
        convert_fn=convert_fn,
        image_fn=lambda rgb: rgb,
        detect_fn=lambda *_a, **_k: None,
        result_fn=lambda _raw: None,
        timestamp_ms=33,
    )
    assert sample.hand_count == 0
    np.testing.assert_array_equal(frame, original)
    scaled = resize_keep_aspect(frame, 20, 16)
    np.testing.assert_array_equal(frame, original)
    assert scaled.shape == (16, 20, 3)


def test_no_stale_landmarks_are_reused_across_empty_frames():
    previous = _result(_hand(0.1, 0.2))
    carried = {"value": previous}

    def detect_fn(_image, _ts):
        return None

    def result_fn(raw):
        if raw is None:
            return None
        return carried["value"]

    empty = time_primary_stages(
        np.zeros((4, 4, 3), dtype=np.uint8),
        convert_fn=lambda src: src,
        image_fn=lambda rgb: rgb,
        detect_fn=detect_fn,
        result_fn=result_fn,
        timestamp_ms=66,
    )
    assert empty.result is None
    assert empty.hand_count == 0
    quality = two_hand_quality([empty.result, empty.result, previous])
    assert quality["zero_hand_rate"] == 2 / 3
    assert quality["one_hand_rate"] == 1 / 3
    assert quality["both_hands_rate"] == 0.0
    assert quality["stale_reuse_frames"] == 0


def test_candidate_benchmark_code_cannot_silently_become_production_default():
    assert candidate_is_production_default("resolution_80") is False
    assert candidate_is_production_default(LOWER_BOUND_NUM_HANDS_1_NAME) is False
    assert candidate_is_production_default(BASELINE_A_NAME) is True
    production_files = [
        BACKEND_ROOT / "vision" / "hands_detector.py",
        BACKEND_ROOT / "api" / "websocket.py",
        BACKEND_ROOT / "config.py",
        BACKEND_ROOT / "vision" / "pose_detector.py",
        BACKEND_ROOT / "assessment" / "hands_profile.py",
    ]
    for path in production_files:
        text = path.read_text(encoding="utf-8")
        assert "hands_primary_bench" not in text
        tree = ast.parse(text)
        imported = [
            node.module
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom)
        ]
        assert "vision.hands_primary_bench" not in imported


def test_yolo_pose_camera_configuration_remains_unchanged():
    assert FRAME_WIDTH == 640
    assert FRAME_HEIGHT == 480
    assert YOLO_FRAME_SKIP == 2
    assert TARGET_FPS == 20
    assert CAMERA_RELEASE_DEBOUNCE_S == 2.0
    pose_source = (BACKEND_ROOT / "vision" / "pose_detector.py").read_text(
        encoding="utf-8"
    )
    assert "num_poses=1" in pose_source
    assert "pose_landmarker_lite.task" in (
        BACKEND_ROOT / "vision" / "model_assets.py"
    ).read_text(encoding="utf-8")
    camera_source = (BACKEND_ROOT / "vision" / "camera.py").read_text(encoding="utf-8")
    assert "FRAME_WIDTH" in camera_source
    assert "hands_primary_bench" not in camera_source


def test_redundant_cpu_work_inspector_finds_single_conversion_path():
    report = inspect_primary_python_work()
    assert report["cvtcolor_calls_in_primary_path"] == 1
    assert report["frame_copy_calls_in_primary_path"] == 0
    assert report["detect_for_video_calls"] == 1
    assert report["mp_image_constructions"] == 1
    assert report["meaningful_redundancy"] is False
    assert report["candidate_b_created"] is False


def test_two_hand_quality_and_deviation_metrics():
    both = _result(_hand(0.2, 0.3, "Left"), _hand(0.8, 0.3, "Right"))
    one = _result(_hand(0.2, 0.31, "Left"))
    none = None
    quality = two_hand_quality([both, both, one, none, both])
    assert quality["frames"] == 5
    assert quality["both_hands_rate"] == 0.6
    assert quality["one_hand_rate"] == 0.2
    assert quality["zero_hand_rate"] == 0.2
    assert quality["hand_count_transitions"] == 3
    assert quality["longest_missing_hand_streak"] == 1
    assert quality["longest_below_two_hands_streak"] == 2
    assert quality["dhs_two_palm_evidence_rate"] == 0.6
    shifted = _result(_hand(0.21, 0.30, "Left"), _hand(0.81, 0.30, "Right"))
    deviation = landmark_coordinate_deviation([both], [shifted])
    assert deviation["compared_frames"] == 1
    assert deviation["mean_displacement"] > 0
    continuity = continuity_metrics(
        primary_hits=[True, True, True, False, True],
        hand_counts=[2, 2, 1, 0, 2],
        landmark_available=[True, True, True, False, True],
    )
    assert continuity["hand_count_changes"] == 3


def test_scale_targets_follow_actual_production_dimensions():
    targets = scale_targets_for(640, 480)
    assert targets[0] == ("baseline_a", 640, 480)
    assert targets[1][1:] == (512, 384)
    assert targets[2][1:] == (448, 336)
    odd = scale_targets_for(650, 400)
    assert odd[0] == ("baseline_a", 650, 400)
    assert odd[1][1] < 650 and odd[1][2] < 400


def test_mediapipe_runtime_inspector_reports_installed_api():
    info = inspect_mediapipe_hands_runtime()
    assert "version" in info
    assert "delegate_names" in info
    assert "gpu_supported" in info
    assert "platform" in info
    assert info["hand_landmarker_options_fields"]
    assert "num_hands" in info["hand_landmarker_options_fields"]


def test_lower_bound_is_labeled_not_a_production_candidate():
    assert "NOT A PRODUCTION CANDIDATE" in LOWER_BOUND_NUM_HANDS_1_NAME


def test_gitignore_covers_double_hand_capture_dir():
    text = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert "backend/hands_double_hand_frames/" in text
