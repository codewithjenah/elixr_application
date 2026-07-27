# ELIXR

ELIXR is a development-stage **Windows desktop bottle-flair training application**. The Flutter client presents guided practice, free practice, session history, and progress tracking. A local FastAPI backend owns the webcam and performs real-time computer vision with a custom YOLO model, MediaPipe Hands/Pose, and movement-specific assessment rules.

> The current codebase is the source of truth. This README documents the implemented architecture and runtime behavior rather than an aspirational project plan.

## What the application currently does

- Email/password authentication with Firebase Authentication.
- User profiles, completed sessions, and feedback history stored in Cloud Firestore.
- Guided practice with countdown, live annotated video, movement feedback, score, combo tracking, hold confirmation, music, and an optional session save flow.
- Free-practice camera mode with live detection overlays and no score or saved session.
- Dashboard, session history, and progress statistics derived from Firestore data.
- Local computer vision for nine movements:
  - Easy: Normal Grip, Bartender's Grip, Reverse Grip
  - Medium: Hand Stall, Arm Stall, Elbow Stall
  - Hard: Upper Forearm Stall, Shoulder Stall, Double Hand Stall
    (Double Hand Stall balances two upright bottles simultaneously,
    one on each open palm — not a single bottle between the hands, and not a handoff)

## Runtime architecture

```text
Flutter Windows client
  ├─ Fluent UI screens and reusable widgets
  ├─ Provider ChangeNotifier services
  ├─ GoRouter navigation and authentication redirects
  ├─ Firebase Authentication
  ├─ Cloud Firestore repositories
  └─ WebSocket client
           │ ws://127.0.0.1:8000/ws
           ▼
FastAPI backend
  ├─ WebSocket session orchestration
  ├─ Shared OpenCV webcam capture
  ├─ Custom YOLO bottle detection (backend/best.pt)
  ├─ MediaPipe Hands and Pose landmarks
  ├─ Movement-specific rule engine
  ├─ Rolling session score
  └─ Annotated JPEG frames returned as base64
```

### Important boundary

The **Python backend owns the webcam**. Flutter never opens the camera directly. The backend sends annotated JPEG frames and structured feedback to Flutter over the local WebSocket connection.

## Repository structure

```text
.
├─ lib/
│  ├─ core/                  # Routing, theme, constants, shared widgets
│  ├─ data/
│  │  ├─ database/          # Firestore adapter
│  │  ├─ models/            # Client/domain data models
│  │  └─ repositories/      # Auth, session, and progress persistence
│  ├─ features/             # Feature-oriented Flutter screens
│  ├─ services/             # App state and runtime orchestration
│  ├─ app.dart              # Providers, theme, router, splash gate
│  └─ main.dart             # Firebase bootstrap and runApp
├─ backend/
│  ├─ api/                   # Health and WebSocket endpoints
│  ├─ assessment/
│  │  ├─ rules/             # One movement evaluator per module
│  │  ├─ rule_engine.py     # Movement registry and dispatch
│  │  └─ scoring.py         # Bounded rolling score
│  ├─ models/               # Bundled MediaPipe model assets
│  ├─ schemas/              # Pydantic WebSocket payloads
│  ├─ tests/                # Rule-engine tests
│  ├─ vision/               # Camera, detectors, types, annotation
│  ├─ best.pt               # Custom flair-bottle YOLO model
│  ├─ config.py             # Vision and scoring constants
│  ├─ main.py               # FastAPI application factory
│  ├─ requirements.txt
│  └─ run.ps1
├─ firestore.rules
├─ firestore.indexes.json
├─ firebase.json
├─ AGENTS.md                # Repository-wide agent instructions
└─ .cursor/rules/           # Scoped Cursor project rules
```

## Prerequisites

- Windows 10 or Windows 11.
- Flutter SDK with Windows desktop support and a Dart version compatible with `sdk: ^3.11.0` in `pubspec.yaml`.
- Visual Studio with the **Desktop development with C++** workload required by Flutter Windows builds.
- Python 3.11. It is the common supported version for the current NumPy 2.4.6 and MediaPipe 0.10.9 pins.
- A webcam.
- Access to the configured Firebase project, or your own Firebase project configured for the app.
- Firebase CLI only when deploying Firestore rules or indexes.

Confirm the Flutter toolchain:

```powershell
flutter config --enable-windows-desktop
flutter doctor
```

## Setup

### 1. Clone the repository

```powershell
git clone https://github.com/codewithjenah/elixr_application.git
cd elixr_application
```

### 2. Install Flutter dependencies

```powershell
flutter pub get
```

### 3. Create the backend virtual environment

```powershell
cd backend
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
# Runtime only
python -m pip install -r requirements.txt
# Development and testing
python -m pip install -r requirements-dev.txt
python -c "import cv2, mediapipe, numpy, ultralytics; print('backend imports OK')"
cd ..
```

The repository already contains:

- `backend/best.pt` for bottle detection.
- `backend/models/hand_landmarker.task`.
- `backend/models/pose_landmarker_lite.task`.

The current implementation does not rely on an automatic YOLO model download during normal startup.

### 4. Configure Firebase

The repository is currently configured for the Firebase project `elixr-app-2026` through `firebase.json` and `lib/firebase_options.dart`.

For the existing project:

1. Enable Firebase Authentication with Email/Password.
2. Create Cloud Firestore.
3. Deploy the repository's rules and indexes when they change:

