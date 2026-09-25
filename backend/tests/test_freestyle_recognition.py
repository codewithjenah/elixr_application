"""Freestyle Playground recognition: hysteresis, allowlist, flip, quality."""

from __future__ import annotations

from assessment.feedback_codes import FeedbackCode
from assessment.freestyle import (
    ADVANCED_DISPLAY,
    FLIP_DISPLAY,
    FlipTracker,
    FreestyleRecognizer,
    RecognitionEvent,
    sanitize_allowed_movements,
    static_quality,
)
from assessment.rule_engine import movement_supported_prop_types
from assessment.rules.base import CriterionCheck, RuleResult
from vision.types import (
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
    PropDetection,
)


def _box(
    *,
    x1: int = 300,
    y1: int = 200,
    track_id: int = 1,
    yolo_confirmed: bool = True,
    confidence: float = 0.9,
) -> PropDetection:
    return PropDetection(
        x1=x1,
        y1=y1,
        x2=x1 + 40,
        y2=y1 + 80,
        confidence=confidence,
        track_id=track_id,
        yolo_confirmed=yolo_confirmed,
    )


def _hands_at(x: float, y: float) -> HandsResult:
    from vision.types import HandLandmarks

    return HandsResult(
        hands=[
            HandLandmarks(
                points={
                    0: Point2D(x, y + 0.02),
                    9: Point2D(x, y),
                },
                handedness="Right",
            )
        ]
    )


def _valid(code: str = FeedbackCode.NORMAL_GRIP_LOCKED.value) -> RuleResult:
    return RuleResult(
        feedback="ok",
        feedback_type="positive",
        posture_status="stable",
        feedback_code=code,
        criterion_results={
            "technique": CriterionCheck(True, True, code),
            "stability": CriterionCheck(True, True, "stable"),
            "prop_positioning": CriterionCheck(True, True, "position_ok"),
        },
    )


def _invalid() -> RuleResult:
    return RuleResult(
        feedback="no",
        feedback_type="warning",
        posture_status="unstable",
        feedback_code="not_ready",
        criterion_results={
            "technique": CriterionCheck(True, False, "not_ready"),
            "stability": CriterionCheck(True, False, "unstable"),
            "prop_positioning": CriterionCheck(True, False, "off"),
        },
    )


def _unknown() -> RuleResult:
    return RuleResult(
        feedback="missing",
        feedback_type="error",
        posture_status="unknown",
        feedback_code="prop_not_detected",
    )


class _ScriptedEvaluate:
    def __init__(self, by_movement: dict[str, list[RuleResult] | RuleResult]):
        self.by_movement = by_movement
        self.calls: list[tuple[str, str]] = []

    def __call__(self, movement, bottle, pose, hands, prev_hip, state=None, **kwargs):
        prop_type = kwargs.get("prop_type", "bottle")
        self.calls.append((movement, prop_type))
        script = self.by_movement.get(movement, _invalid())
        if isinstance(script, list):
            if not script:
                result = _invalid()
            else:
                result = script.pop(0) if len(script) > 1 else script[0]
        else:
            result = script
        return result, prev_hip, state or {}


def _recognizer(
    evaluate,
    allowed: set[tuple[str, str]] | None = None,
    confirm: float = 0.2,
    exit_s: float = 0.15,
) -> FreestyleRecognizer:
    return FreestyleRecognizer(
        allowed_movements=frozenset(
            allowed
            if allowed is not None
            else {("Normal Grip", "bottle")}
        ),
        evaluate_fn=evaluate,
        confirm_seconds=confirm,
        exit_seconds=exit_s,
        unknown_grace_seconds=0.2,
    )


def _tick(recognizer: FreestyleRecognizer, t: float, evaluate=None, **kwargs):
    return recognizer.update(
        timestamp=t,
        dt=kwargs.pop("dt", 0.05),
        bottles=kwargs.pop("bottles", [_box()]),
        shakers=kwargs.pop("shakers", []),
        hands=kwargs.pop("hands", _hands_at(0.5, 0.5)),
        pose=kwargs.pop("pose", None),
        width=kwargs.pop("width", 640),
        height=kwargs.pop("height", 480),
    )


