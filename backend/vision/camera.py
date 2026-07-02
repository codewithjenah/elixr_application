import logging
import sys
import threading
import time
from typing import Optional

import cv2
import numpy as np

from config import CAMERA_FALLBACK_INDEX, CAMERA_INDEX, FRAME_HEIGHT, FRAME_WIDTH

logger = logging.getLogger(__name__)

_CAMERA_LOCK = threading.Lock()
_WARMUP_FRAMES = 30
_RELEASE_DELAY_S = 0.4


def _backends() -> list[int | None]:
    if sys.platform == "win32":
        return [cv2.CAP_MSMF, cv2.CAP_DSHOW, None]
    return [None]


def _indices_to_try(preferred: int) -> list[int]:
    indices = [preferred]
    if preferred != CAMERA_FALLBACK_INDEX:
        indices.append(CAMERA_FALLBACK_INDEX)
    return indices


def _open_video_capture(index: int) -> Optional[cv2.VideoCapture]:
    for api in _backends():
        cap = (
            cv2.VideoCapture(index, api)
            if api is not None
            else cv2.VideoCapture(index)
        )
        if not cap.isOpened():
            cap.release()
            continue

        # Set resolution before warmup — Windows MSMF/DSHOW often ignore this if done after reads.
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        cap.set(cv2.CAP_PROP_FPS, 30)

        for _ in range(_WARMUP_FRAMES):
            cap.read()

        for _ in range(20):
            ok, frame = cap.read()
            if ok and frame is not None and float(frame.mean()) > 1.0:
                api_name = "default" if api is None else str(api)
                actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                logger.info(
                    "Camera %s opened via backend %s (requested %sx%s, actual %sx%s, frame %sx%s)",
                    index,
                    api_name,
                    FRAME_WIDTH,
                    FRAME_HEIGHT,
                    actual_w,
                    actual_h,
                    frame.shape[1],
                    frame.shape[0],
                )
                return cap

        ok, frame = cap.read()
        if ok and frame is not None:
            api_name = "default" if api is None else str(api)
            logger.info("Camera %s opened via backend %s (dim warmup)", index, api_name)
            return cap

        cap.release()

    return None


class CameraCapture:
    def __init__(
        self,
        index: int = CAMERA_INDEX,
        width: int = FRAME_WIDTH,
        height: int = FRAME_HEIGHT,
    ):
        self._index = index
        self._active_index: int | None = None
        self._width = width
        self._height = height
        self._cap: Optional[cv2.VideoCapture] = None

    @property
    def is_open(self) -> bool:
        return self._cap is not None and self._cap.isOpened()

    def open(self) -> bool:
        with _CAMERA_LOCK:
            if self.is_open:
                return True

            for candidate in _indices_to_try(self._index):
                cap = _open_video_capture(candidate)
                if cap is not None:
                    self._cap = cap
                    self._active_index = candidate
                    if candidate != self._index:
                        logger.warning(
                            "Camera index %s unavailable; using fallback index %s",
                            self._index,
                            candidate,
                        )
                    logger.info(
                        "Camera %s ready at %sx%s",
                        self._active_index,
                        self._width,
                        self._height,
                    )
                    return True

            logger.error(
                "Failed to open camera index %s (fallback %s also failed)",
                self._index,
                CAMERA_FALLBACK_INDEX,
            )
            return False

    def read(self) -> Optional[np.ndarray]:
        with _CAMERA_LOCK:
            if not self.is_open:
                return None
            ok, frame = self._cap.read()
            if not ok or frame is None:
                return None
            if frame.shape[1] != self._width or frame.shape[0] != self._height:
                frame = cv2.resize(
                    frame,
                    (self._width, self._height),
                    interpolation=cv2.INTER_AREA,
                )
            return frame

    def release(self) -> None:
        with _CAMERA_LOCK:
            if self._cap is not None:
                self._cap.release()
                self._cap = None
                self._active_index = None
                logger.info("Camera released")
                if sys.platform == "win32":
                    time.sleep(_RELEASE_DELAY_S)
