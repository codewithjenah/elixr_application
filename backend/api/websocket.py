import asyncio
import base64
import json
import logging
import time
from typing import Any, Awaitable, Callable

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from assessment.hold_validator import HoldValidator
from assessment.rule_engine import (
    evaluate_movement,
    movement_requires_hands,
    movement_requires_pose,
    validate_movement_difficulty,
)
from assessment.scoring import SessionScorer
from config import (
    FPS_LOG_INTERVAL,
    JPEG_QUALITY,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
)
from schemas.commands import (
    PROTOCOL_VERSION,
    ActivateCommand,
    PrepareCommand,
    PropType,
    StartCommand,
    StopCommand,
    parse_v1_command,
)
from schemas.feedback import FeedbackMessage
from schemas.protocol import CommandAck, ProtocolError
from vision.annotator import annotate_frame
from vision.bottle_detector import BottleDetector, ModelLoadError
from vision.prop_detector import PropDetector
from vision.camera import CameraCapture, camera_display_name, release_shared_camera
from vision.hands_detector import HandsDetector
from vision.pose_detector import PoseDetector
from vision.types import Point2D, PropDetection

router = APIRouter()
logger = logging.getLogger(__name__)

CAMERA_REOPEN_DELAY_S = 0.75
_MAX_CAMERA_INDEX = 10
_MAX_DEVICE_ID_LENGTH = 1024

SESSION_PREPARED = "prepared"
SESSION_ACTIVE = "active"
SESSION_CLOSED = "closed"

SendText = Callable[[str], Awaitable[None]]


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


def parse_prop_type(raw: Any) -> tuple[PropType, str | None]:
    """Parse the optional prop field used by legacy prepare/start payloads."""
    if raw is None:
        return "bottle", None
    if isinstance(raw, str) and raw.strip() in {"bottle", "shaker"}:
        return raw.strip(), None
    return "bottle", "invalid_prop_type"


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


