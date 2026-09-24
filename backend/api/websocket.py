import asyncio
import base64
import json
import logging
import uuid
from pathlib import Path
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass, replace
from typing import Any, Awaitable, Callable

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError
from starlette.websockets import WebSocketState

from assessment.calibration import CalibrationTracker
from assessment.feedback_codes import category_for
from assessment.hold_validator import HoldValidator
from assessment.hands_profile import (
    HANDS_BARTENDER_ROI_MOVEMENTS,
    HANDS_ROTATED_FALLBACK_MOVEMENTS,
)
from assessment.readiness import (
    ReadinessObservation,
    ReadinessSnapshot,
    ReadinessTracker,
    readiness_needs_hands,
    readiness_needs_pose,
    readiness_profile_for,
)
from assessment.freestyle import (
    FREESTYLE_MOVEMENT_LABEL,
    FreestyleRecognizer,
    sanitize_allowed_movements,
)
from assessment.rule_engine import (
    evaluate_movement,
    movement_is_prop_detection_only,
    movement_max_hands,
    movement_requires_hands,
    movement_requires_pose,
    movement_required_prop_type,
    validate_movement_difficulty,
)
from assessment.scoring import RubricTracker
from assessment.rubric import RubricAssessment
from assessment.custom_movement import (
    FrameSample as CustomFrameSample,
    Landmark as CustomLandmark,
    MovementTemplate as CustomMovementTemplate,
    build_template as build_custom_movement_template,
    compare_sequence as compare_custom_movement_sequence,
    validate_sequence as validate_custom_movement_sequence,
)
from config import (
    DETECTION_PRESENTATION_GRACE_S,
    CUSTOM_PRESENTATION_MIN_GRACE_S,
    CUSTOM_PRESENTATION_MAX_GRACE_S,
    CUSTOM_PRESENTATION_CADENCE_MULTIPLIER,
    CUSTOM_INFLIGHT_PRESENTATION_LIMIT_S,
    FPS_LOG_INTERVAL,
    EVIDENCE_JPEG_QUALITY,
    EVIDENCE_MAX_BYTES,
    EVIDENCE_MAX_HEIGHT,
    EVIDENCE_MAX_WIDTH,
    JPEG_QUALITY,
    OVERLAY_DEAD_WORKER_TIMEOUT_S,
    OVERLAY_MAX_CAPTURE_AGE_S,
    OVERLAY_PRESENTATION_BASE_GRACE_S,
    OVERLAY_PRESENTATION_CADENCE_MULTIPLIER,
    OVERLAY_PRESENTATION_MAX_GRACE_S,
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
    CancelSubmissionRecordCommand,
    BuildCustomTemplateCommand,
    ConfirmReadinessCommand,
    DiscardCustomReferenceCommand,
    DeleteCustomReferenceCommand,
    TrimCustomReferenceCommand,
    FinishCustomAssessmentCommand,
    PauseCommand,
    PrepareCommand,
    PropType,
    ResumeCommand,
    StartCommand,
    StartSubmissionRecordCommand,
    StartCustomCaptureCommand,
    StopCommand,
    StopSubmissionRecordCommand,
    StopCustomCaptureCommand,
    parse_v1_command,
)
from schemas.feedback import AssessmentPayload, CriterionScorePayload, FeedbackMessage, PreviewFrameMessage
from schemas.protocol import CommandAck, ProtocolError
from schemas.recognition import RecognitionEventMessage
from vision.annotator import annotate_frame
from vision.bottle_detector import BottleDetector, ModelLoadError
from vision.bottle_marker_detector import BottleMarkerDetector
from vision.dual_prop_detector import DualPropDetector
from vision.prop_detector import PropDetector
from vision.prop_inference import (
    yolo_runtime_device_id,
    yolo_runtime_info,
    yolo_runtime_threads,
)
from vision.camera import (
    CameraCapture,
    CapturedFrame,
    camera_display_name,
    latest_frame_overwrite_count,
    latest_frame_publish_count,
    release_shared_camera,  # Compatibility export; endpoint cleanup is debounced.
    snapshot_capture_producer_telemetry,
)
from vision.startup_diagnostics import (
    MARK_ACTIVATE_ACK,
    MARK_ACTIVATE_START,
    MARK_FIRST_JPEG_ENCODE,
    MARK_FIRST_JPEG_SEND,
    MARK_ORIGIN,
    MARK_PREPARE_END,
    MARK_READINESS_START,
    MARK_READINESS_STABLE,
    MARK_WARMUP_END,
    MARK_WARMUP_START,
    StartupDiagnostics,
    camera_diagnostic_identity,
    default_sink,
    infer_identity_stable_from_device_id,
)
from vision.submission_recorder import (
    SubmissionRecorder,
    SubmissionClipMetadata,
    SubmissionRecorderError,
    cleanup_orphan_submission_temp_files,
)
from vision.pipeline_telemetry import (
    PipelineTimings as _PipelineTimings,
    format_perf_line,
    interval_rate,
    monotonic_counter_delta,
)
from vision.hands_detector import HandsDetector
from vision.overlay_snapshot import OverlaySnapshot, freeze_hands, freeze_overlay, freeze_pose
from vision.pose_detector import PoseDetector
from vision.types import HandsResult, Point2D, PoseLandmarks, PropDetection

router = APIRouter()
logger = logging.getLogger(__name__)

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


