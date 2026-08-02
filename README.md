# ELIXR

ELIXR is a development-stage **Windows desktop bottle-flair training application**. The Flutter client presents guided practice, free practice, session history, and progress tracking. A local FastAPI backend owns the webcam and performs real-time computer vision with a custom YOLO model, MediaPipe Hands/Pose, and movement-specific assessment rules.

> The current codebase is the source of truth. This README documents the implemented architecture and runtime behavior rather than an aspirational project plan.

## What the application currently does

- Email/password authentication with Firebase Authentication.
- User profiles, completed sessions, and feedback history stored in Cloud Firestore.
- Guided practice with countdown, live annotated video, movement feedback, score, combo tracking, hold confirmation, music, and an optional session save flow.
- Free-practice camera mode with live detection overlays and no score or saved session.
- Dashboard, session history, and progress statistics derived from Firestore data.
- Global leaderboard with XP awards for completed sessions, live top-player rankings, and paginated player lists.
- Local computer vision for eleven movements:
  - Easy: Normal Grip, Bartender's Grip, Reverse Grip, Claw Grip
    (Claw Grip is an upright top-down hold with curled fingers around the upper neck)
  - Medium: Hand Stall, One Finger Stall, Forearm Stall, Elbow Stall
    (One Finger Stall balances one upright selected prop on one extended index fingertip)
  - Hard: Reverse Forearm Stall, Shoulder Stall, Double Hand Stall
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
  ├─ Prop-aware YOLO detection (backend/models/bottle_best.pt,
  │  backend/models/shaker_best.pt)
  ├─ MediaPipe Hands and Pose landmarks
  ├─ Movement-specific rule engine
  ├─ Rolling session score
  └─ Annotated JPEG frames returned as base64
```

### Important boundary

The **Python backend owns the webcam**. Flutter never opens the camera directly. The backend sends annotated JPEG frames and structured feedback to Flutter over the local WebSocket connection. Flutter only displays backend-supplied preview and active-session JPEG bytes.

Camera labels shown in Settings come from backend discovery metadata (`display_name`), not from assumed runtime-index ordering.

## Repository structure

```text
.
├─ lib/
│  ├─ core/                  # Routing, theme, constants, shared widgets
│  ├─ data/
│  │  ├─ database/          # Firestore adapter
│  │  ├─ models/            # Client/domain data models
│  │  └─ repositories/      # Auth, session, progress, and leaderboard persistence
│  ├─ features/             # Feature-oriented Flutter screens
│  ├─ services/             # App state and runtime orchestration
│  ├─ app.dart              # Providers, theme, router, splash gate
│  └─ main.dart             # Firebase bootstrap and runApp
├─ backend/
│  ├─ api/                   # Health, camera discovery, and WebSocket endpoints
│  ├─ assessment/
│  │  ├─ rules/             # One movement evaluator per module
│  │  ├─ rule_engine.py     # Movement registry and dispatch
│  │  └─ scoring.py         # Bounded rolling score
│  ├─ models/               # YOLO prop and bundled MediaPipe model assets
│  ├─ schemas/              # Pydantic WebSocket payloads
│  ├─ tests/                # Pytest rule-engine, camera, and session-lifecycle tests
│  ├─ vision/               # Camera, detectors, types, annotation
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

- `backend/models/bottle_best.pt` for bottle detection.
- `backend/models/shaker_best.pt` for cocktail-shaker detection.
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

HTTP health and camera discovery use the same host:

```text
http://127.0.0.1:8000/health
http://127.0.0.1:8000/cameras
```

Those URLs are defined in `lib/core/constants/app_constants.dart`.

## Camera discovery and selection

The backend is the only webcam owner. Flutter discovers cameras through the backend and persists the user's choice locally (not in Firestore).

### Discovery endpoint

`GET /cameras` returns currently usable cameras with identity metadata:

```json
{
  "cameras": [
    {
      "device_id": "\\\\?\\usb#vid_1234&pid_5678",
      "display_name": "Integrated Camera",
      "runtime_index": 0,
      "is_active": false,
      "identity_stable": true,
      "index": 0
    }
  ],
  "active_device_id": null,
  "preferred_index": 1,
  "fallback_index": 0,
  "active_index": null
}
```

