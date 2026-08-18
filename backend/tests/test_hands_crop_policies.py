"""Benchmark-only Bartender ROI crop geometries. Production crop stays unchanged."""

from __future__ import annotations

import inspect
from pathlib import Path

import cv2
import numpy as np

from vision.hands_benchmark import production_hands_defaults
from vision.hands_detector import (
    HandsDetector,
    _bartender_crop_bounds,
    _counterclockwise_crop_point_to_frame,
    _has_bartender_candidate,
)
from vision.hands_crop_policies import (
    CROP_A,
    CROP_B,
    CROP_C,
    CROP_D,
    classify_roi_outcome,
    compare_recoveries,
    crop_bounds_for,
    crop_containment,
    eligible_frame_indices,
    recommend_crop_trial,
    restore_crop_point,
    select_debug_examples,
    summarize_crop_areas,
    write_crop_debug_image,
)
from vision.hands_roi_policies import ImmediateRoiPolicy, evaluate_policy_frame
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _bottle() -> BottleDetection:
    return BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.91)


def _zone_hand() -> HandsResult:
    return HandsResult(
        hands=[
            HandLandmarks(
                points={
                    0: Point2D(0.375, 0.36),
                    4: Point2D(0.365, 0.32),
                    8: Point2D(0.385, 0.32),
                    9: Point2D(0.375, 0.34),
                },
                handedness="Right",
            )
        ]
    )


def _outside_hand() -> HandsResult:
    return HandsResult(
        hands=[
            HandLandmarks(
                points={
                    0: Point2D(0.90, 0.90),
                    4: Point2D(0.89, 0.88),
                    8: Point2D(0.91, 0.88),
                    9: Point2D(0.90, 0.89),
                },
                handedness="Right",
            )
        ]
    )


def test_crop_a_matches_production_geometry():
    bottle = _bottle()
    expected = _bartender_crop_bounds(
        bottle, frame_width=640, frame_height=480
    )
    actual = crop_bounds_for(
        CROP_A, bottle, frame_width=640, frame_height=480
    )
    assert actual == expected
    assert CROP_A.width_factor == 2.5
    assert CROP_A.top_fraction == 0.05
    assert CROP_A.bottom_fraction == 0.65
    assert CROP_A.full_frame is False


def test_crops_b_and_c_are_benchmark_only_and_larger_than_a():
    bottle = _bottle()
    a = crop_bounds_for(CROP_A, bottle, frame_width=640, frame_height=480)
    b = crop_bounds_for(CROP_B, bottle, frame_width=640, frame_height=480)
    c = crop_bounds_for(CROP_C, bottle, frame_width=640, frame_height=480)
    assert a is not None and b is not None and c is not None
    a_area = (a[2] - a[0]) * (a[3] - a[1])
    b_area = (b[2] - b[0]) * (b[3] - b[1])
    c_area = (c[2] - c[0]) * (c[3] - c[1])
    assert b_area > a_area
    assert c_area > b_area
    assert CROP_B.full_frame is False
    assert CROP_C.full_frame is False
    source = inspect.getsource(HandsDetector._detect_bartender_roi)
    assert "CROP_B" not in source
    assert "CROP_C" not in source
    assert "_bartender_crop_bounds(" in source


def test_crop_clipping_stays_inside_frame_bounds():
    edge = BottleDetection(x1=10, y1=5, x2=40, y2=80, confidence=0.8)
    for geometry in (CROP_A, CROP_B, CROP_C, CROP_D):
        bounds = crop_bounds_for(
            geometry, edge, frame_width=640, frame_height=480
        )
        assert bounds is not None
        left, top, right, bottom = bounds
        assert 0 <= left < right <= 640
        assert 0 <= top < bottom <= 480


def test_coordinates_restore_after_crop_and_rotation():
    bounds = (100, 50, 300, 250)
    rotated = Point2D(0.20, 0.25)
    restored = restore_crop_point(
        rotated, bounds, frame_width=640, frame_height=480
    )
    expected = _counterclockwise_crop_point_to_frame(
        rotated, bounds, frame_width=640, frame_height=480
    )
    assert restored.x == expected.x
    assert restored.y == expected.y
    assert restored.x == 0.390625
    assert restored.y == 0.1875


