"""Startup validation for unit-interval assessment ratios."""

from __future__ import annotations

import pytest

from config import _load_unit_ratio


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