def _extract_optional_id(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None
    value = raw.strip()
    if not value or len(value) > 128:
        return None
    return value


_PREPARE_VALUE_ERROR_CODES = (
    "invalid_camera_device_id",
    "invalid_camera_index",
    "invalid_session_purpose",
    "unexpected_assessment_spec",
    "missing_custom_movement_template",
    "unexpected_custom_movement_template",
)


def _validation_error_code(exc: ValidationError) -> str:
    for err in exc.errors():
        loc = tuple(str(part) for part in err.get("loc", ()))
        msg = str(err.get("msg", ""))
        err_type = str(err.get("type", ""))

        for code in _PREPARE_VALUE_ERROR_CODES:
            if code in msg:
                return code
        if "session_purpose" in loc:
            return "invalid_session_purpose"
        if "assessment_spec" in loc:
            return "unexpected_assessment_spec"
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
        "session_not_active": "No matching active session is available.",
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
        "submission_already_recording": (
            "A submission clip is already being recorded."
        ),
        "submission_not_recording": "No submission clip is being recorded.",
        "submission_too_long": (
            "The submission clip reached the maximum duration."
        ),
        "submission_recording_not_allowed": (
            "Submission recording is only available during Teacher-created "
            "assignment practice."
        ),
        "record_failed": "Submission recording failed. Try again.",
        "invalid_session_purpose": (
            "This session purpose has been retired. Use official practice or "
            "teacher-reviewed recording."
        ),
        "unexpected_assessment_spec": (
            "assessment_spec is no longer accepted by the WebSocket API."
        ),
        "invalid_custom_movement": "This custom movement request is invalid.",
        "missing_custom_movement_template": "The saved movement template is missing.",
        "unexpected_custom_movement_template": "A template is not valid for this capture mode.",
        "custom_capture_already_recording": "A movement reference is already being recorded.",
        "custom_capture_not_recording": "No movement reference is being recorded.",
        "single_performer_required": "Keep one performer in frame before recording a reference.",
        "multiple_people_detected": "Reference rejected because multiple people were detected. Keep only one performer in frame and record it again.",
        "invalid_reference_count": "Record at least two valid references before building the template.",
        "invalid_reference_id": "That reference is no longer available.",
        "invalid_trim_range": "Keep more of the movement in the clip.",
        "reference_file_busy": "Close the reference preview and retry deleting it.",
        "insufficient_frames": "The recording was too short. Perform the complete movement and retry.",
        "missing_modality": "Keep your upper body, hands, and selected prop visible.",
        "track_loss": "The selected prop was lost for too long. Reposition and retry.",
        "invalid_timestamps": "The recording timing was invalid. Please retry.",
        "invalid_schema": "The movement template format is not supported.",
        "orientation_model_unavailable": "Bottle rotation assessment needs visible orange top and yellow base markers.",
        "insufficient_orientation": "Bottle top and base were not visible often enough to assess rotation. Improve lighting and retry.",
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


@dataclass
class _CustomReferenceDraft:
    reference_id: str
    samples: tuple[CustomFrameSample, ...]
    clip: SubmissionClipMetadata
    quality: dict[str, Any]
    trim_start_ms: int = 0
    trim_end_ms: int | None = None

    @property
    def video_duration_ms(self) -> int:
        return round(len(self.clip.frame_capture_times) * 1000 / self.clip.fps)

    def effective_samples(self) -> tuple[CustomFrameSample, ...]:
        end = self.trim_end_ms if self.trim_end_ms is not None else self.video_duration_ms
        selected = [sample for sample in self.samples if self.trim_start_ms <= sample.timestamp_ms <= end]
        if not selected:
            return ()
        origin = selected[0].timestamp_ms
        return tuple(replace(sample, timestamp_ms=sample.timestamp_ms - origin) for sample in selected)


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
        readiness_spec: dict | None = None,
        session_mode: str | None = None,
        allowed_movements: list[tuple[str, str]] | None = None,
        custom_movement_template: dict[str, Any] | None = None,
    ):
        if prop_type not in {"bottle", "shaker", "bottle_and_shaker"}:
            raise ValueError("invalid_prop_type")

        self._is_freestyle = session_mode == "freestyle"
        self._is_custom_capture = session_mode == "custom_capture"
        self._is_custom_assessment = session_mode == "custom_assessment"
        self._is_custom = self._is_custom_capture or self._is_custom_assessment
        self._custom_template = (
            CustomMovementTemplate.from_dict(custom_movement_template)
            if custom_movement_template is not None
            else None
        )
        if self._is_custom_assessment and self._custom_template is None:
            raise ValueError("missing_custom_movement_template")
        if (
            self._is_custom_assessment
            and self._custom_template is not None
            and self._custom_template.feature_capabilities.get("prop_rotation", False)
            and prop_type != "bottle"
        ):
            raise ValueError("invalid_custom_movement")
        self._orientation_detector = (
            BottleMarkerDetector()
            if prop_type == "bottle" and (
                self._is_custom_capture
                or (
                    self._is_custom_assessment
                    and self._custom_template is not None
                    and self._custom_template.feature_capabilities.get("prop_rotation", False)
                )
            )
            else None
        )
        self._orientation_enabled = (
            self._orientation_detector is not None
            and self._orientation_detector.available
        )
        if (
            self._custom_template is not None
            and self._custom_template.feature_capabilities.get("prop_rotation", False)
            and not self._orientation_enabled
        ):
            raise ValueError("orientation_model_unavailable")
        if self._is_custom_capture:
            # Observe Hands and Pose during readiness and capture. Readiness
            # still gates camera + selected prop, not landmark visibility.
            readiness_spec = {"hands": "none", "body": "none"}
        elif self._is_custom_assessment and self._custom_template is not None:
            required_sides = self._custom_template.required_hand_sides
            readiness_spec = {
                "hands": (
                    "two_hands"
                    if len(required_sides) >= 2
                    else "one_hand"
                    if required_sides
                    else "none"
                ),
                "body": (
                    "upper_body"
                    if self._custom_template.feature_capabilities.get("pose", False)
                    else "none"
                ),
            }
        if self._is_freestyle:
            prop_type = "bottle_and_shaker"

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
        self.readiness_spec = readiness_spec
        self._yolo_frame_skip = 1 if self._is_custom else YOLO_FRAME_SKIP
        if self._is_freestyle:
            diagnostics_mode = "freestyle"
        elif self._is_custom:
            diagnostics_mode = session_mode or "custom_capture"
        elif movement == "Free Practice":
            diagnostics_mode = "free_practice"
        else:
            diagnostics_mode = session_mode or "guided"
        self.startup = StartupDiagnostics(
            session_id or "legacy-session",
            sink=default_sink(),
            session_mode=diagnostics_mode,
            movement=movement,
        )
        self.startup.mark(MARK_ORIGIN)

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
        # MediaPipe detectors are deferred until camera preparation completes.
        # The session loop warms them before exposing the first live preview.
        self.hands_detector: HandsDetector | None = None
        self.pose_detector: PoseDetector | None = None
        self._prop_detection_only = movement_is_prop_detection_only(movement)
        if self._is_freestyle or self._is_custom:
            self._prop_detection_only = False
        self._hands_rotated_fallback = (
            not self._prop_detection_only
            and (
                self._is_freestyle
                or self._is_custom
                or movement in HANDS_ROTATED_FALLBACK_MOVEMENTS
            )
        )
        self._hands_bartender_roi = (
            not self._prop_detection_only
            and (
                self._is_freestyle
                or self._is_custom
                or movement in HANDS_BARTENDER_ROI_MOVEMENTS
            )
        )
        custom_hands_needed = self._is_custom_capture or (
            self._is_custom_assessment
            and self._custom_template is not None
            and self._custom_template.feature_capabilities.get("hands", False)
        )
        custom_pose_needed = self._is_custom_capture or (
            self._is_custom_assessment
            and self._custom_template is not None
            and self._custom_template.feature_capabilities.get("pose", False)
        )
        self._hands_needed = (
            not self._prop_detection_only
            and (
                self._is_freestyle or custom_hands_needed or movement_requires_hands(movement)
            )
        )
        self._pose_needed = (
            not self._prop_detection_only
            and (
                self._is_freestyle or custom_pose_needed or movement_requires_pose(movement)
            )
        )
        if self._is_custom_assessment and self._custom_template is not None:
            logger.info(
                "CUSTOM_TEMPLATE_CAPABILITIES session_id=%s movement=%s "
                "hands=%s hand_sides=%s pose=%s prop_translation=%s",
                self.session_id,
                self.movement,
                self._custom_template.feature_capabilities.get("hands", False),
                list(self._custom_template.required_hand_sides),
                self._custom_template.feature_capabilities.get("pose", False),
                self._custom_template.feature_capabilities.get(
                    "prop_translation", False
                ),
            )
        if self._is_custom_capture:
            self._hands_max = 2
        elif self._is_custom_assessment and self._custom_template is not None:
            self._hands_max = len(self._custom_template.required_hand_sides)
        elif readiness_spec is not None:
            # Teacher Activities deliberately use the internal Free Practice
            # movement so active recording stays unscored. Their explicit
            # readiness contract must still control MediaPipe construction;
            # Free Practice's catalog max_hands=0 is not authoritative here.
            self._hands_max = {
                "none": 0,
                "one_hand": 1,
                "two_hands": 2,
            }.get(readiness_spec.get("hands"), 0)
        else:
            self._hands_max = (
                2 if (self._is_freestyle or self._is_custom) else movement_max_hands(movement)
            )
        self.rubric = RubricTracker()

        self._frame_index = 0
        self._last_bottles: list[PropDetection] = []
        self._last_shakers: list[PropDetection] = []
        self._last_live_bottles: list[PropDetection] = []
        self._last_live_shakers: list[PropDetection] = []
        self._recognizer: FreestyleRecognizer | None = (
            FreestyleRecognizer(
                allowed_movements=sanitize_allowed_movements(allowed_movements)
            )
            if self._is_freestyle
            else None
        )
        self._recognition_paused = False
        self._pending_recognition_events: list[RecognitionEventMessage] = []
        self._recognition_event_seq = 0
        self._freestyle_display: str | None = None

        # Assessment always uses current-frame landmarks. Only the short-lived
        # render cache below may bridge detector misses within its age limit.
        self._prev_hip_center: Point2D | None = None
        self._movement_state: dict | None = None
        self._model_checked = False
        self._model_error: FeedbackMessage | None = None
        self._readiness_warmed = False
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
        self.preview_timings = _PipelineTimings()
        # Wall-clock start of the latest process_* call (for end_to_end timing).
        self._pipeline_started_at: float | None = None
        self._preview_started_at: float | None = None
        self._overlay_lock = threading.Lock()
        # Presentation state is built by AI and may be expired by preview.
        # Always acquire this before _overlay_lock when both are needed.
        self._presentation_lock = threading.RLock()
        self._overlay_snapshot: OverlaySnapshot | None = None
        self._presentation_generation: int | None = None
        self._prop_confirmed_at: dict[tuple[str, int], float] = {}
        self._presented_props: dict[tuple[str, int], PropDetection] = {}
        self._presented_hands: tuple[HandsResult, float, int] | None = None
        self._presented_pose: tuple[PoseLandmarks, float, int] | None = None
        self._last_overlay_published_at: float | None = None
        self._overlay_publish_period_s: float | None = None
        self._preview_run_lock = threading.Lock()
        # State lock serializes lifecycle mutation against AI analysis.
        # Tick lock enforces at most one actual analyze_tick() execution.
        # These must not be the same lock: lifecycle ownership is not a
        # duplicate AI worker.
        self._ai_state_lock = threading.Lock()
        self._ai_tick_lock = threading.Lock()
        self._last_preview_sequence: int | None = None
        self._last_ai_sequence: int | None = None
        self._last_ai_generation: int | None = None
        self._ai_camera_overwrites = 0
        self._ai_inflight_max = 0
        self._ai_inflight = 0
        self._ai_inflight_started_at: float | None = None
        self._ai_lifecycle_skips = 0
        # Two bounded lanes overlap independent GPU YOLO and CPU landmark work
        # inside the one analyze_tick that is already allowed in flight.
        self._inference_executor = ThreadPoolExecutor(
            max_workers=2,
            thread_name_prefix="elixr-inference",
        )
        self._inference_executor_shutdown = False
        self._submission_recorder: SubmissionRecorder | None = None
        self._submission_recorder_lock = threading.Lock()
        self._custom_references: list[_CustomReferenceDraft] = []
        self._custom_video_recorder: SubmissionRecorder | None = None
        self._custom_video_lock = threading.Lock()
        self._custom_sample_capture_times: list[float] = []
        self._custom_samples: list[CustomFrameSample] | None = None
        self._custom_capture_started_at: float | None = None
        self._custom_capture_deadline: float | None = None
        self._custom_previous_prop: tuple[float, float, int] | None = None
        # Single-person readiness needs two observations. Distinct people need
        # three current-frame observations spanning a short real-time interval.
        self._custom_single_streak = 0
        self._custom_multiple_streak = 0
        self._custom_multiple_first_at: float | None = None
        self._custom_distinct_people_in_frame = False
        self._custom_person_count = 0
        self._custom_person_observed_at: float | None = None
        self._custom_multiple_invalid = False
        self._custom_primary_anchors: dict[str, tuple[float, float, float, float]] = {}
        self._custom_ambiguous_anchors: dict[str, tuple[float, float, float, float]] = {}
        self._custom_awaiting_identity = False
        self._orientation_inference_count = 0
        self._orientation_inference_ms = 0.0

    def set_submission_recorder(self, recorder: SubmissionRecorder | None) -> None:
        with self._submission_recorder_lock:
            self._submission_recorder = recorder

    def _feed_submission_recorder(self, captured: CapturedFrame) -> None:
        with self._submission_recorder_lock:
            recorder = self._submission_recorder
        if recorder is None or not recorder.is_recording:
            return
        recorder.write_frame(
            captured.frame,
            captured_at_monotonic=captured.captured_at_monotonic,
            sequence=captured.sequence,
        )

        # Assignment and reference recording are mutually exclusive session
        # purposes. Both consume the same preview frame; neither opens a camera.

    def _feed_custom_recorder(self, captured: CapturedFrame) -> None:
        with self._custom_video_lock:
            recorder = self._custom_video_recorder
        if recorder is not None and recorder.is_recording:
            recorder.write_frame(
                captured.frame,
                captured_at_monotonic=captured.captured_at_monotonic,
                sequence=captured.sequence,
            )

    @property
    def is_custom_capture_session(self) -> bool:
        return self._is_custom_capture

    @property
    def is_custom_assessment_session(self) -> bool:
        return self._is_custom_assessment

    @property
    def custom_reference_count(self) -> int:
        return len(self._custom_references)

    def _observe_custom_people(
        self, pose: Any, *, captured_at_monotonic: float | None = None
    ) -> None:
        if not self._is_custom_capture:
            return
        # MediaPipe may return two candidates for one body. The detector
        # validates spatially distinct current-frame torso anchors first.
        # A detector without this evidence cannot certify one performer.
        count = min(2, getattr(self.pose_detector, "last_distinct_person_count", 0))
        if count == 1 and pose is None:
            count = 0
        self._custom_person_observed_at = (
            time.monotonic() if captured_at_monotonic is None
            else captured_at_monotonic
        )
        self._custom_distinct_people_in_frame = count >= 2
        if count == 1:
            anchors = self._custom_pose_anchors(
                pose, observed_at=self._custom_person_observed_at
            )
            if self._custom_awaiting_identity:
                comparable = set(anchors) & set(self._custom_ambiguous_anchors)
                if comparable:
                    # Only compare the same joint pair. The position allowance
                    # grows with elapsed time for fast legitimate body motion.
                    for kind in comparable:
                        x, y, width, _ = anchors[kind]
                        old_x, old_y, old_width, old_at = (
                            self._custom_ambiguous_anchors[kind]
                        )
                        max_shift = min(
                            0.35,
                            0.15 + 1.5 * (self._custom_person_observed_at - old_at),
                        )
                        if (
                            abs(x - old_x) > max_shift
                            or abs(y - old_y) > max_shift
                            or width < old_width * 0.5
                            or width > old_width * 2.0
                        ):
                            self._custom_multiple_invalid = True
                    self._custom_awaiting_identity = False
                    self._custom_ambiguous_anchors = {}
            self._custom_primary_anchors.update(anchors)
            self._custom_single_streak += 1
            self._custom_multiple_streak = 0
            self._custom_multiple_first_at = None
            self._custom_person_count = 1 if self._custom_single_streak >= 2 else 0
        elif count >= 2:
            if self._custom_samples is not None and not self._custom_awaiting_identity:
                self._custom_ambiguous_anchors = {
                    kind: anchor
                    for kind, anchor in self._custom_primary_anchors.items()
                    if self._custom_person_observed_at - anchor[3] <= 0.5
                }
                self._custom_awaiting_identity = True
            if self._custom_multiple_streak == 0:
                self._custom_multiple_first_at = self._custom_person_observed_at
            self._custom_multiple_streak += 1
            self._custom_single_streak = 0
            self._custom_person_count = 2 if (
                self._custom_multiple_streak >= 3
                and self._custom_multiple_first_at is not None
                and self._custom_person_observed_at - self._custom_multiple_first_at
                >= 2.0 / TARGET_FPS
            ) else 0
            if self._custom_person_count == 2 and self._custom_samples is not None:
                self._custom_multiple_invalid = True
        else:
            self._custom_single_streak = 0
            self._custom_multiple_streak = 0
            self._custom_multiple_first_at = None
            self._custom_person_count = 0

    @staticmethod
    def _custom_pose_anchors(
        pose: Any, *, observed_at: float
    ) -> dict[str, tuple[float, float, float, float]]:
        if pose is None:
            return {}
        anchors = {}
        for kind, left, right in (("shoulders", 11, 12), ("hips", 23, 24)):
            first = pose.points.get(left)
            second = pose.points.get(right)
            if (
                first is not None
                and second is not None
                and pose.visibility.get(left, 0) >= 0.5
                and pose.visibility.get(right, 0) >= 0.5
            ):
                anchors[kind] = (
                    (first.x + second.x) / 2,
                    (first.y + second.y) / 2,
                    abs(first.x - second.x),
                    observed_at,
                )
        return anchors

    def _single_custom_performer_ready(self) -> bool:
        return (
            self._custom_person_count == 1
            and self._custom_person_observed_at is not None
            and time.monotonic() - self._custom_person_observed_at <= READINESS_SNAPSHOT_MAX_AGE_S
        )

    def start_custom_capture(self, *, duration_seconds: int) -> tuple[bool, str | None]:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom or not self.is_active:
                return False, "invalid_session_purpose"
            if self._custom_samples is not None:
                return False, "custom_capture_already_recording"
            if self._is_custom_capture and len(self._custom_references) >= 10:
                return False, "invalid_reference_count"
            if self._is_custom_capture and not self._single_custom_performer_ready():
                return False, "single_performer_required"
            if self._is_custom_capture:
                recorder = SubmissionRecorder(max_duration_s=duration_seconds)
                try:
                    recorder.start()
                except SubmissionRecorderError as exc:
                    return False, exc.code
                with self._custom_video_lock:
                    self._custom_video_recorder = recorder
            self._custom_samples = []
            self._custom_sample_capture_times = []
            self._custom_multiple_invalid = False
            self._custom_awaiting_identity = False
            self._custom_ambiguous_anchors = {}
            self._custom_capture_started_at = time.monotonic()
            self._custom_capture_deadline = (
                self._custom_capture_started_at + duration_seconds
            )
            self._custom_previous_prop = None
            self._orientation_inference_count = 0
            self._orientation_inference_ms = 0.0
            return True, None
        finally:
            self._release_ai_state()

    def stop_custom_capture(self) -> tuple[bool, str | None, dict[str, Any]]:
        self._acquire_ai_state(blocking=True)
        try:
            samples = tuple(self._custom_samples or ())
            sample_times = tuple(self._custom_sample_capture_times)
            self._custom_sample_capture_times = []
            with self._custom_video_lock:
                recorder = self._custom_video_recorder
                self._custom_video_recorder = None
            self._custom_samples = None
            self._custom_capture_started_at = None
            self._custom_capture_deadline = None
            self._custom_previous_prop = None
            multiple_invalid = self._custom_multiple_invalid
            identity_unresolved = self._custom_awaiting_identity
            self._custom_multiple_invalid = False
            self._custom_awaiting_identity = False
            self._custom_ambiguous_anchors = {}
            if multiple_invalid or identity_unresolved:
                if recorder is not None:
                    recorder.cancel()
                return False, "multiple_people_detected", {
                    "valid": False,
                    "accepted": False,
                    "frame_count": len(samples),
                    "rejected_reason": "multiple_people_detected",
                }
            if not samples:
                if recorder is not None:
                    recorder.cancel()
                return False, "custom_capture_not_recording", {}
            clip = None
            if self._is_custom_capture:
                try:
                    if recorder is None:
                        raise SubmissionRecorderError("record_failed", "Reference video is unavailable.")
                    clip = recorder.stop()
                    paired = [
                        (video_ms, sample)
                        for sample, observed_at in zip(samples, sample_times)
                        if (video_ms := clip.video_ms_for_capture(observed_at)) is not None
                    ]
                    mapped: list[CustomFrameSample] = []
                    for video_ms, sample in paired:
                        timestamp_ms = max(video_ms, mapped[-1].timestamp_ms + 1 if mapped else 0)
                        mapped.append(replace(sample, timestamp_ms=timestamp_ms))
                    samples = tuple(mapped)
                    if not samples:
                        recorder.cancel()
                        return False, "insufficient_frames", {"valid": False, "accepted": False}
                except SubmissionRecorderError as exc:
                    if recorder is not None:
                        recorder.cancel()
                    return False, exc.code, {"valid": False, "accepted": False}
            required_modalities = (
                self._custom_template.required_modalities
                if self._is_custom_assessment and self._custom_template is not None
                else ("prop_translation",)
            )
            required_hand_sides = (
                self._custom_template.required_hand_sides
                if self._is_custom_assessment and self._custom_template is not None
                else ()
            )
            validation = validate_custom_movement_sequence(
                samples,
                required_modalities,
                required_hand_sides=required_hand_sides,
            )
            rejected_reason = (
                validation.codes[0].value if validation.codes else None
            )
            quality = {
                "valid": validation.valid,
                "frame_count": len(samples),
                "duration_ms": samples[-1].timestamp_ms,
                "codes": [code.value for code in validation.codes],
                **self._custom_capture_diagnostics(
                    samples,
                    orientation_ms=self._orientation_inference_ms,
                    orientation_count=self._orientation_inference_count,
                    orientation_provider=(self._orientation_detector.provider if self._orientation_detector else None),
                ),
                "accepted": validation.valid,
                "rejected_reason": rejected_reason,
            }
            logger.info(
                "CUSTOM_CAPTURE_DIAGNOSTICS session_id=%s mode=%s diagnostics=%s",
                self.session_id,
                "assessment" if self._is_custom_assessment else "reference",
                quality,
            )
            if not validation.valid:
                if recorder is not None:
                    recorder.cancel()
                code = validation.codes[0].value if validation.codes else "invalid_reference"
                return False, code, quality
            if self._is_custom_capture:
                assert clip is not None
                draft = _CustomReferenceDraft(
                    reference_id=uuid.uuid4().hex,
                    samples=samples,
                    clip=clip,
                    quality=quality,
                )
                self._custom_references.append(draft)
                quality.update({
                    "reference_id": draft.reference_id,
                    "local_file_path": clip.local_path,
                    "video_duration_ms": draft.video_duration_ms,
                    "trim_start_ms": 0,
                    "trim_end_ms": draft.video_duration_ms,
                })
            else:
                # Assessment capture is retained until finish_custom_assessment.
                self._custom_samples = list(samples)
            return True, None, quality
        finally:
            self._release_ai_state()

    def discard_custom_reference(self) -> int:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom_capture:
                raise ValueError("invalid_session_purpose")
            if self._custom_samples is not None:
                raise ValueError("custom_capture_already_recording")
            if self._custom_references:
                self._delete_custom_draft(self._custom_references[-1])
                self._custom_references.pop()
            return len(self._custom_references)
        finally:
            self._release_ai_state()

    @staticmethod
    def _delete_custom_draft(draft: _CustomReferenceDraft) -> None:
        try:
            Path(draft.clip.local_path).unlink(missing_ok=True)
        except OSError as exc:
            raise ValueError("reference_file_busy") from exc

    def delete_custom_reference(self, reference_id: str) -> int:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom_capture or self._custom_samples is not None:
                raise ValueError("invalid_session_purpose")
            for index, draft in enumerate(self._custom_references):
                if draft.reference_id == reference_id:
                    self._delete_custom_draft(draft)
                    self._custom_references.pop(index)
                    return len(self._custom_references)
            raise ValueError("invalid_reference_id")
        finally:
            self._release_ai_state()

    def trim_custom_reference(self, reference_id: str, start_ms: int, end_ms: int) -> dict[str, Any]:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom_capture or self._custom_samples is not None:
                raise ValueError("invalid_session_purpose")
            draft = next((item for item in self._custom_references if item.reference_id == reference_id), None)
            if draft is None:
                raise ValueError("invalid_reference_id")
            if start_ms < 0 or end_ms > draft.video_duration_ms or end_ms <= start_ms:
                raise ValueError("invalid_trim_range")
            candidate = replace(draft, trim_start_ms=start_ms, trim_end_ms=end_ms)
            validation = validate_custom_movement_sequence(candidate.effective_samples(), ("prop_translation",))
            if not validation.valid:
                raise ValueError("invalid_trim_range")
            draft.trim_start_ms = start_ms
            draft.trim_end_ms = end_ms
            return {"reference_id": reference_id, "trim_start_ms": start_ms, "trim_end_ms": end_ms}
        finally:
            self._release_ai_state()

    def build_custom_template(self) -> dict[str, Any]:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom_capture:
                raise ValueError("invalid_session_purpose")
            template = build_custom_movement_template(
                tuple(draft.effective_samples() for draft in self._custom_references),
            )
            return template.to_dict()
        finally:
            self._release_ai_state()

    def finish_custom_assessment(self) -> dict[str, Any]:
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_custom_assessment or self._custom_template is None:
                raise ValueError("invalid_session_purpose")
            samples = tuple(self._custom_samples or ())
            if not samples:
                raise ValueError("custom_capture_not_recording")
            result = compare_custom_movement_sequence(self._custom_template, samples)
            if not result.validation.valid:
                code = result.validation.codes[0].value
                raise ValueError(code)
            payload = result.to_dict()
            payload["max_total"] = 12
            payload["score_percent"] = round(result.total * 100 / 12, 1)
            payload["feedback"] = [
                f"{name}: {score}/3"
                for name, score in result.component_scores.items()
                if score is not None
            ]
            if (
                result.rotation_diagnostics.get("rotation_required")
                and result.rotation_diagnostics.get("rotation_evidence") != "verified"
            ):
                payload["feedback"].append(
                    "Bottle rotation could not be fully verified. Keep the top and base markers visible during the flip."
                )
            payload["sequence_duration_ms"] = samples[-1].timestamp_ms
            payload["diagnostics"] = self._custom_capture_diagnostics(
                samples,
                orientation_ms=self._orientation_inference_ms,
                orientation_count=self._orientation_inference_count,
                orientation_provider=(self._orientation_detector.provider if self._orientation_detector else None),
            )
            payload["diagnostics"].update(result.rotation_diagnostics)
            self._custom_samples = None
            return payload
        finally:
            self._release_ai_state()

    def _record_custom_sample(
        self,
        *,
        captured: CapturedFrame,
        frame,
        normalized: _NormalizedFrameDetections,
        hands,
        pose,
        yolo_attempted: bool,
        orientation=None,
    ) -> None:
        samples = self._custom_samples
        started = self._custom_capture_started_at
        if samples is None or started is None:
            return
        if self._custom_capture_deadline is not None and time.monotonic() > self._custom_capture_deadline:
            return
        raw_timestamp = round((captured.captured_at_monotonic - started) * 1000)
        timestamp_ms = max(0, raw_timestamp)
        if samples:
            timestamp_ms = max(samples[-1].timestamp_ms + 1, timestamp_ms)

        pose_points: dict[str, CustomLandmark] = {}
        if pose is not None:
            for index, point in pose.points.items():
                pose_points[str(index)] = CustomLandmark(
                    float(point.x), float(point.y),
                    float(pose.visibility.get(index, 0.0)),
                )

        hand_points: dict[str, CustomLandmark] = {}
        if hands is not None:
            for hand_index, hand in enumerate(hands.hands):
                side = str(hand.handedness or "unknown").strip().lower()
                for landmark_index, point in hand.points.items():
                    hand_points[f"{side}:{hand_index}:{landmark_index}"] = CustomLandmark(
                        float(point.x), float(point.y), 1.0
                    )

        # Custom templates are authoritative assessment input.  The tracker
        # may coast a box for presentation, but a coasted prop must never
        # become a recorded reference/assessment landmark.
        detection = (
            max(normalized.primary, key=lambda item: item.confidence)
            if normalized.primary
            else None
        )
        prop_point = None
        prop_metadata: dict[str, Any] = {"yolo_attempted": yolo_attempted}
        if detection is not None:
            height, width = int(frame.shape[0]), int(frame.shape[1])
            center = detection.center_normalized(width, height)
            prop_point = CustomLandmark(
                float(center.x), float(center.y), float(detection.confidence)
            )
            velocity_x = velocity_y = 0.0
            if self._custom_previous_prop is not None:
                previous_x, previous_y, previous_ms = self._custom_previous_prop
                elapsed = max(1, timestamp_ms - previous_ms) / 1000.0
                velocity_x = (center.x - previous_x) / elapsed
                velocity_y = (center.y - previous_y) / elapsed
            self._custom_previous_prop = (center.x, center.y, timestamp_ms)
            prop_metadata = {
                "yolo_attempted": yolo_attempted,
                "track_id": detection.track_id,
                "class": self.prop_type,
                "bbox_width": (detection.x2 - detection.x1) / max(width, 1),
                "bbox_height": (detection.y2 - detection.y1) / max(height, 1),
                "velocity_x": velocity_x,
                "velocity_y": velocity_y,
                "movement_direction": (
                    "stationary" if abs(velocity_x) + abs(velocity_y) < 0.05
                    else "up" if velocity_y < -abs(velocity_x)
                    else "down" if velocity_y > abs(velocity_x)
                    else "left" if velocity_x < 0
                    else "right"
                ),
                "yolo_confirmed": bool(detection.yolo_confirmed),
                "coasted": not bool(detection.yolo_confirmed),
            }

        samples.append(CustomFrameSample(
            timestamp_ms=timestamp_ms,
            pose=pose_points,
            hands=hand_points,
            prop=prop_point,
            prop_metadata=prop_metadata,
            orientation=orientation,
        ))
        self._custom_sample_capture_times.append(captured.captured_at_monotonic)

    @staticmethod
    def _custom_capture_diagnostics(
        samples: tuple[CustomFrameSample, ...],
        *,
        orientation_ms: float = 0.0,
        orientation_count: int = 0,
        orientation_provider: str | None = None,
    ) -> dict[str, Any]:
        frame_count = len(samples)
        duration_ms = samples[-1].timestamp_ms if samples else 0
        attempted = sum(
            frame.prop_metadata.get("yolo_attempted") is True for frame in samples
        )
        confirmed = sum(
            frame.prop_metadata.get("yolo_attempted") is True
            and frame.prop_metadata.get("yolo_confirmed") is True
            for frame in samples
        )
        observed_track_ids = [
            frame.prop_metadata.get("track_id")
            for frame in samples
            if frame.prop is not None
            and frame.prop_metadata.get("track_id") is not None
        ]
        track_changes = sum(
            current != previous
            for previous, current in zip(
                observed_track_ids, observed_track_ids[1:]
            )
        )
        longest_gap = current_gap = 0
        for frame in samples:
            current_gap = current_gap + 1 if frame.prop is None else 0
            longest_gap = max(longest_gap, current_gap)

        def coverage(predicate) -> float:
            if not samples:
                return 0.0
            return round(sum(predicate(frame) for frame in samples) / frame_count, 3)

        return {
            "orientation_inference_ms_mean": round(
                orientation_ms / orientation_count, 2
            ) if orientation_count else None,
            "orientation_provider": orientation_provider,
            "effective_processing_fps": round(
                (frame_count - 1) * 1000 / duration_ms, 2
            )
            if frame_count > 1 and duration_ms > 0
            else 0.0,
            "yolo_confirmation_rate": round(confirmed / attempted, 3)
            if attempted
            else 0.0,
            "yolo_attempts": attempted,
            "prop_track_changes": track_changes,
            "longest_prop_observation_gap_frames": longest_gap,
            "pose_coverage": coverage(
                lambda frame: any(point.usable() for point in frame.pose.values())
            ),
            "left_hand_coverage": coverage(
                lambda frame: any(
                    str(key).split(":", 1)[0].lower() == "left"
                    and point.usable()
                    for key, point in frame.hands.items()
                )
            ),
            "right_hand_coverage": coverage(
                lambda frame: any(
                    str(key).split(":", 1)[0].lower() == "right"
                    and point.usable()
                    for key, point in frame.hands.items()
                )
            ),
            "sequence_duration_ms": duration_ms,
        }

    def _acquire_ai_state(self, *, blocking: bool) -> bool:
        """Exclusive access to AI/lifecycle mutation. Preview must not call this.

        Blocking waits are for lifecycle methods running off the asyncio loop.
        The AI worker uses non-blocking acquire and treats failure as normal
        contention: skip this newest-frame tick rather than crash.
        """
        if blocking:
            self._ai_state_lock.acquire()
            return True
        return self._ai_state_lock.acquire(blocking=False)

    def _release_ai_state(self) -> None:
        self._ai_state_lock.release()

    def _normalize_detections(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
    ) -> _NormalizedFrameDetections:
        """Expose only currently YOLO-confirmed props to rules/UI."""
        bottle_list = tuple(
            detection
            for detection in bottles
            if detection.yolo_confirmed
        )
        shaker_list = tuple(
            detection
            for detection in shakers
            if detection.yolo_confirmed
        )
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
            live_bottles = list(dual_result.bottles)
            live_shakers = list(dual_result.shakers)
        else:
            detected = list(self.prop_detector.detect(frame))
            if self.prop_type == "shaker":
                live_bottles, live_shakers = [], detected
            else:
                live_bottles, live_shakers = detected, []
        self._last_live_bottles = live_bottles
        self._last_live_shakers = live_shakers
        return self._normalize_detections(
            bottles=live_bottles,
            shakers=live_shakers,
        )

    def _cached_normalized_props(self) -> _NormalizedFrameDetections:
        bottles = list(self._last_live_bottles)
        shakers = list(self._last_live_shakers)
        extrapolate = getattr(self.prop_detector, "extrapolate_detections", None)
        if callable(extrapolate):
            bottles, shakers = extrapolate(
                bottles=bottles,
                shakers=shakers,
                now=time.monotonic(),
            )
        self._last_live_bottles = list(bottles)
        self._last_live_shakers = list(shakers)
        return self._normalize_detections(
            bottles=list(bottles),
            shakers=list(shakers),
        )

    def _store_normalized_props(self, normalized: _NormalizedFrameDetections) -> None:
        self._last_bottles = list(normalized.bottles)
        self._last_shakers = list(normalized.shakers)

    def _acquire_captured_frame(
        self,
        *,
        newer_than: int | None = None,
        timeout: float | None = None,
        timings: _PipelineTimings | None = None,
    ) -> CapturedFrame | None:
        """Latest camera frame for preview or AI. Never builds a FIFO backlog."""
        clock = timings if timings is not None else self.timings
        t0 = time.perf_counter()
        peek = getattr(self.camera, "peek_latest", None)
        if callable(peek):
            captured = peek(newer_than=newer_than, timeout=timeout)
        else:
            frame = self.camera.read()
            if frame is None:
                clock.add("camera", time.perf_counter() - t0)
                return None
            captured_at = getattr(self.camera, "last_captured_at_monotonic", None)
            sequence = getattr(self.camera, "last_capture_sequence", None)
            generation = getattr(self.camera, "last_capture_generation", None)
            captured = CapturedFrame(
                frame=frame,
                captured_at_monotonic=(
                    captured_at if captured_at is not None else time.monotonic()
                ),
                sequence=int(sequence or 0),
                generation=int(generation or 0),
            )
            if newer_than is not None and captured.sequence <= newer_than:
                clock.add("camera", time.perf_counter() - t0)
                return None
        clock.add("camera", time.perf_counter() - t0)
        return captured

    def _publish_overlay(self, snapshot: OverlaySnapshot) -> None:
        with self._overlay_lock:
            previous = self._last_overlay_published_at
            if previous is not None:
                period = snapshot.published_at_monotonic - previous
                if period > 0.0:
                    self.preview_timings.add("overlay_publish_interval", period)
                    # A small EMA resists one scheduling outlier while staying
                    # responsive to a sustained slower custom pipeline.
                    old = self._overlay_publish_period_s
                    self._overlay_publish_period_s = (
                        period if old is None else (old * 0.7) + (period * 0.3)
                    )
            self._last_overlay_published_at = snapshot.published_at_monotonic
            self._overlay_snapshot = snapshot

    def _clear_overlay(self) -> None:
        with self._presentation_lock:
            with self._overlay_lock:
                self._overlay_snapshot = None
                self._last_overlay_published_at = None
                self._overlay_publish_period_s = None
                self._ai_inflight_started_at = None
            self._presentation_generation = None
            self._prop_confirmed_at.clear()
            self._presented_props.clear()
            self._presented_hands = None
            self._presented_pose = None

    def _presentation_continuity_s(self) -> float:
        with self._overlay_lock:
            period = self._overlay_publish_period_s
        cadence_grace = (
            period * OVERLAY_PRESENTATION_CADENCE_MULTIPLIER
            if period is not None
            else OVERLAY_PRESENTATION_BASE_GRACE_S
        )
        continuity = min(
            OVERLAY_PRESENTATION_MAX_GRACE_S,
            max(OVERLAY_PRESENTATION_BASE_GRACE_S, cadence_grace),
        )
        return max(continuity, self._custom_presentation_grace_s()) if self._is_custom else continuity

    def _custom_presentation_grace_s(self) -> float:
        if not self._is_custom:
            return DETECTION_PRESENTATION_GRACE_S
        with self._overlay_lock:
            period = self._overlay_publish_period_s
        candidate = (period * CUSTOM_PRESENTATION_CADENCE_MULTIPLIER) if period else CUSTOM_PRESENTATION_MIN_GRACE_S
        return min(CUSTOM_PRESENTATION_MAX_GRACE_S, max(CUSTOM_PRESENTATION_MIN_GRACE_S, candidate))

    def _preview_presentation_metadata(
        self, overlay: OverlaySnapshot | None
    ) -> dict[str, Any]:
        """State of the annotation drawn into a preview JPEG, never scoring."""
        if not self._is_custom:
            return {}
        if overlay is None:
            return {
                "vision_overlay_present": False,
                "prop_presentation_state": "missing",
                "hands_presentation_state": "missing" if self._hands_needed else None,
                "pose_presentation_state": "missing" if self._pose_needed else None,
                "overlay_capture_sequence": None,
            }
        boxes = overlay.boxes
        prop_state = (
            "coasted" if any(not box.yolo_confirmed for box in boxes)
            else "confirmed" if boxes else "missing"
        )
        return {
            "vision_overlay_present": True,
            "prop_presentation_state": prop_state,
            "hands_presentation_state": (
                "tracking" if overlay.hands is not None
                and any(hand.points for hand in overlay.hands.hands) else "missing"
            ) if self._hands_needed else None,
            "pose_presentation_state": (
                "tracking" if overlay.pose is not None and overlay.pose.points else "missing"
            ) if self._pose_needed else None,
            "overlay_capture_sequence": overlay.capture_sequence,
        }

    def _presentation_boxes(
        self, *, captured_at: float, generation: int, run_yolo: bool
    ) -> tuple[list[PropDetection], tuple[float | None, ...]]:
        """Draw live tracks with an independent, brief coast deadline."""
        self._ensure_presentation_generation(generation)
        if self._is_dual_prop:
            live = [("bottle", box) for box in self._last_live_bottles] + [
                ("shaker", box) for box in self._last_live_shakers
            ]
        elif self.prop_type == "shaker":
            live = [("shaker", box) for box in self._last_live_shakers]
        else:
            live = [("bottle", box) for box in self._last_live_bottles]
        boxes: list[PropDetection] = []
        expiries: list[float | None] = []
        live_keys: set[tuple[str, int]] = set()
        grace = self._custom_presentation_grace_s()
        for kind, detection in live:
            key = (kind, detection.track_id if detection.track_id is not None else -1) if (detection.track_id is not None or self._is_custom) else None
            if key is not None:
                live_keys.add(key)
            if detection.yolo_confirmed and run_yolo:
                if key is not None:
                    self._prop_confirmed_at[key] = captured_at
                    self._presented_props[key] = detection
                boxes.append(detection)
                expiries.append(captured_at + grace if self._is_custom else None)
            elif key is not None:
                last_confirmed = self._prop_confirmed_at.get(key)
                if last_confirmed is not None:
                    expires = last_confirmed + grace
                    if captured_at <= expires:
                        # A skipped YOLO tick can extrapolate a prior confirmed
                        # box, but that is tracking geometry, not new evidence.
                        boxes.append(replace(detection, yolo_confirmed=False))
                        expiries.append(expires)
        if self._is_custom:
            confirmed_kinds = {
                kind for kind, detection in live if detection.yolo_confirmed and run_yolo
            }
            for key, last_confirmed in list(self._prop_confirmed_at.items()):
                expires = last_confirmed + grace
                if captured_at > expires or (key[0] in confirmed_kinds and key not in live_keys):
                    self._prop_confirmed_at.pop(key, None)
                    self._presented_props.pop(key, None)
                elif key not in live_keys and key in self._presented_props:
                    boxes.append(replace(self._presented_props[key], yolo_confirmed=False))
                    expiries.append(expires)
        elif run_yolo:
            self._prop_confirmed_at = {
                key: stamp for key, stamp in self._prop_confirmed_at.items() if key in live_keys
            }
        return boxes, tuple(expiries)

    def _ensure_presentation_generation(self, generation: int) -> None:
        if self._presentation_generation != generation:
            self._prop_confirmed_at.clear()
            self._presented_props.clear()
            self._presented_hands = None
            self._presented_pose = None
            self._presentation_generation = generation

    def _presentation_landmarks(
        self, *, hands: HandsResult | None, pose: PoseLandmarks | None,
        captured_at: float, generation: int,
    ) -> tuple[HandsResult | None, PoseLandmarks | None, float | None, float | None]:
        """Bridge detector misses by original observation age for drawing only."""
        self._ensure_presentation_generation(generation)
        grace = self._custom_presentation_grace_s()
        if hands is not None and any(hand.points for hand in hands.hands):
            self._presented_hands = (freeze_hands(hands), captured_at, generation)
            drawn_hands, hands_expiry = hands, captured_at + grace if self._is_custom else None
        elif self._presented_hands is not None:
            cached, observed_at, cached_generation = self._presented_hands
            if (cached_generation == generation
                    and captured_at <= observed_at + grace):
                drawn_hands, hands_expiry = cached, observed_at + grace
            else:
                self._presented_hands = None
                drawn_hands, hands_expiry = None, None
        else:
            drawn_hands, hands_expiry = None, None

        multiple_people = self._is_custom_capture and self._custom_distinct_people_in_frame
        if multiple_people:
            self._presented_pose = None
            drawn_pose, pose_expiry = None, None
        elif pose is not None and pose.points:
            self._presented_pose = (freeze_pose(pose), captured_at, generation)
            drawn_pose, pose_expiry = pose, captured_at + grace if self._is_custom else None
        elif self._presented_pose is not None:
            cached, observed_at, cached_generation = self._presented_pose
            if (cached_generation == generation
                    and captured_at <= observed_at + grace):
                drawn_pose, pose_expiry = cached, observed_at + grace
            else:
                self._presented_pose = None
                drawn_pose, pose_expiry = None, None
        else:
            self._presented_pose = None
            drawn_pose, pose_expiry = None, None
        return drawn_hands, drawn_pose, hands_expiry, pose_expiry

    def _publish_presentation(
        self, *, captured: CapturedFrame, run_yolo: bool,
        hands: HandsResult | None, pose: PoseLandmarks | None,
        feedback: str, feedback_type: str, prop_label: str,
    ) -> OverlaySnapshot:
        with self._presentation_lock:
            boxes, box_expiries = self._presentation_boxes(
                captured_at=captured.captured_at_monotonic,
                generation=captured.generation,
                run_yolo=run_yolo,
            )
            drawn_hands, drawn_pose, hands_expiry, pose_expiry = self._presentation_landmarks(
                hands=hands, pose=pose,
                captured_at=captured.captured_at_monotonic,
                generation=captured.generation,
            )
            snapshot = freeze_overlay(
                published_at_monotonic=time.monotonic(),
                captured_at_monotonic=captured.captured_at_monotonic,
                capture_sequence=captured.sequence,
                capture_generation=captured.generation,
                boxes=boxes,
                box_expires_at=box_expiries,
                hands=drawn_hands,
                hands_expires_at=hands_expiry,
                pose=drawn_pose,
                pose_expires_at=pose_expiry,
                feedback=feedback,
                feedback_type=feedback_type,
                movement=self.display_movement,
                prop_label=prop_label,
            )
            self._publish_overlay(snapshot)
            return snapshot

    def _read_fresh_overlay(
        self,
        *,
        preview: CapturedFrame | None = None,
        now: float | None = None,
    ) -> OverlaySnapshot | None:
        with self._overlay_lock:
            snapshot = self._overlay_snapshot
        if snapshot is None:
            return None
        if now is None:
            now = time.monotonic()
        with self._overlay_lock:
            inflight_started = self._ai_inflight_started_at
        alive_inflight = (
            self._is_custom
            and inflight_started is not None
            and now - inflight_started <= CUSTOM_INFLIGHT_PRESENTATION_LIMIT_S
        )
        if not snapshot.is_fresh(now, OVERLAY_DEAD_WORKER_TIMEOUT_S) and not alive_inflight:
            # A dead AI worker must not leave a positive presentation snapshot
            # around for a later camera frame.
            with self._presentation_lock:
                with self._overlay_lock:
                    if self._overlay_snapshot is snapshot:
                        self._overlay_snapshot = None
                        self._presented_hands = None
                        self._presented_pose = None
                        self._prop_confirmed_at.clear()
                        self._presented_props.clear()
                        self.preview_timings.add_presentation_expiry(dead_worker=True)
            return None
        if preview is None:
            return snapshot
        capture_age_s = (
            preview.captured_at_monotonic - snapshot.captured_at_monotonic
        )
        sequence_gap = preview.sequence - snapshot.capture_sequence
        if preview.generation != snapshot.capture_generation:
            self.preview_timings.add_overlay_alignment_rejection(
                generation_mismatch=True
            )
            with self._presentation_lock:
                with self._overlay_lock:
                    if self._overlay_snapshot is snapshot:
                        self._overlay_snapshot = None
                        self._last_overlay_published_at = None
                        self._overlay_publish_period_s = None
                        self._prop_confirmed_at.clear()
                        self._presented_props.clear()
                        self._presented_hands = None
                        self._presented_pose = None
                        self._presentation_generation = None
            return None
        if capture_age_s < 0.0 or sequence_gap < 0:
            self.preview_timings.add_overlay_alignment_rejection(ahead=True)
            return None
        self.preview_timings.add_overlay_alignment(
            capture_age_s=capture_age_s,
            sequence_gap=sequence_gap,
        )
        if snapshot.is_aligned_with_preview(
            preview_captured_at_monotonic=preview.captured_at_monotonic,
            preview_capture_sequence=preview.sequence,
            preview_capture_generation=preview.generation,
            max_capture_age_s=OVERLAY_MAX_CAPTURE_AGE_S,
        ):
            return self._expire_presentation_geometry(snapshot, preview)
        self.preview_timings.add_overlay_alignment_rejection(stale_capture_age=True)
        # The current snapshot can bridge the normal preview/AI scheduling
        # gap, but only for the short rendering grace. Modality deadlines
        # above still apply to a snapshot containing coasted geometry.
        if capture_age_s <= self._presentation_continuity_s():
            return self._expire_presentation_geometry(snapshot, preview)
        return None

    def _expire_presentation_geometry(
        self, snapshot: OverlaySnapshot, preview: CapturedFrame
    ) -> OverlaySnapshot:
        """Keep each JPEG's geometry and metadata within original observation ages."""
        captured_at = preview.captured_at_monotonic
        boxes_and_expiries = zip(snapshot.boxes, snapshot.box_expires_at)
        boxes = tuple(
            box for box, expires in boxes_and_expiries
            if expires is None or captured_at <= expires
        ) if snapshot.box_expires_at else snapshot.boxes
        if preview.sequence > snapshot.capture_sequence:
            # A later preview is presentation of the last AI observation, not
            # a YOLO confirmation on the newer camera frame.
            boxes = tuple(replace(box, yolo_confirmed=False) for box in boxes)
        hands = (
            None if snapshot.hands_expires_at is not None
            and captured_at > snapshot.hands_expires_at else snapshot.hands
        )
        pose = (
            None if snapshot.pose_expires_at is not None
            and captured_at > snapshot.pose_expires_at else snapshot.pose
        )
        if (len(boxes) != len(snapshot.boxes)
                or (snapshot.hands is not None and hands is None)
                or (snapshot.pose is not None and pose is None)):
            self.preview_timings.add_presentation_expiry()
        return replace(snapshot, boxes=boxes, hands=hands, pose=pose)

    def _timed_detect_normalized_props(self, frame) -> _NormalizedFrameDetections:
        started = time.perf_counter()
        try:
            return self._detect_normalized_props(frame)
        finally:
            self.timings.add("yolo", time.perf_counter() - started)

    def _detect_landmarks(
        self,
        frame,
        *,
        captured_at_monotonic: float,
        needs_hands: bool,
        needs_pose: bool,
        hand_reference: PropDetection | None,
        defer_prop_recovery: bool = False,
    ) -> tuple[Any, Any]:
        """Run the ordered per-session MediaPipe stream for one captured frame."""
        hands = None
        if needs_hands:
            assert self.hands_detector is not None
            started = time.perf_counter()
            try:
                if defer_prop_recovery:
                    independent = self.hands_detector.detect_independent(
                        frame, captured_at_monotonic=captured_at_monotonic,
                    )
                    hands = (independent, time.perf_counter() - started)
                elif getattr(self.hands_detector, "uses_capture_timestamps", False):
                    hands = self.hands_detector.detect(
                        frame,
                        bottle=hand_reference,
                        captured_at_monotonic=captured_at_monotonic,
                    )
                else:  # Compatibility with deterministic test doubles only.
                    hands = self.hands_detector.detect(frame, bottle=hand_reference)
            finally:
                # A failed independent pass has no result to carry through to
                # finish_with_prop, but its time still belongs in telemetry.
                if not defer_prop_recovery or hands is None:
                    self.timings.add("hands", time.perf_counter() - started)

        pose = None
        if needs_pose:
            assert self.pose_detector is not None
            started = time.perf_counter()
            try:
                if getattr(self.pose_detector, "uses_capture_timestamps", False):
                    pose = self.pose_detector.detect(
                        frame,
                        captured_at_monotonic=captured_at_monotonic,
                    )
                else:  # Compatibility with deterministic test doubles only.
                    pose = self.pose_detector.detect(frame)
            finally:
                self.timings.add("pose", time.perf_counter() - started)
        return hands, pose

    def _run_frame_inference(
        self,
        frame,
        *,
        captured_at_monotonic: float,
        run_yolo: bool,
        needs_hands: bool,
        needs_pose: bool,
    ) -> tuple[_NormalizedFrameDetections, Any, Any]:
        """Produce same-frame prop and landmark observations with bounded overlap."""
        has_landmark_work = needs_hands or needs_pose
        staged_hands = bool(
            needs_hands
            and self._is_custom
            and self._hands_bartender_roi
            and self.hands_detector is not None
            and callable(getattr(self.hands_detector, "detect_independent", None))
            and callable(getattr(self.hands_detector, "finish_with_prop", None))
        )
        hands_can_run_without_prop = (
            not needs_hands
            or (
                self.hands_detector is not None
                and (
                    not getattr(self.hands_detector, "requires_current_prop", True)
                    or staged_hands
                )
            )
        )
        can_overlap = (
            self.bottle_detection_enabled
            and run_yolo
            and has_landmark_work
            and hands_can_run_without_prop
            # Generic custom hands can stage prop-independent inference; the
            # prop ROI still waits for the current YOLO result below.
            and (not (needs_hands and self._hands_bartender_roi) or staged_hands)
        )

        if can_overlap:
            join_started = time.perf_counter()
            prop_future = self._inference_executor.submit(
                self._timed_detect_normalized_props,
                frame,
            )
            landmark_future = self._inference_executor.submit(
                self._detect_landmarks,
                frame,
                captured_at_monotonic=captured_at_monotonic,
                needs_hands=needs_hands,
                needs_pose=needs_pose,
                hand_reference=None,
                defer_prop_recovery=staged_hands,
            )
            # Wait for both even when one failed so no orphan worker can touch
            # a detector after error handling or teardown begins.
            wait((prop_future, landmark_future))
            self.timings.add("inference_join", time.perf_counter() - join_started)
            self.timings.record_inference_frame(parallel=True)
            normalized = prop_future.result()
            hands, pose = landmark_future.result()
            if staged_hands:
                independent, independent_seconds = hands
                bottle = normalized.primary[0] if normalized.primary else None
                shaker = normalized.shakers[0] if normalized.shakers else None
                hand_reference = (
                    shaker if shaker is not None else bottle
                ) if self._is_dual_prop else bottle
                started = time.perf_counter()
                try:
                    hands = self.hands_detector.finish_with_prop(
                        frame, independent, hand_reference,
                    )
                finally:
                    self.timings.add(
                        "hands", independent_seconds + time.perf_counter() - started,
                    )
            self._store_normalized_props(normalized)
            return normalized, hands, pose

        if self.bottle_detection_enabled and run_yolo:
            normalized = self._timed_detect_normalized_props(frame)
            self._store_normalized_props(normalized)
        elif not self.bottle_detection_enabled:
            normalized = self._normalize_detections(bottles=[], shakers=[])
            self._store_normalized_props(normalized)
        else:
            normalized = self._cached_normalized_props()

        bottle = normalized.primary[0] if normalized.primary else None
        shakers = list(normalized.shakers)
        shaker = shakers[0] if shakers else None
        hand_reference = (
            (shaker if shaker is not None else bottle)
            if self._is_dual_prop
            else bottle
        )
        hands, pose = self._detect_landmarks(
            frame,
            captured_at_monotonic=captured_at_monotonic,
            needs_hands=needs_hands,
            needs_pose=needs_pose,
            hand_reference=hand_reference,
        )
        self.timings.record_inference_frame(parallel=False)
        return normalized, hands, pose

    def _captured_generation_is_current(self, captured: CapturedFrame) -> bool:
        current_generation = getattr(
            self.camera,
            "current_capture_generation",
            None,
        )
        if callable(current_generation):
            generation = current_generation()
        else:
            generation = getattr(self.camera, "last_capture_generation", None)
        return generation is None or int(generation) == captured.generation

    def _reject_replaced_capture(self, captured: CapturedFrame) -> bool:
        """Drop inference from a producer generation that was replaced mid-tick."""
        if self._captured_generation_is_current(captured):
            return False
        # Do not let old-camera tracker state reach the first frame from the
        # replacement producer. Reset cadence so that frame runs YOLO.
        self._last_bottles = []
        self._last_shakers = []
        self._last_live_bottles = []
        self._last_live_shakers = []
        self._frame_index = 0
        self._last_ai_sequence = None
        self._last_ai_generation = None
        reset_prop_cache = getattr(self.prop_detector, "reset_cache", None)
        if callable(reset_prop_cache):
            reset_prop_cache()
        self._custom_previous_prop = None
        self._clear_overlay()
        return True

    def _accept_capture_generation(self, captured: CapturedFrame) -> None:
        """Never carry tracker or render geometry into a replacement camera."""
        if self._last_ai_generation == captured.generation:
            return
        if self._last_ai_generation is not None:
            self._last_bottles = []
            self._last_shakers = []
            self._last_live_bottles = []
            self._last_live_shakers = []
            self._frame_index = 0
            reset_prop_cache = getattr(self.prop_detector, "reset_cache", None)
            if callable(reset_prop_cache):
                reset_prop_cache()
            self._clear_overlay()
        self._last_ai_generation = captured.generation

    def _wire_session_state(self) -> str:
        if self._lifecycle == SESSION_ACTIVE:
            return "active"
        if self._lifecycle == SESSION_READYING:
            return "readying"
        if self._lifecycle == SESSION_PREPARED:
            return "preparing"
        return "unavailable"

    def _stamp_preview(self, message: PreviewFrameMessage) -> PreviewFrameMessage:
        return message.with_session(self.session_id)

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

    @property
    def display_movement(self) -> str:
        if self._is_freestyle:
            return self._freestyle_display or FREESTYLE_MOVEMENT_LABEL
        return self.movement

    def start(self) -> bool:
        opened = self.camera.open()
        timings = getattr(self.camera, "startup_timings", None)
        if timings is not None:
            self.startup.ingest_camera_timings(
                open_started_at=timings.open_started_at,
                first_usable_at=timings.first_usable_at,
                open_completed_at=timings.open_completed_at,
                reused_shared=bool(timings.reused_shared),
                success=bool(timings.success and opened),
            )
        if opened:
            device_id = getattr(self.camera, "active_device_id", None)
            # Classify from the id string only. Enumerating DirectShow devices
            # here would add discovery latency to prepare.
            self.startup.set_camera_identity(
                camera_diagnostic_identity(
                    device_id,
                    identity_stable=infer_identity_stable_from_device_id(device_id),
                )
            )
        elif timings is None:
            self.startup.fail("camera_open", "camera_unavailable")
        return opened

    def _stamp(self, message: FeedbackMessage) -> FeedbackMessage:
        stamped = message.with_session(self.session_id)
        if stamped.message_type == "feedback":
            return stamped
        return stamped.model_copy(
            update={
                "protocol_version": PROTOCOL_VERSION,
                "message_type": "feedback",
            }
        )

    def _sync_landmark_detectors(self, *, needs_hands: bool, needs_pose: bool) -> None:
        """Create required Hands/Pose detectors and close any unused instances."""
        if needs_hands:
            if self.hands_detector is None:
                self.hands_detector = HandsDetector(
                    max_num_hands=self._hands_max,
                    rotated_fallback=self._hands_rotated_fallback,
                    bartender_roi_fallback=self._hands_bartender_roi,
                    # Generic two-hand custom sessions need recovery only while
                    # a hand is absent; prop-contact replacement is an official
                    # Bartender's Grip behavior, not a template requirement.
                    roi_only_when_below_capacity=(
                        self._is_custom and self._hands_max == 2
                    ),
                )
                logger.info(
                    "HandsDetector created movement=%s hands_max=%s",
                    self.movement,
                    self._hands_max,
                )
        elif self.hands_detector is not None:
            self.hands_detector.close()
            self.hands_detector = None

        if needs_pose:
            if self.pose_detector is None:
                self.pose_detector = (
                    PoseDetector(max_poses=2)
                    if self._is_custom_capture
                    else PoseDetector()
                )
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
        """Create readiness detectors, including optional custom observations."""
        if self._prop_detection_only and self.readiness_spec is None:
            self._sync_landmark_detectors(needs_hands=False, needs_pose=False)
            return
        self._sync_landmark_detectors(
            needs_hands=self._is_custom_capture or readiness_needs_hands(
                self.movement, self.prop_type, self.readiness_spec
            ),
            needs_pose=self._is_custom_capture or readiness_needs_pose(
                self.movement, self.prop_type, self.readiness_spec
            ),
        )

    def _warm_readiness_locked(
        self, *, run_first_inference: bool
    ) -> FeedbackMessage | None:
        """Initialize readiness AI once without updating readiness or scoring.

        The observations are discarded so readiness hysteresis starts only
        after the explicit begin_readiness transition.
        """
        if self._readiness_warmed:
            return self._model_error

        self.startup.mark(MARK_WARMUP_START)
        self._ensure_readiness_detectors()
        model_error = self._check_model()
        if model_error is not None:
            self._readiness_warmed = True
            self.startup.fail("detector_warmup", "model_load_failed")
            self.startup.mark(MARK_WARMUP_END)
            return model_error

        captured = (
            self._acquire_captured_frame(timeout=0.05)
            if run_first_inference
            else None
        )
        if captured is not None:
            normalized = self._detect_normalized_props(captured.frame)
            if self.hands_detector is not None:
                bottle_ref = normalized.primary[0] if normalized.primary else None
                self.hands_detector.detect(captured.frame, bottle=bottle_ref)
            if self.pose_detector is not None:
                self.pose_detector.detect(captured.frame)

        runtime, provider = yolo_runtime_info(self.prop_detector)
        self.startup.set_yolo_runtime(
            runtime,
            provider,
            yolo_runtime_device_id(self.prop_detector),
        )
        self._readiness_warmed = True
        self.startup.mark(MARK_WARMUP_END)
        return None

    def warm_readiness(self) -> FeedbackMessage | None:
        """Warm readiness AI while prepared, serialized with lifecycle changes."""
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle != SESSION_PREPARED:
                return self._model_error
            return self._warm_readiness_locked(run_first_inference=True)
        finally:
            self._release_ai_state()

    def begin_readiness(self) -> bool:
        """Transition prepared → readying. Idempotent when already READYING.

        Returns True on success or when already readying.
        Returns False if CLOSED or ACTIVE.
        """
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle == SESSION_READYING:
                return True
            if self._lifecycle != SESSION_PREPARED:
                return False
            self._warm_readiness_locked(run_first_inference=False)
            self._readiness_tracker = ReadinessTracker(
                self.movement,
                self.prop_type,
                profile=readiness_profile_for(
                    self.movement, self.prop_type, self.readiness_spec
                ),
            )
            self._latest_readiness_snapshot = None
            self._latest_readiness_observed_at = None
            self._readiness_confirmed = False
            self._frozen_readiness_snapshot = None
            self._calibration.reset()
            self._clear_overlay()
            self._last_ai_sequence = None
            self._lifecycle = SESSION_READYING
            self.startup.mark(MARK_READINESS_START)
            return True
        finally:
            self._release_ai_state()

    def confirm_readiness(self) -> tuple[bool, str | None]:
        """Lock readiness after the client confirms stable calibration.

        Idempotent when already confirmed for this readiness cycle.
        Returns (accepted, error_code).
        """
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle != SESSION_READYING:
                if self._lifecycle == SESSION_ACTIVE:
                    return False, "session_already_active"
                return False, "session_not_prepared"

            if self._readiness_confirmed:
                return True, None

            snapshot = self._latest_readiness_snapshot
            if snapshot is None or not snapshot.readiness_stable:
                return False, "readiness_not_stable"
            if self._is_custom_capture and not self._single_custom_performer_ready():
                return False, "single_performer_required"

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
        finally:
            self._release_ai_state()

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
        self._acquire_ai_state(blocking=True)
        try:
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
            self._last_live_bottles = []
            self._last_live_shakers = []
            if self._recognizer is not None:
                self._recognizer.reset()
            self._recognition_paused = False
            self._pending_recognition_events = []
            self._freestyle_display = None
            if self._is_dual_prop:
                self.prop_detector.reset_cache()
            self._frame_index = 0
            self._evidence_emitted = False
            self._readiness_tracker = None
            self._latest_readiness_snapshot = None
            self._latest_readiness_observed_at = None
            self._frozen_readiness_snapshot = None
            self._readiness_confirmed = False
            self._clear_overlay()
            self._last_ai_sequence = None
            self._lifecycle = SESSION_ACTIVE
            return True, None
        finally:
            self._release_ai_state()

    def set_recognition_paused(self, paused: bool) -> tuple[bool, str | None]:
        """Freeze freestyle recognition without tearing down the camera session."""
        self._acquire_ai_state(blocking=True)
        try:
            if not self._is_freestyle:
                return False, "invalid_command"
            if self._lifecycle != SESSION_ACTIVE:
                return False, "session_not_active"
            self._recognition_paused = paused
            if self._recognizer is not None:
                self._recognizer.set_paused(paused)
            return True, None
        finally:
            self._release_ai_state()

    def drain_recognition_events(self) -> list[RecognitionEventMessage]:
        events = self._pending_recognition_events
        self._pending_recognition_events = []
        return events

    def _check_model(self) -> FeedbackMessage | None:
        if not self.bottle_detection_enabled:
            return None

        if self._model_checked:
            return self._model_error

        self._model_checked = True

        try:
            self.prop_detector.ensure_ready()
        except ModelLoadError:
            self._model_error = self._stamp(
                FeedbackMessage(
                    bottle_detected=False,
                    prop_type=self.prop_type,
                    movement=self.display_movement,
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
            return self._model_error

        if self._orientation_enabled:
            assert self._orientation_detector is not None
            try:
                self._orientation_detector.ensure_ready()
            except Exception:
                logger.exception("Bottle marker detector failed to initialize")
                if self._is_custom_capture:
                    # Capture remains usable for body/hand/translation templates.
                    self._orientation_enabled = False
                else:
                    return self._orientation_failure()

        return None

    def _orientation_failure(self) -> FeedbackMessage:
        self._model_error = self._stamp(
            FeedbackMessage(
                bottle_detected=False,
                prop_type=self.prop_type,
                movement=self.display_movement,
                feedback=_human_error_message("orientation_model_unavailable"),
                feedback_type="error",
                posture_status="unknown",
                frame_jpeg_base64=None,
                error_code="orientation_model_unavailable",
                camera_ready=False,
                session_state="unavailable",
            )
        )
        return self._model_error

    def process_preview_frame(self) -> FeedbackMessage | None:
        """Encode a JPEG preview without model load, evaluation, or scoring."""
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at

        captured = self._acquire_captured_frame()
        if captured is None:
            return None
        frame = captured.frame
        self.timings.add_frame_age(time.monotonic() - captured.captured_at_monotonic)

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
                movement=self.display_movement,
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
        self.startup.mark(MARK_FIRST_JPEG_ENCODE)
        return message

    def render_preview(self) -> PreviewFrameMessage | None:
        """JPEG preview from the latest camera frame. Never waits on AI."""
        if not self._preview_run_lock.acquire(blocking=False):
            raise RuntimeError("Preview worker violated single in-flight")
        try:
            return self._render_preview_unlocked()
        finally:
            self._preview_run_lock.release()

    def _render_preview_unlocked(self) -> PreviewFrameMessage | None:
        self._preview_started_at = time.perf_counter()
        total_start = self._preview_started_at
        captured = self._acquire_captured_frame(timings=self.preview_timings)
        if captured is None:
            return None
        if (
            self._last_preview_sequence is not None
            and captured.sequence == self._last_preview_sequence
        ):
            return None

        self._feed_submission_recorder(captured)
        self._feed_custom_recorder(captured)

        self.preview_timings.add_frame_age(
            time.monotonic() - captured.captured_at_monotonic
        )
        overlay = self._read_fresh_overlay(preview=captured)
        annotated = captured.frame
        if overlay is not None:
            t0 = time.perf_counter()
            annotated = annotate_frame(
                captured.frame,
                list(overlay.boxes),
                overlay.hands,
                overlay.feedback,
                overlay.feedback_type,
                overlay.movement,
                pose=overlay.pose,
                prop_label=overlay.prop_label,
            )
            self.preview_timings.add("annotate", time.perf_counter() - t0)

        t0 = time.perf_counter()
        _, buffer = cv2.imencode(
            ".jpg",
            annotated,
            [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
        )
        self.preview_timings.add("jpeg", time.perf_counter() - t0)

        t0 = time.perf_counter()
        frame_b64 = base64.b64encode(buffer).decode("ascii")
        self._last_preview_sequence = captured.sequence
        message = self._stamp_preview(
            PreviewFrameMessage(
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state=self._wire_session_state(),
                capture_sequence=captured.sequence,
                **self._preview_presentation_metadata(overlay),
            )
        )
        self.preview_timings.add("encode", time.perf_counter() - t0)
        self.preview_timings.add("processing_total", time.perf_counter() - total_start)
        self.startup.mark(MARK_FIRST_JPEG_ENCODE)
        return message

    def analyze_tick(self) -> FeedbackMessage | None:
        """Run AI/evaluation for the newest unanalyzed camera frame."""
        if not self._ai_tick_lock.acquire(blocking=False):
            raise RuntimeError("AI worker violated single in-flight")
        try:
            if not self._acquire_ai_state(blocking=False):
                # Lifecycle mutation owns AI state. Skip this stale tick;
                # the next loop iteration analyzes the newest frame.
                self._ai_lifecycle_skips += 1
                return None
            self._ai_inflight += 1
            with self._overlay_lock:
                self._ai_inflight_started_at = time.monotonic()
            if self._ai_inflight > self._ai_inflight_max:
                self._ai_inflight_max = self._ai_inflight
            publish_at_start = latest_frame_publish_count()
            try:
                if self._lifecycle == SESSION_PREPARED:
                    return None
                if self._lifecycle == SESSION_READYING:
                    return self._process_readiness_frame_unlocked(
                        emit_preview_jpeg=False
                    )
                if self._lifecycle == SESSION_ACTIVE:
                    return self._process_frame_unlocked(emit_preview_jpeg=False)
                return None
            finally:
                self._ai_inflight -= 1
                with self._overlay_lock:
                    self._ai_inflight_started_at = None
                self._ai_camera_overwrites += max(
                    0, latest_frame_publish_count() - publish_at_start
                )
                self._release_ai_state()
        finally:
            self._ai_tick_lock.release()

    def process_readiness_frame(
        self, *, emit_preview_jpeg: bool = True
    ) -> FeedbackMessage | None:
        """Run one readiness frame, serialized with lifecycle mutation."""
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle == SESSION_CLOSED:
                return None
            return self._process_readiness_frame_unlocked(
                emit_preview_jpeg=emit_preview_jpeg
            )
        finally:
            self._release_ai_state()

    def _process_readiness_frame_unlocked(
        self, *, emit_preview_jpeg: bool = True
    ) -> FeedbackMessage | None:
        """Run observability checklist without movement evaluation or scoring."""
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        newer_than = None if emit_preview_jpeg else self._last_ai_sequence
        timeout = None if emit_preview_jpeg else 0.05
        captured = self._acquire_captured_frame(
            newer_than=newer_than,
            timeout=timeout,
        )
        if captured is None:
            return None
        frame = captured.frame
        self.timings.add_frame_age(time.monotonic() - captured.captured_at_monotonic)
        self._accept_capture_generation(captured)
        self._last_ai_sequence = captured.sequence

        self._frame_index += 1
        run_yolo = (self._frame_index - 1) % self._yolo_frame_skip == 0

        needs_h = self._is_custom_capture or readiness_needs_hands(
            self.movement, self.prop_type, self.readiness_spec
        )
        needs_p = self._is_custom_capture or readiness_needs_pose(
            self.movement, self.prop_type, self.readiness_spec
        )
        normalized, hands, pose = self._run_frame_inference(
            frame,
            captured_at_monotonic=captured.captured_at_monotonic,
            run_yolo=run_yolo,
            needs_hands=needs_h,
            needs_pose=needs_p,
        )
        if self._reject_replaced_capture(captured):
            return None
        if self._is_custom_capture:
            self._observe_custom_people(
                pose, captured_at_monotonic=captured.captured_at_monotonic
            )
        bottles = list(normalized.bottles)
        shakers = list(normalized.shakers)

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
        if readiness_stable:
            self.startup.mark(MARK_READINESS_STABLE)

        self._publish_presentation(
            captured=captured, run_yolo=run_yolo, hands=hands, pose=pose,
            feedback="Checking readiness\u2026", feedback_type="positive",
            prop_label=self.prop_display_name,
        )

        frame_b64 = None
        if emit_preview_jpeg:
            t0 = time.perf_counter()
            annotated = annotate_frame(
                frame,
                list(normalized.annotation),
                hands,
                "Checking readiness\u2026",
                "positive",
                self.display_movement,
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
            self.timings.add("encode", time.perf_counter() - t0)
        message = self._stamp(
            FeedbackMessage(
                bottle_detected=normalized.selected_detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=self.display_movement,
                feedback="Checking readiness\u2026",
                feedback_type="positive",
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="readying",
                readiness_items=readiness_items,
                readiness_complete=readiness_complete,
                readiness_stable=(
                    readiness_stable and self._single_custom_performer_ready()
                    if self._is_custom_capture
                    else readiness_stable
                ),
                person_count=self._custom_person_count if self._is_custom_capture else None,
                readiness_stable_progress=readiness_stable_progress,
                calibration_scale=self._calibration.scale,
                calibration_source=self._calibration.source,
            )
        )
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_prop_detection_frame(
        self, *, emit_preview_jpeg: bool = True
    ) -> FeedbackMessage | None:
        """Run one prop-only frame, serialized with lifecycle mutation."""
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle == SESSION_CLOSED:
                return None
            return self._process_prop_detection_frame_unlocked(
                emit_preview_jpeg=emit_preview_jpeg
            )
        finally:
            self._release_ai_state()

    def _process_prop_detection_frame_unlocked(
        self, *, emit_preview_jpeg: bool = True
    ) -> FeedbackMessage | None:
        """Active Free Practice: camera + prop detect + annotate, no MediaPipe/scoring."""
        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        newer_than = None if emit_preview_jpeg else self._last_ai_sequence
        timeout = None if emit_preview_jpeg else 0.05
        captured = self._acquire_captured_frame(
            newer_than=newer_than,
            timeout=timeout,
        )
        if captured is None:
            return None
        frame = captured.frame
        self.timings.add_frame_age(time.monotonic() - captured.captured_at_monotonic)
        self._accept_capture_generation(captured)
        self._last_ai_sequence = captured.sequence

        self._frame_index += 1
        run_yolo = (self._frame_index - 1) % self._yolo_frame_skip == 0

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

        if self._reject_replaced_capture(captured):
            return None

        detected = normalized.selected_detected
        if detected:
            feedback = f"{self.prop_display_name} detected"
            feedback_type = "positive"
        else:
            feedback = f"Searching for {self.prop_display_name.lower()}"
            feedback_type = "warning"

        self._publish_presentation(
            captured=captured, run_yolo=run_yolo, hands=None, pose=None,
            feedback=feedback, feedback_type=feedback_type,
            prop_label=self.prop_display_name,
        )

        frame_b64 = None
        if emit_preview_jpeg:
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
            self.timings.add("encode", time.perf_counter() - t0)
        message = self._stamp(
            FeedbackMessage(
                bottle_detected=detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=self.display_movement,
                feedback=feedback,
                feedback_type=feedback_type,
                posture_status="unknown",
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="active",
            )
        )
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def process_frame(self, *, emit_preview_jpeg: bool = True) -> FeedbackMessage | None:
        """Run one active frame, serialized with lifecycle mutation."""
        self._acquire_ai_state(blocking=True)
        try:
            if self._lifecycle == SESSION_CLOSED:
                return None
            return self._process_frame_unlocked(
                emit_preview_jpeg=emit_preview_jpeg
            )
        finally:
            self._release_ai_state()

    def _process_frame_unlocked(
        self, *, emit_preview_jpeg: bool = True
    ) -> FeedbackMessage | None:
        if self._prop_detection_only:
            return self._process_prop_detection_frame_unlocked(
                emit_preview_jpeg=emit_preview_jpeg
            )

        self._pipeline_started_at = time.perf_counter()
        total_start = self._pipeline_started_at
        self._ensure_detectors()
        model_error = self._check_model()

        if model_error is not None:
            return model_error

        newer_than = None if emit_preview_jpeg else self._last_ai_sequence
        timeout = None if emit_preview_jpeg else 0.05
        captured = self._acquire_captured_frame(
            newer_than=newer_than,
            timeout=timeout,
        )
        if captured is None:
            return None
        frame = captured.frame
        self.timings.add_frame_age(time.monotonic() - captured.captured_at_monotonic)
        self._accept_capture_generation(captured)
        self._last_ai_sequence = captured.sequence

        self._frame_index += 1

        # Frame index starts at 1; subtract 1 so the very first frame runs YOLO.
        run_yolo = (self._frame_index - 1) % self._yolo_frame_skip == 0

        normalized, hands, pose = self._run_frame_inference(
            frame,
            captured_at_monotonic=captured.captured_at_monotonic,
            run_yolo=run_yolo,
            needs_hands=self._hands_needed,
            needs_pose=self._pose_needed,
        )
        if self._reject_replaced_capture(captured):
            return None
        if self._is_custom_capture:
            self._observe_custom_people(
                pose, captured_at_monotonic=captured.captured_at_monotonic
            )

        bottles = list(normalized.bottles)
        shakers = list(normalized.shakers)

        # Score on the highest-confidence selected prop for single-prop movements.
        # Double Hand Stall and Double Forearm Stall also receive the full
        # detection list via `bottles`.
        # For shaker sessions, primary holds the shaker detections (compatibility).
        bottle = normalized.primary[0] if normalized.primary else None
        # Important fix:
        # Do not use previous hand landmarks when the current frame has no hand.
        # This prevents "naiiwan yung daliri" / ghost hand dots.
        # Missing Hands when required is a lifecycle bug, not a detection miss.
        # `_run_frame_inference` always returns current-frame landmarks and
        # never reuses a previous Hands/Pose result.

        if self._is_custom:
            orientation = None
            if (
                self._custom_samples is not None
                and self._orientation_enabled
                and normalized.primary
            ):
                assert self._orientation_detector is not None
                try:
                    orientation = self._orientation_detector.observe(
                        frame,
                        max(normalized.primary, key=lambda item: item.confidence),
                    )
                    self._orientation_inference_count += 1
                    self._orientation_inference_ms += self._orientation_detector.last_inference_ms
                    self.timings.add("orientation", self._orientation_detector.last_inference_ms / 1000)
                except Exception:
                    logger.exception("Bottle marker detection failed")
                    if self._is_custom_capture:
                        self._orientation_enabled = False
                    else:
                        return self._orientation_failure()
            if self._reject_replaced_capture(captured):
                return None
            if not self._is_custom_capture or self._custom_samples is None or (
                self._custom_person_count == 1
                and not self._custom_multiple_invalid
                and not self._custom_awaiting_identity
            ):
                self._record_custom_sample(
                    captured=captured,
                    frame=frame,
                    normalized=normalized,
                    hands=hands,
                    pose=pose,
                    yolo_attempted=run_yolo,
                    orientation=orientation,
                )
            feedback = (
                "Recording movement reference…"
                if self._custom_samples is not None
                else "Ready to record the full movement"
            )
            multiple_people_warning = self._is_custom_capture and (
                self._custom_person_count >= 2 or self._custom_multiple_invalid
            )
            if multiple_people_warning:
                feedback = (
                    "Multiple people detected. This reference must be retried."
                    if self._custom_samples is not None
                    else "Multiple people detected. Only one person can be in frame while recording a reference."
                )
            self._publish_presentation(
                captured=captured, run_yolo=run_yolo, hands=hands, pose=pose,
                feedback=feedback,
                feedback_type="warning" if multiple_people_warning else "positive",
                prop_label=self.prop_display_name,
            )
            message = self._stamp(
                FeedbackMessage(
                    bottle_detected=normalized.selected_detected,
                    bottle_count=normalized.selected_count,
                    prop_type=self.prop_type,
                    movement=self.display_movement,
                    feedback=feedback,
                    feedback_type="warning" if multiple_people_warning else "positive",
                    posture_status="unknown",
                    frame_jpeg_base64=None,
                    camera_ready=True,
                    session_state="active",
                    person_count=self._custom_person_count if self._is_custom_capture else None,
                    reference_invalid=self._custom_multiple_invalid if self._is_custom_capture else None,
                )
            )
            self.timings.add("processing_total", time.perf_counter() - total_start)
            return message

        if self._is_freestyle:
            return self._finish_freestyle_frame(
                frame=frame,
                captured=captured,
                normalized=normalized,
                hands=hands,
                pose=pose,
                run_yolo=run_yolo,
                emit_preview_jpeg=emit_preview_jpeg,
                total_start=total_start,
            )

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

        # Publish only render geometry here; movement evaluation above used
        # current observations with bottles and shakers kept separate.
        self._publish_presentation(
            captured=captured, run_yolo=run_yolo, hands=hands, pose=pose,
            feedback=rule_result.feedback, feedback_type=rule_result.feedback_type,
            prop_label=self.prop_display_name,
        )

        need_annotated = emit_preview_jpeg or (
            hold.hold_confirmed and not self._evidence_emitted
        )
        annotated = None
        if need_annotated:
            t0 = time.perf_counter()
            annotated = annotate_frame(
                frame,
                list(normalized.annotation),
                hands,
                rule_result.feedback,
                rule_result.feedback_type,
                self.display_movement,
                pose=pose,
                prop_label=self.prop_display_name,
            )
            self.timings.add("annotate", time.perf_counter() - t0)

        frame_b64 = None
        if emit_preview_jpeg:
            t0 = time.perf_counter()
            _, buffer = cv2.imencode(
                ".jpg",
                annotated,
                [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
            )
            self.timings.add("jpeg", time.perf_counter() - t0)

            t0 = time.perf_counter()
            frame_b64 = base64.b64encode(buffer).decode("ascii")
            self.timings.add("encode", time.perf_counter() - t0)

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
                movement=self.display_movement,
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
        self.timings.add("processing_total", time.perf_counter() - total_start)
        return message

    def _finish_freestyle_frame(
        self,
        *,
        frame,
        captured: CapturedFrame,
        normalized: _NormalizedFrameDetections,
        hands,
        pose,
        run_yolo: bool,
        emit_preview_jpeg: bool,
        total_start: float,
    ) -> FeedbackMessage:
        assert self._recognizer is not None
        height, width = frame.shape[:2]
        t0 = time.perf_counter()
        tick = self._recognizer.update(
            timestamp=time.monotonic(),
            dt=1.0 / max(TARGET_FPS, 1),
            bottles=list(self._last_live_bottles),
            shakers=list(self._last_live_shakers),
            hands=hands,
            pose=pose,
            width=int(width),
            height=int(height),
            calibration_scale=self._calibration.resolved[0],
        )
        self.timings.add("evaluate", time.perf_counter() - t0)

        if tick.recognition_state in {"searching", "candidate"}:
            self._freestyle_display = None
        elif tick.recognized_display:
            self._freestyle_display = tick.recognized_display

        if tick.event is not None:
            self._recognition_event_seq += 1
            event = tick.event
            self._pending_recognition_events.append(
                RecognitionEventMessage(
                    session_id=self.session_id or "",
                    event_id=f"{self.session_id or 'freestyle'}:{self._recognition_event_seq}",
                    kind=event.kind,
                    display_label=event.display_label,
                    identity_revealed=event.identity_revealed,
                    quality=event.quality,
                    movement=event.movement if event.identity_revealed else None,
                    prop_type=event.prop_type
                    if event.prop_type in {"bottle", "shaker", "bottle_and_shaker"}
                    else None,
                    supporting_message=event.supporting_message,
                    capture_sequence=captured.sequence,
                )
            )

        detected = tick.detected_prop_type is not None
        overlay_feedback = tick.recognized_display or "Watching your technique."
        overlay_type = "positive" if tick.recognition_state == "confirmed" else "warning"
        prop_label = {
            "shaker": "Cocktail Shaker",
            "bottle_and_shaker": "Bottle + Cocktail Shaker",
        }.get(tick.detected_prop_type or "", "Bottle")
        self._publish_presentation(
            captured=captured, run_yolo=run_yolo, hands=hands, pose=pose,
            feedback=overlay_feedback, feedback_type=overlay_type,
            prop_label=prop_label,
        )

        annotated = None
        frame_b64 = None
        if emit_preview_jpeg:
            t0 = time.perf_counter()
            annotated = annotate_frame(
                frame,
                list(normalized.annotation),
                hands,
                overlay_feedback,
                overlay_type,
                self.display_movement,
                pose=pose,
                prop_label=prop_label,
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
            self.timings.add("encode", time.perf_counter() - t0)

        message = self._stamp(
            FeedbackMessage(
                bottle_detected=detected,
                bottle_count=normalized.selected_count,
                prop_type=self.prop_type,
                movement=FREESTYLE_MOVEMENT_LABEL,
                feedback=overlay_feedback,
                feedback_type=overlay_type,
                posture_status=(
                    "stable" if tick.recognition_state == "confirmed" else "unknown"
                ),
                frame_jpeg_base64=frame_b64,
                camera_ready=True,
                session_state="active",
                hold_progress=0.0,
                hold_duration_ms=0,
                hold_confirmed=False,
                positive_frame_ratio=0.0,
                hold_target_ms=0,
                recognition_state=tick.recognition_state,
                recognized_display=tick.recognized_display,
                detected_prop_type=tick.detected_prop_type,
            )
        )
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
        self._acquire_ai_state(blocking=True)
        try:
            self._lifecycle = SESSION_CLOSED
            self._readiness_tracker = None
            self._latest_readiness_snapshot = None
            self._latest_readiness_observed_at = None
            self._frozen_readiness_snapshot = None
            self._readiness_confirmed = False
            self._movement_state = None
            self._prev_hip_center = None
            self._calibration.reset()
            self._hold_validator.reset()
            self._clear_overlay()
            with self._custom_video_lock:
                recorder = self._custom_video_recorder
                self._custom_video_recorder = None
            if recorder is not None:
                recorder.cancel()
            for draft in self._custom_references:
                try:
                    self._delete_custom_draft(draft)
                except ValueError:
                    # Startup orphan cleanup can retry after Windows releases
                    # a native playback handle left by a disconnected client.
                    logger.warning("Custom reference clip remained locked at close")
            self._custom_references.clear()
            self.camera.release()
            if not self._inference_executor_shutdown:
                self._inference_executor.shutdown(
                    wait=True,
                    cancel_futures=True,
                )
                self._inference_executor_shutdown = True
            self._sync_landmark_detectors(needs_hands=False, needs_pose=False)
            if self._orientation_detector is not None:
                self._orientation_detector.close()
        finally:
            self._release_ai_state()
            self.startup.finalize()


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


@dataclass
class _OutboundItem:
    kind: str
    payload: str
    started_at: float | None
    must_deliver: bool = False


_FEEDBACK_PENDING_MAX = 8


class _OutboundMailbox:
    """Latest preview slot plus a bounded feedback queue. One writer drains them."""

    def __init__(self) -> None:
        self._preview: _OutboundItem | None = None
        self._feedback: deque[_OutboundItem] = deque()
        self._ready = asyncio.Event()
        self.preview_replaced = 0
        self.feedback_replaced = 0
        self.sends_in_flight = 0
        self.max_sends_in_flight = 0

    def put(self, item: _OutboundItem) -> None:
        if item.kind == "preview":
            if self._preview is not None:
                self.preview_replaced += 1
            self._preview = item
        elif item.must_deliver or len(self._feedback) < _FEEDBACK_PENDING_MAX:
            self._feedback.append(item)
        else:
            self.feedback_replaced += 1
        self._ready.set()

    def wake(self) -> None:
        self._ready.set()

    def drain(self) -> list[_OutboundItem]:
        batch: list[_OutboundItem] = []
        if self._preview is not None:
            batch.append(self._preview)
            self._preview = None
        while self._feedback:
            batch.append(self._feedback.popleft())
        return batch

    async def take_batch(self, closing: asyncio.Event) -> list[_OutboundItem]:
        """Wait for preview/feedback, or return remaining items when closing."""
        while self._preview is None and not self._feedback:
            if closing.is_set():
                return []
            self._ready.clear()
            wait_ready = asyncio.create_task(self._ready.wait())
            wait_close = asyncio.create_task(closing.wait())
            try:
                _done, pending = await asyncio.wait(
                    {wait_ready, wait_close},
                    return_when=asyncio.FIRST_COMPLETED,
                )
                for task in pending:
                    task.cancel()
                for task in _done:
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass
            finally:
                if not wait_ready.done():
                    wait_ready.cancel()
                if not wait_close.done():
                    wait_close.cancel()
        return self.drain()


async def _await_in_flight_worker(task: asyncio.Task | None, label: str) -> None:
    if task is None:
        return
    if not task.done():
        try:
            await task
        except asyncio.CancelledError:
            logger.warning("%s cancelled during session shutdown", label)
        except Exception:
            logger.exception("%s failed during session shutdown", label)
        return
    if task.cancelled():
        return
    exc = task.exception()
    if exc is not None:
        logger.exception(
            "%s failed during session shutdown",
            label,
            exc_info=exc,
        )


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
    readiness_spec: dict | None = None,
    session_mode: str | None = None,
    allowed_movements: list[tuple[str, str]] | None = None,
    custom_movement_template: dict[str, Any] | None = None,
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
            readiness_spec=readiness_spec,
            session_mode=session_mode,
            allowed_movements=allowed_movements,
            custom_movement_template=custom_movement_template,
        )
    except Exception as exc:
        logger.exception("Failed to initialize vision session")

        explicit_code = str(exc) if isinstance(exc, ValueError) else ""
        error_code = (
            explicit_code
            if explicit_code in {"orientation_model_unavailable", "invalid_schema"}
            else "pipeline_init_failed"
        )

        error = FeedbackMessage(
            bottle_detected=False,
            prop_type=prop_type,
            movement=movement,
            feedback=_human_error_message(error_code) if error_code != "pipeline_init_failed" else (
                "Vision pipeline failed to start. From the backend folder run "
                ".\\run.ps1 (or backend\\.venv\\Scripts\\python.exe -m uvicorn "
                "main:app --host 127.0.0.1 --port 8000). Check backend logs for details."
            ),
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
            message=error.feedback,
        )
        await _send(error.model_dump_json())
        return

    preview_worker: asyncio.Task | None = None
    ai_worker: asyncio.Task | None = None
    startup_worker: asyncio.Task | None = None
    readiness_warm_worker: asyncio.Task | None = None
    preview_task: asyncio.Task | None = None
    ai_task: asyncio.Task | None = None
    writer_task: asyncio.Task | None = None
    stop = asyncio.Event()
    writer_closing = asyncio.Event()
    mailbox = _OutboundMailbox()
    outbound_error: str | None = None

    try:
        # Camera startup can be blocked in a native capture call. Keep its
        # worker observable so cancellation waits for it before session.close
        # releases the same camera object.
        startup_worker = asyncio.create_task(asyncio.to_thread(session.start))
        started = await asyncio.shield(startup_worker)

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
            session_ref["mailbox"] = mailbox

        if start_active:
            await asyncio.to_thread(session.activate)

        _signal_prepare_gate(prepare_gate, ok=True)
        session.startup.mark(MARK_PREPARE_END)

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

        # Warm guided/readiness detectors before exposing live video. Model
        # constructors and first inference can contend with capture/JPEG even
        # when called from a worker thread. Once the first JPEG is visible,
        # preview therefore runs without startup model initialization.
        if not start_active and movement != "Free Practice":
            readiness_warm_worker = asyncio.create_task(
                asyncio.to_thread(session.warm_readiness)
            )
            model_error = await asyncio.shield(readiness_warm_worker)
            readiness_warm_worker = None
            if model_error is not None:
                outbound_error = model_error.model_dump_json()
                return

        interval = 1.0 / TARGET_FPS
        preview_count = 0
        ai_count = 0
        loop_ticks = 0
        loop_start = time.perf_counter()
        last_overwrite_count = latest_frame_overwrite_count()
        last_publish_count = latest_frame_publish_count()
        last_preview_replaced = 0
        last_ai_overwrites = 0
        last_ai_lifecycle_skips = 0

        def emit_perf() -> None:
            nonlocal preview_count, ai_count, loop_ticks, loop_start
            nonlocal last_overwrite_count, last_publish_count
            nonlocal last_preview_replaced, last_ai_overwrites
            nonlocal last_ai_lifecycle_skips
            elapsed = time.perf_counter() - loop_start
            preview_fps = interval_rate(preview_count, elapsed)
            ai_fps = interval_rate(ai_count, elapsed)
            publish_now = latest_frame_publish_count()
            publish_delta = monotonic_counter_delta(
                current=publish_now,
                previous=last_publish_count,
            )
            capture_fps = interval_rate(publish_delta, elapsed)
            overwrite_total = latest_frame_overwrite_count()
            overwrite_delta = monotonic_counter_delta(
                current=overwrite_total,
                previous=last_overwrite_count,
            )
            preview_replaced = mailbox.preview_replaced - last_preview_replaced
            ai_overwrites = session._ai_camera_overwrites - last_ai_overwrites
            last_overwrite_count = overwrite_total
            last_publish_count = publish_now
            last_preview_replaced = mailbox.preview_replaced
            last_ai_overwrites = session._ai_camera_overwrites
            skip_now = session._ai_lifecycle_skips
            skip_delta = max(0, skip_now - last_ai_lifecycle_skips)
            last_ai_lifecycle_skips = skip_now
            if skip_delta:
                logger.debug(
                    "AI ticks skipped due to lifecycle contention: "
                    "delta=%s total=%s session_id=%s",
                    skip_delta,
                    skip_now,
                    session_id,
                )
            capture_snapshot = snapshot_capture_producer_telemetry(reset=True)
            yolo_runtime, yolo_provider = yolo_runtime_info(session.prop_detector)
            yolo_threads = yolo_runtime_threads(session.prop_detector)
            hands_diag = ""
            hands_stats = getattr(session.hands_detector, "stats", None)
            if hands_stats is not None and getattr(hands_stats, "detect_calls", 0) > 0:
                format_line = getattr(hands_stats, "format_line", None)
                if callable(format_line):
                    hands_diag = format_line()
                    max_hands = getattr(
                        session.hands_detector, "max_num_hands", None
                    )
                    if isinstance(max_hands, int):
                        hands_diag = f"hands_max={max_hands} {hands_diag}"
                reset = getattr(hands_stats, "reset", None)
                if callable(reset):
                    reset()
            logger.info(
                "%s",
                format_perf_line(
                    session.preview_timings,
                    preview_fps=preview_fps,
                    ai_fps=ai_fps,
                    capture_fps=capture_fps,
                    elapsed_s=elapsed,
                    overwrite_delta=overwrite_delta,
                    target_fps=TARGET_FPS,
                    yolo_skip=session._yolo_frame_skip,
                    imgsz=YOLO_IMGSZ,
                    lifecycle=session.lifecycle,
                    processed=preview_count,
                    ticks=loop_ticks,
                    ai_timings=session.timings,
                    preview_replaced=preview_replaced,
                    ai_overwrites=ai_overwrites,
                    ai_processed=ai_count,
                    capture_snapshot=capture_snapshot,
                    yolo_runtime=yolo_runtime,
                    yolo_provider=yolo_provider,
                    yolo_threads=yolo_threads if yolo_runtime else None,
                    hands_diag=hands_diag,
                ),
            )
            session.preview_timings.reset()
            session.timings.reset()
            preview_count = 0
            ai_count = 0
            loop_ticks = 0
            loop_start = time.perf_counter()

        async def preview_loop() -> None:
            nonlocal preview_worker, preview_count, loop_ticks
            while not stop.is_set():
                tick = time.perf_counter()
                loop_ticks += 1
                if preview_worker is not None and not preview_worker.done():
                    raise RuntimeError(
                        "Preview worker violated single in-flight"
                    )
                preview_worker = asyncio.create_task(
                    asyncio.to_thread(session.render_preview)
                )
                message = await asyncio.shield(preview_worker)
                preview_worker = None
                if message is not None:
                    t_ser = time.perf_counter()
                    payload = message.model_dump_json()
                    session.preview_timings.add(
                        "serialize", time.perf_counter() - t_ser
                    )
                    mailbox.put(
                        _OutboundItem(
                            kind="preview",
                            payload=payload,
                            started_at=session._preview_started_at,
                        )
                    )
                    preview_count += 1
                    if preview_count % FPS_LOG_INTERVAL == 0:
                        emit_perf()
                await asyncio.sleep(
                    max(0.0, interval - (time.perf_counter() - tick))
                )

        async def ai_loop() -> None:
            nonlocal ai_worker, ai_count
            while not stop.is_set():
                if session.lifecycle == SESSION_PREPARED:
                    await asyncio.sleep(0.02)
                    continue
                if ai_worker is not None and not ai_worker.done():
                    raise RuntimeError("AI worker violated single in-flight")
                ai_worker = asyncio.create_task(
                    asyncio.to_thread(session.analyze_tick)
                )
                message = await asyncio.shield(ai_worker)
                ai_worker = None
                if message is None:
                    await asyncio.sleep(0)
                    continue
                t_ser = time.perf_counter()
                payload = message.model_dump_json()
                session.timings.add("serialize", time.perf_counter() - t_ser)
                mailbox.put(
                    _OutboundItem(
                        kind="feedback",
                        payload=payload,
                        started_at=session._pipeline_started_at,
                        must_deliver=bool(
                            message.hold_confirmed
                            or message.error_code
                            or message.evidence_jpeg_base64
                        ),
                    )
                )
                for event in session.drain_recognition_events():
                    mailbox.put(
                        _OutboundItem(
                            kind="feedback",
                            payload=event.model_dump_json(),
                            started_at=session._pipeline_started_at,
                            must_deliver=True,
                        )
                    )
                ai_count += 1
                if message.error_code in {"model_load_failed", "orientation_model_unavailable"}:
                    stop.set()
                    mailbox.wake()
                    return
                await asyncio.sleep(0)

        async def writer_loop() -> None:
            while True:
                batch = await mailbox.take_batch(writer_closing)
                if not batch:
                    return
                for item in batch:
                    mailbox.sends_in_flight += 1
                    if mailbox.sends_in_flight > mailbox.max_sends_in_flight:
                        mailbox.max_sends_in_flight = mailbox.sends_in_flight
                    try:
                        t_send = time.perf_counter()
                        await _send(item.payload)
                        if item.kind == "preview":
                            session.startup.mark(MARK_FIRST_JPEG_SEND)
                        send_s = time.perf_counter() - t_send
                        now = time.perf_counter()
                        if item.kind == "preview":
                            session.preview_timings.add("send", send_s)
                            if item.started_at is not None:
                                session.preview_timings.add(
                                    "end_to_end", now - item.started_at
                                )
                        else:
                            session.timings.add("send", send_s)
                            if item.started_at is not None:
                                session.timings.add(
                                    "end_to_end", now - item.started_at
                                )
                    finally:
                        mailbox.sends_in_flight -= 1

        preview_task = asyncio.create_task(preview_loop(), name="elixr-preview")
        ai_task = asyncio.create_task(ai_loop(), name="elixr-ai")
        writer_task = asyncio.create_task(writer_loop(), name="elixr-ws-writer")
        _done, _pending = await asyncio.wait(
            {preview_task, ai_task},
            return_when=asyncio.FIRST_EXCEPTION,
        )
        for task in _done:
            exc = task.exception()
            if exc is not None:
                raise exc

    except asyncio.CancelledError:
        raise

    except WebSocketDisconnect:
        # The peer can leave while the frame writer is sending. Session
        # cleanup still runs in finally; there is no pipeline error to send.
        pass

    except Exception:
        logger.exception("CV session loop failed")

        outbound_error = FeedbackMessage(
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
        ).with_session(session_id).model_dump_json()

    finally:
        stop.set()
        mailbox.wake()
        _signal_prepare_gate(
            prepare_gate,
            ok=False,
            error_code="session_not_prepared",
            message=_human_error_message("session_not_prepared"),
        )
        await _await_in_flight_worker(startup_worker, "In-flight camera startup")
        await _await_in_flight_worker(preview_worker, "In-flight preview processing")
        await _await_in_flight_worker(ai_worker, "In-flight AI processing")
        await _await_in_flight_worker(
            readiness_warm_worker, "In-flight readiness warm-up"
        )
        await asyncio.sleep(0)
        for task in (preview_task, ai_task):
            if task is not None and not task.done():
                task.cancel()
        for task in (preview_task, ai_task):
            if task is None:
                continue
            try:
                await task
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.exception("Session loop task failed during shutdown")
        writer_closing.set()
        mailbox.wake()
        if writer_task is not None:
            try:
                await asyncio.wait_for(writer_task, timeout=1.0)
            except (asyncio.TimeoutError, asyncio.CancelledError, Exception):
                if not writer_task.done():
                    writer_task.cancel()
                    try:
                        await writer_task
                    except asyncio.CancelledError:
                        pass
                    except Exception:
                        logger.exception("WebSocket writer failed during shutdown")
        leftover = mailbox.drain()
        for item in leftover:
            try:
                await _send(item.payload)
            except WebSocketDisconnect:
                break
            except Exception:
                logger.exception("Failed to flush leftover WebSocket payload")
        if outbound_error is not None:
            try:
                await _send(outbound_error)
            except WebSocketDisconnect:
                pass
            except Exception:
                logger.exception("Failed to send session pipeline error")

        if session_ref is not None:
            if session_ref.get("session") is session:
                session_ref["session"] = None
            if session_ref.get("session_id") == session_id:
                session_ref["session_id"] = None
            if session_ref.get("mailbox") is mailbox:
                session_ref["mailbox"] = None

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
    connection_closed = False
    submission_recorder: SubmissionRecorder | None = None
    submission_cap_task: asyncio.Task | None = None
    submission_recording_allowed = False
    prepare_command_task: asyncio.Task | None = None
    prepare_command_session_id: str | None = None
    cleanup_orphan_submission_temp_files()

    async def _await_prepare_command() -> None:
        nonlocal prepare_command_task, prepare_command_session_id
        task = prepare_command_task
        if task is None:
            return
        try:
            await task
        finally:
            if prepare_command_task is task:
                prepare_command_task = None
                prepare_command_session_id = None

    async def _cancel_prepare_command() -> None:
        nonlocal prepare_command_task, prepare_command_session_id
        task = prepare_command_task
        prepare_command_task = None
        prepare_command_session_id = None
        if task is None:
            return
        if not task.done():
            task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        except WebSocketDisconnect:
            # A completed prepare may have lost its ACK as the peer left.
            pass

    async def safe_send(text: str) -> None:
        nonlocal connection_closed
        async with send_lock:
            if (
                connection_closed
                or getattr(websocket, "client_state", None) == WebSocketState.DISCONNECTED
            ):
                connection_closed = True
                raise WebSocketDisconnect()
            try:
                await websocket.send_text(text)
            except WebSocketDisconnect:
                connection_closed = True
                raise
            except RuntimeError as exc:
                # Starlette raises this exact error after its application-side
                # close. Other state/programming errors must remain visible.
                if str(exc) != 'Cannot call "send" once a close message has been sent.':
                    raise
                connection_closed = True
                raise WebSocketDisconnect() from exc

    async def send_ack(
        *,
        request_id: str,
        session_id: str | None,
        action: str,
        accepted: bool,
        session_state: str | None,
        error_code: str | None = None,
        message: str | None = None,
        selected_camera_fallback_used: bool | None = None,
        active_camera_device_id: str | None = None,
        active_camera_display_name: str | None = None,
        calibration_scale: float | None = None,
        calibration_source: str | None = None,
        local_file_path: str | None = None,
        video_duration_ms: int | None = None,
        video_size_bytes: int | None = None,
        content_type: str | None = None,
        video_sha256: str | None = None,
        reference_count: int | None = None,
        reference_id: str | None = None,
        trim_start_ms: int | None = None,
        trim_end_ms: int | None = None,
        reference_quality: dict[str, Any] | None = None,
        movement_template: dict[str, Any] | None = None,
        custom_assessment: dict[str, Any] | None = None,
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
            selected_camera_fallback_used=selected_camera_fallback_used,
            active_camera_device_id=active_camera_device_id,
            active_camera_display_name=active_camera_display_name,
            calibration_scale=calibration_scale,
            calibration_source=calibration_source,
            local_file_path=local_file_path,
            video_duration_ms=video_duration_ms,
            video_size_bytes=video_size_bytes,
            content_type=content_type,
            video_sha256=video_sha256,
            reference_count=reference_count,
            reference_id=reference_id,
            trim_start_ms=trim_start_ms,
            trim_end_ms=trim_end_ms,
            reference_quality=reference_quality,
            movement_template=movement_template,
            custom_assessment=custom_assessment,
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

    async def _cancel_submission_cap_task() -> None:
        nonlocal submission_cap_task
        task = submission_cap_task
        submission_cap_task = None
        if task is None or task.done():
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    def _detach_submission_recorder() -> None:
        session = session_ref.get("session")
        if session is not None:
            session.set_submission_recorder(None)

    async def _discard_submission_recorder(recorder: SubmissionRecorder | None) -> None:
        if recorder is None:
            return
        _detach_submission_recorder()
        try:
            await asyncio.to_thread(recorder.cleanup)
        except Exception:
            logger.exception("Submission recorder cleanup failed")

    async def _cleanup_submission_recorder() -> None:
        nonlocal submission_recorder
        await _cancel_submission_cap_task()
        recorder = submission_recorder
        submission_recorder = None
        await _discard_submission_recorder(recorder)

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
        readiness_spec: dict | None = None,
        session_mode: str | None = None,
        allowed_movements: list[tuple[str, str]] | None = None,
        custom_movement_template: dict[str, Any] | None = None,
    ) -> tuple[bool, str | None, str | None]:
        nonlocal session_task, current_session_id, submission_recording_allowed

        await _cleanup_submission_recorder()
        submission_recording_allowed = False

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
                readiness_spec=readiness_spec,
                session_mode=session_mode,
                allowed_movements=allowed_movements,
                custom_movement_template=custom_movement_template,
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
        nonlocal movement, difficulty, current_session_id, submission_recording_allowed

        session_mode = getattr(command, "session_mode", None)
        if session_mode in {"custom_capture", "custom_assessment"}:
            auth_difficulty = command.difficulty
            movement_error = (
                None
                if command.movement == "Custom Movement"
                and command.difficulty in {"Easy", "Medium", "Hard"}
                else "invalid_custom_movement"
            )
        else:
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

        assert auth_difficulty is not None

        movement = command.movement
        difficulty = auth_difficulty
        start_active = command.action == "start"
        allowed_entries: list[tuple[str, str]] | None = None
        prop_type = command.prop_type
        if session_mode == "freestyle":
            raw_allowed = getattr(command, "allowed_movements", None) or []
            allowed_entries = [
                (item.movement, item.prop_type) for item in raw_allowed
            ]
            prop_type = "bottle_and_shaker"

        ok, error_code, error_message = await start_session_loop(
            movement_name=movement,
            prop_type=prop_type,
            camera_device_id=command.camera_device_id,
            camera_index=command.camera_index,
            bottle_detection_enabled=command.bottle_detection_enabled,
            start_active=start_active,
            session_id=command.session_id,
            wait_for_prepare=True,
            readiness_spec=(
                command.readiness_spec.model_dump()
                if command.readiness_spec is not None
                else None
            ),
            session_mode=session_mode,
            allowed_movements=allowed_entries,
            custom_movement_template=getattr(
                command, "custom_movement_template", None
            ),
        )

        if ok:
            submission_recording_allowed = (
                bool(command.allow_submission_recording)
                and command.movement == "Free Practice"
                and session_mode != "freestyle"
            )
            prepared_session = session_ref.get("session")
            prepared_camera = (
                getattr(prepared_session, "camera", None)
                if prepared_session is not None
                else None
            )
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=True,
                session_state="active" if start_active else "preparing",
                selected_camera_fallback_used=(
                    getattr(
                        prepared_camera,
                        "selected_camera_fallback_used",
                        False,
                    )
                    if command.camera_device_id is not None
                    else False
                ),
                active_camera_device_id=getattr(
                    prepared_camera,
                    "active_device_id",
                    None,
                ),
                active_camera_display_name=getattr(
                    prepared_camera,
                    "active_display_name",
                    None,
                ),
            )
        else:
            submission_recording_allowed = False
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
        await asyncio.to_thread(session.begin_readiness)

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

        accepted, error_code = await asyncio.to_thread(session.confirm_readiness)
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

        session.startup.mark(MARK_ACTIVATE_START)
        activated, activation_error = await asyncio.to_thread(session.activate)
        logger.info(
            "CV session activate: movement=%s ok=%s lifecycle=%s session_id=%s",
            movement,
            activated,
            session.lifecycle,
            command.session_id,
        )

        if not activated:
            code = activation_error or "session_not_prepared"
            session.startup.fail("activate_ack", code)
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
        session.startup.mark(MARK_ACTIVATE_ACK)

    async def handle_v1_pause_or_resume(command: PauseCommand | ResumeCommand) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id
        paused = isinstance(command, PauseCommand)

        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        if session is None or not session.is_active:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=_public_session_state(
                    session,
                    current_session_id=current_session_id,
                ),
                error_code="session_not_active",
                message=_human_error_message("session_not_active"),
            )
            return

        accepted, error_code = await asyncio.to_thread(
            session.set_recognition_paused, paused
        )
        if not accepted:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state="active",
                error_code=error_code or "invalid_command",
                message=_human_error_message(error_code or "invalid_command"),
            )
            return

        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action=command.action,
            accepted=True,
            session_state="active",
        )

    async def handle_v1_stop(command: StopCommand) -> None:
        nonlocal session_task, current_session_id, submission_recording_allowed

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

        await _cleanup_submission_recorder()
        submission_recording_allowed = False
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

    def _camera_session_ready(session) -> bool:
        if session is None:
            return False
        return bool(session.is_prepared or session.is_readying or session.is_active)

    async def handle_v1_start_submission_record(
        command: StartSubmissionRecordCommand,
    ) -> None:
        nonlocal submission_recorder, submission_cap_task

        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id
        public_state = _public_session_state(
            session, current_session_id=current_session_id
        )

        async def _reject(code: str) -> None:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="start_submission_record",
                accepted=False,
                session_state=public_state,
                error_code=code,
                message=_human_error_message(code),
            )

        if active_id is None or command.session_id != active_id:
            await _reject("session_id_mismatch")
            return
        if not submission_recording_allowed:
            await _reject("submission_recording_not_allowed")
            return
        if not _camera_session_ready(session):
            await _reject("session_not_prepared")
            return
        if submission_recorder is not None and (
            submission_recorder.is_recording or submission_recorder.has_clip
        ):
            await _reject("submission_already_recording")
            return

        recorder = SubmissionRecorder(max_duration_s=command.duration_seconds)
        try:
            await asyncio.to_thread(recorder.start)
        except SubmissionRecorderError as exc:
            await _discard_submission_recorder(recorder)
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="start_submission_record",
                accepted=False,
                session_state=public_state,
                error_code=exc.code,
                message=exc.message,
            )
            return
        except Exception:
            logger.exception("Submission recorder start failed")
            await _discard_submission_recorder(recorder)
            await _reject("record_failed")
            return

        submission_recorder = recorder
        session.set_submission_recorder(recorder)
        await _cancel_submission_cap_task()

        async def _cap() -> None:
            try:
                await asyncio.sleep(command.duration_seconds)
                current = submission_recorder
                if current is not None:
                    await asyncio.to_thread(current.finalize_due_to_cap)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Submission duration cap failed")

        submission_cap_task = asyncio.create_task(_cap(), name="elixr-submission-cap")
        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="start_submission_record",
            accepted=True,
            session_state=public_state,
        )

    async def handle_v1_stop_submission_record(
        command: StopSubmissionRecordCommand,
    ) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id
        public_state = _public_session_state(
            session, current_session_id=current_session_id
        )
        recorder = submission_recorder

        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="stop_submission_record",
                accepted=False,
                session_state=public_state,
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return
        if recorder is None:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="stop_submission_record",
                accepted=False,
                session_state=public_state,
                error_code="submission_not_recording",
                message=_human_error_message("submission_not_recording"),
            )
            return

        await _cancel_submission_cap_task()
        _detach_submission_recorder()
        try:
            metadata = await asyncio.to_thread(recorder.stop)
        except SubmissionRecorderError as exc:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="stop_submission_record",
                accepted=False,
                session_state=public_state,
                error_code=exc.code,
                message=exc.message,
            )
            return
        except Exception:
            logger.exception("Submission recorder stop failed")
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="stop_submission_record",
                accepted=False,
                session_state=public_state,
                error_code="record_failed",
                message=_human_error_message("record_failed"),
            )
            return

        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="stop_submission_record",
            accepted=True,
            session_state=public_state,
            local_file_path=metadata.local_path,
            video_duration_ms=metadata.video_duration_ms,
            video_size_bytes=metadata.video_size_bytes,
            content_type=metadata.content_type,
            video_sha256=metadata.sha256,
        )

    async def handle_v1_cancel_submission_record(
        command: CancelSubmissionRecordCommand,
    ) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id
        public_state = _public_session_state(
            session, current_session_id=current_session_id
        )
        if (
            active_id is not None
            and command.session_id != active_id
            and submission_recorder is not None
            and submission_recorder.is_recording
        ):
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action="cancel_submission_record",
                accepted=False,
                session_state=public_state,
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return

        await _cleanup_submission_recorder()
        await send_ack(
            request_id=command.request_id,
            session_id=command.session_id,
            action="cancel_submission_record",
            accepted=True,
            session_state=_public_session_state(
                session_ref.get("session"),
                current_session_id=current_session_id,
            ),
        )

    async def handle_v1_custom_command(
        command: StartCustomCaptureCommand
        | StopCustomCaptureCommand
        | DiscardCustomReferenceCommand
        | BuildCustomTemplateCommand
        | FinishCustomAssessmentCommand,
    ) -> None:
        session = session_ref.get("session")
        active_id = session_ref.get("session_id") or current_session_id
        state = _public_session_state(
            session, current_session_id=current_session_id
        )
        if active_id is not None and command.session_id != active_id:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=state,
                error_code="session_id_mismatch",
                message=_human_error_message("session_id_mismatch"),
            )
            return
        if session is None or not session.is_active:
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=state,
                error_code="session_not_active",
                message=_human_error_message("session_not_active"),
            )
            return

        try:
            if isinstance(command, StartCustomCaptureCommand):
                accepted, code = await asyncio.to_thread(
                    session.start_custom_capture,
                    duration_seconds=command.duration_seconds,
                )
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=accepted,
                    session_state=state,
                    error_code=code,
                    message=None if accepted else _human_error_message(code or "invalid_command"),
                    reference_count=session.custom_reference_count,
                )
                return

            if isinstance(command, StopCustomCaptureCommand):
                accepted, code, quality = await asyncio.to_thread(
                    session.stop_custom_capture
                )
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=accepted,
                    session_state=state,
                    error_code=code,
                    message=(
                        "Reference accepted."
                        if accepted
                        else _human_error_message(code or "invalid_command")
                    ),
                    reference_count=session.custom_reference_count,
                    reference_quality=quality,
                    reference_id=quality.get("reference_id"),
                    local_file_path=quality.get("local_file_path"),
                    video_duration_ms=quality.get("video_duration_ms"),
                    trim_start_ms=quality.get("trim_start_ms"),
                    trim_end_ms=quality.get("trim_end_ms"),
                )
                return

            if isinstance(command, DiscardCustomReferenceCommand):
                count = await asyncio.to_thread(session.discard_custom_reference)
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=True,
                    session_state=state,
                    reference_count=count,
                )
                return

            if isinstance(command, DeleteCustomReferenceCommand):
                count = await asyncio.to_thread(session.delete_custom_reference, command.reference_id)
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=True,
                    session_state=state,
                    reference_count=count,
                    reference_id=command.reference_id,
                )
                return

            if isinstance(command, TrimCustomReferenceCommand):
                trim = await asyncio.to_thread(
                    session.trim_custom_reference,
                    command.reference_id,
                    command.trim_start_ms,
                    command.trim_end_ms,
                )
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=True,
                    session_state=state,
                    reference_id=command.reference_id,
                    trim_start_ms=trim["trim_start_ms"],
                    trim_end_ms=trim["trim_end_ms"],
                )
                return

            if isinstance(command, BuildCustomTemplateCommand):
                template = await asyncio.to_thread(session.build_custom_template)
                await send_ack(
                    request_id=command.request_id,
                    session_id=command.session_id,
                    action=command.action,
                    accepted=True,
                    session_state=state,
                    reference_count=session.custom_reference_count,
                    movement_template=template,
                )
                return

            assessment = await asyncio.to_thread(session.finish_custom_assessment)
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=True,
                session_state=state,
                custom_assessment=assessment,
            )
        except ValueError as exc:
            code = str(exc).split(",", 1)[0] or "invalid_command"
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=state,
                error_code=code,
                message=_human_error_message(code),
                reference_count=getattr(session, "custom_reference_count", None),
            )
        except Exception:
            logger.exception("Custom movement command failed: %s", command.action)
            await send_ack(
                request_id=command.request_id,
                session_id=command.session_id,
                action=command.action,
                accepted=False,
                session_state=state,
                error_code="pipeline_error",
                message=_human_error_message("pipeline_error"),
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
        elif isinstance(command, PauseCommand):
            await handle_v1_pause_or_resume(command)
        elif isinstance(command, ResumeCommand):
            await handle_v1_pause_or_resume(command)
        elif isinstance(command, BeginReadinessCommand):
            await handle_v1_begin_readiness(command)
        elif isinstance(command, ConfirmReadinessCommand):
            await handle_v1_confirm_readiness(command)
        elif isinstance(command, StopCommand):
            await handle_v1_stop(command)
        elif isinstance(command, StartSubmissionRecordCommand):
            await handle_v1_start_submission_record(command)
        elif isinstance(command, StopSubmissionRecordCommand):
            await handle_v1_stop_submission_record(command)
        elif isinstance(command, CancelSubmissionRecordCommand):
            await handle_v1_cancel_submission_record(command)
        elif isinstance(
            command,
            (
                StartCustomCaptureCommand,
                StopCustomCaptureCommand,
                DiscardCustomReferenceCommand,
                BuildCustomTemplateCommand,
                FinishCustomAssessmentCommand,
            ),
        ):
            await handle_v1_custom_command(command)

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

            activated, activation_error = await asyncio.to_thread(session.activate)
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

            is_v1 = "protocol_version" in data
            action = data.get("action")

            pending_stop: StopCommand | None = None
            if is_v1 and action == "stop":
                try:
                    parsed = parse_v1_command(data)
                except (ValidationError, ValueError):
                    parsed = None
                if isinstance(parsed, StopCommand):
                    pending_stop = parsed

            if (
                pending_stop is not None
                and prepare_command_task is not None
                and not prepare_command_task.done()
                and pending_stop.session_id == prepare_command_session_id
            ):
                # A v1 stop is allowed to preempt a slow camera prepare.  The
                # matching session is cancelled by handle_v1_stop. The prepare
                # command stays alive long enough to receive its correlated
                # rejection from the prepare gate, so clients can immediately
                # issue a fresh attempt instead of waiting for a timeout.
                await handle_v1(data)
                continue

            # Preserve command ordering for every other command.  Only stop
            # needs to overtake an in-flight prepare to make teardown prompt.
            await _await_prepare_command()

            if is_v1 and action in {"prepare", "start"}:
                prepare_command_task = asyncio.create_task(handle_v1(data))
                prepare_command_session_id = (
                    data.get("session_id")
                    if isinstance(data.get("session_id"), str)
                    else None
                )
                continue

            if is_v1:
                await handle_v1(data)
            else:
                await handle_legacy(data)

    except WebSocketDisconnect:
        connection_closed = True
        logger.info("Client disconnected")

    finally:
        await _cancel_prepare_command()
        await _cleanup_submission_recorder()
        await _stop_session_task(session_task)
        session_ref["session"] = None
        session_ref["session_id"] = None
