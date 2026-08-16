"""Unit tests for backend-authoritative hold confirmation."""

from __future__ import annotations

from assessment.hold_validator import HoldValidator
from config import HOLD_UNKNOWN_GRACE_SECONDS


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


def _invalid(
    validator: HoldValidator,
    timestamp: float,
    *,
    feedback_type: str = "warning",
    posture_status: str = "stable",
):
    return validator.update(
        feedback_type=feedback_type,
        posture_status=posture_status,
        session_active=True,
        timestamp=timestamp,
    )


def test_isolated_invalid_frame_does_not_zero_multi_second_progress():
    """A single warning/error surrounded by valid frames must not wipe hold time."""
    validator = HoldValidator(
        confirmation_seconds=2.5,
        max_frame_gap_seconds=0.5,
        min_positive_ratio=0.85,
    )
    validator.activate()

    snapshot = None
    for i in range(21):
        snapshot = _valid(validator, i * 0.1)
    assert snapshot is not None
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms >= 1900

    dropped = _invalid(validator, 2.1)
    assert dropped.hold_confirmed is False
    assert dropped.hold_progress > 0.5
    assert dropped.hold_duration_ms >= 1900
    assert 0.0 < dropped.positive_frame_ratio < 1.0

    # Resume valid frames; accumulated progress must continue, not restart.
    resumed = _valid(validator, 2.2)
    assert resumed.hold_duration_ms >= dropped.hold_duration_ms
    assert resumed.hold_progress > 0.5


def test_sustained_warning_stretch_resets_hold():
    validator = HoldValidator(
        confirmation_seconds=2.5,
        max_frame_gap_seconds=0.5,
        min_positive_ratio=0.85,
    )
    validator.activate()

    for i in range(20):
        _valid(validator, i * 0.1)

    # Dropout budget is (1 - 0.85) * 2.5s = 0.375s. Five 0.1s warnings exceed it.
    snapshot = None
    for i in range(5):
        snapshot = _invalid(validator, 2.0 + i * 0.1)
    assert snapshot is not None
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_progress == 0.0
    assert snapshot.hold_duration_ms == 0

    restarted = _valid(validator, 2.5)
    assert restarted.hold_confirmed is False
    assert restarted.hold_duration_ms == 0


def test_sustained_error_stretch_resets_hold():
    validator = HoldValidator(
        confirmation_seconds=2.5,
        max_frame_gap_seconds=0.5,
        min_positive_ratio=0.85,
    )
    validator.activate()

    for i in range(15):
        _valid(validator, i * 0.1)

    snapshot = None
    for i in range(5):
        snapshot = _invalid(
            validator,
            1.5 + i * 0.1,
            feedback_type="error",
            posture_status="unstable",
        )
    assert snapshot is not None
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


def test_positive_frame_ratio_tracks_rolling_window():
    validator = HoldValidator(confirmation_seconds=2.5, max_frame_gap_seconds=0.5)
    validator.activate()

    _valid(validator, 0.0)
    snapshot = _valid(validator, 0.1)
    assert snapshot.positive_frame_ratio == 1.0

    _invalid(validator, 0.2)
    mixed = _valid(validator, 0.3)
    assert 0.0 < mixed.positive_frame_ratio < 1.0


def test_positive_ratio_below_threshold_delays_confirmation():
    """HOLD_MIN_POSITIVE_RATIO must actually gate confirmation over the window."""
    validator = HoldValidator(
        confirmation_seconds=1.0,
        max_frame_gap_seconds=0.5,
        min_positive_ratio=0.85,
    )
    validator.activate()

    t = 0.0
    snapshot = None
    # 3 valid + 1 invalid (~75% positive) for well past the 1.0s target.
    for i in range(24):
        if i % 4 == 3:
            snapshot = _invalid(validator, t)
        else:
            snapshot = _valid(validator, t)
        t += 0.1

    assert snapshot is not None
    assert snapshot.hold_confirmed is False
    assert snapshot.positive_frame_ratio < 0.85


def _unknown(validator: HoldValidator, timestamp: float):
    return validator.update(
        feedback_type="warning",
        posture_status="unknown",
        session_active=True,
        timestamp=timestamp,
    )


def _hold_with_progress() -> tuple[HoldValidator, object]:
    validator = HoldValidator(
        confirmation_seconds=2.5,
        max_frame_gap_seconds=0.5,
        min_positive_ratio=0.85,
        unknown_grace_seconds=HOLD_UNKNOWN_GRACE_SECONDS,
    )
    validator.activate()
    snapshot = None
    for i in range(20):
        snapshot = _valid(validator, i * 0.1)
    assert snapshot is not None
    assert snapshot.hold_confirmed is False
    assert snapshot.hold_duration_ms >= 1800
    return validator, snapshot


def test_brief_unknown_pauses_and_preserves_hold_progress():
    validator, before = _hold_with_progress()
    step = 0.1
    unknown_until = 2.0 + (HOLD_UNKNOWN_GRACE_SECONDS * 0.5)
    t = 2.0
    paused = before
    while t <= unknown_until:
        paused = _unknown(validator, t)
        t += step

    assert paused.hold_confirmed is False
    assert paused.hold_duration_ms == before.hold_duration_ms
    assert paused.hold_progress == before.hold_progress
    assert paused.positive_frame_ratio == before.positive_frame_ratio

    resumed = _valid(validator, t)
    assert resumed.hold_duration_ms == paused.hold_duration_ms
    continued = _valid(validator, t + step)
    assert continued.hold_duration_ms > paused.hold_duration_ms
    assert continued.hold_confirmed is False


def test_prolonged_unknown_resets_hold_segment_without_invalid_sample():
    validator, before = _hold_with_progress()
    step = 0.1
    t = 2.0
    snapshot = before
    while t <= 2.0 + HOLD_UNKNOWN_GRACE_SECONDS + step:
        snapshot = _unknown(validator, t)
        t += step

    assert snapshot.hold_confirmed is False
    assert snapshot.hold_progress == 0.0
    assert snapshot.hold_duration_ms == 0
    assert snapshot.positive_frame_ratio == 0.0

    restarted = _valid(validator, t)
    assert restarted.hold_duration_ms == 0
    assert restarted.hold_confirmed is False


def test_wrong_dropout_budget_is_independent_of_unknown_grace():
    validator, _ = _hold_with_progress()
    snapshot = None
    for i in range(5):
        snapshot = _invalid(validator, 2.0 + i * 0.1)
    assert snapshot is not None
    assert snapshot.hold_progress == 0.0
    assert snapshot.hold_duration_ms == 0


def test_unknown_frames_do_not_lower_positive_frame_ratio():
    validator, before = _hold_with_progress()
    paused = _unknown(validator, 2.1)
    assert paused.positive_frame_ratio == before.positive_frame_ratio
    assert paused.positive_frame_ratio >= 0.85
