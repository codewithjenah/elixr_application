"""Benchmark-only Bartender ROI policies. Production HandsDetector stays immediate."""

from __future__ import annotations

import numpy as np

from vision.hands_benchmark import production_hands_defaults
from vision.hands_detector import HandsDetector, _has_bartender_candidate
from vision.hands_roi_policies import (
    CooldownRoiPolicy,
    ConsecutiveMissRoiPolicy,
    ImmediateRoiPolicy,
    classify_wasted_roi,
    evaluate_policy_frame,
    measure_recovery_delay,
)
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _blank() -> np.ndarray:
    return np.zeros((480, 640, 3), dtype=np.uint8)


def _bottle() -> BottleDetection:
    return BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.9)


def _zone_hand(cx: float, cy: float) -> HandLandmarks:
    return HandLandmarks(
        points={
            0: Point2D(cx, cy + 0.04),
            4: Point2D(cx - 0.01, cy),
            8: Point2D(cx + 0.01, cy),
            9: Point2D(cx, cy),
        },
        handedness="Right",
    )


def _in_zone() -> HandsResult:
    return HandsResult(hands=[_zone_hand(0.375, 0.32)])


def _out_of_zone() -> HandsResult:
    return HandsResult(hands=[_zone_hand(0.90, 0.90)])


def test_immediate_policy_reproduces_current_behavior():
    policy = ImmediateRoiPolicy()
    bottle = _bottle()
    miss = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    hit = evaluate_policy_frame(
        policy,
        primary=_in_zone(),
        bottle=bottle,
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert miss.eligible is True
    assert miss.ran_roi is True
    assert miss.recovered is True
    assert hit.eligible is False
    assert hit.ran_roi is False


def test_n2_does_not_run_on_first_missing_candidate_frame():
    policy = ConsecutiveMissRoiPolicy(n=2)
    first = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert first.eligible is True
    assert first.ran_roi is False
    assert first.recovered is False
    assert first.output is not None
    assert not _has_bartender_candidate(
        first.output, _bottle(), frame_width=640, frame_height=480
    )


def test_n2_runs_on_second_consecutive_missing_candidate_frame():
    policy = ConsecutiveMissRoiPolicy(n=2)
    evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    second = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert second.eligible is True
    assert second.ran_roi is True
    assert second.recovered is True


def test_valid_candidate_resets_miss_count():
    policy = ConsecutiveMissRoiPolicy(n=2)
    evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    evaluate_policy_frame(
        policy,
        primary=_in_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    after_hit = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert after_hit.ran_roi is False


def test_recovery_resets_miss_count():
    policy = ConsecutiveMissRoiPolicy(n=2)
    evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    recovered = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert recovered.recovered is True
    next_miss = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert next_miss.ran_roi is False


def test_no_bottle_does_not_advance_eligible_miss_state():
    policy = ConsecutiveMissRoiPolicy(n=2)
    evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    no_bottle = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=None,
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert no_bottle.eligible is False
    assert no_bottle.ran_roi is False
    after = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert after.ran_roi is False


def test_no_stale_result_is_reused():
    policy = ConsecutiveMissRoiPolicy(n=2)
    evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    recovered = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert recovered.recovered is True
    skipped = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert skipped.ran_roi is False
    assert skipped.output is not recovered.output
    assert not _has_bartender_candidate(
        skipped.output, _bottle(), frame_width=640, frame_height=480
    )


def test_delayed_recovery_is_measured_correctly():
    a = [
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 40,
        },
    ]
    b = [
        {
            "ran_roi": False,
            "recovered": False,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 40,
        },
    ]
    report = measure_recovery_delay(a, b)
    assert report["immediate_recoveries"] == 0
    assert report["delayed_recoveries"] == 1
    assert report["lost_recoveries"] == 0
    assert report["mean_recovery_delay_frames"] == 1.0
    assert report["mean_recovery_delay_ms"] == 40.0
    assert report["max_recovery_delay_frames"] == 1
    assert report["max_recovery_delay_ms"] == 40


def test_lost_recovery_is_measured_correctly():
    a = [
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": False,
            "recovered": False,
            "primary_usable": True,
            "relative_time_ms": 33,
        },
    ]
    b = [
        {
            "ran_roi": False,
            "recovered": False,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": False,
            "recovered": False,
            "primary_usable": True,
            "relative_time_ms": 33,
        },
    ]
    report = measure_recovery_delay(a, b)
    assert report["lost_recoveries"] == 1
    assert report["delayed_recoveries"] == 0
    assert report["immediate_recoveries"] == 0

    a_fail = [
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "relative_time_ms": 33,
        },
    ]
    b_fail = [
        {
            "ran_roi": False,
            "recovered": False,
            "primary_usable": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": True,
            "recovered": False,
            "primary_usable": False,
            "relative_time_ms": 33,
        },
    ]
    lost_on_attempt = measure_recovery_delay(a_fail, b_fail)
    assert lost_on_attempt["lost_recoveries"] == 1


