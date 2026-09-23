"""Optional bottle top/base inference using a validated YOLO pose ONNX export.

The model is warmed once per custom session, never for official movements.
DirectML is selected when available; ONNX CPU is the fallback. Prop detection
and identity remain owned by the existing combined detector.
"""

from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path
import time
from typing import Any

import numpy as np

from config import (
    BOTTLE_ORIENTATION_MANIFEST_PATH,
    BOTTLE_ORIENTATION_ONNX_PATH,
    YOLO_DML_DEVICE_ID,
    YOLO_ONNX_INTRA_OP_THREADS,
)
from vision.bottle_orientation import BottleKeypoint, BottleOrientation
from vision.prop_inference import (
    ModelLoadError,
    default_onnx_session_factory,
    default_onnx_session_options,
    dml_is_available,
    parse_onnx_class_names,
    parse_onnx_static_input_hw,
)
from vision.types import PropDetection


logger = logging.getLogger(__name__)


def validated_orientation_asset(
    onnx_path: Path = BOTTLE_ORIENTATION_ONNX_PATH,
    manifest_path: Path = BOTTLE_ORIENTATION_MANIFEST_PATH,
) -> bool:
    """A file alone does not opt an unvalidated model into live assessment."""
    if not onnx_path.is_file() or not manifest_path.is_file():
        return False
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        return (
            manifest.get("validated") is True
            and manifest.get("task") == "pose"
            and manifest.get("keypoints") == ["top", "base"]
            and manifest.get("sha256") == hashlib.sha256(onnx_path.read_bytes()).hexdigest()
        )
    except (OSError, ValueError, TypeError):
        return False


def _parse_pose_rows(
    raw: np.ndarray,
    *,
    letterboxed_hw: tuple[int, int],
    frame_hw: tuple[int, int],
    prop: PropDetection,
) -> BottleOrientation | None:
    """Decode Ultralytics 8.4 pose output after NMS; associate to confirmed prop."""
    import torch
    from ultralytics.utils import nms
    from ultralytics.utils.ops import scale_boxes, scale_coords

    prediction = torch.from_numpy(np.ascontiguousarray(raw))
    if prediction.ndim == 2:
        prediction = prediction.unsqueeze(0)
    if prediction.ndim != 3 or prediction.shape[1] != 11:
        raise ModelLoadError("Bottle orientation ONNX output must contain one class and two xyz keypoints")
    rows = nms.non_max_suppression(
        prediction, conf_thres=0.4, iou_thres=0.45, max_det=2, nc=1
    )[0]
    if rows is None or len(rows) == 0:
        return None
    best: tuple[float, BottleOrientation] | None = None
    height, width = frame_hw
    for row in rows:
        if len(row) != 12:  # xyxy, confidence, class, 2 * (x,y,confidence)
            raise ModelLoadError("Bottle orientation pose row has invalid keypoint shape")
        box = scale_boxes(letterboxed_hw, row[:4].clone().unsqueeze(0), frame_hw)[0]
        left = max(float(box[0]), prop.x1)
        top_y = max(float(box[1]), prop.y1)
        right = min(float(box[2]), prop.x2)
        bottom = min(float(box[3]), prop.y2)
        intersection = max(0.0, right - left) * max(0.0, bottom - top_y)
        prop_area = max(1.0, float((prop.x2 - prop.x1) * (prop.y2 - prop.y1)))
        pose_area = max(1.0, float((box[2] - box[0]) * (box[3] - box[1])))
        if intersection / prop_area < 0.45 or intersection / pose_area < 0.45:
            continue
        points = row[6:].clone().reshape(2, 3)
        points[:, :2] = scale_coords(letterboxed_hw, points[:, :2], frame_hw)
        top = BottleKeypoint(float(points[0, 0]) / width, float(points[0, 1]) / height, float(points[0, 2]))
        base = BottleKeypoint(float(points[1, 0]) / width, float(points[1, 1]) / height, float(points[1, 2]))
        margin_x = 0.1 * (prop.x2 - prop.x1)
        margin_y = 0.1 * (prop.y2 - prop.y1)
        if any(
            not (
                prop.x1 - margin_x <= point.x * width <= prop.x2 + margin_x
                and prop.y1 - margin_y <= point.y * height <= prop.y2 + margin_y
            )
            for point in (top, base)
        ):
            continue
        observation = BottleOrientation.observed(
            top, base, float(row[4]), image_aspect_ratio=width / height,
        )
        if observation is not None:
            rank = float(row[4]) * intersection / prop_area
            if best is None or rank > best[0]:
                best = (rank, observation)
    return best[1] if best else None


