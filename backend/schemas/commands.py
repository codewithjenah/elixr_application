"""Strict inbound WebSocket command schemas (protocol version 1)."""

from __future__ import annotations

from typing import Annotated, Literal, Optional, Union

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


class PrepareCommand(_CommandBase):
    action: Literal["prepare"]
    movement: Annotated[str, Field(min_length=1, max_length=MAX_MOVEMENT_LENGTH)]
    difficulty: Annotated[str, Field(min_length=1, max_length=MAX_DIFFICULTY_LENGTH)]
    bottle_detection_enabled: StrictBool = True
    prop_type: PropType = "bottle"
    camera_device_id: Optional[str] = None
    camera_index: Optional[StrictInt] = None
    allow_submission_recording: StrictBool = False

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
        return self

class ActivateCommand(_CommandBase):
    action: Literal["activate"]


class BeginReadinessCommand(_CommandBase):
    action: Literal["begin_readiness"]


class ConfirmReadinessCommand(_CommandBase):
    action: Literal["confirm_readiness"]


class StopCommand(_CommandBase):
    action: Literal["stop"]


class StartSubmissionRecordCommand(_CommandBase):
    action: Literal["start_submission_record"]


class StopSubmissionRecordCommand(_CommandBase):
    action: Literal["stop_submission_record"]


class CancelSubmissionRecordCommand(_CommandBase):
    action: Literal["cancel_submission_record"]


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
    StartCommand,
    StartSubmissionRecordCommand,
    StopSubmissionRecordCommand,
    CancelSubmissionRecordCommand,
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
    if action == "start":
        return StartCommand.model_validate(data)
    if action == "start_submission_record":
        return StartSubmissionRecordCommand.model_validate(data)
    if action == "stop_submission_record":
        return StopSubmissionRecordCommand.model_validate(data)
    if action == "cancel_submission_record":
        return CancelSubmissionRecordCommand.model_validate(data)
    raise ValueError("unknown_action")
