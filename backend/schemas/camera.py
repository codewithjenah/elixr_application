from typing import Optional

from pydantic import BaseModel, Field


class CameraInfo(BaseModel):
    device_id: str
    display_name: str
    runtime_index: int
    is_active: bool = False
    identity_stable: bool = False

    # Legacy migration field (same as runtime_index). Prefer device_id.
    index: Optional[int] = None


class CamerasResponse(BaseModel):
    cameras: list[CameraInfo] = Field(default_factory=list)
    active_device_id: Optional[str] = None

    # Legacy migration fields. New clients must not use these for naming.
    preferred_index: Optional[int] = None
    fallback_index: Optional[int] = None
    active_index: Optional[int] = None