def test_endless_target_filters_catalog_and_resets_candidate():
    evaluate = _ScriptedEvaluate({
        "Normal Grip": _valid(),
        "Reverse Grip": _valid(),
    })
    recognizer = FreestyleRecognizer(
        allowed_movements=frozenset({
            ("Normal Grip", "bottle"), ("Reverse Grip", "bottle"),
        }),
        targeted=True,
        evaluate_fn=evaluate,
        confirm_seconds=0.15,
    )
    assert _tick(recognizer, 0.0).event is None
    assert evaluate.calls == []
    assert not recognizer.set_target("movement", "Hand Stall", "bottle")
    assert not recognizer.set_target("movement", "Normal Grip", "shaker")
    assert not recognizer.set_target("movement", "Double Hand Stall", "bottle")
    assert not recognizer.set_target("toss_catch", None, "shaker")
    assert recognizer.set_target("movement", "Normal Grip", "bottle")
    _tick(recognizer, 0.05)
    _tick(recognizer, 0.10)
    assert recognizer._candidate_key == ("Normal Grip", "bottle")
    assert recognizer.set_target("movement", "Reverse Grip", "bottle")
    assert recognizer._candidate_key is None
    assert recognizer._confirmed_key is None
    evaluate.calls.clear()
    events = [_tick(recognizer, 1 + i * 0.05).event for i in range(10)]
    assert {name for name, _ in evaluate.calls} == {"Reverse Grip"}
    assert len([event for event in events if event is not None]) == 1
    assert next(event for event in events if event is not None).movement == "Reverse Grip"
    recognizer.set_paused(True)
    assert _tick(recognizer, 2.0).event is None
    recognizer.set_paused(False)
    assert recognizer._target == ("Reverse Grip", "bottle")
    recognizer.clear_target()
    assert recognizer._target is None


def test_endless_candidate_survives_brief_landmark_tracking_loss():
    class LandmarkSensitiveEvaluate:
        def __call__(
            self, movement, bottle, pose, hands, prev_hip, state=None, **kwargs
        ):
            result = _unknown() if hands is None or pose is None else _valid()
            return result, prev_hip, state

    evaluate = LandmarkSensitiveEvaluate()
    allowed = frozenset({("Normal Grip", "bottle")})
    standard = FreestyleRecognizer(allowed_movements=allowed)
    recognizer = FreestyleRecognizer(
        allowed_movements=allowed,
        targeted=True,
        evaluate_fn=evaluate,
        confirm_seconds=0.2,
        exit_seconds=0.1,
    )
    assert standard.unknown_grace_seconds == 0.35
    assert recognizer.unknown_grace_seconds == 0.5
    assert recognizer.set_target("movement", "Normal Grip", "bottle")
    pose = PoseLandmarks(points={11: Point2D(0.4, 0.3)})

    _tick(recognizer, 0.0, pose=pose)
    for index in range(1, 10):
        tick = _tick(
            recognizer,
            index * 0.05,
            hands=None,
            pose=None,
        )
        assert tick.recognition_state == "candidate"

    events = [
        _tick(recognizer, index * 0.05, pose=pose).event
        for index in range(10, 18)
    ]
    confirmed = [event for event in events if event is not None]
    assert len(confirmed) == 1
    assert confirmed[0].movement == "Normal Grip"


def test_generic_airborne_event_is_named_toss_catch():
    assert FLIP_DISPLAY == "Toss & Catch"


