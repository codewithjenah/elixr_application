"""Discrete Playground freestyle recognition events."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

from schemas.commands import PROTOCOL_VERSION, PropType

RecognitionKind = Literal[
    "movement",
    "flip",
    "advanced_technique",
    "failed_action",
]
Quality = Literal["perfect", "great", "nice"]


class RecognitionEventMessage(BaseModel):
    protocol_version: Literal[1] = PROTOCOL_VERSION
    message_type: Literal["recognition_event"] = "recognition_event"
    session_id: str
    event_id: str
    kind: RecognitionKind
    display_label: str = ""
    identity_revealed: bool = False
    quality: Optional[Quality] = None
    movement: Optional[str] = None
    prop_type: Optional[PropType] = None
    supporting_message: Optional[str] = None
    capture_sequence: Optional[int] = None

    @model_validator(mode="after")
    def _hide_locked_identity(self) -> "RecognitionEventMessage":
        if not self.identity_revealed:
            self.movement = None
            if self.kind == "advanced_technique":
                self.display_label = "Advanced technique detected"
            elif self.kind == "failed_action":
                self.display_label = ""
        elif self.kind == "flip":
            self.movement = None
            if not self.display_label:
                self.display_label = "Flip"
        return self
