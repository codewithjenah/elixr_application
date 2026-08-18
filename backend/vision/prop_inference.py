"""YOLO inference backends for combined bottle/shaker detection.

Business logic (class mapping, per-class confidence, tracking) stays in
``prop_detector``. This module only runs the selected engine and returns
raw boxes in original-image coordinates.
"""

from __future__ import annotations

import ast
import logging
import threading
from abc import ABC, abstractmethod
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from config import (
    MAX_BOTTLES,
    YOLO_DML_DEVICE_ID,
    YOLO_IMGSZ,
    YOLO_IOU,
    YOLO_ONNX_INTRA_OP_THREADS,
)
from vision.types import PropDetection

logger = logging.getLogger(__name__)


class ModelLoadError(RuntimeError):
    """Raised when the combined prop model cannot be loaded or configured."""


@dataclass(frozen=True)
class RawDetection:
    class_id: int
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float


@dataclass(frozen=True)
class RuntimeSelection:
    runtime: str
    provider: str
    reason: str
    fallback_from: str | None = None


_VALID_RUNTIMES = frozenset({"auto", "pytorch", "onnx_cpu", "onnx_dml"})
_DML_PROVIDER = "DmlExecutionProvider"
_CPU_PROVIDER = "CPUExecutionProvider"


class PropInferenceBackend(ABC):
    """One persistent YOLO engine. Call ``load()`` once, then ``infer()``."""

    runtime_name: str = ""
    provider: str = ""
    model_path: Path = Path()
    intra_op_threads: int = 0

    @property
    @abstractmethod
    def names(self) -> dict[int, str]:
        """Declared class id → name mapping."""

    @abstractmethod
    def load(self) -> None:
        """Create the engine/session. Must be idempotent."""

    @abstractmethod
    def infer(self, frame: np.ndarray, **kwargs: Any) -> list[RawDetection]:
        """Run one forward pass. Boxes are in the original frame pixel space."""


def onnxruntime_is_available() -> bool:
    try:
        import onnxruntime  # noqa: F401
    except ImportError:
        return False
    return True


def dml_is_available() -> bool:
    try:
        import onnxruntime as ort
    except ImportError:
        return False
    return _DML_PROVIDER in ort.get_available_providers()


def _provider_label(providers: Sequence[Any]) -> str:
    if not providers:
        return ""
    first = providers[0]
    if isinstance(first, tuple):
        return str(first[0])
    return str(first)


def select_prop_runtime(
    requested: str,
    *,
    pytorch_path: Path,
    onnx_path: Path,
    onnxruntime_available: bool,
    dml_available: bool,
) -> RuntimeSelection:
    """Deterministic runtime choice. DirectML is never selected by auto."""
    requested = (requested or "").strip().lower()
    if requested not in _VALID_RUNTIMES:
        raise ModelLoadError(
            "Invalid YOLO_RUNTIME "
            f"{requested!r}; expected auto, pytorch, onnx_cpu, or onnx_dml"
        )

    pytorch_ok = pytorch_path.is_file()
    onnx_ok = onnx_path.is_file()

    def require_pytorch(
        reason: str,
        fallback_from: str | None = None,
    ) -> RuntimeSelection:
        if not pytorch_ok:
            raise ModelLoadError(f"YOLO model file is missing: {pytorch_path}")
        return RuntimeSelection(
            runtime="pytorch",
            provider="cpu",
            reason=reason,
            fallback_from=fallback_from,
        )

    def require_onnx_cpu(
        reason: str,
        fallback_from: str | None = None,
    ) -> RuntimeSelection:
        if not onnx_ok:
            return require_pytorch("fallback_missing_onnx", fallback_from)
        if not onnxruntime_available:
            return require_pytorch(
                "fallback_onnxruntime_unavailable",
                fallback_from,
            )
        return RuntimeSelection(
            runtime="onnx_cpu",
            provider=_CPU_PROVIDER,
            reason=reason,
            fallback_from=fallback_from,
        )

    if requested == "pytorch":
        return require_pytorch("explicit_pytorch")

    if requested == "onnx_cpu":
        if not onnx_ok:
            return require_pytorch("fallback_missing_onnx", "onnx_cpu")
        if not onnxruntime_available:
            return require_pytorch(
                "fallback_onnxruntime_unavailable",
                "onnx_cpu",
            )
        return RuntimeSelection(
            runtime="onnx_cpu",
            provider=_CPU_PROVIDER,
            reason="explicit_onnx_cpu",
        )

    if requested == "onnx_dml":
        if dml_available and onnx_ok and onnxruntime_available:
            return RuntimeSelection(
                runtime="onnx_dml",
                provider=_DML_PROVIDER,
                reason="explicit_onnx_dml",
            )
        return require_onnx_cpu("fallback_dml_unavailable", "onnx_dml")

    # auto keeps PyTorch: isolated CPU inference at the conservative intra-op
    # cap was not a meaningful win over Ultralytics. ONNX remains opt-in.
    if pytorch_ok:
        return require_pytorch("auto_pytorch")
    return require_onnx_cpu("auto_onnx_cpu_pytorch_missing")


