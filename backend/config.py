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

# Lightweight GET /cameras discovery (separate from strict session startup).
DISCOVERY_MAX_INDEX = int(os.getenv("DISCOVERY_MAX_INDEX", "4"))
DISCOVERY_CACHE_TTL_S = float(os.getenv("DISCOVERY_CACHE_TTL_S", "30"))
# 0.75s/1-frame was too tight for a second physical device probed right after
# another: a legitimately connected (e.g. built-in) camera could fail to
# produce a usable frame in time and be dropped from the list. Widened to
# give real hardware room to warm up while staying well under the client's
# HTTP timeout for a small number of devices.
DISCOVERY_PROBE_TIMEOUT_S = float(os.getenv("DISCOVERY_PROBE_TIMEOUT_S", "1.5"))
DISCOVERY_PROBE_REQUIRED_CONSECUTIVE = int(
    os.getenv("DISCOVERY_PROBE_REQUIRED_CONSECUTIVE", "2")
)
DISCOVERY_PROBE_READ_SLEEP_S = float(os.getenv("DISCOVERY_PROBE_READ_SLEEP_S", "0.03"))

YOLO_FRAME_SKIP = 2

FPS_LOG_INTERVAL = 60
MIN_TARGET_FPS = 15
MAX_TARGET_FPS = 30

# Custom YOLO model settings. The selected prop detector resolves class IDs
# from each model's declared names at load time; do not assume class zero.
YOLO_CONFIDENCE = 0.4
# NMS IoU threshold: collapse overlapping boxes on the same bottle.
YOLO_IOU = 0.45
# Kept as a compatibility constant for older imports; PropDetector performs
# model-specific class resolution instead of using this value for filtering.
CUSTOM_BOTTLE_CLASS_ID = 0
# Hard cap on how many selected props can be detected/tracked at once.
MAX_BOTTLES = 2


def _load_yolo_imgsz() -> int:
    """Ultralytics inference size. Default 640 preserves current accuracy."""
    raw = os.getenv("YOLO_IMGSZ", "640")
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(
            f"YOLO_IMGSZ must be an integer (got {raw!r})"
        ) from exc
    if value < 32 or value > 1280:
        raise ValueError(
            f"YOLO_IMGSZ must be between 32 and 1280 (got {value})"
        )
    if value % 32 != 0:
        raise ValueError(
            f"YOLO_IMGSZ must be a multiple of 32 (got {value})"
        )
    return value


YOLO_IMGSZ = _load_yolo_imgsz()

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

# Reverse Forearm Stall: target is proximal (elbow -> wrist), between elbow and mid.
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

# Hand Stall: one upright bottle resting on a single open palm.
# Independently tunable from Double Hand Stall (same units: normalized 0-1).
HAND_STALL_UPRIGHT_ASPECT_RATIO = 1.25
HAND_STALL_OPEN_PALM_EXTENSION_RATIO = 1.18
HAND_STALL_MIN_EXTENDED_FINGERS = 3
HAND_STALL_BASE_TO_PALM = 0.11
HAND_STALL_MAX_HORIZONTAL_OFFSET = 0.09
# Reject when bottle bottom-center sits clearly below the palm (image y).
HAND_STALL_BELOW_PALM_REJECT = 0.03

# One Finger Stall: one upright prop balanced on an extended index fingertip.
# All positional values use normalized image coordinates (0-1).
ONE_FINGER_STALL_UPRIGHT_ASPECT_RATIO = 1.25
ONE_FINGER_STALL_INDEX_EXTENSION_RATIO = 1.30
ONE_FINGER_STALL_MIN_STRAIGHT_ANGLE_DEG = 145.0
ONE_FINGER_STALL_OTHER_FINGER_EXTENSION_RATIO = 1.15
ONE_FINGER_STALL_MAX_OTHER_EXTENDED_FINGERS = 1
ONE_FINGER_STALL_BASE_TO_INDEX_TIP = 0.10
ONE_FINGER_STALL_MAX_HORIZONTAL_OFFSET = 0.07
# Reject when the prop bottom-center sits clearly below the fingertip (image y).
ONE_FINGER_STALL_BELOW_FINGERTIP_REJECT = 0.035

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

# Backend-authoritative hold confirmation (active sessions only).
HOLD_CONFIRMATION_SECONDS = float(os.getenv("HOLD_CONFIRMATION_SECONDS", "2.5"))
# Reject hold accumulation when evaluated frames are spaced farther apart.
HOLD_MAX_FRAME_GAP_SECONDS = float(os.getenv("HOLD_MAX_FRAME_GAP_SECONDS", "0.35"))
# Minimum share of positive/stable frames in the current hold segment.
HOLD_MIN_POSITIVE_RATIO = float(os.getenv("HOLD_MIN_POSITIVE_RATIO", "0.85"))

MOVEMENT_CONFIG: dict[str, dict] = {
    "Normal Grip": {"difficulty": "Easy", "requires_hands": True},
    "Bartender's Grip": {"difficulty": "Easy", "requires_hands": True},
    "Reverse Grip": {"difficulty": "Easy", "requires_hands": True},
    "Claw Grip": {"difficulty": "Easy", "requires_hands": True},
    "Hand Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": False},
    "One Finger Stall": {
        "difficulty": "Medium",
        "requires_hands": True,
        "requires_pose": False,
    },
    "Forearm Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
    "Elbow Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
    "Reverse Forearm Stall": {
        "difficulty": "Hard",
        "requires_hands": True,
        "requires_pose": True,
    },
    # Legacy movement names for historical sessions and backward compatibility.
    "Arm Stall": {"difficulty": "Medium", "requires_hands": True, "requires_pose": True},
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
    # Internal Free Practice vision mode: prop detection + preview only.
    # Not a user-selectable catalog movement (Flutter catalog omits it).
    "Free Practice": {
        "difficulty": "Easy",
        "requires_hands": False,
        "requires_pose": False,
        "internal": True,
        "prop_detection_only": True,
    },
}