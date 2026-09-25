"""Strict inbound WebSocket command schemas (protocol version 1)."""

from __future__ import annotations

from typing import Annotated, Any, Literal, Optional, Union

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    field_validator,
    model_validator,
)

PROTOCOL_VERSION = 1
MAX_ID_LENGTH = 128
MAX_MOVEMENT_LENGTH = 128
MAX_DIFFICULTY_LENGTH = 64
MAX_DEVICE_ID_LENGTH = 1024
MAX_CAMERA_INDEX = 10
PropType = Literal["bottle", "shaker", "bottle_and_shaker"]

NonEmptyId = Annotated[str, Field(min_length=1, max_length=MAX_ID_LENGTH)]


class _CommandBase(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    protocol_version: Literal[1]
    request_id: NonEmptyId
    session_id: NonEmptyId

    @field_validator("request_id", "session_id", mode="before")
    @classmethod
    def _strip_ids(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value


class TeacherActivityReadinessSpec(BaseModel):
    model_config = ConfigDict(extra="forbid")
    hands: Literal["none", "one_hand", "two_hands"]
    body: Literal["none", "upper_body"]


class AllowedMovement(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    movement: Annotated[str, Field(min_length=1, max_length=MAX_MOVEMENT_LENGTH)]
    prop_type: PropType

    @field_validator("movement", mode="before")
    @classmethod
    def _strip_movement(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value


class PrepareCommand(_CommandBase):
    action: Literal["prepare"]
    movement: Annotated[str, Field(min_length=1, max_length=MAX_MOVEMENT_LENGTH)]
    difficulty: Annotated[str, Field(min_length=1, max_length=MAX_DIFFICULTY_LENGTH)]
    bottle_detection_enabled: StrictBool = True
    prop_type: PropType = "bottle"
    camera_device_id: Optional[str] = None
    camera_index: Optional[StrictInt] = None
    allow_submission_recording: StrictBool = False
    readiness_spec: Optional[TeacherActivityReadinessSpec] = None
    session_mode: Optional[
        Literal["freestyle", "endless", "custom_capture", "custom_assessment"]
    ] = None
    custom_movement_template: Optional[dict[str, Any]] = None
    allowed_movements: Optional[list[AllowedMovement]] = Field(
        default=None, max_length=32
    )

    @field_validator("movement", "difficulty", mode="before")
    @classmethod
    def _strip_text(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value

    @field_validator("camera_device_id", mode="before")
    @classmethod
    def _normalize_device_id(cls, value):
        if value is None:
            return None
        if isinstance(value, bool) or isinstance(value, (int, float)):
            raise ValueError("invalid_camera_device_id")
        if not isinstance(value, str):
            raise ValueError("invalid_camera_device_id")
        stripped = value.strip()
        if not stripped:
            raise ValueError("invalid_camera_device_id")
        if len(stripped) > MAX_DEVICE_ID_LENGTH:
            raise ValueError("invalid_camera_device_id")
        return stripped

    @field_validator("camera_index")
    @classmethod
    def _validate_camera_index(cls, value: Optional[int]) -> Optional[int]:
        if value is None:
            return None
        if value < 0 or value > MAX_CAMERA_INDEX:
            raise ValueError("invalid_camera_index")
        return value

    @model_validator(mode="after")
    def _reject_dual_camera_selection(self) -> "PrepareCommand":
        # Explicit dual selection is rejected for protocol v1. Auto-select uses
        # camera_device_id=null without camera_index.
        if self.camera_device_id is not None and self.camera_index is not None:
            raise ValueError("invalid_camera_device_id")
        if (
            self.session_mode in {"custom_capture", "custom_assessment"}
            and self.prop_type == "bottle_and_shaker"
        ):
            # The v1 template format has one synchronized prop trajectory.
            # Reject dual-prop custom capture instead of silently recording only
            # the bottle and misrepresenting the resulting capability.
            raise ValueError("unsupported_custom_prop_type")
        if self.session_mode == "endless" and self.prop_type == "bottle_and_shaker":
            raise ValueError("invalid_prop_type")
        if self.session_mode == "custom_assessment":
            if self.custom_movement_template is None:
                raise ValueError("missing_custom_movement_template")
        elif self.custom_movement_template is not None:
            raise ValueError("unexpected_custom_movement_template")
        return self

class ActivateCommand(_CommandBase):
    action: Literal["activate"]


class BeginReadinessCommand(_CommandBase):
    action: Literal["begin_readiness"]


class ConfirmReadinessCommand(_CommandBase):
    action: Literal["confirm_readiness"]


class StopCommand(_CommandBase):
    action: Literal["stop"]


class PauseCommand(_CommandBase):
    action: Literal["pause"]


class ResumeCommand(_CommandBase):
    action: Literal["resume"]


class SetEndlessTargetCommand(_CommandBase):
    action: Literal["set_endless_target"]
    target_generation: Annotated[StrictInt, Field(ge=1)]
    target_type: Literal["movement", "toss_catch", "custom_movement"]
    movement: Optional[Annotated[str, Field(min_length=1, max_length=MAX_MOVEMENT_LENGTH)]] = None
    prop_type: Literal["bottle", "shaker"]
    custom_movement_id: Optional[NonEmptyId] = None
    revision_id: Optional[NonEmptyId] = None
    custom_movement_template: Optional[dict[str, Any]] = None

    @model_validator(mode="after")
    def _validate_target_shape(self) -> "SetEndlessTargetCommand":
        custom = self.target_type == "custom_movement"
        if (self.target_type != "toss_catch") != (self.movement is not None):
            raise ValueError("invalid_endless_target")
        if custom != (self.custom_movement_id is not None and
                       self.revision_id is not None and
                       self.custom_movement_template is not None):
            raise ValueError("invalid_endless_target")
        if not custom and any(value is not None for value in (
            self.custom_movement_id, self.revision_id, self.custom_movement_template
        )):
            raise ValueError("invalid_endless_target")
        return self


class StartSubmissionRecordCommand(_CommandBase):
    action: Literal["start_submission_record"]
    duration_seconds: Literal[15, 30, 45, 60] = 30


class StopSubmissionRecordCommand(_CommandBase):
    action: Literal["stop_submission_record"]


class CancelSubmissionRecordCommand(_CommandBase):
    action: Literal["cancel_submission_record"]


class StartCustomCaptureCommand(_CommandBase):
    action: Literal["start_custom_capture"]
    duration_seconds: Annotated[StrictInt, Field(ge=5, le=60)] = 15


class StopCustomCaptureCommand(_CommandBase):
    action: Literal["stop_custom_capture"]


class DiscardCustomReferenceCommand(_CommandBase):
    action: Literal["discard_custom_reference"]


class DeleteCustomReferenceCommand(_CommandBase):
    action: Literal["delete_custom_reference"]
    reference_id: Annotated[str, Field(min_length=1, max_length=64)]


class TrimCustomReferenceCommand(_CommandBase):
    action: Literal["trim_custom_reference"]
    reference_id: Annotated[str, Field(min_length=1, max_length=64)]
    trim_start_ms: Annotated[StrictInt, Field(ge=0)]
    trim_end_ms: Annotated[StrictInt, Field(gt=0)]


class BuildCustomTemplateCommand(_CommandBase):
    action: Literal["build_custom_template"]


class FinishCustomAssessmentCommand(_CommandBase):
    action: Literal["finish_custom_assessment"]


class StartCommand(_CommandBase):
    """Version-1 form of legacy start (prepare + activate)."""

    action: Literal["start"]
    movement: Annotated[str, Field(min_length=1, max_length=MAX_MOVEMENT_LENGTH)]
    difficulty: Annotated[str, Field(min_length=1, max_length=MAX_DIFFICULTY_LENGTH)]
    bottle_detection_enabled: StrictBool = True
    prop_type: PropType = "bottle"
    camera_device_id: Optional[str] = None
    camera_index: Optional[StrictInt] = None
    allow_submission_recording: StrictBool = False
    readiness_spec: Optional[TeacherActivityReadinessSpec] = None

    @field_validator("movement", "difficulty", mode="before")
    @classmethod
    def _strip_text(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value

    @field_validator("camera_device_id", mode="before")
    @classmethod
    def _normalize_device_id(cls, value):
        return PrepareCommand._normalize_device_id(value)

    @field_validator("camera_index")
    @classmethod
    def _validate_camera_index(cls, value: Optional[int]) -> Optional[int]:
        return PrepareCommand._validate_camera_index(value)

    @model_validator(mode="after")
    def _reject_dual_camera_selection(self) -> "StartCommand":
        if self.camera_device_id is not None and self.camera_index is not None:
            raise ValueError("invalid_camera_device_id")
        return self


InboundCommand = Union[
    PrepareCommand,
    ActivateCommand,
    BeginReadinessCommand,
    ConfirmReadinessCommand,
    StopCommand,
    PauseCommand,
    ResumeCommand,
    SetEndlessTargetCommand,
    StartCommand,
    StartSubmissionRecordCommand,
    StopSubmissionRecordCommand,
    CancelSubmissionRecordCommand,
    StartCustomCaptureCommand,
    StopCustomCaptureCommand,
    DiscardCustomReferenceCommand,
    DeleteCustomReferenceCommand,
    TrimCustomReferenceCommand,
    BuildCustomTemplateCommand,
    FinishCustomAssessmentCommand,
]


def parse_v1_command(data: dict) -> InboundCommand:
    """Parse a protocol-version-1 command using action discrimination."""
    action = data.get("action")
    if action == "prepare":
        return PrepareCommand.model_validate(data)
    if action == "activate":
        return ActivateCommand.model_validate(data)
    if action == "begin_readiness":
        return BeginReadinessCommand.model_validate(data)
    if action == "confirm_readiness":
        return ConfirmReadinessCommand.model_validate(data)
    if action == "stop":
        return StopCommand.model_validate(data)
    if action == "pause":
        return PauseCommand.model_validate(data)
    if action == "resume":
        return ResumeCommand.model_validate(data)
    if action == "set_endless_target":
        return SetEndlessTargetCommand.model_validate(data)
    if action == "start":
        return StartCommand.model_validate(data)
    if action == "start_submission_record":
        return StartSubmissionRecordCommand.model_validate(data)
    if action == "stop_submission_record":
        return StopSubmissionRecordCommand.model_validate(data)
    if action == "cancel_submission_record":
        return CancelSubmissionRecordCommand.model_validate(data)
    if action == "start_custom_capture":
        return StartCustomCaptureCommand.model_validate(data)
    if action == "stop_custom_capture":
        return StopCustomCaptureCommand.model_validate(data)
    if action == "discard_custom_reference":
        return DiscardCustomReferenceCommand.model_validate(data)
    if action == "delete_custom_reference":
        return DeleteCustomReferenceCommand.model_validate(data)
    if action == "trim_custom_reference":
        return TrimCustomReferenceCommand.model_validate(data)
    if action == "build_custom_template":
        return BuildCustomTemplateCommand.model_validate(data)
    if action == "finish_custom_assessment":
        return FinishCustomAssessmentCommand.model_validate(data)
    raise ValueError("unknown_action")