def _static_positive_int(value: Any) -> int | None:
    if isinstance(value, bool) or isinstance(value, str):
        return None
    if isinstance(value, (int, np.integer)):
        parsed = int(value)
        if parsed > 0:
            return parsed
    return None


def parse_onnx_static_input_hw(shape: Sequence[Any] | None) -> tuple[int, int]:
    """Read static NCHW spatial size from an ONNX input. Never guess."""
    if shape is None or len(shape) != 4:
        raise ModelLoadError(
            "ONNX model input shape must be static [1, 3, H, W]; "
            f"got {shape!r}"
        )
    batch, channels, height, width = shape
    batch_n = _static_positive_int(batch)
    channel_n = _static_positive_int(channels)
    height_n = _static_positive_int(height)
    width_n = _static_positive_int(width)
    if batch_n != 1 or channel_n != 3 or height_n is None or width_n is None:
        raise ModelLoadError(
            "ONNX model input shape must be static [1, 3, H, W]; "
            f"got {list(shape)!r}"
        )
    if height_n % 32 != 0 or width_n % 32 != 0:
        raise ModelLoadError(
            "ONNX model spatial size must be multiples of 32; "
            f"got H={height_n} W={width_n}"
        )
    return height_n, width_n


def parse_onnx_class_names(metadata: Mapping[str, str]) -> dict[int, str]:
    raw = metadata.get("names")
    if not raw or not str(raw).strip():
        raise ModelLoadError("ONNX model metadata is missing class names")
    try:
        parsed = ast.literal_eval(str(raw))
    except (SyntaxError, ValueError) as exc:
        raise ModelLoadError("ONNX model class names are invalid") from exc

    if isinstance(parsed, Mapping):
        mapping = {int(key): str(value) for key, value in parsed.items()}
    elif isinstance(parsed, (list, tuple)):
        mapping = {index: str(name) for index, name in enumerate(parsed)}
    else:
        raise ModelLoadError("ONNX model class names are not a mapping or list")
    if not mapping:
        raise ModelLoadError("ONNX model metadata is missing class names")
    return mapping


def split_raw_detections(
    detections: Sequence[RawDetection],
    *,
    bottle_class_id: int,
    shaker_class_id: int,
    bottle_conf: float,
    shaker_conf: float,
) -> tuple[list[PropDetection], list[PropDetection]]:
    """Filter, convert, and sort raw boxes into ELIXR prop lists."""
    bottles: list[PropDetection] = []
    shakers: list[PropDetection] = []
    for detection in detections:
        box = PropDetection(
            x1=int(detection.x1),
            y1=int(detection.y1),
            x2=int(detection.x2),
            y2=int(detection.y2),
            confidence=float(detection.confidence),
        )
        if (
            detection.class_id == bottle_class_id
            and detection.confidence >= bottle_conf
        ):
            bottles.append(box)
        elif (
            detection.class_id == shaker_class_id
            and detection.confidence >= shaker_conf
        ):
            shakers.append(box)
    bottles.sort(key=lambda item: item.confidence, reverse=True)
    shakers.sort(key=lambda item: item.confidence, reverse=True)
    return bottles, shakers


