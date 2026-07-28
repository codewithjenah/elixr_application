import os

TARGET_FPS = 20
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
JPEG_QUALITY = 70

# Auto-select try order uses ephemeral OpenCV/DirectShow runtime indices.
# These are NOT stable physical-camera identities across machines or reconnects.
# Explicit selection must use camera_device_id from discovery.
# Override without editing this file, e.g.:
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

# Upper Forearm Stall: target is proximal (elbow -> wrist), between elbow and mid.
# Ratio is the fraction of elbow-to-wrist distance used for the stall point.
UPPER_FOREARM_RATIO = 0.33
UPPER_FOREARM_STALL_PROXIMITY = 0.16
# Absolute proximity zones that mean the bottle is on the elbow or ordinary mid-forearm.
UPPER_FOREARM_ELBOW_ZONE = 0.09
UPPER_FOREARM_MID_ZONE = 0.09

# Shoulder Stall: expect the bottle slightly above the shoulder joint (smaller y).
SHOULDER_ABOVE_OFFSET = 0.045
SHOULDER_STALL_PROXIMITY = 0.16
# Bottle centers farther below the shoulder than this are treated as chest/below.
SHOULDER_BELOW_REJECT = 0.03

# Double Hand Stall: two upright bottles, one on each open palm.
# All geometry thresholds use normalized image coordinates (0-1).
# Values are intentionally conservative across typical webcam distances.
DOUBLE_HAND_BOTTLE_BASE_TO_PALM = 0.12
DOUBLE_HAND_MAX_PALM_HEIGHT_DIFF = 0.10
DOUBLE_HAND_MIN_PALM_SEPARATION = 0.12
DOUBLE_HAND_MAX_BOTTLE_HEIGHT_DIFF = 0.12
# Minimum bbox height/width for an approximately upright bottle.
DOUBLE_HAND_UPRIGHT_ASPECT_RATIO = 1.2
# Finger tip must be at least this multiple of wrist-to-MCP distance.
DOUBLE_HAND_OPEN_PALM_EXTENSION_RATIO = 1.2
DOUBLE_HAND_MIN_EXTENDED_FINGERS = 3
# Reject when bottle bottom-center sits clearly below the assigned palm (image y).
DOUBLE_HAND_BELOW_REJECT = 0.03

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
    "Upper Forearm Stall": {
        "difficulty": "Hard",
        "requires_hands": True,
        "requires_pose": True,
    },
    "Shoulder Stall": {
        "difficulty": "Hard",
        "requires_hands": True,
        "requires_pose": True,
    },
    "Double Hand Stall": {
        "difficulty": "Hard",
        "requires_hands": True,
        "requires_pose": False,
    },
}