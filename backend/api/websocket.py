import asyncio
import base64
import json
import logging
import time

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from assessment.rule_engine import (
    evaluate_movement,
    movement_requires_hands,
    movement_requires_pose,
)
from assessment.scoring import SessionScorer
from config import (
    FPS_LOG_INTERVAL,
    JPEG_QUALITY,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
)
from schemas.feedback import FeedbackMessage
from vision.annotator import annotate_frame
from vision.bottle_detector import BottleDetector, ModelLoadError
from vision.camera import CameraCapture, camera_display_name, release_shared_camera
from vision.hands_detector import HandsDetector
from vision.pose_detector import PoseDetector
from vision.types import BottleDetection, Point2D

router = APIRouter()
logger = logging.getLogger(__name__)

CAMERA_REOPEN_DELAY_S = 0.75
_MAX_CAMERA_INDEX = 10


def parse_camera_index(raw) -> tuple[int | None, str | None]:
    """Validate a WebSocket ``camera_index`` value.

    Returns ``(camera_index, error_code)``.
    ``None`` camera_index means Auto-select.
    """
    if raw is None:
        return None, None

    if isinstance(raw, bool):
        return None, "invalid_camera_index"

    if isinstance(raw, int):
        if raw < 0 or raw > _MAX_CAMERA_INDEX:
            return None, "invalid_camera_index"
        return raw, None

    if isinstance(raw, float):
        if not raw.is_integer():
            return None, "invalid_camera_index"
        as_int = int(raw)
        if as_int < 0 or as_int > _MAX_CAMERA_INDEX:
            return None, "invalid_camera_index"
        return as_int, None

    return None, "invalid_camera_index"


def _camera_unavailable_message(camera_index: int | None) -> tuple[str, str]:
    if camera_index is None:
        return (
            "No usable camera is available. Check that a camera is connected "
            "and not being used by another application.",
            "camera_unavailable",
        )

    label = camera_display_name(camera_index)
    return (
        f"{label} is unavailable. Reconnect it, choose another "
        "camera in Settings, or use Auto-select.",
        "selected_camera_unavailable",
    )


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
    def __init__(
        self,
        movement: str,
        *,
        camera_index: int | None = None,
        bottle_detection_enabled: bool = True,
    ):
        self.movement = movement
        self.camera_index = camera_index
        self.bottle_detection_enabled = bottle_detection_enabled

        self.camera = CameraCapture(camera_index=camera_index)
        self.bottle_detector = BottleDetector(enabled=bottle_detection_enabled)
        self.hands_detector = HandsDetector(
            rotated_fallback=movement == "Normal Grip",
            bartender_roi_fallback=movement == "Bartender's Grip",
        )
        # Pose is enabled for every movement with requires_pose in MOVEMENT_CONFIG
        # (hand/arm/elbow/upper-forearm/shoulder stalls).
        self.pose_detector = (
            PoseDetector() if movement_requires_pose(movement) else None
        )
        self.scorer = SessionScorer()

        self._frame_index = 0
        self._last_bottles: list[BottleDetection] = []

        # Do not cache hands landmarks.
        # Hands move fast, and caching causes ghost/stuck finger dots.
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
            self.bottle_detector.ensure_ready()
        except ModelLoadError:
            return FeedbackMessage(
                bottle_detected=False,
                movement=self.movement,
                score=0,
                feedback=(
                    "Model load failed. Check that best.pt exists in the backend "
                    "folder and ultralytics is installed."
                ),
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

        # Frame index starts at 1; subtract 1 so the very first frame runs YOLO.
        run_yolo = (self._frame_index - 1) % YOLO_FRAME_SKIP == 0

        bottles = self._last_bottles

        if self.bottle_detection_enabled and run_yolo:
            bottles = self.bottle_detector.detect(frame)
            self._last_bottles = bottles
        elif not self.bottle_detection_enabled:
            bottles = []
            self._last_bottles = []

        # Score on the highest-confidence bottle for single-bottle movements.
        # Double Hand Stall also receives the full detection list via `bottles`.
        bottle = bottles[0] if bottles else None

        # Important fix:
        # Do not use previous hand landmarks when the current frame has no hand.
        # This prevents "naiiwan yung daliri" / ghost hand dots.
        if movement_requires_hands(self.movement):
            hands = self.hands_detector.detect(
                frame,
                bottle=bottle,
            )
        else:
            hands = None

        pose = self.pose_detector.detect(frame) if self.pose_detector else None

        rule_result, self._prev_hip_center, self._movement_state = evaluate_movement(
            self.movement,
            bottle,
            pose,
            hands,
            self._prev_hip_center,
            self._movement_state,
            bottle_detection_enabled=self.bottle_detection_enabled,
            bottles=bottles if self.bottle_detection_enabled else None,
        )

        self.scorer.record(rule_result.feedback_type)

        annotated = annotate_frame(
            frame,
            bottles,
            hands,
            rule_result.feedback,
            rule_result.feedback_type,
            self.movement,
            self.scorer.score,
            pose=pose,
        )

        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )

        frame_b64 = base64.b64encode(buffer).decode("ascii")

        return FeedbackMessage(
            bottle_detected=len(bottles) > 0,
            bottle_count=len(bottles),
            movement=self.movement,
            score=self.scorer.score,
            feedback=rule_result.feedback,
            feedback_type=rule_result.feedback_type,
            posture_status=rule_result.posture_status,
            frame_jpeg_base64=frame_b64,
        )

    def close(self) -> None:
        self.camera.release()
        self.hands_detector.close()
        if self.pose_detector is not None:
            self.pose_detector.close()


