"""Strict AssessmentSpec v1 parsing and fail-closed extra-field rejection."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    AssessmentCapabilityStatus,
    capability_for,
)


def _golden(*, laterality: str = "either", **extra):
    payload = {
        "schema_version": 1,
        "template_id": "balance_stall.wrist_v1",
        "prop": "bottle",
        "target": "wrist",
        "laterality": laterality,
    }
    payload.update(extra)
    return payload


def test_golden_wrist_spec():
    spec = AssessmentSpec.model_validate(_golden())
    assert spec.schema_version == 1
    assert spec.template_id == "balance_stall.wrist_v1"
    assert spec.prop == "bottle"
    assert spec.target == "wrist"
    assert spec.laterality == "either"


@pytest.mark.parametrize("laterality", ["either", "left", "right"])
def test_supported_laterality(laterality: str):
    spec = AssessmentSpec.model_validate(_golden(laterality=laterality))
    assert spec.laterality == laterality
    assert capability_for(spec) is AssessmentCapabilityStatus.SUPPORTED


@pytest.mark.parametrize(
    "extra",
    [
        {"threshold": 0.2},
        {"thresholds": {"proximity": 0.1}},
        {"hold_seconds": 2},
        {"eval": "1+1"},
        {"formula": "x * 2"},
        {"code": "print(1)"},
        {"python": "os.system('id')"},
        {"javascript": "1+1"},
        {"arbitrary_unknown_key": True},
    ],
)
def test_unknown_and_dangerous_extra_keys_rejected(extra: dict):
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(**extra))


def test_shaker_rejected():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(prop="shaker"))


def test_wrong_target_rejected():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(target="forearm"))


def test_unknown_template_rejected():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(template_id="balance_stall.elbow_v1"))


def test_invalid_laterality_rejected():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(laterality="both"))


@pytest.mark.parametrize("schema_version", [0, 2, "1"])
def test_wrong_schema_rejected(schema_version):
    payload = _golden()
    payload["schema_version"] = schema_version
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(payload)


@pytest.mark.parametrize(
    "missing",
    ["schema_version", "template_id", "prop", "target", "laterality"],
)
def test_missing_required_fields_rejected(missing: str):
    payload = _golden()
    del payload[missing]
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(payload)


def test_canonical_wrist_spec_is_supported():
    spec = AssessmentSpec.model_validate(_golden())
    assert capability_for(spec) is AssessmentCapabilityStatus.SUPPORTED


def test_no_other_automatic_scoring_capability_is_supported():
    assert set(AssessmentCapabilityStatus) == {
        AssessmentCapabilityStatus.SUPPORTED,
        AssessmentCapabilityStatus.UNSUPPORTED,
    }
    foreign = AssessmentSpec.model_construct(
        schema_version=1,
        template_id="not_a_supported_template",
        prop="bottle",
        target="wrist",
        laterality="either",
    )
    assert capability_for(foreign) is AssessmentCapabilityStatus.UNSUPPORTED