- `device_id` is the selection identifier exposed by discovery for explicit selection.
- `display_name` is the user-facing label from OS enumeration when available.
- `runtime_index` is the current OpenCV/DirectShow index and may change after reconnects, reboots, or driver changes.
- `identity_stable` is `true` for native Windows/DirectShow device identities that can remain stable across runtime-index changes; it is `false` for OpenCV fallback IDs such as `opencv:0`, which are tied to an ephemeral runtime index and must not be treated as permanent physical identities.
- `index` is a legacy migration field equal to `runtime_index`.
- `preferred_index` / `fallback_index` reflect backend Auto-select try order from environment/config; they are not physical-camera identities.
- `force_refresh=true` bypasses the short-lived discovery cache for an explicit user refresh.

Discovery probing is bounded (`DISCOVERY_PROBE_TIMEOUT_S`, `DISCOVERY_MAX_INDEX`, `DISCOVERY_PROBE_REQUIRED_CONSECUTIVE`) and cached (`DISCOVERY_CACHE_TTL_S`). Devices that open but produce black or unusable frames are excluded.

### Explicit selection vs Auto-select

| Mode | WebSocket field | Behavior |
| ---- | --------------- | -------- |
| Auto-select (recommended) | `camera_device_id: null` (omit legacy `camera_index`) | Backend tries `CAMERA_INDEX`, then `CAMERA_FALLBACK_INDEX` if different |
| Explicit device | `camera_device_id` from discovery | Opens that device only; no silent fallback to another camera. Prefer entries with `identity_stable: true` when available. |
| Legacy migration | `camera_index` when `camera_device_id` is absent | Compatibility only; Flutter migrates saved settings to `camera_device_id` after discovery |

**Do not assume runtime index `0` is always built-in or index `1` is always external.** Indices are ephemeral. Never document or label cameras by guessed index order.

Camera preferences are stored in local settings (`%APPDATA%\Elixr\settings.json` on Windows) as `camera_device_id` and a cached `camera_display_name`. If a saved device disconnects, practice shows a fatal `selected_camera_unavailable` error (or `camera_unavailable` for Auto-select with no usable camera). Settings keeps the saved preference visible with a warning until the user chooses another camera or Auto-select.

## Backend configuration

`backend/config.py` contains the implemented camera, inference, scoring, and rule thresholds.

### Camera environment variables (Auto-select order only)

These influence **internal Auto-select try order only**. They are not stable physical-camera identities.

| Variable | Default | Purpose |
| -------- | ------: | ------- |
| `CAMERA_INDEX` | `1` | First runtime index tried for Auto-select |
| `CAMERA_FALLBACK_INDEX` | `0` | Second runtime index tried when different from `CAMERA_INDEX` |
| `DISCOVERY_MAX_INDEX` | `4` | Maximum runtime index probed when OS enumeration is unavailable |
| `DISCOVERY_CACHE_TTL_S` | `30` | Discovery result cache lifetime (seconds) |
| `DISCOVERY_PROBE_TIMEOUT_S` | `1.5` | Per-device discovery warm-up timeout (seconds) |
| `DISCOVERY_PROBE_REQUIRED_CONSECUTIVE` | `2` | Consecutive usable frames required during discovery |
| `DISCOVERY_PROBE_READ_SLEEP_S` | `0.03` | Sleep between discovery frame reads (seconds) |

Example (adjust Auto-select order for a specific machine):

```powershell
$env:CAMERA_INDEX = "0"
$env:CAMERA_FALLBACK_INDEX = "1"
cd backend
.\run.ps1
```

Explicit user selection in the app always uses `camera_device_id` from discovery, not these indices.

Other values such as `TARGET_FPS`, `YOLO_FRAME_SKIP`, JPEG quality, model confidence, scoring weights, and movement thresholds are currently Python constants. Change them deliberately in `backend/config.py`, then test the affected camera and movement behavior.

## Data model

Firestore uses five top-level collections:

- `users` — per-user profile documents keyed by Firebase UID.
- `sessions` — completed practice sessions owned by the authenticated user.
- `feedbacks` — feedback messages linked to a session.
- `leaderboard` — public aggregate ranking entries keyed by Firebase UID (`leaderboard/{userId}`).
- `leaderboard_processed_sessions` — idempotency markers keyed by session ID (`leaderboard_processed_sessions/{sessionId}`).

The client uses snake_case Firestore fields such as `user_id`, `movement_name`, `created_at`, and `feedback_type`. Query indexes are declared in `firestore.indexes.json`.

Current session persistence stores the final score, duration, selected movement,
difficulty, selected prop (`prop_type`, defaulting to `bottle` for old records),
and deduplicated feedback messages. Camera frames are not written to Firestore
by the current implementation.

