import os

TARGET_FPS = int(os.getenv("ELIXR_TARGET_FPS", "20"))
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
JPEG_QUALITY = 70

CAMERA_INDEX = int(os.getenv("ELIXR_CAMERA_INDEX", "1"))
CAMERA_FALLBACK_INDEX = int(os.getenv("ELIXR_CAMERA_FALLBACK_INDEX", "0"))
YOLO_FRAME_SKIP = int(os.getenv("ELIXR_YOLO_FRAME_SKIP", "2"))
POSE_FRAME_SKIP = int(os.getenv("ELIXR_POSE_FRAME_SKIP", "1"))

FPS_LOG_INTERVAL = 60
MIN_TARGET_FPS = 15
MAX_TARGET_FPS = 30
YOLO_CONFIDENCE = 0.4
COCO_BOTTLE_CLASS_ID = 39

SHOULDER_ALIGN_THRESHOLD = 0.05
HAND_BOTTLE_PROXIMITY = 0.15
STALL_PROXIMITY = 0.12
STANCE_JITTER_THRESHOLD = 0.025
GRIP_ANGLE_MIN = 140.0
GRIP_ANGLE_MAX = 180.0
REVERSE_GRIP_ANGLE_MIN = 30.0
REVERSE_GRIP_ANGLE_MAX = 90.0

PINCH_DISTANCE = 0.06
BASKET_PROXIMITY = 0.14
TAP_CONTACT_THRESHOLD = 0.10
FLIP_HISTORY_FRAMES = 12
FLIP_ARC_THRESHOLD = 0.04
HAND_SWITCH_PROXIMITY = 0.15
CHEST_LEVEL_MARGIN = 0.08
MIDLINE_CROSS_MARGIN = 0.06
ELBOW_TAP_CONTACT_THRESHOLD = 0.12

SCORE_WINDOW = 30
SCORE_POSITIVE = 5
SCORE_WARNING = -3
SCORE_ERROR = -8
SCORE_BASE = 70

MOVEMENT_CONFIG: dict[str, dict] = {
    "Normal Grip": {"difficulty": "Easy", "requires_hands": True},
    "Bartender's Grip": {"difficulty": "Easy", "requires_hands": True},
    "Reverse Grip": {"difficulty": "Easy", "requires_hands": True},
    "Hand Stall": {"difficulty": "Easy", "requires_hands": True},
    "Arm Stall": {"difficulty": "Easy", "requires_hands": False},
    "Elbow Stall": {"difficulty": "Easy", "requires_hands": False},
    "Clip": {"difficulty": "Medium", "requires_hands": True},
    "Tap": {"difficulty": "Medium", "requires_hands": True},
    "Basket": {"difficulty": "Medium", "requires_hands": True},
    "Switching": {"difficulty": "Medium", "requires_hands": True},
    "Front Flip": {"difficulty": "Medium", "requires_hands": True},
    "Side Flip": {"difficulty": "Medium", "requires_hands": True},
    "Quick Chest Pass": {"difficulty": "Hard", "requires_hands": True},
    "Staggered Switch": {"difficulty": "Hard", "requires_hands": True},
    "Elbow Tap": {"difficulty": "Hard", "requires_hands": False},
}
