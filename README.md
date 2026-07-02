# ELIXR

Bottle flair training app — Flutter Windows UI with a Python computer-vision backend (YOLO11n, MediaPipe Pose/Hands, rule-based assessment).

## Prerequisites

- **Flutter SDK** with Windows desktop enabled (`flutter config --enable-windows-desktop`)
- **Python 3.10+**
- A webcam (used by the Python backend only — Flutter never opens the camera)

## Setup

### Flutter

```bash
flutter pub get
```

### Python backend

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate

pip install -r requirements.txt
```

On first inference, Ultralytics downloads `yolo11n.pt` automatically.

## Running (two terminals)

**Terminal 1 — backend:**

```bash
cd backend
.venv\Scripts\activate
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

**Terminal 2 — Flutter app:**

```bash
flutter run -d windows
```

Default WebSocket URL: `ws://127.0.0.1:8000/ws` (configured in `lib/core/constants/app_constants.dart`).

Health check: `http://127.0.0.1:8000/health`

## Performance tuning

Target throughput is **15–30 FPS**. Adjust in `backend/config.py` or via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ELIXR_TARGET_FPS` | `20` | WebSocket frame rate cap |
| `ELIXR_YOLO_FRAME_SKIP` | `2` | Run YOLO every N frames |
| `ELIXR_POSE_FRAME_SKIP` | `1` | Run Pose every N frames |
| `ELIXR_CAMERA_INDEX` | `1` | Preferred webcam device index |
| `ELIXR_CAMERA_FALLBACK_INDEX` | `0` | Fallback index if preferred camera fails |

Benchmark the pipeline:

```bash
cd backend
python scripts/profile_fps.py
```

The backend logs rolling FPS every 60 frames during active sessions.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| **Backend offline / connection error** | Start uvicorn first; confirm port 8000 is free |
| **Camera unavailable** | Close other apps using the webcam; try `ELIXR_CAMERA_INDEX=1` |
| **Model load failed** | Re-run `pip install ultralytics`; ensure internet for first YOLO download |
| **Low FPS** | Increase `ELIXR_YOLO_FRAME_SKIP` to `3` or lower `ELIXR_TARGET_FPS` to `15` |
| **Firewall** | Allow local connections on `127.0.0.1:8000` |

## Firebase

Data is stored in **Cloud Firestore** (project `elixr-app-2026`). **Firebase Authentication** handles email/password sign-in — app users only need an email and password in the app, not a Firebase developer account.

One-time console setup:

1. Enable **Firestore** and **Authentication → Email/Password** in the [Firebase console](https://console.firebase.google.com/project/elixr-app-2026).
2. Deploy rules and indexes:

```bash
firebase deploy --only firestore
```

## Out of scope (for now)

- PyInstaller / `.exe` packaging
- Flutter release builds
- Custom YOLO training