def test_cooldown_skips_exactly_the_intended_attempt():
    policy = CooldownRoiPolicy()
    first = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_out_of_zone(),
        max_num_hands=1,
    )
    skipped = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    allowed = evaluate_policy_frame(
        policy,
        primary=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
        roi_result=_in_zone(),
        max_num_hands=1,
    )
    assert first.ran_roi is True
    assert first.recovered is False
    assert skipped.eligible is True
    assert skipped.ran_roi is False
    assert allowed.ran_roi is True
    assert allowed.recovered is True


def test_benchmark_policies_do_not_modify_production_defaults():
    before = production_hands_defaults()
    ImmediateRoiPolicy()
    ConsecutiveMissRoiPolicy(n=2)
    CooldownRoiPolicy()
    after = production_hands_defaults()
    assert before == after
    assert after["bartender_roi_fallback"] is False
    assert after["rotated_fallback"] is False
    assert after["max_num_hands"] == 2
    assert after["timestamp_clock"] is None


def test_production_hands_detector_remains_immediate_roi_behavior():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = False
            self._bartender_roi_fallback = True
            self._max_num_hands = 1
            self.roi_calls = 0

        def _detect_primary(self, frame):
            return _out_of_zone()

        def _detect_bartender_roi(self, frame, bottle):
            self.roi_calls += 1
            return _in_zone()

    detector = Stub()
    first = detector.detect(_blank(), _bottle())
    second = detector.detect(_blank(), _bottle())
    assert detector.roi_calls == 2
    assert _has_bartender_candidate(
        first, _bottle(), frame_width=640, frame_height=480
    )
    assert _has_bartender_candidate(
        second, _bottle(), frame_width=640, frame_height=480
    )
    defaults = production_hands_defaults()
    assert defaults["bartender_roi_fallback"] is False


def test_wasted_roi_classifies_no_hand_and_outside_zone():
    no_hand = classify_wasted_roi(
        primary=None,
        recovered=None,
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
    )
    outside = classify_wasted_roi(
        primary=None,
        recovered=_out_of_zone(),
        bottle=_bottle(),
        frame_width=640,
        frame_height=480,
    )
    assert no_hand == "roi_returned_no_hand"
    assert outside == "hand_outside_bartender_zone"


def test_immediate_recovery_miss_bucket_and_primary_cause():
    from vision.hands_roi_policies import classify_immediate_recoveries

    events = [
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": False,
            "relative_time_ms": 0,
        },
        {
            "ran_roi": True,
            "recovered": False,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": True,
            "relative_time_ms": 40,
        },
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": True,
            "relative_time_ms": 80,
        },
        {
            "ran_roi": True,
            "recovered": False,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": False,
            "relative_time_ms": 120,
        },
        {
            "ran_roi": True,
            "recovered": False,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": False,
            "relative_time_ms": 160,
        },
        {
            "ran_roi": True,
            "recovered": True,
            "primary_usable": False,
            "bottle_present": True,
            "primary_had_hand": False,
            "relative_time_ms": 200,
        },
    ]
    report = classify_immediate_recoveries(events)
    assert report["a_recoveries"] == 3
    assert report["first_miss"] == 1
    assert report["second_miss"] == 1
    assert report["third_or_later"] == 1
    assert report["primary_no_hand"] == 2
    assert report["primary_hand_outside_zone"] == 1


def test_frozen_bottle_objects_are_reused_for_ab():
    from vision.hands_benchmark import freeze_bottles

    bottles = freeze_bottles([_bottle(), None, _bottle()])
    again = bottles
    assert again[0] is bottles[0]
    assert again[1] is None
    assert again[2] is bottles[2]
    assert bottles[0].x1 == 200
    assert bottles[0].confidence == 0.9
