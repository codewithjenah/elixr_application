"""Movement-by-movement Hands requirement table vs current production wiring."""

from __future__ import annotations

from assessment.hands_profile import (
    HANDS_BARTENDER_ROI_MOVEMENTS,
    HANDS_ROTATED_FALLBACK_MOVEMENTS,
    SEMANTIC_MAX_HANDS,
    all_hands_profiles,
    hands_profile_for,
)
from assessment.readiness import readiness_needs_hands, readiness_needs_pose
from assessment.rule_engine import movement_requires_hands, movement_requires_pose
from config import MOVEMENT_CONFIG


def test_profile_covers_every_configured_movement():
    profiles = {row.movement: row for row in all_hands_profiles()}
    assert set(profiles) == set(MOVEMENT_CONFIG)
    assert set(SEMANTIC_MAX_HANDS) == set(MOVEMENT_CONFIG)


def test_semantic_max_hands_only_allows_0_1_2():
    for movement, count in SEMANTIC_MAX_HANDS.items():
        assert count in (0, 1, 2), movement


def test_max_hands_comes_from_movement_config():
    from assessment.rule_engine import movement_max_hands

    for movement, cfg in MOVEMENT_CONFIG.items():
        assert "max_hands" in cfg, movement
        assert cfg["max_hands"] in (0, 1, 2), movement
        assert movement_max_hands(movement) == cfg["max_hands"], movement
        assert hands_profile_for(movement).semantic_max_hands == cfg["max_hands"], movement
        assert SEMANTIC_MAX_HANDS[movement] == cfg["max_hands"], movement
        requires_hands = movement_requires_hands(movement)
        if requires_hands:
            assert cfg["max_hands"] in (1, 2), movement
        else:
            assert cfg["max_hands"] == 0, movement


def test_unknown_movement_max_hands_defaults_to_one():
    from assessment.rule_engine import movement_max_hands

    assert movement_max_hands("Not A Catalog Movement") == 1


def test_catalog_movements_match_readiness_and_active_schedule():
    expected_catalog = {
        "Normal Grip": (True, True, 1, True, False, False),
        "Bartender's Grip": (True, True, 1, False, True, False),
        "Reverse Grip": (True, True, 1, False, False, False),
        "Claw Grip": (True, True, 1, True, False, False),
        "Hand Stall": (True, True, 1, False, False, False),
        "One Finger Stall": (True, True, 1, False, False, False),
        "Forearm Stall": (False, False, 0, False, False, True),
        "Elbow Stall": (False, False, 0, False, False, True),
        "Reverse Forearm Stall": (False, False, 0, False, False, True),
        "Shoulder Stall": (False, False, 0, False, False, True),
        "Double Hand Stall": (True, True, 2, False, False, False),
        "Bottle in a tin": (True, True, 1, False, False, False),
    }
    for movement, expected in expected_catalog.items():
        row = hands_profile_for(movement)
        (
            ready_h,
            scheduled_h,
            max_hands,
            rotated,
            bartender,
            pose,
        ) = expected
        assert row.readiness_needs_hands is ready_h, movement
        assert row.active_scheduled_hands is scheduled_h, movement
        assert row.semantic_max_hands == max_hands, movement
        assert row.rotated_fallback is rotated, movement
        assert row.bartender_roi_fallback is bartender, movement
        assert row.active_needs_pose is pose, movement
        assert row.readiness_needs_hands is readiness_needs_hands(movement)
        assert row.readiness_needs_pose is readiness_needs_pose(movement)
        assert row.active_scheduled_hands is movement_requires_hands(movement)
        assert row.active_needs_pose is movement_requires_pose(movement)


def test_pose_stalls_do_not_schedule_hands():
    for movement in (
        "Forearm Stall",
        "Elbow Stall",
        "Reverse Forearm Stall",
        "Shoulder Stall",
        "Arm Stall",
        "Upper Forearm Stall",
    ):
        row = hands_profile_for(movement)
        assert row.rule_uses_hands is False, movement
        assert row.readiness_needs_hands is False, movement
        assert row.active_scheduled_hands is False, movement
        assert row.semantic_max_hands == 0, movement
        assert row.readiness_needs_pose is True, movement
        assert row.active_needs_pose is True, movement
        assert movement_requires_hands(movement) is False, movement
        assert movement_requires_pose(movement) is True, movement