async def _cv_session_loop(
    websocket: WebSocket,
    movement: str,
    *,
    camera_index: int | None = None,
    bottle_detection_enabled: bool = True,
):
    try:
        session = VisionSession(
            movement,
            camera_index=camera_index,
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
        feedback, error_code = _camera_unavailable_message(camera_index)
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback=feedback,
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=error_code,
        )

        await websocket.send_text(error.model_dump_json())
        session.close()
        return

    logger.info(
        "Camera selection active: mode=%s requested=%s active_index=%s "
        "used_fallback=%s",
        "auto-select" if camera_index is None else "explicit",
        camera_index,
        session.camera.active_index,
        session.camera.used_fallback,
    )

    interval = 1.0 / TARGET_FPS
    frame_count = 0
    loop_start = time.perf_counter()
    frame_task: asyncio.Task | None = None

    try:
        while True:
            tick = time.perf_counter()

            frame_task = asyncio.create_task(
                asyncio.to_thread(session.process_frame)
            )

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

                camera_index, camera_error = parse_camera_index(
                    data.get("camera_index")
                )

                if camera_error is not None:
                    error = FeedbackMessage(
                        bottle_detected=False,
                        movement=movement,
                        score=0,
                        feedback=(
                            "Invalid camera selection. Choose Auto-select or a "
                            "valid camera index in Settings."
                        ),
                        feedback_type="error",
                        posture_status="unknown",
                        frame_jpeg_base64=None,
                        error_code=camera_error,
                    )
                    await websocket.send_text(error.model_dump_json())
                    continue

                await _stop_session_task(session_task)

                session_task = asyncio.create_task(
                    _cv_session_loop(
                        websocket,
                        movement,
                        camera_index=camera_index,
                        bottle_detection_enabled=bottle_detection_enabled,
                    )
                )

                logger.info(
                    "CV session started: %s (%s, bottle_detection=%s, "
                    "camera_mode=%s, camera_index=%s)",
                    movement,
                    difficulty,
                    bottle_detection_enabled,
                    "auto-select" if camera_index is None else "explicit",
                    camera_index,
                )

            elif action == "stop":
                await _stop_session_task(session_task)
                session_task = None

                logger.info("CV session stopped")

    except WebSocketDisconnect:
        logger.info("Client disconnected")

    finally:
        await _stop_session_task(session_task)
        release_shared_camera()
