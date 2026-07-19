import logging
from typing import Optional

import numpy as np
from ultralytics import YOLO

from config import CUSTOM_BOTTLE_CLASS_ID, MAX_BOTTLES, YOLO_CONFIDENCE, YOLO_IOU
from vision.types import BottleDetection

logger = logging.getLogger(__name__)


class ModelLoadError(Exception):
    pass


class BottleDetector:
    def __init__(
        self,
        model_name: str = "best.pt",
        confidence: float = YOLO_CONFIDENCE,
        enabled: bool = True,
    ):
        self._confidence = confidence
        self._model: Optional[YOLO] = None
        self._model_name = model_name
        self._load_failed = False
        self._enabled = enabled

    @property
    def enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = enabled

    @property
    def load_failed(self) -> bool:
        return self._load_failed

    def ensure_ready(self) -> None:
        """Load the model now, raising ModelLoadError on failure."""
        self._ensure_model()

    def _ensure_model(self) -> YOLO:
        if self._load_failed:
            raise ModelLoadError(f"YOLO model {self._model_name} failed to load")

        if self._model is None:
            logger.info("Loading YOLO model %s", self._model_name)

            try:
                self._model = YOLO(self._model_name)
                logger.info("Loaded YOLO classes: %s", self._model.names)
            except Exception as exc:
                self._load_failed = True
                logger.exception("Failed to load YOLO model %s", self._model_name)
                raise ModelLoadError(str(exc)) from exc

        return self._model

    def detect(self, frame: np.ndarray) -> list[BottleDetection]:
        """Return up to MAX_BOTTLES detections, highest confidence first."""
        if not self._enabled:
            return []

        try:
            model = self._ensure_model()
        except ModelLoadError:
            return []

        try:
            results = model(
                frame,
                verbose=False,
                conf=self._confidence,
                iou=YOLO_IOU,
                max_det=MAX_BOTTLES,
            )
        except Exception:
            logger.exception("YOLO inference failed")
            return []

        detections: list[BottleDetection] = []

        for result in results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                cls_id = int(box.cls[0])

                # Your custom Roboflow YOLO model uses:
                # class 0 = flair_bottle
                if cls_id != CUSTOM_BOTTLE_CLASS_ID:
                    continue

                conf = float(box.conf[0])
                x1, y1, x2, y2 = (int(v) for v in box.xyxy[0].tolist())

                detections.append(
                    BottleDetection(
                        x1=x1,
                        y1=y1,
                        x2=x2,
                        y2=y2,
                        confidence=conf,
                    )
                )

        detections.sort(key=lambda d: d.confidence, reverse=True)
        return detections[:MAX_BOTTLES]