def _extract_optional_id(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None
    value = raw.strip()
    if not value or len(value) > 128:
        return None
    return value


def _validation_error_code(exc: ValidationError) -> str:
    for err in exc.errors():
        loc = tuple(str(part) for part in err.get("loc", ()))
        msg = str(err.get("msg", ""))
        err_type = str(err.get("type", ""))

        if "invalid_camera_device_id" in msg:
            return "invalid_camera_device_id"
        if "invalid_camera_index" in msg:
            return "invalid_camera_index"
        if "bottle_detection_enabled" in loc:
            return "invalid_boolean"
        if "protocol_version" in loc:
            return "unsupported_protocol_version"
        if "request_id" in loc:
            return "missing_request_id"
        if "session_id" in loc:
            return "missing_session_id"
        if "camera_index" in loc:
            return "invalid_camera_index"
        if "camera_device_id" in loc:
            return "invalid_camera_device_id"
        if "prop_type" in loc:
            return "invalid_prop_type"
        if err_type.startswith("bool_type") or "bool" in err_type:
            return "invalid_boolean"
    return "invalid_command"


def _human_error_message(error_code: str) -> str:
    return {
        "invalid_json": "The WebSocket message is not valid JSON.",
        "invalid_command": "The WebSocket command is invalid.",
        "unsupported_protocol_version": "Unsupported WebSocket protocol version.",
        "missing_request_id": "A non-empty request_id is required.",
        "missing_session_id": "A non-empty session_id is required.",
        "unknown_action": "Unknown WebSocket action.",
        "invalid_movement": "Unknown or unsupported movement name.",
        "difficulty_mismatch": (
            "Difficulty does not match the configured movement difficulty."
        ),
        "invalid_boolean": "Boolean fields must be true or false JSON booleans.",
        "invalid_camera_device_id": "Invalid camera_device_id.",
        "invalid_camera_index": "Invalid camera_index.",
        "invalid_prop_type": (
            "Invalid prop_type. Choose 'bottle' or 'shaker'."
        ),
        "camera_unavailable": (
            "No usable camera is available. Check that a camera is connected "
            "and not being used by another application."
        ),
        "selected_camera_unavailable": (
            "Selected camera is unavailable. Reconnect it, choose another "
            "camera in Settings, or use Auto-select."
        ),
        "session_not_prepared": "No matching prepared session is available.",
        "session_id_mismatch": "The session_id does not match the current session.",
        "pipeline_init_failed": "Vision pipeline failed to start.",
        "model_load_failed": "Model load failed.",
        "pipeline_error": "Vision pipeline error.",
    }.get(error_code, "The WebSocket command was rejected.")


class VisionSession:
    def __init__(
        self,
        movement: str,
        *,
        prop_type: PropType = "bottle",
        camera_index: int | None = None,
        camera_device_id: str | None = None,
        bottle_detection_enabled: bool = True,
        session_id: str | None = None,
    ):
        if prop_type not in {"bottle", "shaker"}:
            raise ValueError("invalid_prop_type")

        self.movement = movement
        self.prop_type = prop_type
        self.prop_display_name = (
            "Cocktail Shaker" if prop_type == "shaker" else "Bottle"
        )
        self.camera_index = camera_index
        self.camera_device_id = camera_device_id
        self.bottle_detection_enabled = bottle_detection_enabled
        self.session_id = session_id

        self.camera = CameraCapture(
            camera_index=camera_index,
            camera_device_id=camera_device_id,
        )
        # Prop weights load lazily on the first evaluated frame. Keep the
        # bottle wrapper for compatibility with older tests/scripts.
        if prop_type == "bottle":
            self.prop_detector = BottleDetector(enabled=bottle_detection_enabled)
        else:
            self.prop_detector = PropDetector(
                prop_type=prop_type,
                enabled=bottle_detection_enabled,
            )
        self.bottle_detector = self.prop_detector
        # MediaPipe detectors are deferred so prepare can open the camera and
        # stream preview JPEGs before model init cost.
        self.hands_detector: HandsDetector | None = None
        self.pose_detector: PoseDetector | None = None
        self._hands_rotated_fallback = movement in {"Normal Grip", "Claw Grip"}
        self._hands_bartender_roi = movement == "Bartender's Grip"
        self._pose_needed = movement_requires_pose(movement)
        self.scorer = SessionScorer()

        self._frame_index = 0
        self._last_bottles: list[PropDetection] = []

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

    def _stamp(self, message: FeedbackMessage) -> FeedbackMessage:
        return message.with_session(self.session_id)

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
            self.prop_detector.ensure_ready()
        except ModelLoadError:
            return self._stamp(
                FeedbackMessage(
                    bottle_detected=False,
                    prop_type=self.prop_type,
                    movement=self.movement,
                    score=0,
                    feedback=(
                        f"{self.prop_display_name} model load failed. "
                        "Check the backend model files and ultralytics installation."
                    ),
                    feedback_type="error",
                    posture_status="unknown",
                    frame_jpeg_base64=None,
                    error_code="model_load_failed",
                    camera_ready=False,
                    session_state="unavailable",
                )
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

        return self._stamp(
            FeedbackMessage(
                bottle_detected=False,
                bottle_count=0,
                prop_type=self.prop_type,
                movement=self.movement,
                score=self.scorer.score,
                feedback="Preparing camera…",
                feedback_type="positive",
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="preparing",
            )
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
            bottles = self.prop_detector.detect(frame)
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
            prop_type=self.prop_type,
            prop_label=self.prop_display_name,
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
            prop_label=self.prop_display_name,
        )

        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )

        frame_b64 = base64.b64encode(buffer).decode("ascii")

        return self._stamp(
            FeedbackMessage(
                bottle_detected=len(bottles) > 0,
                bottle_count=len(bottles),
                prop_type=self.prop_type,
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


def _signal_prepare_gate(
    prepare_gate: dict | None,
    *,
    ok: bool,
    error_code: str | None = None,
    message: str | None = None,
) -> None:
    if prepare_gate is None:
        return
    if prepare_gate.get("signaled"):
        return
    prepare_gate["ok"] = ok
    prepare_gate["error_code"] = error_code
    prepare_gate["message"] = message
    prepare_gate["signaled"] = True
    event = prepare_gate.get("event")
    if event is not None and not event.is_set():
        event.set()


async def _cv_session_loop(
    websocket: WebSocket,
    movement: str,
    *,
    prop_type: PropType = "bottle",
    camera_index: int | None = None,
    camera_device_id: str | None = None,
    bottle_detection_enabled: bool = True,
    session_ref: dict | None = None,
    start_active: bool = False,
    session_id: str | None = None,
    prepare_gate: dict | None = None,
    send_text: SendText | None = None,
):
    async def _send(payload: str) -> None:
        if send_text is not None:
            await send_text(payload)
        else:
            await websocket.send_text(payload)

    try:
        session = VisionSession(
            movement,
            prop_type=prop_type,
            camera_index=camera_index,
            camera_device_id=camera_device_id,
            bottle_detection_enabled=bottle_detection_enabled,
            session_id=session_id,
        )
    except Exception:
        logger.exception("Failed to initialize vision session")

        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
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
        ).with_session(session_id)

        _signal_prepare_gate(
            prepare_gate,
            ok=False,
            error_code="pipeline_init_failed",
            message=error.feedback,
        )
        await _send(error.model_dump_json())
        return

    if session_ref is not None:
        session_ref["session"] = session
        session_ref["session_id"] = session_id

    if not session.start():
        feedback, error_code = _camera_unavailable_message(
            camera_device_id=camera_device_id,
            camera_index=camera_index,
        )
        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
            movement=movement,
            score=0,
            feedback=feedback,
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=error_code,
            camera_ready=False,
            session_state="unavailable",
        ).with_session(session_id)

        _signal_prepare_gate(
            prepare_gate,
            ok=False,
            error_code=error_code,
            message=feedback,
        )
        await _send(error.model_dump_json())
        if session_ref is not None:
            session_ref["session"] = None
            session_ref["session_id"] = None
        session.close()
        return

    if start_active:
        session.activate()

    _signal_prepare_gate(prepare_gate, ok=True)

    explicit = camera_device_id is not None or camera_index is not None
    logger.info(
        "Camera selection active: mode=%s requested_device_id=%s "
        "requested_index=%s active_index=%s active_device_id=%s "
        "used_fallback=%s lifecycle=%s session_id=%s",
        "explicit" if explicit else "auto-select",
        camera_device_id,
        camera_index,
        getattr(session.camera, "active_index", None),
        getattr(session.camera, "active_device_id", None),
        getattr(session.camera, "used_fallback", False),
        session.lifecycle,
        session_id,
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
                    await _send(message.model_dump_json())
                    break

                await _send(message.model_dump_json())

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
            prop_type=prop_type,
            movement=movement,
            score=0,
            feedback="Vision pipeline error. Check backend logs for details.",
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code="pipeline_error",
            camera_ready=False,
            session_state="unavailable",
        ).with_session(session_id)

        await _send(error.model_dump_json())

    finally:
        if frame_task is not None and not frame_task.done():
            try:
                await frame_task
            except Exception:
                pass

        if session_ref is not None and session_ref.get("session") is session:
            session_ref["session"] = None
            if session_ref.get("session_id") == session_id:
                session_ref["session_id"] = None

        session.close()


def _parse_session_request(data: dict, movement: str, difficulty: str):
    """Parse shared prepare/start fields. Returns tuple or error FeedbackMessage."""
    movement = data.get("movement", movement)
    difficulty = data.get("difficulty", difficulty)

    bottle_detection_enabled = bool(data.get("bottle_detection_enabled", True))
    prop_type, prop_error = parse_prop_type(data.get("prop_type"))
    if prop_error is not None:
        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
            movement=movement,
            score=0,
            feedback=_human_error_message(prop_error),
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=prop_error,
            camera_ready=False,
            session_state="unavailable",
        )
        return None, error

    camera_device_id, camera_index, camera_error = parse_camera_selection(data)

    if camera_error is not None:
        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
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
            "prop_type": prop_type,
            "camera_device_id": camera_device_id,
            "camera_index": camera_index,
            "bottle_detection_enabled": bottle_detection_enabled,
        },
        None,
    )