def test_targeted_toss_catch_emits_generic_event_without_rotation_claim():
    recognizer = FreestyleRecognizer(
        allowed_movements=frozenset({("Normal Grip", "bottle")}),
        targeted=True,
    )
    recognizer._flip = FlipTracker(
        grip_seconds=0.1,
        min_airborne_seconds=0.1,
        catch_stable_seconds=0.1,
        release_speed=0.2,
        catch_speed=0.5,
    )
    assert recognizer.set_target("toss_catch", None, "bottle")
    hands = _hands_at(0.5, 0.48)
    far_hands = _hands_at(0.12, 0.82)
    t = 0.0
    events = []

    def tick(y, current_hands):
        nonlocal t
        result = _tick(
            recognizer, t,
            bottles=[_box(x1=300, y1=y, track_id=9)],
            hands=current_hands,
        )
        if result.event is not None:
            events.append(result.event)
        t += 0.05

    for _ in range(5):
        tick(220, hands)
    for y in (185, 150, 115, 80):
        tick(y, far_hands)
    for y in (90, 140, 190, 208, 216, 220):
        tick(y, hands if y >= 208 else far_hands)
    for _ in range(6):
        tick(220, hands)
    assert len(events) == 1
    assert events[0].kind == "flip"  # Wire compatibility; no rotation evidence.
    assert events[0].display_label == "Toss & Catch"
    assert events[0].movement is None


def test_sanitize_allowed_movements_drops_internal_and_unknown():
    cleaned = sanitize_allowed_movements(
        [
            ("Normal Grip", "bottle"),
            ("Free Practice", "bottle"),
            ("Not A Move", "bottle"),
            ("Bottle in a tin", "bottle"),
            ("Bottle in a tin", "bottle_and_shaker"),
            ("Normal Grip", "shaker"),
        ]
    )
    assert ("Normal Grip", "bottle") in cleaned
    assert ("Free Practice", "bottle") not in cleaned
    assert ("Not A Move", "bottle") not in cleaned
    assert ("Bottle in a tin", "bottle") not in cleaned
    assert ("Bottle in a tin", "bottle_and_shaker") in cleaned
    assert ("Normal Grip", "shaker") not in cleaned


def test_backend_freestyle_prop_variants_match_the_official_catalog():
    # Mirrors Flutter movementCatalog: the five medium stalls support both
    # single props, Bottle in a tin is dual-prop, all remaining variants are
    # bottle-only.
    bottle_or_shaker = {
        "Hand Stall",
        "One Finger Stall",
        "Forearm Stall",
        "Elbow Stall",
        "Wrist Stall",
    }
    dual_prop = {"Bottle in a tin"}
    expected_bottle_only = {
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Claw Grip",
        "Body Grip",
        "Reverse Forearm Stall",
        "Shoulder Stall",
        "Double Hand Stall",
        "Double Forearm Stall",
    }
    for movement in bottle_or_shaker:
        assert movement_supported_prop_types(movement) == ("bottle", "shaker")
    for movement in dual_prop:
        assert movement_supported_prop_types(movement) == ("bottle_and_shaker",)
    for movement in expected_bottle_only:
        assert movement_supported_prop_types(movement) == ("bottle",)


def test_single_frame_does_not_confirm():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.2)
    tick = _tick(recognizer, 0.0)
    assert tick.event is None
    assert tick.recognition_state == "candidate"
    assert tick.recognized_display is None


def test_stable_unlocked_normal_grip_emits_one_event():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.2)
    events: list[RecognitionEvent] = []
    for i in range(10):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None:
            events.append(tick.event)
    assert len(events) == 1
    assert events[0].movement == "Normal Grip"
    assert events[0].identity_revealed is True
    assert events[0].quality in {"perfect", "great", "nice"}
    # Holding continues without more events.
    later = _tick(recognizer, 1.0)
    assert later.event is None
    assert later.recognized_display == "Normal Grip"


def test_holding_does_not_spam_and_reentry_emits_again():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.15, exit_s=0.1)
    first = None
    for i in range(8):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None:
            first = tick.event
    assert first is not None

    evaluate.by_movement["Normal Grip"] = _invalid()
    for i in range(8, 16):
        tick = _tick(recognizer, i * 0.05)
        assert tick.event is None or tick.event.kind != "movement"

    evaluate.by_movement["Normal Grip"] = _valid()
    second = None
    for i in range(16, 28):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None and tick.event.kind == "movement":
            second = tick.event
    assert second is not None
    assert second.movement == "Normal Grip"


