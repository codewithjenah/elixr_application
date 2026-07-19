import os

TARGET_FPS = 20
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
JPEG_QUALITY = 70

# Camera setup:
# CAMERA_INDEX = 0  -> built-in laptop camera
# CAMERA_INDEX = 1  -> Hikvision USB webcam
#
# Default: Hikvision USB webcam. Override without editing this file, e.g.:
#   $env:CAMERA_INDEX = "0"; .\run.ps1
CAMERA_INDEX = int(os.getenv("CAMERA_INDEX", "1"))
CAMERA_FALLBACK_INDEX = int(os.getenv("CAMERA_FALLBACK_INDEX", "0"))

# Keep the webcam open briefly when sessions restart.
CAMERA_RELEASE_DEBOUNCE_S = 2.0

YOLO_FRAME_SKIP = 2

FPS_LOG_INTERVAL = 60
MIN_TARGET_FPS = 15
MAX_TARGET_FPS = 30

# Custom YOLO model settings
# Your trained best.pt from Roboflow has one class:
# class 0 = flair_bottle
YOLO_CONFIDENCE = 0.4
# NMS IoU threshold: collapse overlapping boxes on the same bottle.
YOLO_IOU = 0.45
CUSTOM_BOTTLE_CLASS_ID = 0
# Hard cap on how many bottles can be detected/tracked at once.
MAX_BOTTLES = 2

HAND_BOTTLE_PROXIMITY = 0.15
STALL_PROXIMITY = 0.12
# Wider tolerance for arm/elbow stalls, which rest away from the palm.
ARM_STALL_PROXIMITY = 0.22
# Tolerance when the stall point comes from MediaPipe Pose joints (wrist/elbow),
# which sit slightly off from where the bottle actually rests.
POSE_STALL_PROXIMITY = 0.18
# Max bottle drift (normalized) allowed while a stall is held.
STALL_STABILITY_THRESHOLD = 0.06
STALL_HISTORY_FRAMES = 12

PINCH_DISTANCE = 0.06
BASKET_PROXIMITY = 0.14
TAP_CONTACT_THRESHOLD = 0.10

SCORE_WINDOW = 30
SCORE_POSITIVE = 5
SCORE_WARNING = -3
SCORE_ERROR = -8
SCORE_BASE = 70

MOVEMENT_CONFIG: dict[str, dict] = {
    "Normal Grip": {"difficulty": "Easy", "requires_hands": True},
    "Bartender's Grip": {"difficulty": "Easy", "requires_hands": True},
    "Reverse Grip": {"difficulty": "Easy", "requires_hands": True},
    "Hand Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
    "Arm Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
    "Elbow Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
    "Tap": {"difficulty": "Hard", "requires_hands": True},
    "Basket": {"difficulty": "Hard", "requires_hands": True},
}