"""Outbound WebSocket protocol control messages (acks and protocol errors)."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

from schemas.commands import PROTOCOL_VERSION


class CommandAck(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[1] = PROTOCOL_VERSION
    message_type: Literal["command_ack"] = "command_ack"
    request_id: str
    session_id: Optional[str] = None
    action: str
    accepted: bool
    session_state: Optional[str] = None
    error_code: Optional[str] = None
    message: Optional[str] = None
    calibration_scale: Optional[float] = None
    calibration_source: Optional[Literal["shoulders", "palm_fallback", "default"]] = None
    local_file_path: Optional[str] = None
    video_duration_ms: Optional[int] = None
    video_size_bytes: Optional[int] = None
    content_type: Optional[str] = None
    video_sha256: Optional[str] = None


class ProtocolError(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[1] = PROTOCOL_VERSION
    message_type: Literal["protocol_error"] = "protocol_error"
    request_id: Optional[str] = None
    session_id: Optional[str] = None
    error_code: str
    message: str = Field(min_length=1)
