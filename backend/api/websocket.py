import asyncio
import base64
import json
import logging
import time
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from assessment.calibration import CalibrationTracker
from assessment.feedback_codes import category_for
from assessment.hold_validator import HoldValidator
from assessment.readiness import (
    ReadinessObservation,
    ReadinessSnapshot,
    ReadinessTracker,
    readiness_needs_hands,
    readiness_needs_pose,
)
from assessment.rule_engine import (
    evaluate_movement,
    movement_is_prop_detection_only,
    movement_required_prop_type,
    movement_requires_hands,
    movement_requires_pose,
    validate_movement_difficulty,
)
from assessment.scoring import RubricTracker
from assessment.rubric import RubricAssessment
from config import (
    FPS_LOG_INTERVAL,
    EVIDENCE_JPEG_QUALITY,
    EVIDENCE_MAX_BYTES,
    EVIDENCE_MAX_HEIGHT,
    EVIDENCE_MAX_WIDTH,
    JPEG_QUALITY,
    READINESS_SNAPSHOT_MAX_AGE_S,
    SESSION_PREP_TIMEOUT_S,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
    YOLO_IMGSZ,
)
from schemas.commands import (
    PROTOCOL_VERSION,
    ActivateCommand,
    BeginReadinessCommand,
    ConfirmReadinessCommand,
    PrepareCommand,
    PropType,
    StartCommand,
    StopCommand,
    parse_v1_command,
)
from schemas.feedback import AssessmentPayload, CriterionScorePayload, FeedbackMessage
from schemas.protocol import CommandAck, ProtocolError
from vision.annotator import annotate_frame
from vision.bottle_detector import BottleDetector, ModelLoadError
from vision.dual_prop_detector import DualPropDetector
from vision.prop_detector import PropDetector
from vision.camera import (
    CameraCapture,
    camera_display_name,
    latest_frame_overwrite_count,
    release_shared_camera,
)
from vision.hands_detector import HandsDetector
from vision.pose_detector import PoseDetector
from vision.types import Point2D, PropDetection

router = APIRouter()
logger = logging.getLogger(__name__)

CAMERA_REOPEN_DELAY_S = 0.75
_MAX_CAMERA_INDEX = 10
_MAX_DEVICE_ID_LENGTH = 1024

SESSION_PREPARED = "prepared"
SESSION_READYING = "readying"
SESSION_ACTIVE = "active"
SESSION_CLOSED = "closed"

SendText = Callable[[str], Awaitable[None]]


def encode_evidence_jpeg(frame) -> bytes | None:
    """Encode an annotated evidence image within the Storage size contract.

    This runs in the existing frame worker, never in the asyncio event loop.
    Returning ``None`` makes evidence best-effort: an encoding problem must
    not turn an otherwise valid movement assessment into a failed session.
    """
    if frame is None or getattr(frame, "size", 0) == 0:
        return None
    height, width = frame.shape[:2]
    scale = min(1.0, EVIDENCE_MAX_WIDTH / width, EVIDENCE_MAX_HEIGHT / height)
    image = frame
    if scale < 1.0:
        image = cv2.resize(
            frame,
            (max(1, round(width * scale)), max(1, round(height * scale))),
            interpolation=cv2.INTER_AREA,
        )

    for quality in (EVIDENCE_JPEG_QUALITY, 55, 45, 35):
        ok, encoded = cv2.imencode(
            ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), quality]
        )
        if ok and len(encoded) <= EVIDENCE_MAX_BYTES:
            return encoded.tobytes()
    # Resolution reduction is bounded so pathological images cannot produce
    # unbounded CPU work or oversized uploads.
    for _ in range(3):
        next_width = max(1, image.shape[1] // 2)
        next_height = max(1, image.shape[0] // 2)
        image = cv2.resize(image, (next_width, next_height), interpolation=cv2.INTER_AREA)
        ok, encoded = cv2.imencode(
            ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), 35]
        )
        if ok and len(encoded) <= EVIDENCE_MAX_BYTES:
            return encoded.tobytes()
    return None


def _assessment_payload(assessment: RubricAssessment) -> AssessmentPayload:
    """Convert domain RubricAssessment into the WebSocket payload schema."""
    payload = assessment.to_payload()
    criteria = {
        key: CriterionScorePayload(**value)
        for key, value in payload["criteria"].items()
    }
    return AssessmentPayload(
        version=2,
        criteria=criteria,
        total=payload["total"],
        performance_level=payload["performance_level"],
    )

_PIPELINE_STAGE_ORDER = (
    "camera",
    "yolo",
    "hands",
    "pose",
    "evaluate",
    "annotate",
    "jpeg",
    "encode",
    "send",
    "processing_total",
    "end_to_end",
)


