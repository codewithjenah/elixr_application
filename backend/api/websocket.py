import asyncio
import base64
import json
import logging
import time

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from assessment.rule_engine import evaluate_movement, movement_requires_hands
from assessment.scoring import SessionScorer
from config import (
    FPS_LOG_INTERVAL,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    JPEG_QUALITY,
    POSE_FRAME_SKIP,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
)
from schemas.feedback import FeedbackMessage
from vision.annotator import annotate_frame
from vision.bottle_detector import BottleDetector, ModelLoadError
from vision.camera import CameraCapture
from vision.hands_detector import HandsDetector
from vision.pose_detector import PoseDetector
from vision.types import BottleDetection, Point2D

router = APIRouter()
logger = logging.getLogger(__name__)

CAMERA_REOPEN_DELAY_S = 0.5


async def _stop_session_task(session_task: asyncio.Task | None) -> None:
    if session_task is None or session_task.done():
        return
    session_task.cancel()
    try:
        await session_task
    except asyncio.CancelledError:
        pass
    await asyncio.sleep(CAMERA_REOPEN_DELAY_S)


class VisionSession:
    def __init__(self, movement: str, *, bottle_detection_enabled: bool = True):
        self.movement = movement
        self.bottle_detection_enabled = bottle_detection_enabled
        self.camera = CameraCapture()
        self.bottle_detector = BottleDetector(enabled=bottle_detection_enabled)
        self.pose_detector = PoseDetector()
        self.hands_detector = HandsDetector()
        self.scorer = SessionScorer()
        self._frame_index = 0
        self._last_bottle: BottleDetection | None = None
        self._last_pose = None
        self._last_hands = None
        self._prev_hip_center: Point2D | None = None
        self._movement_state: dict | None = None
        self._model_checked = False

    def start(self) -> bool:
        return self.camera.open()

    def _check_model(self) -> FeedbackMessage | None:
        if not self.bottle_detection_enabled:
            return None
        if self._model_checked:
            return None
        self._model_checked = True
        try:
            self.bottle_detector._ensure_model()
        except ModelLoadError:
            return FeedbackMessage(
                bottle_detected=False,
                movement=self.movement,
                score=0,
                feedback="Model load failed. Check that yolo11n.pt can download and ultralytics is installed.",
                feedback_type="error",
                posture_status="unknown",
                frame_jpeg_base64=None,
                error_code="model_load_failed",
            )
        return None

    def process_frame(self) -> FeedbackMessage | None:
        model_error = self._check_model()
        if model_error is not None:
            return model_error

        frame = self.camera.read()
        if frame is None:
            return None

        self._frame_index += 1
        run_yolo = self._frame_index % YOLO_FRAME_SKIP == 0
        run_pose = self._frame_index % POSE_FRAME_SKIP == 0

        bottle = self._last_bottle
        if self.bottle_detection_enabled and run_yolo:
            bottle = self.bottle_detector.detect(frame)
            self._last_bottle = bottle
        elif not self.bottle_detection_enabled:
            bottle = None
            self._last_bottle = None

        if run_pose:
            detected_pose = self.pose_detector.detect(frame)
            if detected_pose is not None:
                self._last_pose = detected_pose
        pose = self._last_pose

        if movement_requires_hands(self.movement):
            detected_hands = self.hands_detector.detect(frame)
            if detected_hands is not None:
                self._last_hands = detected_hands
        hands = self._last_hands if movement_requires_hands(self.movement) else None

        rule_result, self._prev_hip_center, self._movement_state = evaluate_movement(
            self.movement,
            bottle,
            pose,
            hands,
            self._prev_hip_center,
            self._movement_state,
            bottle_detection_enabled=self.bottle_detection_enabled,
        )
        self.scorer.record(rule_result.feedback_type)

        annotated = annotate_frame(
            frame,
            bottle,
            pose,
            hands,
            rule_result.feedback,
            rule_result.feedback_type,
            self.movement,
            self.scorer.score,
        )
        _, buffer = cv2.imencode(
            ".jpg", annotated, [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY]
        )
        frame_b64 = base64.b64encode(buffer).decode("ascii")

        return FeedbackMessage(
            bottle_detected=bottle is not None,
            movement=self.movement,
            score=self.scorer.score,
            feedback=rule_result.feedback,
            feedback_type=rule_result.feedback_type,
            posture_status=rule_result.posture_status,
            frame_jpeg_base64=frame_b64,
        )

    def close(self) -> None:
        self.camera.release()
        self.pose_detector.close()
        self.hands_detector.close()


