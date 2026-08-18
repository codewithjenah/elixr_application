from __future__ import annotations

import logging
import re
import time
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

import numpy as np

from config import (
    MAX_BOTTLES,
    YOLO_BOTTLE_CONFIDENCE,
    YOLO_CONFIDENCE,
    YOLO_IMGSZ,
    YOLO_IOU,
    YOLO_MODEL_PATH,
    YOLO_ONNX_INTRA_OP_THREADS,
    YOLO_ONNX_MODEL_PATH,
    YOLO_RUNTIME,
    YOLO_SHAKER_CONFIDENCE,
)
from vision.prop_inference import (
    ModelLoadError,
    PropInferenceBackend,
    PyTorchPropBackend,
    RuntimeSelection,
    create_prop_backend,
    dml_is_available,
    onnxruntime_is_available,
    select_prop_runtime,
    split_raw_detections,
)
from vision.prop_tracker import PropTracker
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


@dataclass(frozen=True)
class CombinedDetectionResult:
    bottles: list[PropDetection]
    shakers: list[PropDetection]


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
        onnx_model_path: Path | str | None = None,
        model_loader: Callable[[str], Any] | None = None,
        inference_backend: PropInferenceBackend | None = None,
        runtime: str | None = None,
    ):
        self._confidence = confidence
        self._backend: PropInferenceBackend | None = inference_backend
        self._model_path = (
            Path(model_path).resolve()
            if model_path is not None
            else YOLO_MODEL_PATH
        )
        self._onnx_model_path = (
            Path(onnx_model_path).resolve()
            if onnx_model_path is not None
            else YOLO_ONNX_MODEL_PATH
        )
        self._model_loader = model_loader
        self._requested_runtime = (
            runtime if runtime is not None else YOLO_RUNTIME
        )
        self._injected_backend = inference_backend is not None
        self._load_failed = False
        self._runtime_logged = False
        self._enabled = enabled
        self._bottle_class_id: int | None = None
        self._shaker_class_id: int | None = None
        self._class_names: dict[int, str] = {}
        self._bottle_tracker = PropTracker()
        self._shaker_tracker = PropTracker()

        logger.info(
            "Configured combined prop detector: model_path=%s onnx_path=%s "
            "runtime=%s",
            self._model_path,
            self._onnx_model_path,
            self._requested_runtime,
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

    @property
    def yolo_runtime(self) -> str:
        if self._backend is None:
            return ""
        return self._backend.runtime_name

    @property
    def yolo_provider(self) -> str:
        if self._backend is None:
            return ""
        return self._backend.provider

    @property
    def yolo_threads(self) -> int:
        if self._backend is None:
            return 0
        return int(getattr(self._backend, "intra_op_threads", 0) or 0)

    def reset_tracks(self) -> None:
        """Drop live identities so the next frame starts a new track_id sequence."""
        self._bottle_tracker.reset()
        self._shaker_tracker.reset()

    def extrapolate_detections(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        now: float,
    ) -> tuple[list[PropDetection], list[PropDetection]]:
        """Coast last YOLO boxes by per-track velocity for skipped frames."""
        return (
            self._bottle_tracker.extrapolate(bottles, now),
            self._shaker_tracker.extrapolate(shakers, now),
        )

    def ensure_ready(self) -> None:
        """Load and validate the combined model now."""
        self._ensure_backend()

    def _ensure_backend(self) -> PropInferenceBackend:
        if self._load_failed:
            raise ModelLoadError("YOLO combined prop model failed to load")

        if self._backend is not None and self._bottle_class_id is not None:
            return self._backend

        backend = self._backend
        try:
            if backend is None:
                backend = self._create_backend()
            self._finish_backend_load(backend)
            assert self._backend is not None
            return self._backend
        except Exception as exc:
            fallback = self._pytorch_fallback_backend(failed=backend, error=exc)
            if fallback is None:
                self._load_failed = True
                if isinstance(exc, ModelLoadError):
                    logger.exception(
                        "Invalid YOLO model configuration: path=%s",
                        self._model_path,
                    )
                    raise
                logger.exception(
                    "Failed to load YOLO model: path=%s",
                    self._model_path,
                )
                raise ModelLoadError(
                    "Failed to load the combined YOLO model"
                ) from exc
            try:
                self._finish_backend_load(fallback)
                assert self._backend is not None
                return self._backend
            except Exception:
                self._load_failed = True
                logger.exception(
                    "Failed to load YOLO model: path=%s",
                    self._model_path,
                )
                raise

    def _finish_backend_load(self, backend: PropInferenceBackend) -> None:
        backend.load()
        bottle_id, shaker_id, class_names = resolve_bottle_and_shaker_class_ids(
            backend.names,
        )
        self._backend = backend
        self._bottle_class_id = bottle_id
        self._shaker_class_id = shaker_id
        self._class_names = class_names
        if not self._runtime_logged:
            logger.info(
                "YOLO runtime selected: runtime=%s provider=%s threads=%s "
                "model=%s imgsz=%s",
                backend.runtime_name,
                backend.provider,
                int(getattr(backend, "intra_op_threads", 0) or 0),
                Path(backend.model_path).name,
                YOLO_IMGSZ,
            )
            logger.info(
                "Loaded combined prop detector: path=%s classes=%s "
                "bottle_class_id=%s shaker_class_id=%s provider=%s imgsz=%s",
                backend.model_path,
                self._class_names,
                self._bottle_class_id,
                self._shaker_class_id,
                backend.provider,
                YOLO_IMGSZ,
            )
            self._runtime_logged = True

    def _pytorch_fallback_backend(
        self,
        *,
        failed: PropInferenceBackend | None,
        error: BaseException,
    ) -> PropInferenceBackend | None:
        if self._injected_backend or self._model_loader is not None:
            return None
        failed_runtime = (
            getattr(failed, "runtime_name", "") or self._requested_runtime
        )
        if failed_runtime not in {"onnx_cpu", "onnx_dml"}:
            return None
        if not self._model_path.is_file():
            return None
        logger.warning(
            "YOLO ONNX initialization failed; falling back to PyTorch reason=%s",
            error,
        )
        return create_prop_backend(
            RuntimeSelection(
                runtime="pytorch",
                provider="cpu",
                reason="fallback_onnx_init_failed",
                fallback_from=failed_runtime,
            ),
            pytorch_path=self._model_path,
            onnx_path=self._onnx_model_path,
            inference_conf=min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE),
            iou=YOLO_IOU,
            max_det=MAX_BOTTLES * 2,
            imgsz=YOLO_IMGSZ,
            intra_op_threads=YOLO_ONNX_INTRA_OP_THREADS,
        )

    def _create_backend(self) -> PropInferenceBackend:
        inference_conf = min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE)
        if self._model_loader is not None:
            if not self._model_path.is_file():
                raise ModelLoadError(
                    f"YOLO model file is missing: {self._model_path}"
                )
            return PyTorchPropBackend(
                self._model_path,
                model_loader=self._model_loader,
                inference_conf=inference_conf,
                iou=YOLO_IOU,
                max_det=MAX_BOTTLES * 2,
                imgsz=YOLO_IMGSZ,
            )

        selection = select_prop_runtime(
            self._requested_runtime,
            pytorch_path=self._model_path,
            onnx_path=self._onnx_model_path,
            onnxruntime_available=onnxruntime_is_available(),
            dml_available=dml_is_available(),
        )
        if selection.fallback_from:
            logger.warning(
                "YOLO runtime fallback: requested=%s selected=%s reason=%s",
                selection.fallback_from,
                selection.runtime,
                selection.reason,
            )
        return create_prop_backend(
            selection,
            pytorch_path=self._model_path,
            onnx_path=self._onnx_model_path,
            inference_conf=inference_conf,
            iou=YOLO_IOU,
            max_det=MAX_BOTTLES * 2,
            imgsz=YOLO_IMGSZ,
            intra_op_threads=YOLO_ONNX_INTRA_OP_THREADS,
        )

    def detect_all(self, frame: np.ndarray) -> CombinedDetectionResult:
        """Run one YOLO inference and return bottle and shaker detections."""
        if not self._enabled:
            return CombinedDetectionResult(bottles=[], shakers=[])

        backend = self._ensure_backend()
        assert self._bottle_class_id is not None
        assert self._shaker_class_id is not None

        # Ultralytics accepts one global conf; run at the lower threshold, then
        # post-filter each class against its own (higher-or-equal) cutoff.
        inference_conf = min(YOLO_BOTTLE_CONFIDENCE, YOLO_SHAKER_CONFIDENCE)
        try:
            raw = backend.infer(
                frame,
                conf=inference_conf,
                iou=YOLO_IOU,
                max_det=MAX_BOTTLES * 2,
                imgsz=YOLO_IMGSZ,
            )
        except Exception:
            logger.exception("YOLO inference failed for combined prop detector")
            return CombinedDetectionResult(bottles=[], shakers=[])

        bottles, shakers = split_raw_detections(
            raw,
            bottle_class_id=self._bottle_class_id,
            shaker_class_id=self._shaker_class_id,
            bottle_conf=YOLO_BOTTLE_CONFIDENCE,
            shaker_conf=YOLO_SHAKER_CONFIDENCE,
        )
        now = time.monotonic()
        self._bottle_tracker.update(bottles[:MAX_BOTTLES], timestamp=now)
        self._shaker_tracker.update(shakers[:MAX_BOTTLES], timestamp=now)
        return CombinedDetectionResult(
            bottles=self._bottle_tracker.live_detections(now),
            shakers=self._shaker_tracker.live_detections(now),
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
        model_loader: Callable[[str], Any] | None = None,
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

    @property
    def yolo_runtime(self) -> str:
        return self._combined.yolo_runtime

    @property
    def yolo_provider(self) -> str:
        return self._combined.yolo_provider

    @property
    def yolo_threads(self) -> int:
        return self._combined.yolo_threads

    def ensure_ready(self) -> None:
        """Load and validate the combined model now."""
        self._combined.ensure_ready()

    def extrapolate_detections(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        now: float,
    ) -> tuple[list[PropDetection], list[PropDetection]]:
        """Coast last YOLO boxes by per-track velocity for skipped frames."""
        return self._combined.extrapolate_detections(
            bottles=bottles,
            shakers=shakers,
            now=now,
        )

    def detect_all(self, frame: np.ndarray) -> CombinedDetectionResult:
        """Run one combined inference and return both prop lists."""
        return self._combined.detect_all(frame)

    def detect(self, frame: np.ndarray) -> list[PropDetection]:
        """Return up to MAX_BOTTLES detections for the configured prop."""
        result = self._combined.detect_all(frame)
        if self._prop_type == "bottle":
            return list(result.bottles)
        return list(result.shakers)