```powershell
firebase deploy --only firestore
```

For a different Firebase project, run FlutterFire configuration for Windows and review `firebase.json`, `.firebaserc`, Firestore rules, and generated options before committing changes.

Never commit service-account keys, private credentials, or local secret files.

## Run the application

Use two terminals from the repository root.

### Terminal 1 — backend

```powershell
cd backend
.\run.ps1
```

Equivalent command:

```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Verify the health endpoint:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected response:

```json
{ "status": "ok" }
```

### Terminal 2 — Flutter client

```powershell
flutter run -d windows
```

The Flutter client connects to:

```text
ws://127.0.0.1:8000/ws
```

That URL is defined in `lib/core/constants/app_constants.dart`.

## Backend configuration

`backend/config.py` contains the implemented camera, inference, scoring, and rule thresholds.

Only these camera settings are currently environment-variable driven:

| Variable                | Default | Purpose                |
| ----------------------- | ------: | ---------------------- |
| `CAMERA_INDEX`          |     `1` | Preferred webcam index |
| `CAMERA_FALLBACK_INDEX` |     `0` | Fallback webcam index  |

Example:

```powershell
$env:CAMERA_INDEX = "0"
$env:CAMERA_FALLBACK_INDEX = "1"
cd backend
.\run.ps1
```

Other values such as `TARGET_FPS`, `YOLO_FRAME_SKIP`, JPEG quality, model confidence, scoring weights, and movement thresholds are currently Python constants. Change them deliberately in `backend/config.py`, then test the affected camera and movement behavior.

## Data model

Firestore uses three top-level collections:

- `users`
- `sessions`
- `feedbacks`

The client uses snake_case Firestore fields such as `user_id`, `movement_name`, `created_at`, and `feedback_type`. Query indexes are declared in `firestore.indexes.json`.

Current session persistence stores the final score, duration, selected movement, difficulty, and deduplicated feedback messages. Camera frames are not written to Firestore by the current implementation.

## WebSocket contract

Flutter sends control messages such as:

```json
{
  "action": "start",
  "movement": "Hand Stall",
  "difficulty": "Medium",
  "bottle_detection_enabled": true
}
```

or:

```json
{ "action": "stop" }
```

The backend returns the Pydantic `FeedbackMessage` payload. Important fields include:

```text
bottle_detected
bottle_count
movement
score
feedback
feedback_type
posture_status
frame_jpeg_base64
error_code
```

The backend currently emits `bottle_count`; the Dart `PracticeFeedback` model does not expose that field yet. Extra JSON fields are ignored, but a future client use of `bottle_count` must update the Dart model and its tests explicitly.

Any contract change must update the backend producer and Dart parser together:

- `backend/schemas/feedback.py`
- `backend/api/websocket.py`
- `lib/data/models/practice_feedback.dart`
- `lib/services/websocket_service.dart`

## Verification

### Flutter

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

For changes affecting Windows integration or startup:

```powershell
flutter build windows
```

### Python backend

Install pytest in the virtual environment if it is not already available:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pip install pytest
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m compileall api assessment schemas vision main.py config.py
```

Computer-vision unit tests should prefer synthetic landmarks and detections. A real webcam and model inference are manual or integration checks, not prerequisites for every rule test.

## Troubleshooting

### Backend is offline

- Start the FastAPI backend before beginning practice.
- Confirm port `8000` is free.
- Open `http://127.0.0.1:8000/health`.
- Confirm `AppConstants.wsUrl` still matches the backend host and port.

### Camera unavailable or black

- Close Teams, Zoom, OBS, browser camera tabs, and other webcam consumers.
- Try the built-in webcam with `$env:CAMERA_INDEX = "0"`.
- Review backend logs for the selected OpenCV backend and camera index.
- Keep camera ownership in Python; do not add a competing Flutter camera plugin.

### Model load failed

- Start Uvicorn with `backend` as the working directory so the relative `best.pt` path resolves.
- Confirm `backend/best.pt` exists.
- Reinstall the pinned Python requirements in the active virtual environment.

### Firebase permission or index error

- Confirm the signed-in user is authorized by `firestore.rules`.
- Deploy current rules and indexes.
- Follow any Firestore console link shown for a missing composite index, then reconcile it with `firestore.indexes.json`.

### Flutter package or Windows build failure

```powershell
flutter clean
flutter pub get
flutter doctor -v
flutter run -d windows
```

## Controlled agentic development

This repository includes `AGENTS.md`, nested agent instructions, and scoped Cursor rules. They are designed for controlled AI-assisted development:

1. Inspect the implementation before proposing changes.
2. Treat code, tests, schemas, and configuration as the source of truth.
3. Define acceptance criteria for non-trivial work.
4. Make the smallest coherent change across every required contract boundary.
5. Run relevant verification.
6. Review the diff as untrusted code.
7. Report commands, results, assumptions, and anything not verified.

Generated code is not considered complete merely because it compiles or looks plausible.

## Current project constraints

- Windows is the primary supported client platform.
- The vision backend is a separate local Python process.
- The WebSocket endpoint is designed for loopback development and does not implement application-level authentication.
- Release packaging and installer automation are not currently provided.
- Custom model retraining is outside the application runtime.

## License

No license file is currently present. Add an explicit license before treating the repository as reusable open-source software.
