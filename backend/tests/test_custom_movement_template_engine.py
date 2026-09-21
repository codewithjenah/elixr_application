from assessment.custom_movement import (
    FailureCode, FrameSample, Landmark, MovementTemplate, build_template,
    compare_sequence, detect_prop_events, normalize_sequence, validate_sequence,
)


def _sequence(*, shift=0.0, scale=1.0, count=12, interval=100, reverse=False, prop=True, miss=(), static=False):
    values = list(range(count))
    if reverse:
        values.reverse()
    frames = []
    for i, value in enumerate(values):
        cx, cy = shift + .5 * scale, shift + .3 * scale
        x = shift + (.2 + .035 * value) * scale
        if static:
            x = shift + .2 * scale
        pose = {
            "11": Landmark(cx - .2 * scale, cy), "12": Landmark(cx + .2 * scale, cy),
            "15": Landmark(x, shift + .4 * scale),
        }
        hands = {"left": Landmark(x - .03 * scale, shift + .42 * scale), "right": Landmark(x + .1 * scale, shift + .42 * scale)}
        frames.append(FrameSample(i * interval, pose, hands, None if i in miss or not prop else Landmark(x, shift + .38 * scale)))
    return tuple(frames)


def _template():
    return build_template([_sequence(), _sequence(shift=.1), _sequence(scale=1.1)], ("pose", "hands", "prop_translation"))


def _release_sequence(*, catch=True, interval=100):
    path = [0, 0, .4, .6, .4, 0, 0, 0] if catch else [0, 0, .4, .6, .5, .4, .4, .4]
    return tuple(
        FrameSample(
            i * interval,
            pose={"11": Landmark(.3, .3), "12": Landmark(.7, .3)},
            hands={"left": Landmark(0, 0)},
            prop=Landmark(x, 0),
        )
        for i, x in enumerate(path)
    )


def test_valid_and_invalid_reference_validation():
    assert validate_sequence(_sequence(), ("pose", "hands", "prop_translation")).valid
    invalid = validate_sequence(_sequence(count=4, prop=False), ("pose", "prop_translation"))
    assert FailureCode.INSUFFICIENT_FRAMES in invalid.codes
    assert FailureCode.MISSING_MODALITY in invalid.codes


def test_template_requires_three_references_and_is_serializable_deterministically():
    try:
        build_template([_sequence(), _sequence()], ("pose",))
        assert False
    except ValueError as error:
        assert error.args[0] == FailureCode.INVALID_REFERENCE_COUNT.value
    first, second = _template(), _template()
    assert first.to_dict() == second.to_dict()
    assert first.reference_count == 3 and len(first.canonical_sequence) == 32
    loaded = MovementTemplate.from_dict(first.to_dict())
    assert loaded.to_dict() == first.to_dict()
    assert loaded.feature_capabilities["prop_rotation"] is False
    bad = first.to_dict()
    bad["feature_capabilities"]["prop_rotation"] = True
    try:
        MovementTemplate.from_dict(bad)
        assert False
    except ValueError as error:
        assert error.args[0] == FailureCode.INVALID_SCHEMA.value


def test_normalization_removes_translation_and_scale_without_mirroring_hands():
    a, b = normalize_sequence(_sequence()), normalize_sequence(_sequence(shift=3, scale=2))
    assert abs(a[4].hands["left"].x - b[4].hands["left"].x) < 1e-12
    assert abs(a[4].hands["right"].x - b[4].hands["right"].x) < 1e-12
    assert a[4].hands["left"].x < a[4].hands["right"].x


def test_matching_speed_tolerance_and_wrong_order_static_and_prop_trajectory_scores():
    template = _template()
    good = compare_sequence(template, _sequence(interval=50))
    wrong_order = compare_sequence(template, _sequence(reverse=True))
    static = compare_sequence(template, _sequence(static=True))
    different_prop = compare_sequence(template, tuple(
        FrameSample(f.timestamp_ms, f.pose, f.hands, Landmark(-f.prop.x, f.prop.y) if f.prop else None) for f in _sequence()
    ))
    assert good.component_scores["Body technique"] == 3
    assert good.component_scores["Prop path"] == 3
    assert wrong_order.component_scores["Body technique"] < good.component_scores["Body technique"]
    assert static.component_scores["Prop path"] < good.component_scores["Prop path"]
    assert different_prop.component_scores["Prop path"] < good.component_scores["Prop path"]


def test_missing_modality_and_unrecoverable_track_loss_are_safe_and_not_perfect():
    template = _template()
    temporary = compare_sequence(template, _sequence(miss=(5,)))
    assert temporary.validation.valid
    assert temporary.component_scores["Prop path"] < 3
    lost = compare_sequence(template, _sequence(miss=(3, 4, 5, 6)))
    assert FailureCode.TRACK_LOSS in lost.validation.codes
    assert lost.total == 0


def test_generic_release_and_catch_require_stable_contact_and_ignore_one_miss():
    frames = []
    for i, x in enumerate((.0, .0, .0, .4, .6, .4, .0, .0, .0)):
        prop = None if i == 1 else Landmark(x, 0)
        frames.append(FrameSample(i * 100, hands={"left": Landmark(0, 0)}, prop=prop))
    kinds = [event.kind for event in detect_prop_events(frames)]
    assert "release" in kinds and "airborne" in kinds and "catch" in kinds
    # A single missing detector sample in an otherwise stable hold does not
    # manufacture a release/airborne transition.
    held = [FrameSample(i * 100, hands={"left": Landmark(0, 0)}, prop=None if i == 2 else Landmark(0, 0)) for i in range(6)]
    held_kinds = [event.kind for event in detect_prop_events(held)]
    assert "release" not in held_kinds and "airborne" not in held_kinds


def test_release_catch_capability_compares_event_lifecycle_and_timing():
    references = [_release_sequence(), _release_sequence(interval=110), _release_sequence(interval=90)]
    template = build_template(references, ("pose", "hands", "prop_translation"))
    assert template.feature_capabilities["release_catch"] is True

    matched = compare_sequence(template, _release_sequence())
    missed_catch = compare_sequence(template, _release_sequence(catch=False))
    assert matched.component_scores["Timing"] >= 2
    assert missed_catch.component_scores["Timing"] < matched.component_scores["Timing"]


def test_release_catch_capability_is_not_claimed_without_both_events():
    assert _template().feature_capabilities["release_catch"] is False


def test_fast_pass_near_hand_is_not_a_stable_catch():
    frames = [FrameSample(i * 10, hands={"left": Landmark(0, 0)}, prop=Landmark(.2 - i * .08, 0)) for i in range(6)]
    kinds = [event.kind for event in detect_prop_events(frames)]
    assert "catch" not in kinds and "stable_contact" not in kinds
