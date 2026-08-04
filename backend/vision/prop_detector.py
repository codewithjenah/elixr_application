from __future__ import annotations

import logging
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Literal, Optional

import numpy as np
from ultralytics import YOLO

from config import MAX_BOTTLES, YOLO_CONFIDENCE, YOLO_IMGSZ, YOLO_IOU, YOLO_MODEL_PATH
from vision.types import PropDetection

logger = logging.getLogger(__name__)

PropType = Literal["bottle", "shaker"]

# Normalized aliases derived from the trained combined model's declared names:
#   0: flair_bottle
#   1: shaker_bottle
_CLASS_ALIASES: dict[PropType, set[str]] = {
    "bottle": {"flairbottle"},
    "shaker": {"shakerbottle"},
}


class ModelLoadError(RuntimeError):
    """Raised when the combined prop model cannot be loaded or configured."""


@dataclass(frozen=True)
class CombinedDetectionResult:
    bottles: list[PropDetection]
    shakers: list[PropDetection]


def _resolve_model_device(model: YOLO) -> str:
    """Best-effort device label for observability (does not force GPU/FP16)."""
    device = getattr(model, "device", None)
    if device is not None:
        return str(device)
    overrides = getattr(model, "overrides", None)
    if isinstance(overrides, Mapping) and overrides.get("device") is not None:
        return str(overrides["device"])
    return "cpu"


def _normalize_class_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def _class_mapping(names: object) -> dict[int, str]:
    if isinstance(names, Mapping):
        entries = names.items()
    elif isinstance(names, (list, tuple)):
        entries = enumerate(names)
    else:
        raise ModelLoadError("YOLO model class names are not a mapping or list")

    mapping: dict[int, str] = {}
    for raw_id, raw_name in entries:
        try:
            class_id = int(raw_id)
        except (TypeError, ValueError) as exc:
            raise ModelLoadError("YOLO model contains an invalid class id") from exc
        if not isinstance(raw_name, str) or not raw_name.strip():
            raise ModelLoadError("YOLO model contains an invalid class name")
        mapping[class_id] = raw_name

    if not mapping:
        raise ModelLoadError("YOLO model does not declare any classes")
    return mapping


def _resolve_single_prop_class_id(
    mapping: dict[int, str],
    prop_type: PropType,
) -> int:
    aliases = _CLASS_ALIASES[prop_type]
    matches = [
        class_id
        for class_id, class_name in mapping.items()
        if _normalize_class_name(class_name) in aliases
    ]

    if len(matches) != 1:
        expected = ", ".join(sorted(aliases))
        declared = ", ".join(
            f"{class_id}={class_name!r}" for class_id, class_name in mapping.items()
        )
        raise ModelLoadError(
            f"Could not resolve the {prop_type} class from YOLO names "
            f"({declared}); expected one of: {expected}"
        )

    return matches[0]


def resolve_prop_class_id(names: object, prop_type: PropType) -> tuple[int, dict[int, str]]:
    """Resolve one prop class from model names without assuming class id zero."""
    if prop_type not in _CLASS_ALIASES:
        raise ModelLoadError(f"Unsupported prop type: {prop_type}")

    mapping = _class_mapping(names)
    return _resolve_single_prop_class_id(mapping, prop_type), mapping


def resolve_bottle_and_shaker_class_ids(
    names: object,
) -> tuple[int, int, dict[int, str]]:
    """Resolve bottle and shaker class IDs from the combined model names."""
    mapping = _class_mapping(names)
    bottle_id = _resolve_single_prop_class_id(mapping, "bottle")
    shaker_id = _resolve_single_prop_class_id(mapping, "shaker")

    if bottle_id == shaker_id:
        raise ModelLoadError(
            "Bottle and shaker classes resolved to the same class id"
        )

    return bottle_id, shaker_id, mapping


