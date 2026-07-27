import asyncio

from fastapi import APIRouter

from schemas.camera import CamerasResponse
from vision.camera import discover_cameras

router = APIRouter()


@router.get("/cameras", response_model=CamerasResponse)
async def list_cameras() -> CamerasResponse:
    """Return currently usable camera indices.

    Blocking OpenCV probing runs in a worker thread so the event loop stays free.
    Does not interrupt an active shared practice-session camera.
    """
    payload = await asyncio.to_thread(discover_cameras)
    return CamerasResponse.model_validate(payload)