def test_variants_use_identical_frozen_bottle_boxes():
    bottles = [_bottle(), None, _bottle()]
    a_boxes = [bottle for bottle in bottles]
    b_boxes = [bottle for bottle in bottles]
    c_boxes = [bottle for bottle in bottles]
    assert a_boxes == b_boxes == c_boxes
    assert a_boxes[0] is bottles[0]
    for geometry in (CROP_A, CROP_B, CROP_C):
        crop_bounds_for(geometry, bottles[0], frame_width=640, frame_height=480)
    assert bottles[0].x1 == 200
    assert bottles[0].x2 == 280
    assert bottles[0].confidence == 0.91


def test_variants_use_identical_eligible_frames():
    bottle = _bottle()
    primaries = [_zone_hand(), _outside_hand(), None, _outside_hand()]
    bottles = [bottle, bottle, bottle, bottle]
    eligible = eligible_frame_indices(
        primaries, bottles, frame_width=640, frame_height=480
    )
    assert eligible == [1, 2, 3]
    for _geometry in (CROP_A, CROP_B, CROP_C):
        assert (
            eligible_frame_indices(
                primaries, bottles, frame_width=640, frame_height=480
            )
            == eligible
        )


def test_a_recoveries_cannot_be_silently_omitted():
    comparison = compare_recoveries(
        a_ids=(10, 20, 30),
        variant_ids=(20, 40),
    )
    assert comparison["preserved"] == [20]
    assert comparison["lost_vs_a"] == [10, 30]
    assert comparison["additional"] == [40]
    assert comparison["lost_count"] == 2