class CombinedPropDetector:
    """Lazy combined YOLO detector for flair bottles and shaker bottles."""

    def __init__(
        self,
        confidence: float = YOLO_CONFIDENCE,
        enabled: bool = True,
        *,
        model_path: Path | str | None = None,
        model_loader: Callable[[str], YOLO] | None = None,
    ):
        self._confidence = confidence
        self._model: Optional[YOLO] = None
        self._model_path = (
            Path(model_path).resolve()
            if model_path is not None
            else YOLO_MODEL_PATH
        )
        self._model_loader = model_loader or YOLO
        self._load_failed = False
        self._enabled = enabled
        self._bottle_class_id: int | None = None
        self._shaker_class_id: int | None = None
        self._class_names: dict[int, str] = {}

        logger.info(
            "Configured combined prop detector: model_path=%s",
            self._model_path,
        )

    @property
    def model_path(self) -> Path:
        return self._model_path

    @property
    def enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = enabled

    @property
    def load_failed(self) -> bool:
        return self._load_failed

    @property
    def bottle_class_id(self) -> int | None:
        return self._bottle_class_id

    @property
    def shaker_class_id(self) -> int | None:
        return self._shaker_class_id

    @property
    def class_names(self) -> dict[int, str]:
        return dict(self._class_names)

    def ensure_ready(self) -> None:
        """Load and validate the combined model now."""
        self._ensure_model()

    def _ensure_model(self) -> YOLO:
        if self._load_failed:
            raise ModelLoadError("YOLO combined prop model failed to load")

        if self._model is not None:
            return self._model

        if not self._model_path.is_file():
            self._load_failed = True
            raise ModelLoadError(
                f"YOLO model file is missing: {self._model_path}"
            )

        logger.info("Loading combined YOLO model: path=%s", self._model_path)
        try:
            model = self._model_loader(str(self._model_path))
            bottle_id, shaker_id, class_names = resolve_bottle_and_shaker_class_ids(
                getattr(model, "names", None),
            )
        except ModelLoadError:
            self._load_failed = True
            logger.exception(
                "Invalid YOLO model configuration: path=%s",
                self._model_path,
            )
            raise
        except Exception as exc:
            self._load_failed = True
            logger.exception(
                "Failed to load YOLO model: path=%s",
                self._model_path,
            )
            raise ModelLoadError("Failed to load the combined YOLO model") from exc

        self._model = model
        self._bottle_class_id = bottle_id
        self._shaker_class_id = shaker_id
        self._class_names = class_names
        device = _resolve_model_device(model)
        logger.info(
            "Loaded combined prop detector: path=%s classes=%s "
            "bottle_class_id=%s shaker_class_id=%s device=%s imgsz=%s",
            self._model_path,
            self._class_names,
            self._bottle_class_id,
            self._shaker_class_id,
            device,
            YOLO_IMGSZ,
        )
        return model

    def detect_all(self, frame: np.ndarray) -> CombinedDetectionResult:
        """Run one YOLO inference and return bottle and shaker detections."""
        if not self._enabled:
            return CombinedDetectionResult(bottles=[], shakers=[])

        model = self._ensure_model()
        assert self._bottle_class_id is not None
        assert self._shaker_class_id is not None

        try:
            results = model(
                frame,
                verbose=False,
                conf=self._confidence,
                iou=YOLO_IOU,
                max_det=MAX_BOTTLES * 2,
                imgsz=YOLO_IMGSZ,
            )
        except Exception:
            logger.exception("YOLO inference failed for combined prop detector")
            return CombinedDetectionResult(bottles=[], shakers=[])

        bottles: list[PropDetection] = []
        shakers: list[PropDetection] = []
        for result in results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                cls_id = int(box.cls[0])
                confidence = float(box.conf[0])
                x1, y1, x2, y2 = (
                    int(value) for value in box.xyxy[0].tolist()
                )
                detection = PropDetection(
                    x1=x1,
                    y1=y1,
                    x2=x2,
                    y2=y2,
                    confidence=confidence,
                )
                if cls_id == self._bottle_class_id:
                    bottles.append(detection)
                elif cls_id == self._shaker_class_id:
                    shakers.append(detection)

        bottles.sort(key=lambda detection: detection.confidence, reverse=True)
        shakers.sort(key=lambda detection: detection.confidence, reverse=True)
        return CombinedDetectionResult(
            bottles=bottles[:MAX_BOTTLES],
            shakers=shakers[:MAX_BOTTLES],
        )


class PropDetector:
    """Lazy single-prop view over the shared combined YOLO model."""

    def __init__(
        self,
        prop_type: PropType = "bottle",
        confidence: float = YOLO_CONFIDENCE,
        enabled: bool = True,
        *,
        model_path: Path | str | None = None,
        model_loader: Callable[[str], YOLO] | None = None,
        combined_detector: CombinedPropDetector | None = None,
    ):
        if prop_type not in _CLASS_ALIASES:
            raise ValueError(f"invalid_prop_type: {prop_type!r}")

        self._prop_type = prop_type
        self._combined = combined_detector or CombinedPropDetector(
            confidence=confidence,
            enabled=enabled,
            model_path=model_path,
            model_loader=model_loader,
        )

        logger.info(
            "Configured prop detector: prop=%s model_path=%s",
            self._prop_type,
            self._combined.model_path,
        )

    @property
    def prop_type(self) -> PropType:
        return self._prop_type

    @property
    def model_path(self) -> Path:
        return self._combined.model_path

    @property
    def enabled(self) -> bool:
        return self._combined.enabled

    def set_enabled(self, enabled: bool) -> None:
        self._combined.set_enabled(enabled)

    @property
    def load_failed(self) -> bool:
        return self._combined.load_failed

    @property
    def resolved_class_id(self) -> int | None:
        if self._prop_type == "bottle":
            return self._combined.bottle_class_id
        return self._combined.shaker_class_id

    @property
    def class_names(self) -> dict[int, str]:
        return self._combined.class_names

    def ensure_ready(self) -> None:
        """Load and validate the combined model now."""
        self._combined.ensure_ready()

    def detect_all(self, frame: np.ndarray) -> CombinedDetectionResult:
        """Run one combined inference and return both prop lists."""
        return self._combined.detect_all(frame)

    def detect(self, frame: np.ndarray) -> list[PropDetection]:
        """Return up to MAX_BOTTLES detections for the configured prop."""
        result = self._combined.detect_all(frame)
        if self._prop_type == "bottle":
            return list(result.bottles)
        return list(result.shakers)
