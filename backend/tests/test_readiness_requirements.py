"""Deterministic tests for observability-only pre-practice readiness."""

from __future__ import annotations

import pytest

from assessment.readiness import (
    ReadinessObservation,
    ReadinessTracker,
    enabled_catalog_movements,
    requirements_for,
)
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)


def _bottle(x: int = 200, conf: float = 0.9) -> BottleDetection:
    return BottleDetection(x1=x, y1=100, x2=x + 80, y2=300, confidence=conf)


def _hand(
    *,
    cx: float = 0.5,
    cy: float = 0.5,
    indices: tuple[int, ...] | None = None,
    closed_tips: bool = False,
) -> HandLandmarks:
    """Build a hand with selected landmarks. closed_tips keeps tips near MCP."""
    if indices is None:
        indices = (0, 4, 5, 6, 7, 8, 9, 12, 16, 20)
    points: dict[int, Point2D] = {}
    # Palm core
    if 0 in indices:
        points[0] = Point2D(cx, cy + 0.04)
    if 9 in indices:
        points[9] = Point2D(cx, cy)
    # Index chain
    if 5 in indices:
        points[5] = Point2D(cx - 0.02, cy - 0.02)
    if 6 in indices:
        points[6] = Point2D(cx - 0.03, cy - 0.04)
    if 7 in indices:
        points[7] = Point2D(cx - 0.04, cy - 0.06)
    if 8 in indices:
        tip_y = cy - 0.01 if closed_tips else cy - 0.10
        points[8] = Point2D(cx - 0.05, tip_y)
    if 4 in indices:
        points[4] = Point2D(cx + 0.03, cy)
    # Other fingertips (curl/close them when closed_tips)
    for idx, dx in ((12, 0.0), (16, 0.02), (20, 0.04)):
        if idx in indices:
            tip_y = cy - 0.01 if closed_tips else cy - 0.10
            points[idx] = Point2D(cx + dx, tip_y)
    return HandLandmarks(points=points, handedness="Right")


def _hands(*hands: HandLandmarks) -> HandsResult:
    return HandsResult(hands=list(hands))


def _pose_upper_body() -> PoseLandmarks:
    return PoseLandmarks(
        points={
            11: Point2D(0.35, 0.3),
            12: Point2D(0.65, 0.3),
            13: Point2D(0.4, 0.4),
            15: Point2D(0.45, 0.55),
            14: Point2D(0.6, 0.4),
            16: Point2D(0.65, 0.55),
        },
        visibility={11: 1.0, 12: 1.0, 13: 1.0, 15: 1.0, 14: 1.0, 16: 1.0},
    )


def _pose_arm() -> PoseLandmarks:
    return PoseLandmarks(
        points={
            13: Point2D(0.4, 0.4),
            15: Point2D(0.45, 0.55),
            14: Point2D(0.6, 0.4),
            16: Point2D(0.65, 0.55),
        },
        visibility={13: 1.0, 15: 1.0, 14: 1.0, 16: 1.0},
    )


def _pose_shoulder() -> PoseLandmarks:
    return PoseLandmarks(
        points={11: Point2D(0.4, 0.3), 12: Point2D(0.6, 0.3)},
        visibility={11: 1.0, 12: 1.0},
    )


def _advance_ready(
    tracker: ReadinessTracker,
    obs: ReadinessObservation,
    *,
    clock: list[float],
) -> None:
    """Drive all items to ready then past stable duration using fake clock."""
    snap = None
    for _ in range(tracker.pass_frames):
        snap = tracker.update(obs)
    assert snap is not None
    assert snap.readiness_complete
    # Advance time past stable duration
    clock[0] += tracker.stable_duration_s + 0.01
    snap = tracker.update(obs)
    assert snap.readiness_stable
    assert snap.readiness_stable_progress == pytest.approx(1.0)