def test_candidate_switch_does_not_flicker_labels():
    evaluate = _ScriptedEvaluate(
        {
            "Normal Grip": _valid(),
            "Bartender's Grip": _valid(FeedbackCode.BARTENDER_GRIP_LOCKED.value),
        }
    )
    recognizer = _recognizer(
        evaluate,
        allowed={("Normal Grip", "bottle"), ("Bartender's Grip", "bottle")},
        confirm=0.3,
    )
    displays = []
    for i in range(4):
        tick = _tick(recognizer, i * 0.05)
        displays.append(tick.recognized_display)
        assert tick.recognition_state in {"candidate", "searching"}
    assert all(label is None for label in displays)


def test_locked_movement_is_generic():
    evaluate = _ScriptedEvaluate({"Bartender's Grip": _valid("bartenders_grip_locked")})
    recognizer = _recognizer(
        evaluate,
        allowed={("Normal Grip", "bottle")},
        confirm=0.15,
    )
    event = None
    for i in range(10):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None:
            event = tick.event
    assert event is not None
    assert event.kind == "advanced_technique"
    assert event.identity_revealed is False
    assert event.movement is None
    assert event.display_label == ADVANCED_DISPLAY
    assert tick.recognized_display == ADVANCED_DISPLAY


def test_allowlist_is_movement_and_prop_specific():
    evaluate = _ScriptedEvaluate({"Hand Stall": _valid("hand_stall_locked")})
    recognizer = _recognizer(
        evaluate,
        allowed={("Hand Stall", "bottle")},
        confirm=0.15,
    )
    event = None
    for i in range(10):
        tick = _tick(
            recognizer,
            i * 0.05,
            bottles=[],
            shakers=[_box()],
        )
        if tick.event is not None:
            event = tick.event
    assert event is not None
    assert event.kind == "advanced_technique"
    assert event.movement is None


def test_shaker_variant_emits_an_unlocked_movement_event():
    evaluate = _ScriptedEvaluate({"Hand Stall": _valid("hand_stall_locked")})
    recognizer = _recognizer(
        evaluate,
        allowed={("Hand Stall", "shaker")},
        confirm=0.15,
    )
    event = None
    for i in range(12):
        tick = _tick(recognizer, i * 0.05, bottles=[], shakers=[_box()])
        if tick.event is not None:
            event = tick.event
    assert event is not None
    assert event.kind == "movement"
    assert event.movement == "Hand Stall"
    assert event.prop_type == "shaker"


def test_bottle_only_movements_are_not_evaluated_for_shaker_detections():
    evaluate = _ScriptedEvaluate({})
    recognizer = _recognizer(evaluate)
    _tick(recognizer, 0.0, bottles=[], shakers=[_box()])
    evaluated = {movement for movement, prop_type in evaluate.calls if prop_type == "shaker"}
    assert evaluated == {
        "Hand Stall",
        "One Finger Stall",
        "Forearm Stall",
        "Elbow Stall",
        "Wrist Stall",
    }
    assert ("Normal Grip", "shaker") not in evaluate.calls


def test_bottle_in_a_tin_requires_both_official_props():
    evaluate = _ScriptedEvaluate({"Bottle in a tin": _valid("bottle_in_tin_locked")})
    recognizer = _recognizer(
        evaluate,
        allowed={("Bottle in a tin", "bottle_and_shaker")},
        confirm=0.15,
    )
    _tick(recognizer, 0.0, bottles=[_box()], shakers=[])
    assert ("Bottle in a tin", "bottle_and_shaker") not in evaluate.calls

    event = None
    for i in range(1, 12):
        tick = _tick(recognizer, i * 0.05, bottles=[_box()], shakers=[_box(track_id=2)])
        if tick.event is not None:
            event = tick.event
    assert event is not None
    assert event.kind == "movement"
    assert event.movement == "Bottle in a tin"
    assert event.prop_type == "bottle_and_shaker"