class _PipelineTimings:
    """Rolling stage timings logged at the FPS interval (not every frame)."""

    def __init__(self) -> None:
        self._sums: dict[str, float] = {name: 0.0 for name in _PIPELINE_STAGE_ORDER}
        self._counts: dict[str, int] = {name: 0 for name in _PIPELINE_STAGE_ORDER}
        self._frame_age_sum = 0.0
        self._frame_age_count = 0
        self._frame_age_max = 0.0

    def add(self, stage: str, seconds: float) -> None:
        if stage not in self._sums:
            self._sums[stage] = 0.0
            self._counts[stage] = 0
        self._sums[stage] += seconds
        self._counts[stage] += 1

    def add_frame_age(self, seconds: float) -> None:
        self._frame_age_sum += seconds
        self._frame_age_count += 1
        if seconds > self._frame_age_max:
            self._frame_age_max = seconds

    def reset(self) -> None:
        for name in list(self._sums):
            self._sums[name] = 0.0
            self._counts[name] = 0
        self._frame_age_sum = 0.0
        self._frame_age_count = 0
        self._frame_age_max = 0.0

    def format_averages_ms(self, *, frame_budget_ms: float) -> str:
        parts: list[str] = []
        for name in _PIPELINE_STAGE_ORDER:
            count = self._counts.get(name, 0)
            if count <= 0:
                continue
            avg_ms = (self._sums[name] / count) * 1000.0
            over = "!" if avg_ms > frame_budget_ms and name in {
                "processing_total",
                "end_to_end",
                "total",
            } else ""
            if name not in {"processing_total", "end_to_end", "total"} and avg_ms > (
                frame_budget_ms * 0.35
            ):
                over = "!"
            parts.append(f"{name}={avg_ms:.1f}ms{over}")
        if self._frame_age_count > 0:
            avg_age = (self._frame_age_sum / self._frame_age_count) * 1000.0
            max_age = self._frame_age_max * 1000.0
            parts.append(f"frame_age_avg={avg_age:.1f}ms")
            parts.append(f"frame_age_max={max_age:.1f}ms")
        return ", ".join(parts)


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
    if isinstance(raw, str) and raw.strip() in {
        "bottle",
        "shaker",
        "bottle_and_shaker",
    }:
        return raw.strip(), None
    return "bottle", "invalid_prop_type"


def parse_legacy_boolean(raw: Any, *, default: bool = True) -> tuple[bool, str | None]:
    """Parse legacy prepare/start boolean fields without truthy string coercion.

    Unlike ``bool("false")``, string literals ``"true"`` / ``"false"`` are
    accepted. Other strings and numeric types are rejected.
    """
    if raw is None:
        return default, None
    if isinstance(raw, bool):
        return raw, None
    if isinstance(raw, str):
        lowered = raw.strip().lower()
        if lowered == "true":
            return True, None
        if lowered == "false":
            return False, None
        return default, "invalid_boolean"
    return default, "invalid_boolean"


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
            "Invalid prop_type. Choose 'bottle', 'shaker', or 'bottle_and_shaker'."
        ),
        "movement_prop_mismatch": (
            "This movement requires a specific prop selection. Choose the "
            "prop combination configured for this movement."
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
        "session_already_active": "The session is already active.",
        "session_id_mismatch": "The session_id does not match the current session.",
        "readiness_not_stable": (
            "Readiness is not stable yet. Keep the required inputs visible "
            "and try again."
        ),
        "readiness_stale": (
            "Calibration data is no longer current. Keep the required inputs "
            "visible while the camera refreshes."
        ),
        "readiness_not_confirmed": (
            "Readiness must be confirmed before activation. Complete calibration "
            "and press Start Practice."
        ),
        "pipeline_init_failed": "Vision pipeline failed to start.",
        "prepare_timeout": (
            "Camera preparation timed out. Check the camera connection and try again."
        ),
        "model_load_failed": "Model load failed.",
        "pipeline_error": "Vision pipeline error.",
    }.get(error_code, "The WebSocket command was rejected.")