def yolo_runtime_info(detector: object) -> tuple[str, str]:
    """Read selected runtime/provider from a detector or its combined wrapper."""
    runtime = getattr(detector, "yolo_runtime", None)
    provider = getattr(detector, "yolo_provider", None)
    if isinstance(runtime, str) and isinstance(provider, str) and runtime:
        return runtime, provider
    combined = getattr(detector, "combined_detector", None)
    if combined is not None and combined is not detector:
        return yolo_runtime_info(combined)
    inner = getattr(detector, "_combined", None)
    if inner is not None and inner is not detector:
        return yolo_runtime_info(inner)
    return "", ""


def yolo_runtime_threads(detector: object) -> int:
    """Read ONNX intra-op threads from a detector or its combined wrapper."""
    threads = getattr(detector, "yolo_threads", None)
    if isinstance(threads, int):
        return threads
    combined = getattr(detector, "combined_detector", None)
    if combined is not None and combined is not detector:
        return yolo_runtime_threads(combined)
    inner = getattr(detector, "_combined", None)
    if inner is not None and inner is not detector:
        return yolo_runtime_threads(inner)
    return int(getattr(detector, "intra_op_threads", 0) or 0)


def default_onnx_session_options(intra_op_threads: int):
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.inter_op_num_threads = 1
    if intra_op_threads > 0:
        options.intra_op_num_threads = intra_op_threads
    return options


def default_onnx_session_factory(
    path: Path,
    sess_options: object,
    providers: Sequence[Any],
):
    import onnxruntime as ort

    return ort.InferenceSession(
        str(path),
        sess_options=sess_options,
        providers=list(providers),
    )


def _xyxy_values(box: object) -> list[float]:
    xyxy = getattr(box, "xyxy")[0]
    if hasattr(xyxy, "tolist"):
        return [float(value) for value in xyxy.tolist()]
    return [float(value) for value in xyxy]


def _box_scalar(value: object) -> float:
    item = getattr(value, "item", None)
    if callable(item):
        return float(item())
    return float(value)


