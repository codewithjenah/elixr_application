import asyncio

from fastapi import APIRouter

from schemas.camera import CamerasResponse
from vision.camera import discover_cameras

router = APIRouter()


@router.get("/cameras", response_model=CamerasResponse)
async def list_cameras(force_refresh: bool = False) -> CamerasResponse:
    """Return currently usable cameras with stable device identities.

    Blocking OpenCV probing runs in a worker thread so the event loop stays free.
    Does not interrupt an active shared practice-session camera.

    ``force_refresh`` lets an explicit user-initiated refresh bypass the
    short-lived discovery cache; single-flight coordination still prevents
    overlapping hardware scans from concurrent callers.
    """
    payload = await asyncio.to_thread(discover_cameras, force_refresh=force_refresh)
    return CamerasResponse.model_validate(payload)