def test_legacy_pose_stall_aliases_match_canonical():
    forearm = hands_profile_for("Forearm Stall")
    reverse = hands_profile_for("Reverse Forearm Stall")
    arm_alias = hands_profile_for("Arm Stall")
    upper_alias = hands_profile_for("Upper Forearm Stall")
    assert arm_alias.readiness_needs_hands is forearm.readiness_needs_hands
    assert arm_alias.active_scheduled_hands is forearm.active_scheduled_hands
    assert arm_alias.active_needs_pose is forearm.active_needs_pose
    assert upper_alias.readiness_needs_hands is reverse.readiness_needs_hands
    assert upper_alias.active_scheduled_hands is reverse.active_scheduled_hands
    assert upper_alias.active_needs_pose is reverse.active_needs_pose


def test_hand_based_movements_still_schedule_hands():
    for movement in (
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Claw Grip",
        "Hand Stall",
        "One Finger Stall",
        "Double Hand Stall",
        "Bottle in a tin",
    ):
        row = hands_profile_for(movement)
        assert row.readiness_needs_hands is True, movement
        assert row.active_scheduled_hands is True, movement
        assert row.rule_uses_hands is True, movement
        assert movement_requires_hands(movement) is True, movement
    assert hands_profile_for("Double Hand Stall").semantic_max_hands == 2


def test_fallback_sets_are_exactly_the_grip_exceptions():
    assert HANDS_ROTATED_FALLBACK_MOVEMENTS == frozenset(
        {"Normal Grip", "Claw Grip"}
    )
    assert HANDS_BARTENDER_ROI_MOVEMENTS == frozenset({"Bartender's Grip"})


def test_session_flags_match_profile(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import _patch_vision

    _patch_vision(monkeypatch)
    for row in all_hands_profiles():
        session = websocket_api.VisionSession(row.movement)
        try:
            assert session._hands_rotated_fallback is row.rotated_fallback, row.movement
            assert session._hands_bartender_roi is row.bartender_roi_fallback, row.movement
            assert session._hands_needed is row.active_scheduled_hands, row.movement
            assert session._pose_needed is row.active_needs_pose, row.movement
            assert session._hands_max == row.semantic_max_hands, row.movement
        finally:
            session.close()


def test_session_constructs_hands_detector_with_movement_max(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import StubHandsDetector, _patch_vision

    _patch_vision(monkeypatch)
    captured: dict[str, dict] = {}

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            captured["kwargs"] = kwargs
            super().__init__(**kwargs)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)

    expected = {
        "Normal Grip": (1, True, False),
        "Bartender's Grip": (1, False, True),
        "Reverse Grip": (1, False, False),
        "Claw Grip": (1, True, False),
        "Hand Stall": (1, False, False),
        "One Finger Stall": (1, False, False),
        "Bottle in a tin": (1, False, False),
        "Double Hand Stall": (2, False, False),
    }
    for movement, (max_hands, rotated, bartender) in expected.items():
        captured.clear()
        session = websocket_api.VisionSession(movement)
        try:
            session.start()
            assert session.begin_readiness() is True
            assert session.hands_detector is not None, movement
            assert session.hands_detector.max_num_hands == max_hands, movement
            assert captured["kwargs"]["max_num_hands"] == max_hands, movement
            assert captured["kwargs"]["rotated_fallback"] is rotated, movement
            assert captured["kwargs"]["bartender_roi_fallback"] is bartender, movement
        finally:
            session.close()


def test_pose_only_and_free_practice_do_not_construct_hands_detector(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import _patch_vision

    _patch_vision(monkeypatch)
    hands_inits = {"n": 0}

    class TrackingHands:
        def __init__(self, **kwargs):
            hands_inits["n"] += 1

        def close(self):
            pass

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)

    for movement in (
        "Forearm Stall",
        "Elbow Stall",
        "Reverse Forearm Stall",
        "Shoulder Stall",
        "Arm Stall",
        "Upper Forearm Stall",
        "Free Practice",
    ):
        hands_inits["n"] = 0
        session = websocket_api.VisionSession(movement)
        try:
            session.start()
            session.begin_readiness()
            session._ensure_detectors()
            assert session.hands_detector is None, movement
            assert hands_inits["n"] == 0, movement
        finally:
            session.close()