class PyTorchPropBackend(PropInferenceBackend):
    """Ultralytics PyTorch path. Preserves the current ``model(frame, ...)`` call."""

    def __init__(
        self,
        model_path: Path | str,
        *,
        model_loader: Callable[[str], Any] | None = None,
        inference_conf: float = 0.4,
        iou: float = YOLO_IOU,
        max_det: int = MAX_BOTTLES * 2,
        imgsz: int = YOLO_IMGSZ,
    ) -> None:
        from ultralytics import YOLO

        self.model_path = Path(model_path)
        self.runtime_name = "pytorch"
        self.provider = "cpu"
        self._model_loader = model_loader or YOLO
        self.intra_op_threads = 0
        self._inference_conf = inference_conf
        self._iou = iou
        self._max_det = max_det
        self._imgsz = imgsz
        self._model: Any = None
        self._names: dict[int, str] = {}

    @property
    def names(self) -> dict[int, str]:
        return dict(self._names)

    def load(self) -> None:
        if self._model is not None:
            return
        if not self.model_path.is_file():
            raise ModelLoadError(f"YOLO model file is missing: {self.model_path}")
        model = self._model_loader(str(self.model_path))
        self._model = model
        raw_names = getattr(model, "names", None)
        if isinstance(raw_names, Mapping):
            self._names = {int(key): str(value) for key, value in raw_names.items()}
        elif isinstance(raw_names, (list, tuple)):
            self._names = {index: str(name) for index, name in enumerate(raw_names)}
        else:
            raise ModelLoadError("YOLO model class names are not a mapping or list")
        device = getattr(model, "device", None)
        if device is not None:
            self.provider = str(device)
        else:
            overrides = getattr(model, "overrides", None)
            if isinstance(overrides, Mapping) and overrides.get("device") is not None:
                self.provider = str(overrides["device"])

    def infer(self, frame: np.ndarray, **kwargs: Any) -> list[RawDetection]:
        if self._model is None:
            self.load()
        conf = kwargs.get("conf", self._inference_conf)
        iou = kwargs.get("iou", self._iou)
        max_det = kwargs.get("max_det", self._max_det)
        imgsz = kwargs.get("imgsz", self._imgsz)
        results = self._model(
            frame,
            verbose=False,
            conf=conf,
            iou=iou,
            max_det=max_det,
            imgsz=imgsz,
        )
        detections: list[RawDetection] = []
        for result in results:
            boxes = getattr(result, "boxes", None)
            if boxes is None:
                continue
            for box in boxes:
                x1, y1, x2, y2 = _xyxy_values(box)
                detections.append(
                    RawDetection(
                        class_id=int(_box_scalar(box.cls[0])),
                        confidence=float(_box_scalar(box.conf[0])),
                        x1=x1,
                        y1=y1,
                        x2=x2,
                        y2=y2,
                    )
                )
        return detections


class OnnxPropBackend(PropInferenceBackend):
    """Persistent ONNX Runtime session with Ultralytics-compatible postprocess."""

    def __init__(
        self,
        model_path: Path | str,
        *,
        runtime_name: str = "onnx_cpu",
        providers: Sequence[Any] | None = None,
        imgsz: int = YOLO_IMGSZ,
        intra_op_threads: int = YOLO_ONNX_INTRA_OP_THREADS,
        session_factory: Callable[..., Any] | None = None,
        session_options_factory: Callable[[], Any] | None = None,
        inference_conf: float = 0.4,
        iou: float = YOLO_IOU,
        max_det: int = MAX_BOTTLES * 2,
    ) -> None:
        self.model_path = Path(model_path)
        self.runtime_name = runtime_name
        self._providers = list(providers or [_CPU_PROVIDER])
        self.provider = _provider_label(self._providers)
        self._imgsz = imgsz
        self._intra_op_threads = intra_op_threads
        self.intra_op_threads = intra_op_threads
        self._session_factory = session_factory or default_onnx_session_factory
        self._session_options_factory = session_options_factory or (
            lambda: default_onnx_session_options(self._intra_op_threads)
        )
        self._inference_conf = inference_conf
        self._iou = iou
        self._max_det = max_det
        self._session: Any = None
        self._input_name = "images"
        self._output_names: list[str] = ["output0"]
        self._names: dict[int, str] = {}
        self._letterbox: Any = None
        self.input_height = 0
        self.input_width = 0
        self._infer_lock = threading.Lock()

    @property
    def names(self) -> dict[int, str]:
        return dict(self._names)

    def load(self) -> None:
        if self._session is not None:
            return
        if not self.model_path.is_file():
            raise ModelLoadError(f"YOLO model file is missing: {self.model_path}")
        session = self._session_factory(
            self.model_path,
            self._session_options_factory(),
            self._providers,
        )
        inputs = session.get_inputs()
        outputs = session.get_outputs()
        if not inputs:
            raise ModelLoadError("ONNX model has no inputs")
        self._input_name = inputs[0].name
        self.input_height, self.input_width = parse_onnx_static_input_hw(
            getattr(inputs[0], "shape", None)
        )
        if outputs:
            self._output_names = [item.name for item in outputs]
        metadata = {}
        modelmeta = getattr(session, "get_modelmeta", None)
        if callable(modelmeta):
            meta = modelmeta()
            metadata = dict(getattr(meta, "custom_metadata_map", {}) or {})
        self._names = parse_onnx_class_names(metadata)
        from ultralytics.data.augment import LetterBox

        # The loaded graph is authoritative. Do not square-pad to YOLO_IMGSZ
        # when the model already declares a static rectangular H/W.
        self._letterbox = LetterBox(
            (self.input_height, self.input_width),
            auto=False,
            stride=32,
        )
        self._session = session
        self.provider = _provider_label(self._providers)

    def infer(self, frame: np.ndarray, **kwargs: Any) -> list[RawDetection]:
        if self._session is None:
            self.load()
        conf = float(kwargs.get("conf", self._inference_conf))
        iou = float(kwargs.get("iou", self._iou))
        max_det = int(kwargs.get("max_det", self._max_det))
        letterboxed = self._letterbox(image=frame)
        blob = letterboxed[:, :, ::-1].transpose(2, 0, 1)
        blob = np.ascontiguousarray(blob, dtype=np.float32)[None, ...]
        blob /= 255.0
        with self._infer_lock:
            outputs = self._session.run(
                self._output_names,
                {self._input_name: blob},
            )
        return _postprocess_yolo_onnx(
            outputs[0],
            letterboxed_hw=letterboxed.shape[:2],
            orig_shape=frame.shape,
            conf=conf,
            iou=iou,
            max_det=max_det,
            num_classes=len(self._names),
        )


