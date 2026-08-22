"""Versioned AssessmentSpec models, capability checks, and isolated evaluators.

Phase 7A supplies strict parsing. Phase 7B adds a pure Wrist Stall evaluator
that is not wired to WebSocket dispatch or the official rule engine.
"""

from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    AssessmentCapabilityStatus,
    capability_for,
)
from assessment.specs.wrist_v1 import evaluate as evaluate_wrist_v1

__all__ = [
    "AssessmentSpec",
    "AssessmentCapabilityStatus",
    "capability_for",
    "evaluate_wrist_v1",
]