def test_candidate_temporal_inputs_are_isolated_and_reset():
    class _TemporalEvaluate:
        def __init__(self):
            self.expected_hips: dict[str, Point2D] = {}
            self.calls: list[str] = []

        def __call__(self, movement, bottle, pose, hands, prev_hip, state=None, **kwargs):
            state = state or {}
            assert state.get("owner", movement) == movement
            assert prev_hip == self.expected_hips.get(movement)
            next_hip = Point2D(float(len(self.calls) + 1), 0.0)
            self.expected_hips[movement] = next_hip
            self.calls.append(movement)
            return _invalid(), next_hip, {"owner": movement}

    evaluate = _TemporalEvaluate()
    recognizer = _recognizer(evaluate)
    _tick(recognizer, 0.0)
    first_frame_candidates = set(evaluate.calls)
    _tick(recognizer, 0.05)
    assert {movement for movement, _ in recognizer._prev_hips} == first_frame_candidates
    assert {movement for movement, _ in recognizer._states} == first_frame_candidates
    assert all(state["owner"] == movement for (movement, _), state in recognizer._states.items())

    recognizer.reset()
    assert recognizer._prev_hips == {}
    assert recognizer._states == {}


def _body_grip_hands() -> HandsResult:
    # Realistic body-wrap fixture: it positively matches Body Grip while the
    # overlapping neck-grip rules reject its mid-body contact geometry.
    return HandsResult(
        hands=[
            HandLandmarks(
                points={
                    0: Point2D(0.42, 0.56),
                    1: Point2D(0.44, 0.54),
                    2: Point2D(0.46, 0.53),
                    3: Point2D(0.48, 0.525),
                    4: Point2D(0.50, 0.53),
                    5: Point2D(0.44, 0.53),
                    6: Point2D(0.47, 0.58),
                    7: Point2D(0.50, 0.57),
                    8: Point2D(0.52, 0.55),
                    9: Point2D(0.45, 0.54),
                    10: Point2D(0.48, 0.58),
                    11: Point2D(0.51, 0.57),
                    12: Point2D(0.52, 0.55),
                    13: Point2D(0.46, 0.55),
                    14: Point2D(0.49, 0.59),
                    15: Point2D(0.51, 0.57),
                    16: Point2D(0.52, 0.56),
                    17: Point2D(0.46, 0.56),
                    18: Point2D(0.49, 0.60),
                    19: Point2D(0.51, 0.58),
                    20: Point2D(0.53, 0.56),
                },
                handedness="Right",
            )
        ]
    )


def test_real_body_grip_fixture_beats_overlapping_neck_grip_rules():
    recognizer = FreestyleRecognizer(
        allowed_movements=frozenset({("Body Grip", "bottle")}),
        confirm_seconds=0.10,
        exit_seconds=0.15,
    )
    body_bottle = PropDetection(
        x1=300,
        y1=140,
        x2=340,
        y2=340,
        confidence=0.9,
    )
    event = None
    for i in range(8):
        tick = _tick(
            recognizer,
            i * 0.05,
            bottles=[body_bottle],
            hands=_body_grip_hands(),
        )
        if tick.event is not None:
            event = tick.event
    assert event is not None
    assert event.kind == "movement"
    assert event.movement == "Body Grip"


def test_pause_freezes_recognition():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.15)
    recognizer.set_paused(True)
    for i in range(10):
        tick = _tick(recognizer, i * 0.05)
        assert tick.event is None
        assert tick.recognition_state == "paused"


def test_unknown_grace_does_not_leave_confirmed_movement():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.15, exit_s=0.4)
    event = None
    for i in range(8):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None:
            event = tick.event
    assert event is not None
    evaluate.by_movement["Normal Grip"] = _unknown()
    tick = _tick(recognizer, 0.5, dt=0.05)
    assert tick.recognized_display == "Normal Grip"
    assert tick.event is None


def test_quality_mapping_is_deterministic():
    assert static_quality(valid_ratio=1.0, criteria_satisfied=3, criteria_observed=3) == "perfect"
    assert static_quality(valid_ratio=0.8, criteria_satisfied=2, criteria_observed=3) == "great"
    assert static_quality(valid_ratio=0.5, criteria_satisfied=1, criteria_observed=3) == "nice"


