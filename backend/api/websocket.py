import asyncio
import base64
import json
import logging
import time

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from assessment.hold_validator import HoldValidator
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
_MAX_DEVICE_ID_LENGTH = 1024

SESSION_PREPARED = "prepared"
SESSION_ACTIVE = "active"
SESSION_CLOSED = "closed"


def parse_camera_index(raw) -> tuple[int | None, str | None]:
    """Validate a legacy WebSocket ``camera_index`` value.

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


def parse_camera_device_id(raw) -> tuple[str | None, str | None]:
    """Validate a WebSocket ``camera_device_id`` value.

    Returns ``(camera_device_id, error_code)``.
    ``None`` means Auto-select.
    """
    if raw is None:
        return None, None

    if isinstance(raw, bool) or isinstance(raw, (int, float)):
        return None, "invalid_camera_device_id"

    if isinstance(raw, str):
        value = raw.strip()
        if not value:
            return None, "invalid_camera_device_id"
        if len(value) > _MAX_DEVICE_ID_LENGTH:
            return None, "invalid_camera_device_id"
        return value, None

    return None, "invalid_camera_device_id"


def parse_camera_selection(
    data: dict,
) -> tuple[str | None, int | None, str | None]:
    """Parse camera selection from a prepare/start payload.

    Prefers ``camera_device_id`` when the key is present. Falls back to legacy
    ``camera_index`` for migration. Returns
    ``(camera_device_id, legacy_camera_index, error_code)``.
    """
    if "camera_device_id" in data:
        device_id, error = parse_camera_device_id(data.get("camera_device_id"))
        return device_id, None, error

    if "camera_index" in data:
        camera_index, error = parse_camera_index(data.get("camera_index"))
        return None, camera_index, error

    return None, None, None


def _camera_unavailable_message(
    *,
    camera_device_id: str | None = None,
    camera_index: int | None = None,
) -> tuple[str, str]:
    if camera_device_id is None and camera_index is None:
        return (
            "No usable camera is available. Check that a camera is connected "
            "and not being used by another application.",
            "camera_unavailable",
        )

    label = camera_display_name(
        device_id=camera_device_id,
        runtime_index=camera_index,
    )
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
        camera_device_id: str | None = None,
        bottle_detection_enabled: bool = True,
    ):
        self.movement = movement
        self.camera_index = camera_index
        self.camera_device_id = camera_device_id
        self.bottle_detection_enabled = bottle_detection_enabled

        self.camera = CameraCapture(
            camera_index=camera_index,
            camera_device_id=camera_device_id,
        )
        # Bottle weights load lazily on activate / first evaluated frame.
        self.bottle_detector = BottleDetector(enabled=bottle_detection_enabled)
        # MediaPipe detectors are deferred so prepare can open the camera and
        # stream preview JPEGs before model init cost.
        self.hands_detector: HandsDetector | None = None
        self.pose_detector: PoseDetector | None = None
        self._hands_rotated_fallback = movement in {"Normal Grip", "Claw Grip"}
        self._hands_bartender_roi = movement == "Bartender's Grip"
        self._pose_needed = movement_requires_pose(movement)
        self.scorer = SessionScorer()

        self._frame_index = 0
        self._last_bottles: list[BottleDetection] = []

        # Do not cache hands landmarks.
        # Hands move fast, and caching causes ghost/stuck finger dots.
        self._prev_hip_center: Point2D | None = None
        self._movement_state: dict | None = None
        self._model_checked = False
        self._lifecycle = SESSION_PREPARED
        self._hold_validator = HoldValidator()

    @property
    def lifecycle(self) -> str:
        return self._lifecycle

    @property
    def is_prepared(self) -> bool:
        return self._lifecycle == SESSION_PREPARED

    @property
    def is_active(self) -> bool:
        return self._lifecycle == SESSION_ACTIVE

    def start(self) -> bool:
        return self.camera.open()

    def _ensure_detectors(self) -> None:
        if self.hands_detector is None:
            self.hands_detector = HandsDetector(
                rotated_fallback=self._hands_rotated_fallback,
                bartender_roi_fallback=self._hands_bartender_roi,
            )
        if self._pose_needed and self.pose_detector is None:
            self.pose_detector = PoseDetector()

    def activate(self) -> bool:
        """Transition prepared → active without reopening the camera.

        Returns True when activation succeeded or the session was already
        active (idempotent). Returns False when the session is closed.
        """
        if self._lifecycle == SESSION_ACTIVE:
            return True

        if self._lifecycle != SESSION_PREPARED:
            return False

        self._ensure_detectors()
        self.scorer.reset()
        self._hold_validator.activate()
        self._prev_hip_center = None
        self._movement_state = None
        self._last_bottles = []
        self._frame_index = 0
        self._lifecycle = SESSION_ACTIVE
        return True

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
                camera_ready=False,
                session_state="unavailable",
            )

        return None

    def process_preview_frame(self) -> FeedbackMessage | None:
        """Encode a JPEG preview without model load, evaluation, or scoring."""
        frame = self.camera.read()

        if frame is None:
            return None

        _, buffer = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )

        frame_b64 = base64.b64encode(buffer).decode("ascii")

        return FeedbackMessage(
            bottle_detected=False,
            bottle_count=0,
            movement=self.movement,
            score=self.scorer.score,
            feedback="Preparing camera…",
            feedback_type="positive",
            posture_status="unknown",
            frame_jpeg_base64=frame_b64,
            camera_ready=True,
            session_state="preparing",
        )

    def process_frame(self) -> FeedbackMessage | None:
        self._ensure_detectors()
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
        assert self.hands_detector is not None
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

        hold = self._hold_validator.update(
            feedback_type=rule_result.feedback_type,
            posture_status=rule_result.posture_status,
            session_active=self.is_active,
            timestamp=time.monotonic(),
        )

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
            camera_ready=True,
            session_state="active",
            hold_progress=hold.hold_progress,
            hold_duration_ms=hold.hold_duration_ms,
            hold_confirmed=hold.hold_confirmed,
            positive_frame_ratio=hold.positive_frame_ratio,
        )

    def process_tick(self) -> FeedbackMessage | None:
        if self._lifecycle == SESSION_ACTIVE:
            return self.process_frame()
        if self._lifecycle == SESSION_PREPARED:
            return self.process_preview_frame()
        return None

    def close(self) -> None:
        self._lifecycle = SESSION_CLOSED
        self._hold_validator.reset()
        self.camera.release()
        if self.hands_detector is not None:
            self.hands_detector.close()
        if self.pose_detector is not None:
            self.pose_detector.close()


async def _cv_session_loop(
    websocket: WebSocket,
    movement: str,
    *,
    camera_index: int | None = None,
    camera_device_id: str | None = None,
    bottle_detection_enabled: bool = True,
    session_ref: dict | None = None,
    start_active: bool = False,
):
    try:
        session = VisionSession(
            movement,
            camera_index=camera_index,
            camera_device_id=camera_device_id,
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
            camera_ready=False,
            session_state="unavailable",
        )

        await websocket.send_text(error.model_dump_json())
        return

    if session_ref is not None:
        session_ref["session"] = session

    if not session.start():
        feedback, error_code = _camera_unavailable_message(
            camera_device_id=camera_device_id,
            camera_index=camera_index,
        )
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback=feedback,
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=error_code,
            camera_ready=False,
            session_state="unavailable",
        )

        await websocket.send_text(error.model_dump_json())
        if session_ref is not None:
            session_ref["session"] = None
        session.close()
        return

    if start_active:
        session.activate()

    explicit = camera_device_id is not None or camera_index is not None
    logger.info(
        "Camera selection active: mode=%s requested_device_id=%s "
        "requested_index=%s active_index=%s active_device_id=%s "
        "used_fallback=%s lifecycle=%s",
        "explicit" if explicit else "auto-select",
        camera_device_id,
        camera_index,
        getattr(session.camera, "active_index", None),
        getattr(session.camera, "active_device_id", None),
        getattr(session.camera, "used_fallback", False),
        session.lifecycle,
    )

    interval = 1.0 / TARGET_FPS
    frame_count = 0
    loop_start = time.perf_counter()
    frame_task: asyncio.Task | None = None

    try:
        while True:
            tick = time.perf_counter()

            frame_task = asyncio.create_task(
                asyncio.to_thread(session.process_tick)
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
                    "CV session FPS: %.1f (target=%s, yolo_skip=%s, lifecycle=%s)",
                    actual_fps,
                    TARGET_FPS,
                    YOLO_FRAME_SKIP,
                    session.lifecycle,
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
            camera_ready=False,
            session_state="unavailable",
        )

        await websocket.send_text(error.model_dump_json())

    finally:
        if frame_task is not None and not frame_task.done():
            try:
                await frame_task
            except Exception:
                pass

        if session_ref is not None and session_ref.get("session") is session:
            session_ref["session"] = None

        session.close()


def _parse_session_request(data: dict, movement: str, difficulty: str):
    """Parse shared prepare/start fields. Returns tuple or error FeedbackMessage."""
    movement = data.get("movement", movement)
    difficulty = data.get("difficulty", difficulty)

    bottle_detection_enabled = bool(data.get("bottle_detection_enabled", True))

    camera_device_id, camera_index, camera_error = parse_camera_selection(data)

    if camera_error is not None:
        error = FeedbackMessage(
            bottle_detected=False,
            movement=movement,
            score=0,
            feedback=(
                "Invalid camera selection. Choose Auto-select or a "
                "valid camera in Settings."
            ),
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=camera_error,
            camera_ready=False,
            session_state="unavailable",
        )
        return None, error

    return (
        {
            "movement": movement,
            "difficulty": difficulty,
            "camera_device_id": camera_device_id,
            "camera_index": camera_index,
            "bottle_detection_enabled": bottle_detection_enabled,
        },
        None,
    )


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    session_task: asyncio.Task | None = None
    session_ref: dict = {"session": None}
    movement = "Hand Stall"
    difficulty = "Easy"

    try:
        while True:
            raw = await websocket.receive_text()
            data = json.loads(raw)
            action = data.get("action")

            if action in ("prepare", "start"):
                parsed, error = _parse_session_request(data, movement, difficulty)
                if error is not None:
                    await websocket.send_text(error.model_dump_json())
                    continue

                assert parsed is not None
                movement = parsed["movement"]
                difficulty = parsed["difficulty"]
                camera_device_id = parsed["camera_device_id"]
                camera_index = parsed["camera_index"]
                bottle_detection_enabled = parsed["bottle_detection_enabled"]
                start_active = action == "start"

                await _stop_session_task(session_task)
                session_ref["session"] = None

                session_task = asyncio.create_task(
                    _cv_session_loop(
                        websocket,
                        movement,
                        camera_index=camera_index,
                        camera_device_id=camera_device_id,
                        bottle_detection_enabled=bottle_detection_enabled,
                        session_ref=session_ref,
                        start_active=start_active,
                    )
                )

                explicit = (
                    camera_device_id is not None or camera_index is not None
                )
                logger.info(
                    "CV session %s: %s (%s, bottle_detection=%s, "
                    "camera_mode=%s, camera_device_id=%s, camera_index=%s)",
                    "started" if start_active else "prepared",
                    movement,
                    difficulty,
                    bottle_detection_enabled,
                    "explicit" if explicit else "auto-select",
                    camera_device_id,
                    camera_index,
                )

            elif action == "activate":
                session = session_ref.get("session")
                if session is None or not (
                    session.is_prepared or session.is_active
                ):
                    error = FeedbackMessage(
                        bottle_detected=False,
                        movement=movement,
                        score=0,
                        feedback=(
                            "No prepared camera session to activate. "
                            "Start again to prepare the camera."
                        ),
                        feedback_type="error",
                        posture_status="unknown",
                        frame_jpeg_base64=None,
                        error_code="session_not_prepared",
                        camera_ready=False,
                        session_state="unavailable",
                    )
                    await websocket.send_text(error.model_dump_json())
                    continue

                activated = session.activate()
                logger.info(
                    "CV session activate: movement=%s ok=%s lifecycle=%s",
                    movement,
                    activated,
                    session.lifecycle,
                )

            elif action == "stop":
                await _stop_session_task(session_task)
                session_task = None
                session_ref["session"] = None

                logger.info("CV session stopped")

            else:
                logger.warning("Ignoring unknown WebSocket action: %s", action)
    except WebSocketDisconnect:
        logger.info("Client disconnected")

    finally:
        await _stop_session_task(session_task)
        session_ref["session"] = None
        release_shared_camera()
