from assessment.feedback_codes import FeedbackCode
from assessment.hold_validator import HoldValidator
from assessment.rule_engine import evaluate_movement, movement_requires_hands, movement_requires_pose
from assessment.rules.common_checks import track_bottle_stability
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _body_bottle() -> BottleDetection:
    return BottleDetection(x1=300, y1=140, x2=340, y2=340, confidence=0.9)


def _hand_from_points(points: dict[int, Point2D], handedness: str = "Right") -> HandLandmarks:
    return HandLandmarks(points=points, handedness=handedness)


def _body_wrap_points() -> dict[int, Point2D]:
    """Side wrap around the bottle body (middle third), not the neck."""
    return {
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
    }


def _outside_bbox_body_wrap_points() -> dict[int, Point2D]:
    """A real side wrap: curled fingertips are beyond the visible bottle edge."""
    points = _body_wrap_points()
    for _, pip, dip, tip in (
        (5, 6, 7, 8),
        (9, 10, 11, 12),
        (13, 14, 15, 16),
        (17, 18, 19, 20),
    ):
        points[pip] = Point2D(0.54, 0.60)
        points[dip] = Point2D(0.62, 0.60)
        points[tip] = Point2D(0.595, 0.55)
    return points


def _mirrored_body_wrap_points() -> dict[int, Point2D]:
    return {
        index: Point2D(1.0 - point.x, point.y)
        for index, point in _outside_bbox_body_wrap_points().items()
    }


def _laterally_rising_body_wrap_points() -> dict[int, Point2D]:
    """Side-view fingers can rise in image space while still wrapping the body."""
    points = _outside_bbox_body_wrap_points()
    for mcp, tip in ((5, 8), (9, 12), (13, 16), (17, 20)):
        point = points[tip]
        points[tip] = Point2D(point.x, points[mcp].y - 0.03)
    return points


def _body_points_without_cross_body_wrap() -> dict[int, Point2D]:
    points = _body_wrap_points()
    for index in (8, 12, 16, 20):
        point = points[index]
        points[index] = Point2D(0.49, point.y)
    return points


def _open_hover_body_points() -> dict[int, Point2D]:
    """Palm near the body, fingers extended sideways so they do not wrap."""
    return {
        0: Point2D(0.46, 0.56),
        4: Point2D(0.62, 0.54),
        5: Point2D(0.48, 0.54),
        6: Point2D(0.52, 0.54),
        7: Point2D(0.56, 0.54),
        8: Point2D(0.62, 0.54),
        9: Point2D(0.47, 0.54),
        12: Point2D(0.63, 0.55),
        16: Point2D(0.64, 0.56),
        20: Point2D(0.65, 0.57),
    }


def _in_aabb_sideways_hover_points() -> dict[int, Point2D]:
    """Open sideways hand overlapping the body AABB without curling around."""
    return {
        0: Point2D(0.42, 0.54),
        4: Point2D(0.50, 0.54),
        5: Point2D(0.45, 0.53),
        6: Point2D(0.48, 0.53),
        7: Point2D(0.52, 0.53),
        8: Point2D(0.55, 0.53),
        9: Point2D(0.45, 0.54),
        10: Point2D(0.48, 0.54),
        11: Point2D(0.52, 0.54),
        12: Point2D(0.55, 0.54),
        13: Point2D(0.45, 0.55),
        14: Point2D(0.49, 0.55),
        15: Point2D(0.53, 0.55),
        16: Point2D(0.56, 0.55),
        17: Point2D(0.45, 0.56),
        18: Point2D(0.49, 0.56),
        19: Point2D(0.53, 0.56),
        20: Point2D(0.57, 0.56),
    }


