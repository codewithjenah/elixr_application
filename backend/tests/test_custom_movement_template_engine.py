from dataclasses import replace

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


def test_template_requires_two_references_and_is_serializable_deterministically():
    try:
        build_template([_sequence()], ("pose",))
        assert False
    except ValueError as error:
        assert error.args[0] == FailureCode.INVALID_REFERENCE_COUNT.value
    assert build_template([_sequence(), _sequence()], ("pose",)).reference_count == 2
    for count in (3, 4, 5):
        assert build_template([_sequence() for _ in range(count)], ("pose",)).reference_count == count
    lone_observation = tuple(replace(frame, pose={**frame.pose, "99": Landmark(.5, .5)}) for frame in _sequence())
    agreement = build_template([lone_observation, _sequence()], ("pose", "prop_translation"))
    assert all("99" not in frame.pose for frame in agreement.canonical_sequence)
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


def _sided_sequence(*, sides=("left",), include_pose=True, moving_pose=False):
    frames = []
    for index in range(12):
        pose_x = 0.35 + (0.02 * index if moving_pose else 0.0)
        pose = (
            {
                "11": Landmark(0.3, 0.3),
                "12": Landmark(0.7, 0.3),
                "15": Landmark(pose_x, 0.5),
            }
            if include_pose
            else {}
        )
        hands = {
            side: Landmark(0.25 if side == "left" else 0.75, 0.45)
            for side in sides
        }
        frames.append(
            FrameSample(
                index * 100,
                pose=pose,
                hands=hands,
                prop=Landmark(0.2 + 0.03 * index, 0.4),
            )
        )
    return tuple(frames)


def test_one_hand_template_does_not_require_unused_hand_or_static_pose():
    references = [_sided_sequence() for _ in range(3)]

    template = build_template(references)

    assert template.required_modalities == ("hands", "prop_translation")
    assert template.feature_capabilities["left_hand"] is True
    assert template.feature_capabilities["right_hand"] is False
    assert template.feature_capabilities["pose"] is False
    comparison = compare_sequence(template, _sided_sequence(include_pose=False))
    assert comparison.validation.valid
    assert comparison.component_scores["Hand technique"] == 3
    assert comparison.component_scores["Prop path"] == 3


def test_non_required_hand_is_filtered_from_canonical_and_scoring():
    def with_transient_right(reference_index, *, candidate=False):
        frames = []
        for index, frame in enumerate(_sided_sequence(include_pose=False)):
            hands = dict(frame.hands)
            if candidate or (reference_index < 2 and index < 6):
                hands["right"] = Landmark(
                    (0.9 - index * 0.1) if candidate else 0.75,
                    0.2,
                )
            frames.append(
                FrameSample(
                    frame.timestamp_ms,
                    pose=frame.pose,
                    hands=hands,
                    prop=frame.prop,
                )
            )
        return tuple(frames)

    template = build_template([with_transient_right(index) for index in range(3)])

    assert template.required_hand_sides == ("left",)
    assert all(
        _hand_key.split(":", 1)[0] != "right"
        for frame in template.canonical_sequence
        for _hand_key in frame.hands
    )
    comparison = compare_sequence(template, with_transient_right(0, candidate=True))
    assert comparison.component_scores["Hand technique"] == 3


def test_pose_optional_hand_normalization_handles_camera_offset_and_scale():
    def camera_view(*, shift, scale):
        return tuple(
            FrameSample(
                index * 100,
                hands={
                    "left:0:0": Landmark(shift + 0.2 * scale, 0.4 * scale),
                    "left:0:9": Landmark(shift + 0.2 * scale, 0.5 * scale),
                },
                prop=Landmark(
                    shift + (0.25 + index * 0.02) * scale,
                    0.35 * scale,
                ),
            )
            for index in range(12)
        )

    template = build_template(
        [
            camera_view(shift=0.0, scale=1.0),
            camera_view(shift=0.1, scale=0.8),
            camera_view(shift=-0.1, scale=1.2),
        ]
    )
    comparison = compare_sequence(
        template,
        camera_view(shift=0.2, scale=0.7),
    )
    baseline = compare_sequence(template, camera_view(shift=0.0, scale=1.0))

    assert template.feature_capabilities["pose"] is False
    assert template.normalization_metadata["scale"] == "hand_size"
    assert comparison.component_scores["Prop path"] == baseline.component_scores[
        "Prop path"
    ]
    assert comparison.component_scores["Prop path"] >= 2


def test_two_hand_template_requires_both_observed_sides():
    references = [_sided_sequence(sides=("left", "right")) for _ in range(3)]
    template = build_template(references)

    assert template.required_hand_sides == ("left", "right")
    missing_right = compare_sequence(template, _sided_sequence(sides=("left",)))

    assert not missing_right.validation.valid
    assert FailureCode.MISSING_MODALITY in missing_right.validation.codes


def test_meaningful_pose_is_inferred_but_pose_optional_sequence_remains_valid():
    pose_template = build_template(
        [_sided_sequence(moving_pose=True) for _ in range(3)]
    )
    pose_optional = build_template([_sided_sequence() for _ in range(3)])

    assert pose_template.feature_capabilities["pose"] is True
    assert pose_optional.feature_capabilities["pose"] is False
    assert compare_sequence(
        pose_optional, _sided_sequence(include_pose=False)
    ).validation.valid


def _phase_shifted_sequence(peak_index: int):
    values = [0.0] * 12
    for offset, value in ((-2, 0.2), (-1, 0.6), (0, 1.0), (1, 0.6), (2, 0.2)):
        index = peak_index + offset
        if 0 <= index < len(values):
            values[index] = value
    return tuple(
        FrameSample(
            index * 100,
            hands={"left": Landmark(0.0, 0.0)},
            prop=Landmark(value, 0.4),
        )
        for index, value in enumerate(values)
    )


def test_dtw_aligned_references_preserve_phase_peak_and_are_deterministic():
    references = [
        _phase_shifted_sequence(4),
        _phase_shifted_sequence(6),
        _phase_shifted_sequence(8),
    ]

    first = build_template(references)
    second = build_template(references)
    peak = max(frame.prop.x for frame in first.canonical_sequence if frame.prop)

    assert peak > 0.9
    assert first.to_dict() == second.to_dict()


def test_legacy_version_one_template_without_hand_sides_remains_readable():
    current = _template().to_dict()
    current["feature_capabilities"].pop("left_hand")
    current["feature_capabilities"].pop("right_hand")

    loaded = MovementTemplate.from_dict(current)

    assert loaded.required_hand_sides == ("left", "right")


def test_production_hand_index_reordering_does_not_lose_laterality():
    def reference(left_index, right_index):
        return tuple(
            FrameSample(
                frame * 100,
                hands={
                    f"left:{left_index}:0": Landmark(0.2 + frame * 0.01, 0.4),
                    f"right:{right_index}:0": Landmark(0.8 - frame * 0.01, 0.4),
                },
                prop=Landmark(0.2 + frame * 0.03, 0.35),
            )
            for frame in range(10)
        )

    template = build_template(
        [reference(0, 1), reference(1, 0), reference(0, 1)]
    )
    candidate = reference(1, 0)

    assert template.required_hand_sides == ("left", "right")
    assert compare_sequence(template, candidate).validation.valid
    assert compare_sequence(template, candidate).component_scores["Hand technique"] == 3
