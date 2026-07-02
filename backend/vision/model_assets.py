import logging
from pathlib import Path
from urllib.request import urlretrieve

logger = logging.getLogger(__name__)

MODEL_DIR = Path(__file__).resolve().parent.parent / "models"

MODELS = {
    "pose_landmarker_lite.task": (
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        "pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
    ),
    "hand_landmarker.task": (
        "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
        "hand_landmarker/float16/1/hand_landmarker.task"
    ),
}


def ensure_model(name: str) -> Path:
    path = MODEL_DIR / name
    if path.exists():
        return path

    url = MODELS.get(name)
    if url is None:
        raise FileNotFoundError(f"Unknown model: {name}")

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    logger.info("Downloading %s", name)
    urlretrieve(url, path)
    return path


def ensure_pose_model() -> Path:
    return ensure_model("pose_landmarker_lite.task")


def ensure_hand_model() -> Path:
    return ensure_model("hand_landmarker.task")
