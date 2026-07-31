"""Unit tests for backend-authoritative hold confirmation."""

from __future__ import annotations

from assessment.hold_validator import HoldValidator


def _valid(validator: HoldValidator, timestamp: float):
    return validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=timestamp,
    )


def test_no_confirmation_before_required_duration():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    t = 0.0
    while t < 2.4:
        snapshot = validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=t,
        )
        assert snapshot.hold_confirmed is False
        assert snapshot.hold_progress < 1.0
        t += 0.1

    assert validator.is_confirmed is False


def test_confirmation_at_or_after_configured_duration():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    t = 0.0
    snapshot = None
    while t <= 2.6:
        snapshot = validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=t,
        )
        t += 0.1

    assert snapshot is not None
    assert snapshot.hold_confirmed is True
    assert snapshot.hold_progress == 1.0
    assert snapshot.hold_duration_ms >= 2500


def test_warning_feedback_resets_hold():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    for i in range(20):
        _valid(validator, i * 0.1)

    mid = validator.update(
        feedback_type="warning",
        posture_status="stable",
        session_active=True,
        timestamp=2.0,
    )
    assert mid.hold_confirmed is False
    assert mid.hold_progress == 0.0
    assert mid.hold_duration_ms == 0

    snapshot = _valid(validator, 2.1)
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms == 0


def test_error_feedback_resets_hold():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    for i in range(15):
        _valid(validator, i * 0.1)

    snapshot = validator.update(
        feedback_type="error",
        posture_status="unstable",
        session_active=True,
        timestamp=1.5,
    )
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_progress == 0.0


def test_unstable_posture_does_not_accumulate():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    snapshot = validator.update(
        feedback_type="positive",
        posture_status="unstable",
        session_active=True,
        timestamp=0.0,
    )
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms == 0
    assert snapshot.positive_frame_ratio == 0.0


def test_excessive_frame_gap_prevents_false_confirmation():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.35)
    validator.activate()

    _valid(validator, 0.0)
    for i in range(1, 24):
        _valid(validator, i * 0.1)

    almost = _valid(validator, 2.3)
    assert almost.hold_confirmed is False
    assert almost.hold_duration_ms < 2500

    after_gap = _valid(validator, 3.0)
    assert after_gap.hold_confirmed is False
    assert after_gap.hold_duration_ms == 0


def test_confirmation_happens_only_once():
    validator = HoldValidator(confirmation_seconds=1.0, max_frame_gap_seconds=0.5)
    validator.activate()

    confirmed = None
    for i in range(20):
        snapshot = validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=i * 0.1,
        )
        if snapshot.hold_confirmed and confirmed is None:
            confirmed = snapshot

    assert confirmed is not None
    assert confirmed.hold_confirmed is True

    later = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=3.0,
    )
    assert later.hold_confirmed is True
    assert validator.is_confirmed is True


def test_stop_restart_creates_fresh_validator():
    validator = HoldValidator(confirmation_seconds=1.0, max_frame_gap_seconds=0.5)
    validator.activate()
    for i in range(12):
        validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=i * 0.1,
        )
    assert validator.is_confirmed is True

    validator.reset()
    assert validator.is_confirmed is False

    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=10.0,
    )
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms == 0


def test_reactivate_resets_hold_state():
    validator = HoldValidator(confirmation_seconds=1.0, max_frame_gap_seconds=0.5)
    validator.activate()
    for i in range(12):
        validator.update(
            feedback_type="positive",
            posture_status="stable",
            session_active=True,
            timestamp=i * 0.1,
        )
    assert validator.is_confirmed is True

    validator.activate()
    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=20.0,
    )
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms == 0


def test_preview_processing_does_not_update_hold():
    validator = HoldValidator(confirmation_seconds=1.0, max_frame_gap_seconds=0.5)

    snapshot = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=False,
        timestamp=0.0,
    )
    assert snapshot.hold_progress == 0.0
    assert snapshot.hold_confirmed is False

    validator.activate()
    active = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=1.0,
    )
    assert active.hold_duration_ms == 0
    assert active.hold_confirmed is False


def test_positive_frame_ratio_tracks_current_segment():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    _valid(validator, 0.0)
    snapshot = _valid(validator, 0.1)
    assert snapshot.positive_frame_ratio == 1.0

    validator.update(
        feedback_type="warning",
        posture_status="stable",
        session_active=True,
        timestamp=0.2,
    )
    reset = _valid(validator, 0.3)
    assert reset.positive_frame_ratio == 1.0