async def _cv_session_loop(
    websocket: WebSocket,
    movement: str,
    difficulty: str,
    *,
    bottle_detection_enabled: bool = True,
):
    try:
        session = VisionSession(
            movement,
            bottle_detection_enabled=bottle_detection_enabled,
        )
    except Exception:
        logger.exception("Failed to initialize vision session")
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback=(
                "Vision pipeline failed to start. From the backend folder run "
                ".\\run.ps1 (or backend\\.venv\\Scripts\\python.exe -m uvicorn "
                "main:app --host 127.0.0.1 --port 8000). Check backend logs for details."
            ),
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code="pipeline_init_failed",
        )
        await websocket.send_text(error.model_dump_json())
        return

    if not session.start():
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback="Camera unavailable. Check that a webcam is connected.",
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code="camera_unavailable",
        )
        await websocket.send_text(error.model_dump_json())
        session.close()
        return

    interval = 1.0 / TARGET_FPS
    frame_count = 0
    loop_start = time.perf_counter()
    frame_task: asyncio.Task | None = None
    try:
        while True:
            tick = time.perf_counter()
            frame_task = asyncio.create_task(asyncio.to_thread(session.process_frame))
            try:
                message = await frame_task
            except asyncio.CancelledError:
                if not frame_task.done():
                    await frame_task
                raise
            frame_task = None

            if message is not None:
                if message.error_code == "model_load_failed":
                    await websocket.send_text(message.model_dump_json())
                    break
                await websocket.send_text(message.model_dump_json())

            frame_count += 1
            if frame_count % FPS_LOG_INTERVAL == 0:
                elapsed = time.perf_counter() - loop_start
                actual_fps = frame_count / elapsed if elapsed > 0 else 0
                logger.info(
                    "CV session FPS: %.1f (target=%s, yolo_skip=%s)",
                    actual_fps,
                    TARGET_FPS,
                    YOLO_FRAME_SKIP,
                )

            processing = time.perf_counter() - tick
            sleep_time = max(0.0, interval - processing)
            await asyncio.sleep(sleep_time)
    except asyncio.CancelledError:
        raise
    except Exception:
        logger.exception("CV session loop failed")
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback="Vision pipeline error. Check backend logs for details.",
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code="pipeline_error",
        )
        await websocket.send_text(error.model_dump_json())
    finally:
        if frame_task is not None and not frame_task.done():
            try:
                await frame_task
            except Exception:
                pass
        session.close()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    session_task: asyncio.Task | None = None
    movement = "Hand Stall"
    difficulty = "Easy"

    try:
        while True:
            raw = await websocket.receive_text()
            data = json.loads(raw)
            action = data.get("action")

            if action == "start":
                movement = data.get("movement", movement)
                difficulty = data.get("difficulty", difficulty)
                bottle_detection_enabled = bool(
                    data.get("bottle_detection_enabled", True)
                )

                await _stop_session_task(session_task)
                session_task = asyncio.create_task(
                    _cv_session_loop(
                        websocket,
                        movement,
                        difficulty,
                        bottle_detection_enabled=bottle_detection_enabled,
                    )
                )
                logger.info(
                    "CV session started: %s (%s, bottle_detection=%s)",
                    movement,
                    difficulty,
                    bottle_detection_enabled,
                )

            elif action == "stop":
                await _stop_session_task(session_task)
                session_task = None
                logger.info("CV session stopped")

    except WebSocketDisconnect:
        logger.info("Client disconnected")
    finally:
        await _stop_session_task(session_task)