### Leaderboard

Each eligible completed session awards **25 XP** (`GamificationRules.xpPerSession`). Awards run in a Firestore transaction (`LeaderboardRepository.recordCompletedSession`):

1. Read the source `sessions/{sessionId}` document and verify `user_id` matches the authenticated user.
2. Check `leaderboard_processed_sessions/{sessionId}`; if a marker already exists, skip the award.
3. Create the processed-session marker with `session_id`, `user_id`, `score`, `xp_awarded` (25), and `processed_at`.
4. Merge aggregate fields into `leaderboard/{userId}`.

Leaderboard documents store `user_id`, `display_name`, `total_xp`, `sessions_completed`, `score_sum`, `average_score`, `best_score`, `last_session_at`, `updated_at`, and `last_awarded_session_id`. Display-name-only updates do not change XP or score aggregates.

Rankings are ordered by `total_xp` descending, then `best_score` descending (`LeaderboardRepository.watchTopPlayers` and `fetchPlayersPage`). Paginated fetches default to 50 entries per page and use a Firestore document cursor for `startAfter`. The live top-players stream defaults to 10 entries. The compound index in `firestore.indexes.json` matches this ordering.

Access model (`firestore.rules`):

- `leaderboard`: authenticated read; create/update only on the caller's own document (`userId == request.auth.uid`); delete denied.
- `leaderboard_processed_sessions`: authenticated get/list constrained to the caller's markers; create allowed for own sessions; update/delete denied.

Leaderboard data is **not** globally writable. The current client-written transaction model is appropriate for a controlled capstone environment but is **not** a trusted server-authoritative ranking system against a hostile modified client.

Camera preferences are stored locally (`%APPDATA%\Elixr\settings.json` on Windows), not in Firestore.

## Practice session lifecycle

Guided practice and free practice follow the same camera lifecycle. The practice timer and scoring must **not** start while:

- The backend is unavailable.
- The selected camera is still opening.
- The preview is black or the client is still waiting for the first usable JPEG frame.
- The session has not been explicitly activated.

### End-to-end flow

1. **Backend connection** — Flutter connects to `ws://127.0.0.1:8000/ws` (`WebSocketConnectionState.connected`).
2. **Camera/session preparation** — Flutter sends a protocol v1 `prepare` command with `request_id`, `session_id`, movement, difficulty, selected `prop_type`, `bottle_detection_enabled`, and camera selection (`camera_device_id` or legacy `camera_index`). The backend opens the camera, then returns a correlated `command_ack` with `accepted: true` and `session_state: "preparing"`. Preview frames stream without scoring.
3. **Waiting for first usable preview frame** — Flutter stays in `PracticeRunPhase.preparingCamera` until a preview JPEG arrives (20 s preparation timeout). Countdown must not start merely because prepare was sent.
4. **Countdown** — After the first usable frame, Flutter enters `PracticeRunPhase.countdown` and plays countdown audio/SFX.
5. **Explicit activation** — After countdown, Flutter sends protocol v1 `activate` for the same `session_id`. Backend activates only the matching prepared session and returns `command_ack` with `session_state: "active"`.
6. **Timer and scoring start** — Flutter enters `PracticeRunPhase.active` only after accepted activation (or matching authoritative active feedback), starts the elapsed timer from `00:00`, and enables scoring/combo/hold UI and music.
7. **Hold confirmation** — The Python backend accumulates continuous positive/stable hold time during `session_state: active` and emits `hold_progress`, `hold_duration_ms`, `hold_confirmed`, and `positive_frame_ratio` on each evaluated frame. Flutter displays backend `hold_progress` and completes the movement only when `hold_confirmed` is true. Preview and countdown frames never advance hold confirmation.
8. **Stop, cancellation, disconnect, or navigation teardown** — Flutter sends protocol v1 `stop` for the current `session_id`; backend cancels the frame loop, closes detectors, and releases the shared camera (with debounce). A stale `session_id` cannot stop a newer session. Disconnect/navigation also stops the session and releases backend camera resources.

Legacy compatibility: commands without `protocol_version` (including `{"action":"start", ...}`) still prepare/activate with the older permissive behavior and do not require acknowledgments. New guided/free practice uses protocol v1 `prepare` → `activate`.

### WebSocket contract

Primary protocol for new Flutter clients is **version 1**.

Prepare (preview only):