def _full_obs_for(
    movement: str,
    prop_type: str = "bottle",
    *,
    closed_palm: bool = False,
) -> ReadinessObservation:
    grip = _hand(closed_tips=closed_palm)
    palm = _hand(indices=(0, 9), closed_tips=closed_palm)
    index = _hand(indices=(0, 5, 6, 7, 8), closed_tips=closed_palm)
    left = _hand(cx=0.3, cy=0.5, indices=(0, 9), closed_tips=closed_palm)
    right = _hand(cx=0.7, cy=0.5, indices=(0, 9), closed_tips=closed_palm)

    bottles = [_bottle()]
    shakers: list[BottleDetection] = []
    hands = _hands(grip)
    pose = None

    if movement == "Hand Stall":
        hands = _hands(palm)
        if prop_type == "shaker":
            bottles = []
            shakers = [_bottle(300)]
    elif movement == "One Finger Stall":
        hands = _hands(index)
        if prop_type == "shaker":
            bottles = []
            shakers = [_bottle(300)]
    elif movement in ("Forearm Stall", "Elbow Stall", "Arm Stall"):
        pose = _pose_upper_body()
        hands = None
        if prop_type == "shaker":
            bottles = []
            shakers = [_bottle(300)]
    elif movement in ("Reverse Forearm Stall", "Upper Forearm Stall"):
        pose = _pose_upper_body()
        hands = None
    elif movement == "Shoulder Stall":
        pose = _pose_upper_body()
        hands = None
    elif movement == "Double Hand Stall":
        bottles = [_bottle(150), _bottle(350)]
        hands = _hands(left, right)
    elif movement == "Bottle in a tin":
        shakers = [_bottle(400)]
        hands = _hands(palm)

    return ReadinessObservation(
        has_camera_frame=True,
        bottles=bottles,
        shakers=shakers,
        hands=hands,
        pose=pose,
    )


class TestRequirementRegistry:
    def test_all_twelve_movements_have_camera_and_codes(self):
        for movement in enabled_catalog_movements():
            specs = requirements_for(movement, "bottle")
            codes = [r.code for r in specs]
            assert codes[0] == "camera_frame"
            assert len(codes) >= 2

    def test_grip_movements_use_observability_codes(self):
        for movement in (
            "Normal Grip",
            "Bartender's Grip",
            "Reverse Grip",
            "Claw Grip",
        ):
            codes = [r.code for r in requirements_for(movement)]
            assert codes == [
                "camera_frame",
                "prop_detected",
                "grip_landmarks_visible",
            ]

    def test_hand_stall_uses_palm_not_open_palm(self):
        codes = [r.code for r in requirements_for("Hand Stall", "bottle")]
        assert "palm_landmarks_visible" in codes
        assert "open_palm" not in codes

    def test_double_hand_uses_two_hands_not_open_palm(self):
        codes = [r.code for r in requirements_for("Double Hand Stall")]
        assert codes == [
            "camera_frame",
            "prop_count_two",
            "two_hands_visible",
        ]

    def test_bottle_in_a_tin_supporting_hand_visibility_only(self):
        codes = [r.code for r in requirements_for("Bottle in a tin")]
        assert codes == [
            "camera_frame",
            "bottle_detected",
            "shaker_detected",
            "supporting_hand_visible",
        ]

    def test_reverse_forearm_and_shoulder_do_not_require_hands(self):
        for movement in ("Reverse Forearm Stall", "Shoulder Stall"):
            codes = [r.code for r in requirements_for(movement)]
            assert "grip_landmarks_visible" not in codes
            assert "palm_landmarks_visible" not in codes
            assert "two_hands_visible" not in codes

    def test_forearm_profile_omits_redundant_pose_upper_forearm(self):
        for movement in ("Forearm Stall", "Elbow Stall", "Reverse Forearm Stall"):
            codes = [r.code for r in requirements_for(movement)]
            assert "upper_body_visible" in codes
            assert "pose_upper_forearm" not in codes

    def test_legacy_aliases_resolve_to_canonical_profiles(self):
        assert [r.code for r in requirements_for("Arm Stall")] == [
            r.code for r in requirements_for("Forearm Stall")
        ]
        assert [r.code for r in requirements_for("Upper Forearm Stall")] == [
            r.code for r in requirements_for("Reverse Forearm Stall")
        ]
        assert "Arm Stall" not in enabled_catalog_movements()
        assert "Upper Forearm Stall" not in enabled_catalog_movements()


def test_enabled_movements_have_declared_non_camera_only_profiles():
    from assessment.readiness import assert_readiness_profiles_complete

    assert_readiness_profiles_complete()