def test_yolo_miss_is_not_release():
    tracker = FlipTracker()
    hands = _hands_at(0.5, 0.48)
    held = _box(x1=300, y1=200, track_id=7, yolo_confirmed=True)
    t = 0.0
    for _ in range(6):
        event = tracker.update(
            timestamp=t,
            bottles=[held],
            shakers=[],
            hands=hands,
            width=640,
            height=480,
        )
        assert event is None
        t += 0.05
    miss = _box(x1=300, y1=200, track_id=7, yolo_confirmed=False)
    event = tracker.update(
        timestamp=t,
        bottles=[miss],
        shakers=[],
        hands=hands,
        width=640,
        height=480,
    )
    assert event is None
    assert tracker._phase == "gripped"


def test_reacquisition_alone_is_not_catch():
    tracker = FlipTracker(
        grip_seconds=0.1,
        min_airborne_seconds=0.1,
        catch_stable_seconds=0.1,
        release_speed=0.2,
        catch_speed=0.4,
    )
    hands = _hands_at(0.5, 0.48)
    t = 0.0
    held = _box(x1=300, y1=220, track_id=3, yolo_confirmed=True)
    for _ in range(5):
        tracker.update(
            timestamp=t,
            bottles=[held],
            shakers=[],
            hands=hands,
            width=640,
            height=480,
        )
        t += 0.05
    far_hands = _hands_at(0.15, 0.80)
    airborne = _box(x1=300, y1=40, track_id=3, yolo_confirmed=True)
    for _ in range(5):
        event = tracker.update(
            timestamp=t,
            bottles=[airborne],
            shakers=[],
            hands=far_hands,
            width=640,
            height=480,
        )
        assert event is None
        t += 0.05
        airborne = _box(x1=300, y1=30, track_id=3, yolo_confirmed=True)
    # Reacquired at the airborne location, still far from the hand.
    event = tracker.update(
        timestamp=t,
        bottles=[_box(x1=300, y1=30, track_id=3, yolo_confirmed=True)],
        shakers=[],
        hands=far_hands,
        width=640,
        height=480,
    )
    assert event is None
    assert tracker._phase == "airborne"


def test_successful_flip_emits_once_for_bottle_and_shaker():
    for prop, bottles, shakers in (
        ("bottle", True, False),
        ("shaker", False, True),
    ):
        tracker = FlipTracker(
            grip_seconds=0.1,
            min_airborne_seconds=0.1,
            catch_stable_seconds=0.1,
            release_speed=0.2,
            catch_speed=0.5,
        )
        hands = _hands_at(0.5, 0.48)
        t = 0.0
        held = _box(x1=300, y1=220, track_id=9, yolo_confirmed=True)
        for _ in range(5):
            tracker.update(
                timestamp=t,
                bottles=[held] if bottles else [],
                shakers=[held] if shakers else [],
                hands=hands,
                width=640,
                height=480,
            )
            t += 0.05
        far_hands = _hands_at(0.12, 0.82)
        y = 220
        for _ in range(4):
            y -= 35
            flying = _box(x1=300, y1=y, track_id=9, yolo_confirmed=True)
            tracker.update(
                timestamp=t,
                bottles=[flying] if bottles else [],
                shakers=[flying] if shakers else [],
                hands=far_hands,
                width=640,
                height=480,
            )
            t += 0.05
        # Decelerate into the catching hand so speed is a catch, not a drop.
        for y in (90, 140, 190, 208, 216, 220):
            returning = _box(x1=300, y1=y, track_id=9, yolo_confirmed=True)
            near_catch = y >= 208
            tracker.update(
                timestamp=t,
                bottles=[returning] if bottles else [],
                shakers=[returning] if shakers else [],
                hands=hands if near_catch else far_hands,
                width=640,
                height=480,
            )
            t += 0.05
        events = []
        caught = _box(x1=300, y1=220, track_id=9, yolo_confirmed=True)
        for _ in range(6):
            event = tracker.update(
                timestamp=t,
                bottles=[caught] if bottles else [],
                shakers=[caught] if shakers else [],
                hands=hands,
                width=640,
                height=480,
            )
            if event is not None:
                events.append(event)
            t += 0.05
        assert len(events) == 1, prop
        assert events[0].kind == "flip"
        assert events[0].display_label == FLIP_DISPLAY
        assert events[0].prop_type == prop