class BottleOrientationDetector:
    def __init__(
        self,
        *,
        onnx_path: Path = BOTTLE_ORIENTATION_ONNX_PATH,
        manifest_path: Path = BOTTLE_ORIENTATION_MANIFEST_PATH,
        session_factory=default_onnx_session_factory,
    ) -> None:
        self.onnx_path = onnx_path
        self.manifest_path = manifest_path
        self._session_factory = session_factory
        self._session: Any = None
        self._letterbox: Any = None
        self._input_name = "images"
        self._output_name = "output0"
        self._input_hw = (0, 0)
        self.provider = ""
        self.last_inference_ms = 0.0
        self._force_cpu = False

    @property
    def available(self) -> bool:
        return validated_orientation_asset(self.onnx_path, self.manifest_path)

    def ensure_ready(self) -> None:
        if self._session is not None:
            return
        if not self.available:
            raise ModelLoadError("Validated bottle orientation model unavailable")
        dml = dml_is_available() and not self._force_cpu
        providers: list[Any] = ["CPUExecutionProvider"]
        if dml:
            providers.insert(0, ("DmlExecutionProvider", {"device_id": YOLO_DML_DEVICE_ID}))
        def open_session(selected_providers: list[Any]):
            return self._session_factory(
                self.onnx_path,
                default_onnx_session_options(YOLO_ONNX_INTRA_OP_THREADS, directml=selected_providers[0] != "CPUExecutionProvider"),
                selected_providers,
            )
        try:
            session = open_session(providers)
        except Exception:
            if not dml:
                raise
            logger.warning("Bottle orientation DirectML initialization failed; using ONNX CPU", exc_info=True)
            providers = ["CPUExecutionProvider"]
            session = open_session(providers)
        inputs, outputs = session.get_inputs(), session.get_outputs()
        if len(inputs) != 1 or len(outputs) != 1:
            raise ModelLoadError("Bottle orientation ONNX must have one input and one output")
        self._input_hw = parse_onnx_static_input_hw(inputs[0].shape)
        metadata = dict(getattr(session.get_modelmeta(), "custom_metadata_map", {}) or {})
        if metadata.get("task") != "pose" or metadata.get("kpt_shape") not in {"[2, 3]", "(2, 3)"}:
            raise ModelLoadError("Bottle orientation ONNX must declare pose task and [2,3] keypoints")
        if parse_onnx_class_names(metadata) != {0: "bottle"}:
            raise ModelLoadError("Bottle orientation ONNX must declare one bottle class")
        from ultralytics.data.augment import LetterBox
        self._letterbox = LetterBox(self._input_hw, auto=False, stride=32)
        self._input_name = inputs[0].name
        self._output_name = outputs[0].name
        self._session = session
        self.provider = session.get_providers()[0]
        logger.info("Bottle orientation runtime provider=%s input_hw=%s", self.provider, self._input_hw)

    def observe(self, frame: np.ndarray, prop: PropDetection) -> BottleOrientation | None:
        self.ensure_ready()
        start = time.perf_counter()
        letterboxed = self._letterbox(image=frame)
        blob = np.ascontiguousarray(letterboxed[:, :, ::-1].transpose(2, 0, 1), dtype=np.float32)[None]
        blob /= 255.0
        try:
            raw = self._session.run([self._output_name], {self._input_name: blob})[0]
        except Exception:
            if self.provider != "DmlExecutionProvider":
                raise
            logger.warning("Bottle orientation DirectML inference failed; retrying once on ONNX CPU", exc_info=True)
            self.close()
            self._force_cpu = True
            self.ensure_ready()
            raw = self._session.run([self._output_name], {self._input_name: blob})[0]
        observation = _parse_pose_rows(
            raw,
            letterboxed_hw=letterboxed.shape[:2],
            frame_hw=frame.shape[:2],
            prop=prop,
        )
        self.last_inference_ms = (time.perf_counter() - start) * 1000
        return observation

    def close(self) -> None:
        self._session = None
        self._letterbox = None
