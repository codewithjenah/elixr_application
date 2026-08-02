"""Compatibility wrapper for the bottle-specific prop detector."""

from config import YOLO_CONFIDENCE
from vision.prop_detector import ModelLoadError, PropDetector


class BottleDetector(PropDetector):
    """Backward-compatible alias for ``PropDetector(prop_type="bottle")``."""

    def __init__(
        self,
        model_name: str | None = None,
        confidence: float = YOLO_CONFIDENCE,
        enabled: bool = True,
    ):
        # ``model_name`` was accepted by the old detector. Preserve it for
        # scripts that still pass a custom path; the default always uses the
        # explicit bottle model under backend/models.
        model_path = model_name
        super().__init__(
            prop_type="bottle",
            confidence=confidence,
            enabled=enabled,
            model_path=model_path,
        )


__all__ = ["BottleDetector", "ModelLoadError"]