def test_detector_requirements_derived_from_profiles():
    from assessment.readiness import readiness_needs_hands, readiness_needs_pose

    assert readiness_needs_hands("Normal Grip") is True
    assert readiness_needs_pose("Normal Grip") is False
    assert readiness_needs_hands("Forearm Stall") is False
    assert readiness_needs_pose("Forearm Stall") is True
    assert readiness_needs_hands("Bottle in a tin") is True
    assert readiness_needs_pose("Bottle in a tin") is False


@pytest.mark.parametrize("movement", list(enabled_catalog_movements()))
def test_matrix_reaches_stable_with_full_inputs(movement: str):
    clock = [100.0]
    tracker = ReadinessTracker(
        movement,
        "bottle",
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.5,
        monotonic=lambda: clock[0],
    )
    obs = _full_obs_for(movement, "bottle")
    _advance_ready(tracker, obs, clock=clock)


@pytest.mark.parametrize(
    "movement,prop_type",
    [
        ("Hand Stall", "shaker"),
        ("One Finger Stall", "shaker"),
        ("Forearm Stall", "shaker"),
        ("Elbow Stall", "shaker"),
    ],
)
def test_prop_aware_stalls_accept_shaker(movement: str, prop_type: str):
    clock = [0.0]
    tracker = ReadinessTracker(
        movement,
        prop_type,
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.2,
        monotonic=lambda: clock[0],
    )
    obs = _full_obs_for(movement, prop_type)
    _advance_ready(tracker, obs, clock=clock)


class TestObservabilityBoundary:
    def test_closed_palm_can_be_ready_for_hand_stall(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Hand Stall",
            "bottle",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=0.2,
            monotonic=lambda: clock[0],
        )
        obs = _full_obs_for("Hand Stall", closed_palm=True)
        _advance_ready(tracker, obs, clock=clock)

    def test_closed_palms_can_be_ready_for_double_hand_stall(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Double Hand Stall",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=0.2,
            monotonic=lambda: clock[0],
        )
        obs = _full_obs_for("Double Hand Stall", closed_palm=True)
        _advance_ready(tracker, obs, clock=clock)

    def test_wrong_grip_orientation_still_ready_when_landmarks_present(self):
        """Landmark completeness only — orientation is technique, not readiness."""
        clock = [0.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=0.2,
            monotonic=lambda: clock[0],
        )
        # Upside-down-looking wrist/mcp still has required indices present.
        hand = _hand(cx=0.5, cy=0.7, closed_tips=True)
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=_hands(hand),
        )
        _advance_ready(tracker, obs, clock=clock)

    def test_bottle_in_a_tin_does_not_require_hand_shaker_proximity(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Bottle in a tin",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=0.2,
            monotonic=lambda: clock[0],
        )
        # Hand far from shaker geometrically — readiness must still pass.
        far_hand = _hand(cx=0.05, cy=0.05, indices=(0, 9))
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle(100)],
            shakers=[_bottle(500)],
            hands=_hands(far_hand),
        )
        _advance_ready(tracker, obs, clock=clock)


