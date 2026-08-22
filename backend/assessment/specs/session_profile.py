"""Typed official-vs-template session context for VisionSession.

Official sessions keep MOVEMENT_CONFIG detector/readiness ownership.
Template sessions use a validated AssessmentSpec and never register a
catalog movement.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from assessment.readiness import ReadinessProfile, template_readiness_profile
from assessment.rule_engine import (
    movement_is_prop_detection_only,
    movement_max_hands,
    movement_requires_hands,
    movement_requires_pose,
)
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    AssessmentCapabilityStatus,
    capability_for,
    template_display_label,
    template_max_hands,
    template_requires_hands,
    template_requires_pose,
)

SessionPurpose = Literal["official", "template_scored", "live_test"]
TEMPLATE_PURPOSES = frozenset({"template_scored", "live_test"})


@dataclass(frozen=True)
class SessionProfile:
    purpose: SessionPurpose
    movement: str
    display_movement: str
    prop_type: str
    assessment_spec: AssessmentSpec | None
    requires_pose: bool
    requires_hands: bool
    max_hands: int
    is_prop_detection_only: bool
    readiness_profile: ReadinessProfile | None

    @property
    def is_template(self) -> bool:
        return self.purpose in TEMPLATE_PURPOSES and self.assessment_spec is not None


def build_session_profile(
    *,
    purpose: str,
    movement: str,
    prop_type: str,
    assessment_spec: AssessmentSpec | dict | None,
) -> SessionProfile:
    if purpose not in {"official", "template_scored", "live_test"}:
        raise ValueError("invalid_session_purpose")

    if purpose == "official":
        if assessment_spec is not None:
            raise ValueError("unexpected_assessment_spec")
        return SessionProfile(
            purpose="official",
            movement=movement,
            display_movement=movement,
            prop_type=prop_type,
            assessment_spec=None,
            requires_pose=movement_requires_pose(movement),
            requires_hands=movement_requires_hands(movement),
            max_hands=movement_max_hands(movement),
            is_prop_detection_only=movement_is_prop_detection_only(movement),
            readiness_profile=None,
        )

    if assessment_spec is None:
        raise ValueError("missing_assessment_spec")

    spec = AssessmentSpec.model_validate(
        assessment_spec.model_dump()
        if isinstance(assessment_spec, AssessmentSpec)
        else assessment_spec
    )
    if capability_for(spec) != AssessmentCapabilityStatus.SUPPORTED:
        raise ValueError("unsupported_assessment_spec")
    if spec.prop != prop_type:
        raise ValueError("assessment_spec_prop_mismatch")

    return SessionProfile(
        purpose=purpose,
        movement=movement,
        display_movement=template_display_label(spec),
        prop_type=prop_type,
        assessment_spec=spec,
        requires_pose=template_requires_pose(spec),
        requires_hands=template_requires_hands(spec),
        max_hands=template_max_hands(spec),
        is_prop_detection_only=False,
        readiness_profile=template_readiness_profile(spec),
    )
