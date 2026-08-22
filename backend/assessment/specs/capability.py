"""Pure capability lookup for a validated AssessmentSpec.

This module does not evaluate frames, persist documents, or talk to
Firebase. It only answers whether the current backend can automatically
score a spec that has already passed schema validation.
"""

from __future__ import annotations

from enum import Enum

from assessment.specs.assessment_spec import AssessmentSpec

_SUPPORTED_TEMPLATE_ID = "balance_stall.wrist_v1"
_SUPPORTED_PROP = "bottle"
_SUPPORTED_TARGET = "wrist"
_SUPPORTED_LATERALITY = frozenset({"either", "left", "right"})


class AssessmentCapabilityStatus(str, Enum):
    SUPPORTED = "supported"
    UNSUPPORTED = "unsupported"


def capability_for(spec: AssessmentSpec) -> AssessmentCapabilityStatus:
    if (
        spec.schema_version == 1
        and spec.template_id == _SUPPORTED_TEMPLATE_ID
        and spec.prop == _SUPPORTED_PROP
        and spec.target == _SUPPORTED_TARGET
        and spec.laterality in _SUPPORTED_LATERALITY
    ):
        return AssessmentCapabilityStatus.SUPPORTED
    return AssessmentCapabilityStatus.UNSUPPORTED


def _require_supported(spec: AssessmentSpec) -> None:
    if capability_for(spec) != AssessmentCapabilityStatus.SUPPORTED:
        raise ValueError("unsupported_assessment_spec")


def template_requires_pose(spec: AssessmentSpec) -> bool:
    _require_supported(spec)
    return True


def template_requires_hands(spec: AssessmentSpec) -> bool:
    _require_supported(spec)
    return False


def template_max_hands(spec: AssessmentSpec) -> int:
    _require_supported(spec)
    return 0


def template_prop_type(spec: AssessmentSpec) -> str:
    _require_supported(spec)
    return spec.prop


def template_display_label(spec: AssessmentSpec) -> str:
    """Presentation label only. Never an official catalog / dispatch name."""
    _require_supported(spec)
    return "Wrist Stall"
