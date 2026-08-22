"""Versioned AssessmentSpec models and capability checks.

Phase 7A supplies strict parsing only. No frame evaluation, WebSocket
dispatch, or Teacher-reviewed fallback lives here.
"""

from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    AssessmentCapabilityStatus,
    capability_for,
)

__all__ = [
    "AssessmentSpec",
    "AssessmentCapabilityStatus",
    "capability_for",
]
