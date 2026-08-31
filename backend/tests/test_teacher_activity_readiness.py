from __future__ import annotations

import pytest
from pydantic import ValidationError

from assessment.readiness import (
    readiness_needs_hands,
    readiness_needs_pose,
    readiness_profile_from_activity_spec,
)
from schemas.commands import PrepareCommand, StartSubmissionRecordCommand


def _codes(spec: dict[str, str]) -> list[str]:
    return [item.code for item in readiness_profile_from_activity_spec(spec).requirements]


@pytest.mark.parametrize(
    ("prop", "expected"),
    [
        ("none", ["camera_frame"]),
        ("one_bottle", ["camera_frame", "bottle_detected"]),
        ("one_shaker", ["camera_frame", "shaker_detected"]),
        ("bottle_and_shaker", ["camera_frame", "bottle_detected", "shaker_detected"]),
        ("two_bottles", ["camera_frame", "prop_count_two"]),
    ],
)
def test_activity_prop_requirements_are_visibility_only(prop: str, expected: list[str]) -> None:
    assert _codes({"prop": prop, "hands": "none", "body": "none"}) == expected


def test_activity_hand_and_body_requirements_activate_only_needed_detectors() -> None:
    camera_only = {"prop": "none", "hands": "none", "body": "none"}
    assert readiness_needs_hands("Free Practice", readiness_spec=camera_only) is False
    assert readiness_needs_pose("Free Practice", readiness_spec=camera_only) is False

    combined = {"prop": "none", "hands": "two_hands", "body": "upper_body"}
    assert _codes(combined) == ["camera_frame", "two_hands_visible", "upper_body_visible"]
    assert readiness_needs_hands("Free Practice", readiness_spec=combined) is True
    assert readiness_needs_pose("Free Practice", readiness_spec=combined) is True


def test_prepare_contract_rejects_unknown_activity_readiness_values() -> None:
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(
            {
                "protocol_version": 1,
                "request_id": "request",
                "session_id": "session",
                "action": "prepare",
                "movement": "Free Practice",
                "difficulty": "Easy",
                "readiness_spec": {"prop": "glass", "hands": "none", "body": "none"},
            }
        )


@pytest.mark.parametrize("duration", [15, 30, 45, 60])
def test_submission_duration_presets(duration: int) -> None:
    parsed = StartSubmissionRecordCommand.model_validate(
        {
            "protocol_version": 1,
            "request_id": "request",
            "session_id": "session",
            "action": "start_submission_record",
            "duration_seconds": duration,
        }
    )
    assert parsed.duration_seconds == duration


@pytest.mark.parametrize("duration", [0, 20, 61])
def test_submission_duration_rejects_non_presets(duration: int) -> None:
    with pytest.raises(ValidationError):
        StartSubmissionRecordCommand.model_validate(
            {
                "protocol_version": 1,
                "request_id": "request",
                "session_id": "session",
                "action": "start_submission_record",
                "duration_seconds": duration,
            }
        )