def test_drop_does_not_count_as_flip():
    tracker = FlipTracker(
        grip_seconds=0.1,
        min_airborne_seconds=0.1,
        release_speed=0.2,
    )
    hands = _hands_at(0.5, 0.48)
    t = 0.0
    held = _box(x1=300, y1=220, track_id=4, yolo_confirmed=True)
    for _ in range(5):
        tracker.update(
            timestamp=t,
            bottles=[held],
            shakers=[],
            hands=hands,
            width=640,
            height=480,
        )
        t += 0.05
    far_hands = _hands_at(0.1, 0.85)
    flying = _box(x1=300, y1=40, track_id=4, yolo_confirmed=True)
    tracker.update(
        timestamp=t,
        bottles=[flying],
        shakers=[],
        hands=far_hands,
        width=640,
        height=480,
    )
    t += 0.05
    event = None
    for _ in range(6):
        event = tracker.update(
            timestamp=t,
            bottles=[],
            shakers=[],
            hands=far_hands,
            width=640,
            height=480,
        )
        t += 0.05
        if event is not None:
            break
    assert event is not None
    assert event.kind == "failed_action"
    assert event.identity_revealed is False


def test_equally_valid_locked_and_unlocked_candidates_fail_closed():
    evaluate = _ScriptedEvaluate(
        {
            "Normal Grip": _valid(),
            "Bartender's Grip": _valid(FeedbackCode.BARTENDER_GRIP_LOCKED.value),
        }
    )
    recognizer = _recognizer(
        evaluate,
        allowed={("Normal Grip", "bottle")},
        confirm=0.15,
    )
    events = []
    for i in range(12):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None:
            events.append(tick.event)
    assert events == []
    assert tick.recognition_state == "searching"


def test_unconfirmed_yolo_box_does_not_confirm_static_movement():
    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.15)
    events = []
    for i in range(12):
        tick = _tick(
            recognizer,
            i * 0.05,
            bottles=[_box(yolo_confirmed=False)],
        )
        if tick.event is not None:
            events.append(tick.event)
    assert events == []
    assert tick.recognition_state in {"searching", "candidate"}


def test_failed_flip_does_not_suppress_static_confirmation():
    class _FailingFlip:
        def update(self, **kwargs):
            return RecognitionEvent(
                kind="failed_action",
                display_label="",
                identity_revealed=False,
            )

        def reset(self):
            return None

    evaluate = _ScriptedEvaluate({"Normal Grip": _valid()})
    recognizer = _recognizer(evaluate, confirm=0.15)
    recognizer._flip = _FailingFlip()
    movement_events = []
    for i in range(12):
        tick = _tick(recognizer, i * 0.05)
        if tick.event is not None and tick.event.kind == "movement":
            movement_events.append(tick.event)
    assert len(movement_events) == 1
    assert movement_events[0].movement == "Normal Grip"


def test_airborne_short_gap_is_not_a_failed_flip():
    tracker = FlipTracker(
        grip_seconds=0.1,
        min_airborne_seconds=0.1,
        release_speed=0.2,
        miss_grace_seconds=0.2,
    )
    hands = _hands_at(0.5, 0.48)
    t = 0.0
    held = _box(x1=300, y1=220, track_id=4, yolo_confirmed=True)
    for _ in range(5):
        tracker.update(
            timestamp=t,
            bottles=[held],
            shakers=[],
            hands=hands,
            width=640,
            height=480,
        )
        t += 0.05
    far_hands = _hands_at(0.1, 0.85)
    flying = _box(x1=300, y1=40, track_id=4, yolo_confirmed=True)
    tracker.update(
        timestamp=t,
        bottles=[flying],
        shakers=[],
        hands=far_hands,
        width=640,
        height=480,
    )
    t += 0.05
    event = tracker.update(
        timestamp=t,
        bottles=[],
        shakers=[],
        hands=far_hands,
        width=640,
        height=480,
    )
    assert event is None
    assert tracker._phase == "airborne"
    t += 0.05
    event = tracker.update(
        timestamp=t,
        bottles=[_box(x1=300, y1=30, track_id=4, yolo_confirmed=True)],
        shakers=[],
        hands=far_hands,
        width=640,
        height=480,
    )
    assert event is None
    assert tracker._phase == "airborne"