class TestStabilizationAlgorithm:
    def test_item_needs_consecutive_pass_frames(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=3,
            fail_frames=3,
            stable_duration_s=1.0,
            monotonic=lambda: clock[0],
        )
        good = _full_obs_for("Normal Grip")
        bad = ReadinessObservation(has_camera_frame=True)

        snap = tracker.update(good)
        assert all(i.status == "waiting" for i in snap.items)
        snap = tracker.update(good)
        assert all(i.status == "waiting" for i in snap.items)
        snap = tracker.update(good)
        assert snap.readiness_complete
        assert not snap.readiness_stable

        # Interrupting pass streak before ready keeps waiting
        tracker.reset()
        tracker.update(good)
        tracker.update(bad)
        snap = tracker.update(good)
        prop = next(i for i in snap.items if i.code == "prop_detected")
        assert prop.status == "waiting"

    def test_ready_item_demotes_only_after_fail_frames(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=2,
            fail_frames=3,
            stable_duration_s=10.0,
            monotonic=lambda: clock[0],
        )
        good = _full_obs_for("Normal Grip")
        missing_prop = ReadinessObservation(
            has_camera_frame=True,
            hands=_hands(_hand()),
        )
        tracker.update(good)
        tracker.update(good)
        assert tracker.update(good).readiness_complete

        tracker.update(missing_prop)
        tracker.update(missing_prop)
        snap = tracker.update(missing_prop)
        # After 3 fails, prop demotes and complete resets
        prop = next(i for i in snap.items if i.code == "prop_detected")
        assert prop.status == "waiting"
        assert not snap.readiness_complete
        assert snap.readiness_stable_progress == 0.0

    def test_global_timer_starts_only_when_all_ready_and_resets_on_demotion(
        self,
    ):
        clock = [10.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=1.0,
            monotonic=lambda: clock[0],
        )
        good = _full_obs_for("Normal Grip")
        tracker.update(good)
        snap = tracker.update(good)
        assert snap.readiness_complete
        assert snap.readiness_stable_progress == pytest.approx(0.0)

        clock[0] = 10.5
        snap = tracker.update(good)
        assert snap.readiness_stable_progress == pytest.approx(0.5)
        assert not snap.readiness_stable

        clock[0] = 11.0
        snap = tracker.update(good)
        assert snap.readiness_stable
        assert snap.readiness_stable_progress == pytest.approx(1.0)

        # Demotion resets progress
        missing = ReadinessObservation(
            has_camera_frame=True,
            hands=_hands(_hand()),
        )
        tracker.update(missing)
        snap = tracker.update(missing)
        assert snap.readiness_stable_progress == 0.0
        assert not snap.readiness_stable

    def test_progress_clamped_to_one(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=1,
            fail_frames=1,
            stable_duration_s=0.5,
            monotonic=lambda: clock[0],
        )
        good = _full_obs_for("Normal Grip")
        tracker.update(good)
        clock[0] = 5.0
        snap = tracker.update(good)
        assert snap.readiness_stable_progress == pytest.approx(1.0)

    def test_reset_clears_counters(self):
        clock = [0.0]
        tracker = ReadinessTracker(
            "Normal Grip",
            pass_frames=1,
            fail_frames=1,
            stable_duration_s=0.1,
            monotonic=lambda: clock[0],
        )
        good = _full_obs_for("Normal Grip")
        assert tracker.update(good).readiness_complete
        clock[0] = 1.0
        assert tracker.update(good).readiness_stable
        tracker.reset()
        clock[0] = 2.0
        snap = tracker.update(
            ReadinessObservation(has_camera_frame=True)
        )
        assert not snap.readiness_complete
        assert snap.readiness_stable_progress == 0.0


class TestMissingInputs:
    def test_missing_hand_landmarks_stay_waiting(self):
        tracker = ReadinessTracker(
            "Normal Grip", pass_frames=2, fail_frames=2, stable_duration_s=1.0
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=_hands(_hand(indices=(0,))),  # incomplete
        )
        tracker.update(obs)
        snap = tracker.update(obs)
        grip = next(i for i in snap.items if i.code == "grip_landmarks_visible")
        assert grip.status == "waiting"

    def test_missing_pose_keeps_upper_body_waiting(self):
        tracker = ReadinessTracker(
            "Shoulder Stall", pass_frames=2, fail_frames=2, stable_duration_s=1.0
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=None,
        )
        tracker.update(obs)
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_item_error_sets_error_status(self):
        tracker = ReadinessTracker(
            "Normal Grip", pass_frames=1, fail_frames=1, stable_duration_s=1.0
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=_hands(_hand()),
            item_errors={
                "prop_detected": "Bottle model unavailable.",
            },
        )
        snap = tracker.update(obs)
        prop = next(i for i in snap.items if i.code == "prop_detected")
        assert prop.status == "error"
        assert "unavailable" in prop.message.lower()
        assert not snap.readiness_complete

    def test_double_hand_needs_two_bottles(self):
        tracker = ReadinessTracker(
            "Double Hand Stall",
            pass_frames=2,
            fail_frames=2,
            stable_duration_s=1.0,
        )
        left = _hand(cx=0.3, indices=(0, 9))
        right = _hand(cx=0.7, indices=(0, 9))
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=_hands(left, right),
        )
        tracker.update(obs)
        snap = tracker.update(obs)
        count = next(i for i in snap.items if i.code == "prop_count_two")
        assert count.status == "waiting"