def _public_session_state(
    session: VisionSession | None,
    *,
    current_session_id: str | None,
) -> str:
    if session is None or current_session_id is None:
        return "idle"
    if session.is_active:
        return "active"
    if session.is_prepared:
        return "preparing"
    return "idle"


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    session_task: asyncio.Task | None = None
    session_ref: dict = {"session": None, "session_id": None}
    current_session_id: str | None = None
    movement = "Hand Stall"
    difficulty = "Easy"
    send_lock = asyncio.Lock()

    async def safe_send(text: str) -> None:
        async with send_lock:
            await websocket.send_text(text)

    async def send_ack(
        *,
        request_id: str,
        session_id: str | None,
        action: str,
        accepted: bool,
        session_state: str | None,
        error_code: str | None = None,
        message: str | None = None,
    ) -> None:
        ack = CommandAck(
            protocol_version=PROTOCOL_VERSION,
            request_id=request_id,
            session_id=session_id,
            action=action,
            accepted=accepted,
            session_state=session_state,
            error_code=error_code,
            message=message,
        )
        await safe_send(ack.model_dump_json())

    async def send_protocol_error(
        *,
        error_code: str,
        message: str | None = None,
        request_id: str | None = None,
        session_id: str | None = None,
    ) -> None:
        payload = ProtocolError(
            protocol_version=PROTOCOL_VERSION,
            request_id=request_id,
            session_id=session_id,
            error_code=error_code,
            message=message or _human_error_message(error_code),
        )
        await safe_send(payload.model_dump_json())

    async def start_session_loop(
        *,
        movement_name: str,
        prop_type: PropType,
        camera_device_id: str | None,
        camera_index: int | None,
        bottle_detection_enabled: bool,
        start_active: bool,
        session_id: str | None,
        wait_for_prepare: bool,
    ) -> tuple[bool, str | None, str | None]:
        nonlocal session_task, current_session_id

        await _stop_session_task(session_task)
        session_task = None
        session_ref["session"] = None
        session_ref["session_id"] = None

        prepare_gate: dict | None = None
        if wait_for_prepare:
            prepare_gate = {
                "event": asyncio.Event(),
                "ok": False,
                "error_code": None,
                "message": None,
                "signaled": False,
            }

        current_session_id = session_id
        session_task = asyncio.create_task(
            _cv_session_loop(
                websocket,
                movement_name,
                prop_type=prop_type,
                camera_index=camera_index,
                camera_device_id=camera_device_id,
                bottle_detection_enabled=bottle_detection_enabled,
                session_ref=session_ref,
                start_active=start_active,
                session_id=session_id,
                prepare_gate=prepare_gate,
                send_text=safe_send,
            )
        )

        if prepare_gate is None:
            return True, None, None

        await prepare_gate["event"].wait()
        if prepare_gate["ok"]:
            return True, None, None

        # Failed prepare: task should exit shortly; clear identity if matching.
        if current_session_id == session_id:
            current_session_id = None
        return False, prepare_gate.get("error_code"), prepare_gate.get("message")

    async def handle_v1_prepare_or_start(command: PrepareCommand | StartCommand) -> None:
        nonlocal movement, difficulty, current_session_id

        auth_difficulty, movement_error = validate_movement_difficulty(
            command.movement,
            command.difficulty,
        )
        if movement_error is not None:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=_public_session_state(
                    session_ref.get("session"),
                    current_session_id=current_session_id,
                ),
                error_code=movement_error,
                message=_human_error_message(movement_error),
            )
            return

        assert auth_difficulty is not None
        movement = command.movement
        difficulty = auth_difficulty
        start_active = command.action == "start"

        ok, error_code, error_message = await start_session_loop(
            movement_name=movement,
            prop_type=command.prop_type,
            camera_device_id=command.camera_device_id,
            camera_index=command.camera_index,
            bottle_detection_enabled=command.bottle_detection_enabled,
            start_active=start_active,
            session_id=command.session_id,
            wait_for_prepare=True,
        )

        if ok:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=True,
                session_state="active" if start_active else "preparing",
            )
        else:
            code = error_code or "pipeline_init_failed"
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state="idle",
                error_code=code,
                message=error_message or _human_error_message(code),
            )

    async def handle_v1_activate(command: ActivateCommand) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id

        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="activate",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        if session is None or not (session.is_prepared or session.is_active):
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="activate",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_not_prepared",
                message=_human_error_message("session_not_prepared"),
            )
            return

        activated = session.activate()
        logger.info(
            "CV session activate: movement=%s ok=%s lifecycle=%s session_id=%s",
            movement,
            activated,
            session.lifecycle,
            command.session_id,
        )

        if not activated:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="activate",
                accepted=False,
                session_state="idle",
                error_code="session_not_prepared",
                message=_human_error_message("session_not_prepared"),
            )
            return

        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="activate",
            accepted=True,
            session_state="active",
        )

    async def handle_v1_stop(command: StopCommand) -> None:
        nonlocal session_task, current_session_id

        active_id = session_ref.get("session_id") or current_session_id
        if active_id is not None and command.session_id != active_id:
            # Stale stop must not tear down a newer session.
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="stop",
                accepted=False,
                session_state=_public_session_state(
                    session_ref.get("session"),
                    current_session_id=current_session_id,
                ),
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        await _stop_session_task(session_task)
        session_task = None
        session_ref["session"] = None
        session_ref["session_id"] = None
        current_session_id = None

        logger.info("CV session stopped (protocol v1)")
        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="stop",
            accepted=True,
            session_state="idle",
        )

    async def handle_v1(data: dict) -> None:
        request_id = _extract_optional_id(data.get("request_id"))
        session_id = _extract_optional_id(data.get("session_id"))
        action = data.get("action")

        protocol_version = data.get("protocol_version")
        if protocol_version != PROTOCOL_VERSION:
            if request_id is not None and isinstance(action, str):
                await send_ack(
                    request_id=request_id,
                    session_id=session_id,
                    action=action,
                    accepted=False,
                    session_state=_public_session_state(
                        session_ref.get("session"),
                        current_session_id=current_session_id,
                    ),
                    error_code="unsupported_protocol_version",
                    message=_human_error_message("unsupported_protocol_version"),
                )
            else:
                await send_protocol_error(
                    error_code="unsupported_protocol_version",
                    request_id=request_id,
                    session_id=session_id,
                )
            return

        if request_id is None:
            await send_protocol_error(
                error_code="missing_request_id",
                session_id=session_id,
            )
            return

        if session_id is None:
            await send_protocol_error(
                error_code="missing_session_id",
                request_id=request_id,
            )
            return

        try:
            command = parse_v1_command(data)
        except ValidationError as exc:
            code = _validation_error_code(exc)
            if code in {"missing_request_id", "missing_session_id"}:
                await send_protocol_error(
                    error_code=code,
                    request_id=request_id,
                    session_id=session_id,
                )
                return
            await send_ack(
                request_id=request_id,
                session_id=session_id,
                action=action if isinstance(action, str) else "unknown",
                accepted=False,
                session_state=_public_session_state(
                    session_ref.get("session"),
                    current_session_id=current_session_id,
                ),
                error_code=code,
                message=_human_error_message(code),
            )
            return
        except ValueError as exc:
            code = str(exc) if str(exc) in {
                "unknown_action",
                "invalid_camera_device_id",
                "invalid_camera_index",
            } else "unknown_action"
            if code == "unknown_action" and not isinstance(action, str):
                await send_protocol_error(
                    error_code="invalid_command",
                    request_id=request_id,
                    session_id=session_id,
                )
                return
            await send_ack(
                request_id=request_id,
                session_id=session_id,
                action=action if isinstance(action, str) else "unknown",
                accepted=False,
                session_state=_public_session_state(
                    session_ref.get("session"),
                    current_session_id=current_session_id,
                ),
                error_code=code,
                message=_human_error_message(code),
            )
            return

        if isinstance(command, (PrepareCommand, StartCommand)):
            await handle_v1_prepare_or_start(command)
        elif isinstance(command, ActivateCommand):
            await handle_v1_activate(command)
        elif isinstance(command, StopCommand):
            await handle_v1_stop(command)

    async def handle_legacy(data: dict) -> None:
        nonlocal movement, difficulty, session_task, current_session_id

        action = data.get("action")

        if action in ("prepare", "start"):
            parsed, error = _parse_session_request(data, movement, difficulty)
            if error is not None:
                await safe_send(error.model_dump_json())
                return

            assert parsed is not None
            movement = parsed["movement"]
            difficulty = parsed["difficulty"]
            prop_type = parsed["prop_type"]
            camera_device_id = parsed["camera_device_id"]
            camera_index = parsed["camera_index"]
            bottle_detection_enabled = parsed["bottle_detection_enabled"]
            start_active = action == "start"

            await start_session_loop(
                movement_name=movement,
                prop_type=prop_type,
                camera_device_id=camera_device_id,
                camera_index=camera_index,
                bottle_detection_enabled=bottle_detection_enabled,
                start_active=start_active,
                session_id=None,
                wait_for_prepare=False,
            )

            explicit = camera_device_id is not None or camera_index is not None
            logger.info(
                "CV session %s (legacy): %s (%s, prop=%s, bottle_detection=%s, "
                "camera_mode=%s, camera_device_id=%s, camera_index=%s)",
                "started" if start_active else "prepared",
                movement,
                difficulty,
                prop_type,
                bottle_detection_enabled,
                "explicit" if explicit else "auto-select",
                camera_device_id,
                camera_index,
            )

        elif action == "activate":
            session = session_ref.get("session")
            if session is None or not (session.is_prepared or session.is_active):
                error = FeedbackMessage(
                    bottle_detected=False,
                    prop_type=getattr(session, "prop_type", "bottle"),
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
                await safe_send(error.model_dump_json())
                return

            activated = session.activate()
            logger.info(
                "CV session activate (legacy): movement=%s ok=%s lifecycle=%s",
                movement,
                activated,
                session.lifecycle,
            )

        elif action == "stop":
            await _stop_session_task(session_task)
            session_task = None
            session_ref["session"] = None
            session_ref["session_id"] = None
            current_session_id = None
            logger.info("CV session stopped (legacy)")

        else:
            logger.warning("Ignoring unknown WebSocket action: %s", action)

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await send_protocol_error(error_code="invalid_json")
                continue

            if not isinstance(data, dict):
                await send_protocol_error(error_code="invalid_command")
                continue

            if "protocol_version" in data:
                await handle_v1(data)
            else:
                await handle_legacy(data)

    except WebSocketDisconnect:
        logger.info("Client disconnected")

    finally:
        await _stop_session_task(session_task)
        session_ref["session"] = None
        session_ref["session_id"] = None
        release_shared_camera()
