import pytest
from pydantic import ValidationError

from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    AssessmentCapabilityStatus,
    capability_for,
)


def _golden(**overrides):
    payload = {
        "schema_version": 1,
        "template_id": "balance_stall.wrist_v1",
        "prop": "bottle",
        "target": "wrist",
        "laterality": "left",
    }
    payload.update(overrides)
    return payload


def test_assessment_spec_parses_left_and_right():
    left = AssessmentSpec.model_validate(_golden(laterality="left"))
    right = AssessmentSpec.model_validate(_golden(laterality="right"))
    assert left.laterality == "left"
    assert right.laterality == "right"
    assert capability_for(left) == AssessmentCapabilityStatus.SUPPORTED
    assert capability_for(right) == AssessmentCapabilityStatus.SUPPORTED


def test_assessment_spec_parses_historical_either():
    spec = AssessmentSpec.model_validate(_golden(laterality="either"))
    assert spec.laterality == "either"
    assert capability_for(spec) == AssessmentCapabilityStatus.SUPPORTED


def test_assessment_spec_rejects_unknown_template():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(
            _golden(template_id="balance_stall.elbow_v1")
        )


def test_assessment_spec_rejects_shaker_prop():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(prop="shaker"))


def test_assessment_spec_rejects_thresholds_and_eval():
    for extra in (
        {"threshold": 0.12},
        {"thresholds": {"hold": 2.5}},
        {"eval": "1+1"},
        {"formula": "x"},
        {"hold_seconds": 3},
        {"code": "print(1)"},
    ):
        with pytest.raises(ValidationError):
            AssessmentSpec.model_validate(_golden(**extra))


def test_assessment_spec_rejects_schema_version_2():
    with pytest.raises(ValidationError):
        AssessmentSpec.model_validate(_golden(schema_version=2))
