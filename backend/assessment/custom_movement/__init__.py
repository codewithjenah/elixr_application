"""Pure, versioned building blocks for teacher-authored movement templates.

This package deliberately has no camera, FastAPI, or movement-registry dependency.
The session/API layer can feed it detector observations without granting custom
content access to executable code.
"""

from .template_engine import (
    FailureCode,
    FrameSample,
    Landmark,
    MovementTemplate,
    PropEvent,
    SequenceComparison,
    ValidationResult,
    build_template,
    compare_sequence,
    detect_prop_events,
    normalize_sequence,
    validate_sequence,
)

__all__ = [
    "FailureCode", "FrameSample", "Landmark", "MovementTemplate", "PropEvent",
    "SequenceComparison", "ValidationResult", "build_template", "compare_sequence",
    "detect_prop_events", "normalize_sequence", "validate_sequence",
]