def _neck_wrap_points() -> dict[int, Point2D]:
    return {
        0: Point2D(0.42, 0.51),
        1: Point2D(0.44, 0.47),
        2: Point2D(0.46, 0.43),
        3: Point2D(0.47, 0.41),
        4: Point2D(0.47, 0.39),
        5: Point2D(0.44, 0.45),
        6: Point2D(0.49, 0.41),
        7: Point2D(0.53, 0.43),
        8: Point2D(0.53, 0.47),
        9: Point2D(0.45, 0.46),
        10: Point2D(0.50, 0.43),
        11: Point2D(0.54, 0.45),
        12: Point2D(0.53, 0.48),
        13: Point2D(0.46, 0.47),
        14: Point2D(0.51, 0.45),
        15: Point2D(0.54, 0.47),
        16: Point2D(0.53, 0.49),
        17: Point2D(0.46, 0.48),
        18: Point2D(0.50, 0.46),
        19: Point2D(0.53, 0.48),
        20: Point2D(0.52, 0.49),
    }


def _bartender_points() -> dict[int, Point2D]:
    return {
        0: Point2D(0.30, 0.49),
        1: Point2D(0.36, 0.485),
        2: Point2D(0.40, 0.482),
        3: Point2D(0.445, 0.485),
        4: Point2D(0.47, 0.488),
        5: Point2D(0.46, 0.478),
        6: Point2D(0.495, 0.472),
        7: Point2D(0.515, 0.485),
        8: Point2D(0.505, 0.502),
        9: Point2D(0.485, 0.485),
        10: Point2D(0.50, 0.505),
        11: Point2D(0.51, 0.525),
        12: Point2D(0.515, 0.540),
        13: Point2D(0.48, 0.505),
        14: Point2D(0.50, 0.525),
        15: Point2D(0.515, 0.545),
        16: Point2D(0.525, 0.555),
        17: Point2D(0.475, 0.520),
        18: Point2D(0.495, 0.540),
        19: Point2D(0.51, 0.555),
        20: Point2D(0.52, 0.560),
    }


def _reverse_neck_points() -> dict[int, Point2D]:
    return {
        0: Point2D(0.43, 0.38),
        4: Point2D(0.52, 0.50),
        8: Point2D(0.50, 0.46),
        9: Point2D(0.46, 0.46),
        12: Point2D(0.51, 0.45),
        16: Point2D(0.52, 0.44),
        20: Point2D(0.53, 0.40),
    }


def _claw_points() -> dict[int, Point2D]:
    return {
        0: Point2D(0.52, 0.24),
        4: Point2D(0.55, 0.42),
        5: Point2D(0.50, 0.35),
        6: Point2D(0.47, 0.38),
        7: Point2D(0.45, 0.42),
        8: Point2D(0.43, 0.48),
        9: Point2D(0.51, 0.28),
        10: Point2D(0.48, 0.37),
        11: Point2D(0.46, 0.41),
        12: Point2D(0.44, 0.48),
        13: Point2D(0.52, 0.36),
        14: Point2D(0.49, 0.39),
        15: Point2D(0.47, 0.43),
        16: Point2D(0.45, 0.49),
        17: Point2D(0.53, 0.37),
        18: Point2D(0.50, 0.40),
        19: Point2D(0.48, 0.44),
        20: Point2D(0.46, 0.48),
    }


def _base_wrap_points() -> dict[int, Point2D]:
    points = _body_wrap_points()
    return {
        index: Point2D(point.x, point.y + 0.16)
        for index, point in points.items()
    }


def _default_bottle() -> BottleDetection:
    return BottleDetection(x1=300, y1=200, x2=340, y2=280, confidence=0.9)


