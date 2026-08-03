from __future__ import annotations

import logging
import re
from collections.abc import Mapping
from pathlib import Path
from typing import Callable, Literal, Optional

import numpy as np
from ultralytics import YOLO

from config import MAX_BOTTLES, YOLO_CONFIDENCE, YOLO_IMGSZ, YOLO_IOU
from vision.types import PropDetection

logger = logging.getLogger(__name__)

PropType = Literal["bottle", "shaker"]

_MODEL_DIR = Path(__file__).resolve().parent.parent / "models"
_MODEL_FILES: dict[PropType, str] = {
    "bottle": "bottle_best.pt",
    "shaker": "shaker_best.pt",
}
_CLASS_ALIASES: dict[PropType, set[str]] = {
    "bottle": {
        "bottle",
        "bottles",
        "flairbottle",
        "flairbottles",
    },
    "shaker": {
        "shaker",
        "shakerbottle",
        "cocktailshaker",
        "cocktailshakerbottle",
    },
}


class ModelLoadError(RuntimeError):
    """Raised when a selected prop model cannot be loaded or configured."""


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


def resolve_prop_class_id(names: object, prop_type: PropType) -> tuple[int, dict[int, str]]:
    """Resolve the class for a prop without assuming class id zero."""
    if prop_type not in _MODEL_FILES:
        raise ModelLoadError(f"Unsupported prop type: {prop_type}")

    mapping = _class_mapping(names)
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

    return matches[0], mapping


class PropDetector:
    """Lazy YOLO detector for the selected training prop."""

    def __init__(
        self,
        prop_type: PropType = "bottle",
        confidence: float = YOLO_CONFIDENCE,
        enabled: bool = True,
        *,
        model_path: Path | str | None = None,
        model_loader: Callable[[str], YOLO] | None = None,
    ):
        if prop_type not in _MODEL_FILES:
            raise ValueError(f"invalid_prop_type: {prop_type!r}")

        self._prop_type = prop_type
        self._confidence = confidence
        self._model: Optional[YOLO] = None
        self._model_path = (
            Path(model_path).resolve()
            if model_path is not None
            else (_MODEL_DIR / _MODEL_FILES[prop_type]).resolve()
        )
        self._model_loader = model_loader or YOLO
        self._load_failed = False
        self._enabled = enabled
        self._resolved_class_id: int | None = None
        self._class_names: dict[int, str] = {}

        logger.info(
            "Configured prop detector: prop=%s model_path=%s",
            self._prop_type,
            self._model_path,
        )

    @property
    def prop_type(self) -> PropType:
        return self._prop_type

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
    def resolved_class_id(self) -> int | None:
        return self._resolved_class_id

    @property
    def class_names(self) -> dict[int, str]:
        return dict(self._class_names)

    def ensure_ready(self) -> None:
        """Load and validate the selected model now."""
        self._ensure_model()

    def _ensure_model(self) -> YOLO:
        if self._load_failed:
            raise ModelLoadError(
                f"YOLO model for {self._prop_type} failed to load"
            )

        if self._model is not None:
            return self._model

        if not self._model_path.is_file():
            self._load_failed = True
            raise ModelLoadError(
                f"YOLO model file is missing: {self._model_path}"
            )

        logger.info(
            "Loading YOLO model: prop=%s path=%s",
            self._prop_type,
            self._model_path,
        )
        try:
            model = self._model_loader(str(self._model_path))
            class_id, class_names = resolve_prop_class_id(
                getattr(model, "names", None),
                self._prop_type,
            )
        except ModelLoadError:
            self._load_failed = True
            logger.exception(
                "Invalid YOLO model configuration: prop=%s path=%s",
                self._prop_type,
                self._model_path,
            )
            raise
        except Exception as exc:
            self._load_failed = True
            logger.exception(
                "Failed to load YOLO model: prop=%s path=%s",
                self._prop_type,
                self._model_path,
            )
            raise ModelLoadError(
                f"Failed to load the {self._prop_type} YOLO model"
            ) from exc

        self._model = model
        self._resolved_class_id = class_id
        self._class_names = class_names
        device = _resolve_model_device(model)
        logger.info(
            "Loaded prop detector: prop=%s path=%s classes=%s "
            "resolved_class_id=%s device=%s imgsz=%s",
            self._prop_type,
            self._model_path,
            self._class_names,
            self._resolved_class_id,
            device,
            YOLO_IMGSZ,
        )
        return model

    def detect(self, frame: np.ndarray) -> list[PropDetection]:
        """Return up to MAX_BOTTLES detections, highest confidence first."""
        if not self._enabled:
            return []

        model = self._ensure_model()

        try:
            results = model(
                frame,
                verbose=False,
                conf=self._confidence,
                iou=YOLO_IOU,
                max_det=MAX_BOTTLES,
                imgsz=YOLO_IMGSZ,
            )
        except Exception:
            logger.exception("YOLO inference failed for prop=%s", self._prop_type)
            return []

        detections: list[PropDetection] = []
        for result in results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                cls_id = int(box.cls[0])
                if cls_id != self._resolved_class_id:
                    continue

                confidence = float(box.conf[0])
                x1, y1, x2, y2 = (
                    int(value) for value in box.xyxy[0].tolist()
                )
                detections.append(
                    PropDetection(
                        x1=x1,
                        y1=y1,
                        x2=x2,
                        y2=y2,
                        confidence=confidence,
                    )
                )

        detections.sort(key=lambda detection: detection.confidence, reverse=True)
        return detections[:MAX_BOTTLES]
