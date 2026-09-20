from fastapi import FastAPI

from api.cameras import router as cameras_router
from api.health import router as health_router
from api.websocket import router as ws_router
from logging_config import configure_logging
from vision.camera import release_shared_camera


def create_app() -> FastAPI:
    configure_logging()
    app = FastAPI(title="ELIXR Backend", version="0.3.0")
    app.include_router(health_router)
    app.include_router(cameras_router)
    app.include_router(ws_router)
    # Ordinary WebSocket disconnects use CameraCapture.release() so a successor
    # practice session can reuse the handle during the bounded debounce window.
    # Process teardown is the separate force-release boundary.
    app.router.on_shutdown.append(release_shared_camera)
    return app


app = create_app()