def _evaluate(hand: HandLandmarks, bottle: BottleDetection | None = None):
    result, _, _ = evaluate_movement(
        "Body Grip",
        _body_bottle() if bottle is None else bottle,
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result


def test_body_grip_valid_wrap_succeeds():
    result = _evaluate(_hand_from_points(_body_wrap_points()))
    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value


def test_body_grip_accepts_center_wrap_with_fingertips_outside_raw_bbox():
    points = _outside_bbox_body_wrap_points()
    assert all(points[index].x > 340 / 640 for index in (8, 12, 16, 20))
    result = _evaluate(_hand_from_points(points))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value


def test_body_grip_accepts_mirrored_center_wrap():
    result = _evaluate(_hand_from_points(_mirrored_body_wrap_points(), handedness="Left"))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value


def test_body_grip_accepts_laterally_rising_side_wrap():
    result = _evaluate(_hand_from_points(_laterally_rising_body_wrap_points()))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value


def test_body_grip_accepts_thumb_near_upper_body_boundary():
    points = _outside_bbox_body_wrap_points()
    points[4] = Point2D(0.46, 0.325)
    result = _evaluate(_hand_from_points(points))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value


def test_body_grip_rejects_centered_palm_without_cross_body_wrap():
    result = _evaluate(_hand_from_points(_body_points_without_cross_body_wrap()))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value


def test_body_grip_rejects_neck_wrap():
    result = _evaluate(_hand_from_points(_neck_wrap_points()), _default_bottle())
    assert result.feedback_type == "warning"
    assert result.feedback_code in {
        FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
        FeedbackCode.HAND_NOT_AT_BODY.value,
    }


def test_body_grip_rejects_bartender_pinch():
    result = _evaluate(_hand_from_points(_bartender_points()), _default_bottle())
    assert result.feedback_type == "warning"
    assert result.feedback_code in {
        FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
        FeedbackCode.HAND_NOT_AT_BODY.value,
    }


def test_body_grip_rejects_reverse_neck_grip():
    result = _evaluate(_hand_from_points(_reverse_neck_points()), _default_bottle())
    assert result.feedback_type == "warning"
    assert result.feedback_code in {
        FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
        FeedbackCode.HAND_NOT_AT_BODY.value,
    }


def test_body_grip_rejects_claw_from_above():
    result = _evaluate(_hand_from_points(_claw_points()), _default_bottle())
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value


def test_body_grip_rejects_base_grip():
    result = _evaluate(_hand_from_points(_base_wrap_points()))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.HAND_NOT_AT_BODY.value


def test_body_grip_rejects_proximity_without_wrap():
    result = _evaluate(_hand_from_points(_open_hover_body_points()))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value


def test_body_grip_rejects_sideways_hover_inside_body_aabb():
    result = _evaluate(_hand_from_points(_in_aabb_sideways_hover_points()))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value


def test_body_grip_missing_bottle_fails():
    result, _, _ = evaluate_movement(
        "Body Grip",
        None,
        None,
        HandsResult(hands=[_hand_from_points(_body_wrap_points())]),
        None,
    )
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.PROP_NOT_DETECTED.value


def test_body_grip_missing_hand_fails():
    result, _, _ = evaluate_movement("Body Grip", _body_bottle(), None, None, None)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.HAND_NOT_VISIBLE.value


def test_body_grip_missing_required_hand_geometry_is_uncertain():
    result = _evaluate(
        _hand_from_points(
            {
                4: Point2D(0.50, 0.53),
                9: Point2D(0.45, 0.54),
                8: Point2D(0.52, 0.55),
                12: Point2D(0.52, 0.55),
                16: Point2D(0.52, 0.56),
            }
        )
    )
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.HAND_NOT_FULLY_VISIBLE.value


def test_body_grip_unstable_does_not_confirm():
    validator = HoldValidator(confirmation_seconds=1.0)
    validator.activate()
    hand = _hand_from_points(_open_hover_body_points())
    snapshot = None
    for i in range(20):
        result, _, _ = evaluate_movement(
            "Body Grip",
            _body_bottle(),
            None,
            HandsResult(hands=[hand]),
            None,
        )
        snapshot = validator.update(
            feedback_type=result.feedback_type,
            posture_status=result.posture_status,
            session_active=True,
            timestamp=i * 0.1,
        )
    assert snapshot is not None
    assert snapshot.hold_confirmed is False
    assert result.feedback_type != "positive"


def test_body_grip_detector_profile():
    assert movement_requires_hands("Body Grip") is True
    assert movement_requires_pose("Body Grip") is False


def test_body_grip_does_not_use_stall_history(monkeypatch):
    _ = track_bottle_stability
    result = _evaluate(_hand_from_points(_body_wrap_points()))
    assert result.feedback_code == FeedbackCode.BODY_GRIP_LOCKED.value