def _postprocess_yolo_onnx(
    raw_output: np.ndarray,
    *,
    letterboxed_hw: tuple[int, int],
    orig_shape: tuple[int, ...],
    conf: float,
    iou: float,
    max_det: int,
    num_classes: int,
) -> list[RawDetection]:
    import torch
    from ultralytics.utils import nms
    from ultralytics.utils.ops import scale_boxes

    prediction = torch.from_numpy(np.ascontiguousarray(raw_output))
    if prediction.ndim == 2:
        prediction = prediction.unsqueeze(0)
    preds = nms.non_max_suppression(
        prediction,
        conf_thres=conf,
        iou_thres=iou,
        max_det=max_det,
        nc=num_classes,
    )
    if not preds or preds[0] is None or len(preds[0]) == 0:
        return []
    boxes = preds[0].clone()
    boxes[:, :4] = scale_boxes(letterboxed_hw, boxes[:, :4], orig_shape)
    detections: list[RawDetection] = []
    for row in boxes:
        detections.append(
            RawDetection(
                class_id=int(row[5].item()),
                confidence=float(row[4].item()),
                x1=float(row[0].item()),
                y1=float(row[1].item()),
                x2=float(row[2].item()),
                y2=float(row[3].item()),
            )
        )
    return detections


def create_prop_backend(
    selection: RuntimeSelection,
    *,
    pytorch_path: Path,
    onnx_path: Path,
    model_loader: Callable[[str], Any] | None = None,
    inference_conf: float,
    iou: float,
    max_det: int,
    imgsz: int,
    intra_op_threads: int = YOLO_ONNX_INTRA_OP_THREADS,
    dml_device_id: int = YOLO_DML_DEVICE_ID,
) -> PropInferenceBackend:
    if selection.runtime == "pytorch":
        return PyTorchPropBackend(
            pytorch_path,
            model_loader=model_loader,
            inference_conf=inference_conf,
            iou=iou,
            max_det=max_det,
            imgsz=imgsz,
        )
    providers: list[Any] = [_CPU_PROVIDER]
    if selection.runtime == "onnx_dml":
        providers = [
            (_DML_PROVIDER, {"device_id": dml_device_id}),
            _CPU_PROVIDER,
        ]
    return OnnxPropBackend(
        onnx_path,
        runtime_name=selection.runtime,
        providers=providers,
        imgsz=imgsz,
        intra_op_threads=intra_op_threads,
        inference_conf=inference_conf,
        iou=iou,
        max_det=max_det,
    )