```json
{
  "protocol_version": 1,
  "request_id": "req-...",
  "session_id": "session-...",
  "action": "prepare",
  "movement": "Hand Stall",
  "difficulty": "Medium",
  "prop_type": "shaker",
  "bottle_detection_enabled": true,
  "camera_device_id": "\\\\?\\usb#vid_1234&pid_5678"
}
```

Activate after countdown:

```json
{
  "protocol_version": 1,
  "request_id": "req-...",
  "session_id": "session-...",
  "action": "activate"
}
```

Stop:

```json
{
  "protocol_version": 1,
  "request_id": "req-...",
  "session_id": "session-...",
  "action": "stop"
}
```

Every version-1 command receives a correlated acknowledgment:

```json
{
  "protocol_version": 1,
  "message_type": "command_ack",
  "request_id": "req-...",
  "session_id": "session-...",
  "action": "activate",
  "accepted": true,
  "session_state": "active",
  "error_code": null,
  "message": null
}
```

Malformed JSON or payloads without a usable `request_id` receive `message_type: "protocol_error"` and the connection stays open.

Version-1 feedback includes `protocol_version`, `message_type: "feedback"`, and `session_id` in addition to the existing fields:

```text
bottle_detected
bottle_count
prop_type
movement
score
feedback
feedback_type
posture_status
frame_jpeg_base64
error_code
camera_ready
session_state
hold_progress
hold_duration_ms
hold_confirmed
positive_frame_ratio
```

Flutter treats missing `message_type` as legacy feedback. Flutter session flags advance only from matching acknowledgments/feedback for the current `session_id`, never from merely sending a command.

Hold confirmation is **backend-authoritative**. Flutter must not run a parallel client-side hold timer. During `session_state: active`, the backend tracks continuous positive/stable frames using monotonic time, resets on invalid feedback or excessive frame gaps, and sets `hold_confirmed: true` once per activated session when the configured duration is reached. Preview, unavailable, and error messages use safe hold defaults (`hold_progress: 0`, `hold_confirmed: false`).

`session_state` values used today:

- `preparing` — preview JPEG stream before activation; no scoring updates
- `active` — movement evaluation and scoring are running
- `idle` — no active practice session (used on successful stop acknowledgments)
- `unavailable` — fatal session/camera error (often with `error_code`)

Common `error_code` values:

- `camera_unavailable` — Auto-select found no usable camera
- `selected_camera_unavailable` — explicit `camera_device_id` could not be opened
- `invalid_camera_device_id` / `invalid_camera_index` — malformed selection
- `invalid_prop_type` — prop is not `bottle` or `shaker`
- `session_not_prepared` — `activate` with no prepared session
- `session_id_mismatch` — command targeted a stale practice attempt
- `invalid_movement` / `difficulty_mismatch` / `invalid_boolean` — strict v1 validation
- `invalid_json` / `invalid_command` / `unknown_action` / `unsupported_protocol_version`
- `model_load_failed`, `pipeline_init_failed`, `pipeline_error` — vision pipeline failures
- `command_timeout` — Flutter-side bounded wait for acknowledgment

`bottle_detected` and `bottle_count` remain compatibility fields and are
populated from the selected prop's detections. New feedback also includes
`prop_type`; legacy feedback without it defaults to `bottle` in Dart.

Any contract change must update the backend producer and Dart parser together:

- `backend/schemas/feedback.py`
- `backend/schemas/commands.py`
- `backend/schemas/protocol.py`
- `backend/schemas/camera.py`
- `backend/api/websocket.py`
- `backend/api/cameras.py`
- `lib/data/models/practice_feedback.dart`
- `lib/data/models/ws_protocol.dart`
- `lib/data/models/camera_device.dart`
- `lib/services/websocket_service.dart`
- `lib/services/camera_device_service.dart`
- `lib/services/settings_service.dart`

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
- In Settings → Preferences, refresh the camera list (`GET /cameras?force_refresh=true`) and confirm the selected device appears.
- For Auto-select issues only, you may adjust `CAMERA_INDEX` / `CAMERA_FALLBACK_INDEX` to change try order on that machine. This does not replace explicit `camera_device_id` selection.
- If a saved camera was unplugged, choose another device or Auto-select; the backend returns `selected_camera_unavailable` for the missing device.
- Review backend logs for capture profile, runtime index, and usable-frame rejection.
- Keep camera ownership in Python; do not add a competing Flutter camera plugin.

### Model load failed

- Confirm both `backend/models/bottle_best.pt` and
  `backend/models/shaker_best.pt` exist.
- The detector resolves these paths relative to the backend source and loads
  only the prop selected for the session.
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