@dataclass(frozen=True)
class _NormalizedFrameDetections:
    """Typed bottle/shaker split for readiness, annotation, and active rules.

    ``primary`` is the selected-prop list passed into generic movement rules
    (for ``shaker`` sessions this is the shaker detections, not bottles).
    """

    primary: tuple[PropDetection, ...]
    bottles: tuple[PropDetection, ...]
    shakers: tuple[PropDetection, ...]
    annotation: tuple[PropDetection, ...]
    selected_detected: bool
    selected_count: int


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
        if prop_type not in {"bottle", "shaker", "bottle_and_shaker"}:
            raise ValueError("invalid_prop_type")

        self.movement = movement
        self.prop_type = prop_type
        self.prop_display_name = {
            "shaker": "Cocktail Shaker",
            "bottle_and_shaker": "Bottle + Cocktail Shaker",
        }.get(prop_type, "Bottle")
        self._is_dual_prop = prop_type == "bottle_and_shaker"
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
        elif self._is_dual_prop:
            self.prop_detector = DualPropDetector(
                enabled=bottle_detection_enabled,
            )
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
        self._prop_detection_only = movement_is_prop_detection_only(movement)
        self._hands_rotated_fallback = (
            not self._prop_detection_only
            and movement in {"Normal Grip", "Claw Grip"}
        )
        self._hands_bartender_roi = (
            not self._prop_detection_only and movement == "Bartender's Grip"
        )
        self._hands_needed = (
            not self._prop_detection_only and movement_requires_hands(movement)
        )
        self._pose_needed = (
            not self._prop_detection_only and movement_requires_pose(movement)
        )
        self.rubric = RubricTracker()

        self._frame_index = 0
        self._last_bottles: list[PropDetection] = []
        self._last_shakers: list[PropDetection] = []

        # Do not cache hands landmarks.
        # Hands move fast, and caching causes ghost/stuck finger dots.
        self._prev_hip_center: Point2D | None = None
        self._movement_state: dict | None = None
        self._model_checked = False
        self._lifecycle = SESSION_PREPARED
        self._hold_validator = HoldValidator()
        self._evidence_emitted = False
        self._readiness_tracker: ReadinessTracker | None = None
        self._latest_readiness_snapshot: ReadinessSnapshot | None = None
        # Monotonic timestamp of the latest readiness observation/snapshot.
        self._latest_readiness_observed_at: float | None = None
        self._readiness_confirmed = False
        self._frozen_readiness_snapshot: ReadinessSnapshot | None = None
        self._calibration = CalibrationTracker()
        self.timings = _PipelineTimings()
        # Wall-clock start of the latest process_* call (for end_to_end timing).
        self._pipeline_started_at: float | None = None

    def _normalize_detections(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
    ) -> _NormalizedFrameDetections:
        """Map raw detector output into typed bottle/shaker/primary lists."""
        bottle_list = tuple(bottles)
        shaker_list = tuple(shakers)
        if self._is_dual_prop:
            primary = bottle_list
            annotation = bottle_list + shaker_list
            selected_detected = len(bottle_list) > 0 and len(shaker_list) > 0
            selected_count = len(bottle_list) + len(shaker_list)
        elif self.prop_type == "shaker":
            primary = shaker_list
            annotation = shaker_list
            selected_detected = len(shaker_list) > 0
            selected_count = len(shaker_list)
        else:
            primary = bottle_list
            annotation = bottle_list
            selected_detected = len(bottle_list) > 0
            selected_count = len(bottle_list)
        return _NormalizedFrameDetections(
            primary=primary,
            bottles=bottle_list,
            shakers=shaker_list,
            annotation=annotation,
            selected_detected=selected_detected,
            selected_count=selected_count,
        )

    def _detect_normalized_props(self, frame) -> _NormalizedFrameDetections:
        """Run YOLO and normalize bottle vs shaker lists for this prop_type."""
        if self._is_dual_prop:
            dual_result = self.prop_detector.detect(frame)
            return self._normalize_detections(
                bottles=list(dual_result.bottles),
                shakers=list(dual_result.shakers),
            )
        detected = list(self.prop_detector.detect(frame))
        if self.prop_type == "shaker":
            return self._normalize_detections(bottles=[], shakers=detected)
        return self._normalize_detections(bottles=detected, shakers=[])

    def _cached_normalized_props(self) -> _NormalizedFrameDetections:
        bottles = list(self._last_bottles)
        shakers = list(self._last_shakers)
        extrapolate = getattr(self.prop_detector, "extrapolate_detections", None)
        if callable(extrapolate):
            bottles, shakers = extrapolate(
                bottles=bottles,
                shakers=shakers,
                now=time.monotonic(),
            )
        return self._normalize_detections(
            bottles=list(bottles),
            shakers=list(shakers),
        )

    def _store_normalized_props(self, normalized: _NormalizedFrameDetections) -> None:
        self._last_bottles = list(normalized.bottles)
        self._last_shakers = list(normalized.shakers)

    @property
    def lifecycle(self) -> str:
        return self._lifecycle

    @property
    def is_prepared(self) -> bool:
        return self._lifecycle == SESSION_PREPARED

    @property
    def is_readying(self) -> bool:
        return self._lifecycle == SESSION_READYING

    @property
    def is_active(self) -> bool:
        return self._lifecycle == SESSION_ACTIVE

    @property
    def is_prop_detection_only(self) -> bool:
        return self._prop_detection_only

    def start(self) -> bool:
        return self.camera.open()

    def _stamp(self, message: FeedbackMessage) -> FeedbackMessage:
        return message.with_session(self.session_id)

    def _sync_landmark_detectors(self, *, needs_hands: bool, needs_pose: bool) -> None:
        """Create required Hands/Pose detectors and close any unused instances."""
        if needs_hands:
            if self.hands_detector is None:
                self.hands_detector = HandsDetector(
                    rotated_fallback=self._hands_rotated_fallback,
                    bartender_roi_fallback=self._hands_bartender_roi,
                )
        elif self.hands_detector is not None:
            self.hands_detector.close()
            self.hands_detector = None

        if needs_pose:
            if self.pose_detector is None:
                self.pose_detector = PoseDetector()
        elif self.pose_detector is not None:
            self.pose_detector.close()
            self.pose_detector = None

    def _ensure_detectors(self) -> None:
        if self._prop_detection_only:
            self._sync_landmark_detectors(needs_hands=False, needs_pose=False)
            return
        self._sync_landmark_detectors(
            needs_hands=self._hands_needed,
            needs_pose=self._pose_needed,
        )

    def _ensure_readiness_detectors(self) -> None:
        """Create only the detectors required for readiness observation."""
        if self._prop_detection_only:
            self._sync_landmark_detectors(needs_hands=False, needs_pose=False)
            return
        self._sync_landmark_detectors(
            needs_hands=readiness_needs_hands(self.movement, self.prop_type),
            needs_pose=readiness_needs_pose(self.movement, self.prop_type),
        )

    def begin_readiness(self) -> bool:
        """Transition prepared → readying. Idempotent when already READYING.

        Returns True on success or when already readying.
        Returns False if CLOSED or ACTIVE.
        """
        if self._lifecycle == SESSION_READYING:
            return True
        if self._lifecycle != SESSION_PREPARED:
            return False
        self._ensure_readiness_detectors()
        self._readiness_tracker = ReadinessTracker(self.movement, self.prop_type)
        self._latest_readiness_snapshot = None
        self._latest_readiness_observed_at = None
        self._readiness_confirmed = False
        self._frozen_readiness_snapshot = None
        self._calibration.reset()
        self._lifecycle = SESSION_READYING
        return True

    def confirm_readiness(self) -> tuple[bool, str | None]:
        """Lock readiness after the client confirms stable calibration.

        Idempotent when already confirmed for this readiness cycle.
        Returns (accepted, error_code).
        """
        if self._lifecycle != SESSION_READYING:
            if self._lifecycle == SESSION_ACTIVE:
                return False, "session_already_active"
            return False, "session_not_prepared"

        if self._readiness_confirmed:
            return True, None

        snapshot = self._latest_readiness_snapshot
        if snapshot is None or not snapshot.readiness_stable:
            return False, "readiness_not_stable"

        observed_at = self._latest_readiness_observed_at
        if observed_at is None:
            return False, "readiness_stale"
        age_s = time.monotonic() - observed_at
        if age_s > READINESS_SNAPSHOT_MAX_AGE_S:
            return False, "readiness_stale"

        self._readiness_confirmed = True
        self._frozen_readiness_snapshot = snapshot
        self._calibration.lock()
        return True, None

    @property
    def readiness_confirmed(self) -> bool:
        return self._readiness_confirmed

    def activate(self) -> tuple[bool, str | None]:
        """Transition prepared or readying → active without reopening the camera.

        Free Practice may activate directly from prepared (never entered
        readiness). Guided practice that entered readying must have confirmed
        readiness first; detection loss after confirmation does not revoke it.

        Returns (success, error_code). error_code is None on success.
        """
        if self._lifecycle == SESSION_ACTIVE:
            return True, None

        if self._lifecycle not in (SESSION_PREPARED, SESSION_READYING):
            return False, "session_not_prepared"

        # Sessions that entered the readiness gate require explicit confirmation
        # before activation. prepared→active remains for Free Practice only.
        if self._lifecycle == SESSION_READYING and not self._readiness_confirmed:
            return False, "readiness_not_confirmed"

        self._ensure_detectors()
        self.rubric.activate()
        if not self._prop_detection_only:
            self._hold_validator.activate()
        self._prev_hip_center = None
        self._movement_state = None
        self._last_bottles = []
        self._last_shakers = []
        if self._is_dual_prop:
            self.prop_detector.reset_cache()
        self._frame_index = 0
        self._evidence_emitted = False
        self._readiness_tracker = None
        self._latest_readiness_snapshot = None
        self._latest_readiness_observed_at = None
        self._frozen_readiness_snapshot = None
        self._readiness_confirmed = False
        self._lifecycle = SESSION_ACTIVE
        return True, None

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
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at

        t0 = time.perf_counter()
        frame = self.camera.read()
        self.timings.add("camera", time.perf_counter() - t0)

        if frame is None:
            return None

        captured_at = self.camera.last_captured_at_monotonic
        if captured_at is not None:
            self.timings.add_frame_age(time.monotonic() - captured_at)

        t0 = time.perf_counter()
        _, buffer = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )
        self.timings.add("jpeg", time.perf_counter() - t0)

        t0 = time.perf_counter()
        frame_b64 = base64.b64encode(buffer).decode("ascii")

        message = self._stamp(
            FeedbackMessage(
                bottle_detected=False,
                bottle_count=0,
                prop_type=self.prop_type,
                movement=self.movement,
                feedback="Preparing camera…",
                feedback_type="positive",
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="preparing",
            )
        )
        self.timings.add("encode", time.perf_counter() - t0)
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_readiness_frame(self) -> FeedbackMessage | None:
        """Run observability checklist without movement evaluation or scoring."""
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        t0 = time.perf_counter()
        frame = self.camera.read()
        self.timings.add("camera", time.perf_counter() - t0)

        if frame is None:
            return None

        processing_start = time.monotonic()
        captured_at = self.camera.last_captured_at_monotonic
        if captured_at is not None:
            self.timings.add_frame_age(processing_start - captured_at)

        self._frame_index += 1
        run_yolo = (self._frame_index - 1) % YOLO_FRAME_SKIP == 0

        if self.bottle_detection_enabled and run_yolo:
            t0 = time.perf_counter()
            normalized = self._detect_normalized_props(frame)
            self.timings.add("yolo", time.perf_counter() - t0)
            self._store_normalized_props(normalized)
        elif not self.bottle_detection_enabled:
            normalized = self._normalize_detections(bottles=[], shakers=[])
            self._store_normalized_props(normalized)
        else:
            normalized = self._cached_normalized_props()

        bottles = list(normalized.bottles)
        shakers = list(normalized.shakers)

        needs_h = readiness_needs_hands(self.movement, self.prop_type)
        needs_p = readiness_needs_pose(self.movement, self.prop_type)

        hands = None
        if needs_h and self.hands_detector is not None:
            bottle_ref = (
                normalized.primary[0] if normalized.primary else None
            )
            t0 = time.perf_counter()
            hands = self.hands_detector.detect(frame, bottle=bottle_ref)
            self.timings.add("hands", time.perf_counter() - t0)

        pose = None
        if needs_p and self.pose_detector is not None:
            t0 = time.perf_counter()
            pose = self.pose_detector.detect(frame)
            self.timings.add("pose", time.perf_counter() - t0)

        if not self._calibration.locked:
            self._calibration.sample(pose, hands)

        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=bottles,
            shakers=shakers,
            hands=hands,
            pose=pose,
        )

        snapshot = None
        observed_at = time.monotonic()
        if self._readiness_tracker is not None and not self._readiness_confirmed:
            snapshot = self._readiness_tracker.update(obs)
            self._latest_readiness_snapshot = snapshot
            self._latest_readiness_observed_at = observed_at
        elif self._readiness_confirmed and self._frozen_readiness_snapshot is not None:
            snapshot = self._frozen_readiness_snapshot
            # Keep freshness advancing so post-confirm frames stay current, but
            # do not revoke confirmation when detections drop.
            self._latest_readiness_observed_at = observed_at

        readiness_items = list(snapshot.items) if snapshot is not None else None
        readiness_complete = snapshot.readiness_complete if snapshot is not None else None
        readiness_stable = snapshot.readiness_stable if snapshot is not None else None
        readiness_stable_progress = (
            snapshot.readiness_stable_progress if snapshot is not None else None
        )

        boxes_to_draw = list(normalized.annotation)
        t0 = time.perf_counter()
        annotated = annotate_frame(
            frame,
            boxes_to_draw,
            hands,
            "Checking readiness\u2026",
            "positive",
            self.movement,
            pose=pose,
            prop_label=self.prop_display_name,
        )
        self.timings.add("annotate", time.perf_counter() - t0)

        t0 = time.perf_counter()
        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )
        self.timings.add("jpeg", time.perf_counter() - t0)

        t0 = time.perf_counter()
        frame_b64 = base64.b64encode(buffer).decode("ascii")
        message = self._stamp(
            FeedbackMessage(
                bottle_detected=normalized.selected_detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=self.movement,
                feedback="Checking readiness\u2026",
                feedback_type="positive",
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="readying",
                readiness_items=readiness_items,
                readiness_complete=readiness_complete,
                readiness_stable=readiness_stable,
                readiness_stable_progress=readiness_stable_progress,
                calibration_scale=self._calibration.scale,
                calibration_source=self._calibration.source,
            )
        )
        self.timings.add("encode", time.perf_counter() - t0)
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_prop_detection_frame(self) -> FeedbackMessage | None:
        """Active Free Practice: camera + prop detect + annotate, no MediaPipe/scoring."""
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        t0 = time.perf_counter()
        frame = self.camera.read()
        self.timings.add("camera", time.perf_counter() - t0)

        if frame is None:
            return None

        processing_start = time.monotonic()
        captured_at = self.camera.last_captured_at_monotonic
        if captured_at is not None:
            self.timings.add_frame_age(processing_start - captured_at)

        self._frame_index += 1
        run_yolo = (self._frame_index - 1) % YOLO_FRAME_SKIP == 0

        if self.bottle_detection_enabled and run_yolo:
            t0 = time.perf_counter()
            normalized = self._detect_normalized_props(frame)
            self.timings.add("yolo", time.perf_counter() - t0)
            self._store_normalized_props(normalized)
        elif not self.bottle_detection_enabled:
            normalized = self._normalize_detections(bottles=[], shakers=[])
            self._store_normalized_props(normalized)
        else:
            normalized = self._cached_normalized_props()

        detected = normalized.selected_detected
        if detected:
            feedback = f"{self.prop_display_name} detected"
            feedback_type = "positive"
        else:
            feedback = f"Searching for {self.prop_display_name.lower()}"
            feedback_type = "warning"

        t0 = time.perf_counter()
        annotated = annotate_frame(
            frame,
            list(normalized.annotation),
            None,
            feedback,
            feedback_type,
            self.movement,
            pose=None,
            prop_label=self.prop_display_name,
        )
        self.timings.add("annotate", time.perf_counter() - t0)

        t0 = time.perf_counter()
        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )
        self.timings.add("jpeg", time.perf_counter() - t0)

        t0 = time.perf_counter()
        frame_b64 = base64.b64encode(buffer).decode("ascii")
        message = self._stamp(
            FeedbackMessage(
                bottle_detected=detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=self.movement,
                feedback=feedback,
                feedback_type=feedback_type,
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="active",
            )
        )
        self.timings.add("encode", time.perf_counter() - t0)
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_frame(self) -> FeedbackMessage | None:
        if self._prop_detection_only:
            return self.process_prop_detection_frame()

        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        self._ensure_detectors()
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        t0 = time.perf_counter()
        frame = self.camera.read()
        self.timings.add("camera", time.perf_counter() - t0)

        if frame is None:
            return None

        processing_start = time.monotonic()
        captured_at = self.camera.last_captured_at_monotonic
        if captured_at is not None:
            self.timings.add_frame_age(processing_start - captured_at)

        self._frame_index += 1

        # Frame index starts at 1; subtract 1 so the very first frame runs YOLO.
        run_yolo = (self._frame_index - 1) % YOLO_FRAME_SKIP == 0

        if self.bottle_detection_enabled and run_yolo:
            t0 = time.perf_counter()
            normalized = self._detect_normalized_props(frame)
            self.timings.add("yolo", time.perf_counter() - t0)
            self._store_normalized_props(normalized)
        elif not self.bottle_detection_enabled:
            normalized = self._normalize_detections(bottles=[], shakers=[])
            self._store_normalized_props(normalized)
        else:
            normalized = self._cached_normalized_props()

        bottles = list(normalized.bottles)
        shakers = list(normalized.shakers)

        # Score on the highest-confidence selected prop for single-prop movements.
        # Double Hand Stall also receives the full detection list via `bottles`.
        # For shaker sessions, primary holds the shaker detections (compatibility).
        bottle = normalized.primary[0] if normalized.primary else None
        shaker = shakers[0] if shakers else None
        # The hand is holding the shaker for the dual-prop movement, so prefer
        # it as the hand-detector reference; fall back to the bottle if the
        # shaker is not currently detected.
        hand_reference = (
            (shaker if shaker is not None else bottle)
            if self._is_dual_prop
            else bottle
        )

        # Important fix:
        # Do not use previous hand landmarks when the current frame has no hand.
        # This prevents "naiiwan yung daliri" / ghost hand dots.
        # Missing Hands when required is a lifecycle bug, not a detection miss.
        hands = None
        if self._hands_needed:
            assert self.hands_detector is not None
            t0 = time.perf_counter()
            hands = self.hands_detector.detect(
                frame,
                bottle=hand_reference,
            )
            self.timings.add("hands", time.perf_counter() - t0)

        pose = None
        if self._pose_needed:
            assert self.pose_detector is not None
            t0 = time.perf_counter()
            pose = self.pose_detector.detect(frame)
            self.timings.add("pose", time.perf_counter() - t0)

        # Generic rules expect the selected prop in `bottle` / `bottles`.
        rule_bottles = (
            bottles
            if self._is_dual_prop
            else list(normalized.primary)
        )
        rule_shakers = (
            shakers
            if (self._is_dual_prop and self.bottle_detection_enabled)
            else None
        )

        t0 = time.perf_counter()
        rule_result, self._prev_hip_center, self._movement_state = evaluate_movement(
            self.movement,
            bottle,
            pose,
            hands,
            self._prev_hip_center,
            self._movement_state,
            bottle_detection_enabled=self.bottle_detection_enabled,
            bottles=rule_bottles if self.bottle_detection_enabled else None,
            prop_type=self.prop_type,
            prop_label=self.prop_display_name,
            shakers=rule_shakers,
            calibration_scale=self._calibration.resolved[0],
        )
        self.timings.add("evaluate", time.perf_counter() - t0)

        hold_ts = time.monotonic()
        self.rubric.record(
            feedback_code=rule_result.feedback_code,
            feedback_type=rule_result.feedback_type,
            posture_status=rule_result.posture_status,
            timestamp=hold_ts,
            criterion_results=rule_result.criterion_results,
        )

        hold = self._hold_validator.update(
            feedback_type=rule_result.feedback_type,
            posture_status=rule_result.posture_status,
            session_active=self.is_active,
            timestamp=hold_ts,
        )
        assessment = _assessment_payload(self.rubric.snapshot(hold))

        # Combine both detection lists only for drawing; movement evaluation
        # above kept bottles and shakers separate.
        boxes_to_draw = list(normalized.annotation)

        t0 = time.perf_counter()
        annotated = annotate_frame(
            frame,
            boxes_to_draw,
            hands,
            rule_result.feedback,
            rule_result.feedback_type,
            self.movement,
            pose=pose,
            prop_label=self.prop_display_name,
        )
        self.timings.add("annotate", time.perf_counter() - t0)

        t0 = time.perf_counter()
        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )
        self.timings.add("jpeg", time.perf_counter() - t0)

        t0 = time.perf_counter()
        frame_b64 = base64.b64encode(buffer).decode("ascii")
        evidence_b64 = None
        if hold.hold_confirmed and not self._evidence_emitted:
            # Never substitute a later frame if this best-effort encode fails:
            # evidence, when present, must correspond to the confirming frame.
            self._evidence_emitted = True
            try:
                evidence_jpeg = encode_evidence_jpeg(annotated)
            except cv2.error:
                logger.exception("Could not encode hold-confirmed evidence")
                evidence_jpeg = None
            if evidence_jpeg is not None:
                evidence_b64 = base64.b64encode(evidence_jpeg).decode("ascii")
        feedback_code = rule_result.feedback_code
        category = category_for(feedback_code)
        message = self._stamp(
            FeedbackMessage(
                bottle_detected=normalized.selected_detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=self.movement,
                feedback=rule_result.feedback,
                feedback_type=rule_result.feedback_type,
                posture_status=rule_result.posture_status,
                frame_jpeg_base64=frame_b64,
                evidence_jpeg_base64=evidence_b64,
                camera_ready=True,
                session_state="active",
                hold_progress=hold.hold_progress,
                hold_duration_ms=hold.hold_duration_ms,
                hold_confirmed=hold.hold_confirmed,
                positive_frame_ratio=hold.positive_frame_ratio,
                hold_target_ms=hold.hold_target_ms,
                feedback_code=feedback_code,
                feedback_category=category.value if category is not None else None,
                assessment=assessment,
            )
        )
        self.timings.add("encode", time.perf_counter() - t0)
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_tick(self) -> FeedbackMessage | None:
        if self._lifecycle == SESSION_ACTIVE:
            return self.process_frame()
        if self._lifecycle == SESSION_READYING:
            return self.process_readiness_frame()
        if self._lifecycle == SESSION_PREPARED:
            return self.process_preview_frame()
        return None

    def close(self) -> None:
        self._lifecycle = SESSION_CLOSED
        self._readiness_tracker = None
        self._latest_readiness_snapshot = None
        self._latest_readiness_observed_at = None
        self._frozen_readiness_snapshot = None
        self._readiness_confirmed = False
        self._calibration.reset()
        self._hold_validator.reset()
        self.camera.release()
        self._sync_landmark_detectors(needs_hands=False, needs_pose=False)


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

    frame_task: asyncio.Task | None = None

    try:
        started = await asyncio.to_thread(session.start)

        if not started:
            feedback, error_code = _camera_unavailable_message(
                camera_device_id=camera_device_id,
                camera_index=camera_index,
            )
            error = FeedbackMessage(
                bottle_detected=False,
                prop_type=prop_type,
                movement=movement,
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
            return

        if session_ref is not None:
            session_ref["session"] = session
            session_ref["session_id"] = session_id

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
        frame_budget_ms = interval * 1000.0
        processed_frame_count = 0
        loop_ticks = 0
        loop_start = time.perf_counter()
        last_overwrite_count = latest_frame_overwrite_count()

        while True:
            tick = time.perf_counter()
            loop_ticks += 1

            # At most one frame-processing operation in flight.
            if frame_task is not None and not frame_task.done():
                raise RuntimeError("CV session violated single in-flight processing invariant")

            frame_task = asyncio.create_task(
                asyncio.to_thread(session.process_tick)
            )

            # Shield the in-flight worker so outer cancellation cannot cancel
            # the asyncio wrapper before the thread finishes process_tick.
            message = await asyncio.shield(frame_task)

            frame_task = None

            if message is not None:
                if message.error_code == "model_load_failed":
                    await _send(message.model_dump_json())
                    break

                t_send = time.perf_counter()
                await _send(message.model_dump_json())
                session.timings.add("send", time.perf_counter() - t_send)
                if session._pipeline_started_at is not None:
                    session.timings.add(
                        "end_to_end",
                        time.perf_counter() - session._pipeline_started_at,
                    )
                processed_frame_count += 1

            if processed_frame_count > 0 and processed_frame_count % FPS_LOG_INTERVAL == 0:
                elapsed = time.perf_counter() - loop_start
                actual_fps = (
                    processed_frame_count / elapsed if elapsed > 0 else 0.0
                )
                stage_summary = session.timings.format_averages_ms(
                    frame_budget_ms=frame_budget_ms
                )
                overwrite_total = latest_frame_overwrite_count()
                overwrite_delta = max(0, overwrite_total - last_overwrite_count)
                last_overwrite_count = overwrite_total
                logger.info(
                    "CV session FPS: %.1f (target=%s, yolo_skip=%s, imgsz=%s, "
                    "lifecycle=%s, processed=%s, ticks=%s, "
                    "frame_overwrites=%s, frame_overwrites_delta=%s) stages: %s",
                    actual_fps,
                    TARGET_FPS,
                    YOLO_FRAME_SKIP,
                    YOLO_IMGSZ,
                    session.lifecycle,
                    processed_frame_count,
                    loop_ticks,
                    overwrite_total,
                    overwrite_delta,
                    stage_summary,
                )
                session.timings.reset()
                processed_frame_count = 0
                loop_ticks = 0
                loop_start = time.perf_counter()

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
        if frame_task is not None:
            if not frame_task.done():
                try:
                    await frame_task
                except Exception:
                    logger.exception(
                        "In-flight frame processing failed during session shutdown"
                    )
            else:
                frame_exc = frame_task.exception()
                if frame_exc is not None:
                    logger.exception(
                        "In-flight frame processing failed during session shutdown",
                        exc_info=frame_exc,
                    )

        if session_ref is not None:
            if session_ref.get("session") is session:
                session_ref["session"] = None
            if session_ref.get("session_id") == session_id:
                session_ref["session_id"] = None

        await asyncio.to_thread(session.close)


def _parse_session_request(data: dict, movement: str, difficulty: str):
    """Parse shared prepare/start fields. Returns tuple or error FeedbackMessage."""
    movement = data.get("movement", movement)
    difficulty = data.get("difficulty", difficulty)

    bottle_detection_enabled, bool_error = parse_legacy_boolean(
        data.get("bottle_detection_enabled"),
    )
    if bool_error is not None:
        error = FeedbackMessage(
            bottle_detected=False,
            prop_type="bottle",
            movement=movement,
            feedback=_human_error_message(bool_error),
            feedback_type="error",
            posture_status="unknown",
            frame_jpeg_base64=None,
            error_code=bool_error,
            camera_ready=False,
            session_state="unavailable",
        )
        return None, error

    prop_type, prop_error = parse_prop_type(data.get("prop_type"))
    if prop_error is not None:
        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
            movement=movement,
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
    if session.is_readying:
        return "readying"
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
        calibration_scale: float | None = None,
        calibration_source: str | None = None,
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
            calibration_scale=calibration_scale,
            calibration_source=calibration_source,
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

        try:
            await asyncio.wait_for(
                prepare_gate["event"].wait(),
                timeout=SESSION_PREP_TIMEOUT_S,
            )
        except asyncio.TimeoutError:
            if prepare_gate.get("signaled") and prepare_gate.get("ok"):
                return True, None, None

            await _stop_session_task(session_task)
            session_task = None

            if current_session_id == session_id:
                current_session_id = None
            if session_ref.get("session_id") == session_id:
                session_ref["session"] = None
                session_ref["session_id"] = None
            return (
                False,
                "prepare_timeout",
                _human_error_message("prepare_timeout"),
            )

        if prepare_gate["ok"]:
            return True, None, None

        # Failed prepare: task should exit shortly; clear identity if matching.
        if current_session_id == session_id:
            current_session_id = None
        if session_ref.get("session_id") == session_id:
            session_ref["session"] = None
            session_ref["session_id"] = None
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

        required_prop_type = movement_required_prop_type(command.movement)
        if required_prop_type is not None and command.prop_type != required_prop_type:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=_public_session_state(
                    session_ref.get("session"),
                    current_session_id=current_session_id,
                ),
                error_code="movement_prop_mismatch",
                message=_human_error_message("movement_prop_mismatch"),
            )
            return

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

    async def handle_v1_begin_readiness(command: BeginReadinessCommand) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id

        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="begin_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        if session is not None and session.is_active:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="begin_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_already_active",
                message=_human_error_message("session_already_active"),
            )
            return

        if session is None or not (session.is_prepared or session.is_readying):
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="begin_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_not_prepared",
                message=_human_error_message("session_not_prepared"),
            )
            return

        # Idempotent: begin_readiness returns True if already readying.
        session.begin_readiness()

        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="begin_readiness",
            accepted=True,
            session_state="readying",
        )

    async def handle_v1_confirm_readiness(command: ConfirmReadinessCommand) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id

        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="confirm_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        if session is not None and session.is_active:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="confirm_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_already_active",
                message=_human_error_message("session_already_active"),
            )
            return

        if session is None or not session.is_readying:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="confirm_readiness",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_not_prepared",
                message=_human_error_message("session_not_prepared"),
            )
            return

        accepted, error_code = session.confirm_readiness()
        if not accepted:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="confirm_readiness",
                accepted=False,
                session_state="readying",
                error_code=error_code,
                message=_human_error_message(error_code or "invalid_command"),
            )
            return

        cal_scale, cal_source = session._calibration.resolved
        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="confirm_readiness",
            accepted=True,
            session_state="readying",
            calibration_scale=cal_scale,
            calibration_source=cal_source,
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

        if session is None or not (
            session.is_prepared or session.is_readying or session.is_active
        ):
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

        activated, activation_error = session.activate()
        logger.info(
            "CV session activate: movement=%s ok=%s lifecycle=%s session_id=%s",
            movement,
            activated,
            session.lifecycle,
            command.session_id,
        )

        if not activated:
            code = activation_error or "session_not_prepared"
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="activate",
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code=code,
                message=_human_error_message(code),
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
        elif isinstance(command, BeginReadinessCommand):
            await handle_v1_begin_readiness(command)
        elif isinstance(command, ConfirmReadinessCommand):
            await handle_v1_confirm_readiness(command)
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

            required_prop_type = movement_required_prop_type(movement)
            if required_prop_type is not None and prop_type != required_prop_type:
                error = FeedbackMessage(
                    bottle_detected=False,
                    prop_type=prop_type,
                    movement=movement,
                    feedback=_human_error_message("movement_prop_mismatch"),
                    feedback_type="error",
                    posture_status="unknown",
                    frame_jpeg_base64=None,
                    error_code="movement_prop_mismatch",
                    camera_ready=False,
                    session_state="unavailable",
                )
                await safe_send(error.model_dump_json())
                return

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
            if session is None or not (
                session.is_prepared or session.is_readying or session.is_active
            ):
                error = FeedbackMessage(
                    bottle_detected=False,
                    prop_type=getattr(session, "prop_type", "bottle"),
                    movement=movement,
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

            activated, activation_error = session.activate()
            logger.info(
                "CV session activate (legacy): movement=%s ok=%s lifecycle=%s",
                movement,
                activated,
                session.lifecycle,
            )
            if not activated and activation_error == "readiness_not_confirmed":
                error = FeedbackMessage(
                    bottle_detected=False,
                    prop_type=getattr(session, "prop_type", "bottle"),
                    movement=movement,
                    feedback=_human_error_message("readiness_not_confirmed"),
                    feedback_type="error",
                    posture_status="unknown",
                    frame_jpeg_base64=None,
                    error_code="readiness_not_confirmed",
                    camera_ready=False,
                    session_state="readying",
                )
                await safe_send(error.model_dump_json())

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
