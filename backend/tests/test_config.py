"""Startup validation for unit-interval assessment ratios."""

from __future__ import annotations

import pytest

from config import HOLD_UNKNOWN_GRACE_SECONDS, _load_non_negative_seconds, _load_unit_ratio


@pytest.mark.parametrize(
    "name",
    [
        "RUBRIC_FULL_RATIO",
        "RUBRIC_PARTIAL_RATIO",
        "HOLD_MIN_POSITIVE_RATIO",
        "RUBRIC_COMPLETION_PARTIAL_PROGRESS",
    ],
)
@pytest.mark.parametrize("raw", ["-0.01", "1.01", "2", "100"])
def test_unit_ratio_rejects_values_outside_zero_one(monkeypatch, name: str, raw: str):
    monkeypatch.setenv(name, raw)
    with pytest.raises(ValueError, match=name):
        _load_unit_ratio(name, "0.5")


@pytest.mark.parametrize("raw", ["0", "0.0", "0.65", "1", "1.0"])
def test_unit_ratio_accepts_closed_unit_interval(monkeypatch, raw: str):
    monkeypatch.setenv("RUBRIC_FULL_RATIO", raw)
    value = _load_unit_ratio("RUBRIC_FULL_RATIO", "0.90")
    assert 0.0 <= value <= 1.0
    assert value == float(raw)


def test_unit_ratio_rejects_non_numeric(monkeypatch):
    monkeypatch.setenv("HOLD_MIN_POSITIVE_RATIO", "abc")
    with pytest.raises(ValueError, match="HOLD_MIN_POSITIVE_RATIO"):
        _load_unit_ratio("HOLD_MIN_POSITIVE_RATIO", "0.85")


def _load_hold_unknown_grace() -> float:
    return _load_non_negative_seconds(
        "HOLD_UNKNOWN_GRACE_SECONDS",
        str(HOLD_UNKNOWN_GRACE_SECONDS),
    )


def test_hold_unknown_grace_default_is_single_runtime_value():
    # 0.75–1.0s is documentation/tuning only; runtime default is one value.
    assert HOLD_UNKNOWN_GRACE_SECONDS == 0.75


def test_hold_unknown_grace_reads_env_override(monkeypatch):
    monkeypatch.setenv("HOLD_UNKNOWN_GRACE_SECONDS", "0.9")
    assert _load_hold_unknown_grace() == 0.9


def test_hold_unknown_grace_is_not_clamped_to_tuning_range(monkeypatch):
    monkeypatch.setenv("HOLD_UNKNOWN_GRACE_SECONDS", "1.25")
    assert _load_hold_unknown_grace() == 1.25


@pytest.mark.parametrize("raw", ["-0.1", "abc"])
def test_hold_unknown_grace_rejects_invalid(monkeypatch, raw: str):
    monkeypatch.setenv("HOLD_UNKNOWN_GRACE_SECONDS", raw)
    with pytest.raises(ValueError, match="HOLD_UNKNOWN_GRACE_SECONDS"):
        _load_hold_unknown_grace()