def test_valid_bartender_recovery_uses_current_candidate_semantics():
    bottle = _bottle()
    recovered = classify_roi_outcome(
        primary=_outside_hand(),
        recovered=_zone_hand(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        crop_bounds=crop_bounds_for(
            CROP_A, bottle, frame_width=640, frame_height=480
        ),
    )
    assert recovered["valid_recovery"] is True
    assert recovered["reason"] == "valid_bartender_recovery"
    assert _has_bartender_candidate(
        _zone_hand(), bottle, frame_width=640, frame_height=480
    )
    no_hand = classify_roi_outcome(
        primary=_outside_hand(),
        recovered=None,
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        crop_bounds=crop_bounds_for(
            CROP_A, bottle, frame_width=640, frame_height=480
        ),
    )
    assert no_hand["valid_recovery"] is False
    assert no_hand["reason"] in {
        "roi_returned_no_hand",
        "crop_likely_excludes_hand",
    }
    outside = classify_roi_outcome(
        primary=None,
        recovered=_outside_hand(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        crop_bounds=crop_bounds_for(
            CROP_A, bottle, frame_width=640, frame_height=480
        ),
    )
    assert outside["valid_recovery"] is False
    assert outside["reason"] == "hand_outside_bartender_zone"


def test_debug_output_does_not_modify_source_frames(tmp_path: Path):
    frame = np.full((480, 640, 3), 40, dtype=np.uint8)
    original = frame.copy()
    bottle = _bottle()
    out = tmp_path / "debug.jpg"
    write_crop_debug_image(
        frame,
        bottle,
        {
            "A": crop_bounds_for(CROP_A, bottle, 640, 480),
            "B": crop_bounds_for(CROP_B, bottle, 640, 480),
            "C": crop_bounds_for(CROP_C, bottle, 640, 480),
        },
        out,
    )
    assert np.array_equal(frame, original)
    assert out.is_file()
    saved = cv2.imread(str(out))
    assert saved is not None
    assert saved.shape == frame.shape


def test_production_hands_detector_crop_remains_unchanged():
    source = inspect.getsource(_bartender_crop_bounds)
    assert "_BARTENDER_CROP_WIDTH_FACTOR" in inspect.getsource(
        inspect.getmodule(_bartender_crop_bounds)
    )
    assert "bottle_width * _BARTENDER_CROP_WIDTH_FACTOR" in source
    assert "bottle_height * _BARTENDER_CROP_TOP_FRACTION" in source
    assert "bottle_height * _BARTENDER_CROP_BOTTOM_FRACTION" in source
    detector_source = inspect.getsource(HandsDetector._detect_bartender_roi)
    assert "bounds = _bartender_crop_bounds(" in detector_source
    assert "cv2.ROTATE_90_COUNTERCLOCKWISE" in detector_source
    defaults = production_hands_defaults()
    assert defaults["bartender_roi_fallback"] is False
    assert defaults["max_num_hands"] == 2


def test_crop_containment_classifies_envelope_vs_roi():
    bottle = _bottle()
    bounds = crop_bounds_for(CROP_A, bottle, frame_width=640, frame_height=480)
    inside = crop_containment(
        _zone_hand(), bounds, frame_width=640, frame_height=480
    )
    assert inside["status"] in {
        "fully_inside",
        "partially_inside",
        "mostly_outside",
        "completely_outside",
    }
    assert 0.0 <= inside["landmark_fraction"] <= 1.0
    outside = crop_containment(
        _outside_hand(), bounds, frame_width=640, frame_height=480
    )
    assert outside["status"] == "completely_outside"
    assert outside["wrist_contained"] is False
    assert outside["thumb_contained"] is False
    assert outside["index_contained"] is False


def test_crop_d_is_full_frame_diagnostic_ceiling():
    bounds = crop_bounds_for(
        CROP_D, _bottle(), frame_width=640, frame_height=480
    )
    assert bounds == (0, 0, 640, 480)
    assert CROP_D.full_frame is True
    assert CROP_D.diagnostic_ceiling is True


def test_immediate_eligibility_does_not_depend_on_crop_success():
    bottle = _bottle()
    policy_a = ImmediateRoiPolicy()
    policy_b = ImmediateRoiPolicy()
    a = evaluate_policy_frame(
        policy_a,
        primary=_outside_hand(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        roi_result=None,
        max_num_hands=1,
    )
    b = evaluate_policy_frame(
        policy_b,
        primary=_outside_hand(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        roi_result=_zone_hand(),
        max_num_hands=1,
    )
    assert a.eligible is True
    assert b.eligible is True
    assert a.ran_roi is True
    assert b.ran_roi is True
    assert a.recovered is False
    assert b.recovered is True


def test_select_debug_examples_is_small_and_representative():
    events = [
        {"index": 1, "kind": "a_success"},
        {"index": 2, "kind": "b_or_c_only"},
        {"index": 3, "kind": "all_fail"},
        {"index": 4, "kind": "crop_excludes"},
        {"index": 5, "kind": "all_fail"},
        {"index": 6, "kind": "a_success"},
    ]
    chosen = select_debug_examples(events, limit=4)
    kinds = {item["kind"] for item in chosen}
    assert len(chosen) <= 4
    assert "a_success" in kinds
    assert "b_or_c_only" in kinds
    assert "all_fail" in kinds
    assert "crop_excludes" in kinds


def test_summarize_crop_areas_reports_relative_size():
    bottle = _bottle()
    summary = summarize_crop_areas(
        [bottle, bottle],
        CROP_A,
        frame_width=640,
        frame_height=480,
    )
    assert summary["mean_width"] > 0
    assert summary["mean_height"] > 0
    assert 0.0 < summary["area_fraction"] < 1.0


def test_recommend_crop_trial_requires_preserved_a_and_material_gain():
    keep = recommend_crop_trial(
        a_successes=2,
        b_successes=2,
        c_successes=2,
        b_lost=0,
        c_lost=0,
        b_additional=0,
        c_additional=0,
        a_recovery_rate=0.05,
        b_recovery_rate=0.05,
        c_recovery_rate=0.05,
        d_successes=2,
        eligible=37,
    )
    assert keep["live_trial"] is False
    trial = recommend_crop_trial(
        a_successes=2,
        b_successes=8,
        c_successes=10,
        b_lost=0,
        c_lost=0,
        b_additional=6,
        c_additional=8,
        a_recovery_rate=0.05,
        b_recovery_rate=0.22,
        c_recovery_rate=0.27,
        d_successes=12,
        eligible=37,
    )
    assert trial["live_trial"] is True
    assert trial["best"] in {"B", "C"}
    weak_ceiling = recommend_crop_trial(
        a_successes=0,
        b_successes=4,
        c_successes=3,
        b_lost=0,
        c_lost=0,
        b_additional=4,
        c_additional=3,
        a_recovery_rate=0.0,
        b_recovery_rate=0.108,
        c_recovery_rate=0.081,
        d_successes=5,
        eligible=37,
        b_unhelpful=2,
        c_unhelpful=6,
    )
    assert weak_ceiling["live_trial"] is False
    assert weak_ceiling["decision"] == "CROP NOT THE MAIN PROBLEM"
    lost = recommend_crop_trial(
        a_successes=2,
        b_successes=10,
        c_successes=10,
        b_lost=1,
        c_lost=1,
        b_additional=9,
        c_additional=9,
        a_recovery_rate=0.05,
        b_recovery_rate=0.27,
        c_recovery_rate=0.27,
        d_successes=12,
        eligible=37,
    )
    assert lost["live_trial"] is False
