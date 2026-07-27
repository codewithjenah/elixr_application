# ELIXR Hikvision Webcam Black-Screen Fix

## Repository

`https://github.com/codewithjenah/elixr_application.git`

## Branch constraint

Work only on the existing `main` branch.

Do not:

- create a new branch
- switch branches
- open a pull request
- commit automatically
- push automatically

The user will review and commit manually.

---

## Problem

The built-in laptop camera works reliably, but the external Hikvision USB webcam sometimes shows a black screen during movement sessions.

Known webcam details:

- Hikvision USB webcam
- Native resolution: 1920 × 1080
- Maximum frame rate: 30 FPS
- Windows desktop environment
- ELIXR currently processes camera frames at 640 × 480 with a 20 FPS target

The problem can happen when:

- starting a movement
- switching from one movement to another
- reusing the same camera capture between sessions
- reopening the external webcam after a short delay

---

## Current implementation findings

### Camera capture

Primary file:

`backend/vision/camera.py`

The current implementation:

- tries DirectShow first, then Media Foundation on Windows
- uses one shared `cv2.VideoCapture`
- briefly keeps the camera open between sessions
- detects very dark/blank frames
- retries reads several times
- resizes frames to the configured processing size
- validates only enough frames to find one usable frame when opening
- does not automatically rebuild the capture after a long blank-frame streak

### External-camera codec behavior

The current `_mjpg_attempts(index)` disables MJPG attempts for Windows camera indices greater than zero.

That is risky for a 1080p USB webcam because some external webcams are more stable when opened with MJPG, while others are more stable with the default format.

The application should probe multiple capture profiles instead of permanently excluding MJPG for external cameras.

### Capture settings

The current settings apply:

- frame width
- frame height
- buffer size

The target FPS is logged but is not explicitly requested through `cv2.CAP_PROP_FPS`.

### Camera reuse

The shared capture is reused when possible. This is useful for fast restarts, but an external webcam may keep a stale or degraded capture handle after a movement stops.

The application currently checks whether the shared camera can return a usable frame, but it does not maintain enough health information to recover from intermittent black-frame failures.

### Flutter display

The Flutter UI displays JPEG frames received from the backend.

Relevant files:

- `lib/services/websocket_service.dart`
- `lib/features/practice/practice_screen.dart`
- `lib/features/practice/live_practice_screen.dart`
- `lib/features/practice/widgets/training_camera_workspace.dart`

Do not redesign the camera UI for this task. The root fix belongs primarily in the Python camera layer.

---

## Goal

Make the Hikvision external webcam reliable across:

- first session start
- repeated starts and stops
- switching movements
- short black-frame interruptions
- camera discovery
- explicit camera selection
- Auto-select mode

The built-in laptop camera must continue to work.

---

## Required implementation

### 1. Replace `_mjpg_attempts()` with explicit capture profiles

Refactor `backend/vision/camera.py` so Windows camera opening tests ordered profiles.

For an external camera, use this preferred order:

1. DirectShow + MJPG
2. Media Foundation + MJPG
3. DirectShow + default format
4. Media Foundation + default format

For the built-in camera, preserve a conservative order:

1. DirectShow + default format
2. Media Foundation + default format
3. DirectShow + MJPG
4. Media Foundation + MJPG

Represent each attempt with a small typed structure, tuple, or dataclass containing:

- backend API
- backend label
- use_mjpg
- profile label

Avoid deeply nested conditionals.

Do not assume that camera index `1` is always the Hikvision device. Treat all nonzero indices as likely external only for profile ordering.

### 2. Request FPS explicitly

Inside the capture-settings function, apply:

```python
cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
```

Continue requesting:

- `FRAME_WIDTH`
- `FRAME_HEIGHT`
- `CAP_PROP_BUFFERSIZE = 1`

When MJPG is enabled, apply the FOURCC before width, height, and FPS settings.

Do not fail solely because the driver ignores one `cap.set()` request.

### 3. Validate camera startup with consecutive usable frames

Replace one-usable-frame startup acceptance with a stable startup probe.

Recommended behavior:

- warm up for up to approximately 2 seconds
- require at least 5 consecutive usable frames
- reset the consecutive counter after a blank or failed read
- retain the most recent valid frame only for validation
- reject the capture profile if stability is not reached before timeout

Keep the blank-frame brightness and standard-deviation validation.

Make startup constants configurable at module level, for example:

- `_STARTUP_TIMEOUT_S`
- `_STARTUP_REQUIRED_CONSECUTIVE_FRAMES`
- `_STARTUP_READ_SLEEP_S`

Do not add long blocking delays beyond what is needed to establish a reliable stream.

### 4. Track the active capture profile

Store metadata for the shared capture:

- active camera index
- active backend
- active MJPG state
- active profile label

Log the selected profile when the camera opens.

Example log intent:

```text
Camera 1 opened using DirectShow + MJPG.
Requested 640x480 @ 20 FPS.
Actual 640x480 @ 30 FPS.
FOURCC=MJPG.
```

The exact formatting may differ, but logs must expose enough information to diagnose driver negotiation.

### 5. Add persistent blank-frame recovery

When `CameraCapture.read()` encounters repeated blank or failed reads:

- keep retrying within the existing short read loop
- increment a blank-frame streak
- after a configurable threshold, rebuild the capture
- first retry the same selected camera index
- prefer a different capture profile than the one that just failed
- preserve explicit camera selection: do not silently switch to another index
- in Auto-select mode, only try the fallback camera after the preferred camera cannot be recovered

Suggested module-level constants:

- `_MAX_BLANK_FRAME_STREAK`
- `_RECOVERY_COOLDOWN_S`
- `_MAX_RECOVERY_ATTEMPTS_PER_READ`

Recovery must be thread-safe under `_CAMERA_LOCK`.

Avoid recursive `read()` calls.

### 6. Rotate capture profiles during recovery

Maintain enough state to know which profile is currently active.

When recovery occurs:

1. release the stale handle
2. pause briefly for Windows device release
3. retry the same camera using profiles starting after the failed profile
4. wrap around to remaining profiles
5. if all profiles fail:
   - explicit selection: return camera-unavailable behavior for that index
   - Auto-select: try the configured fallback index

Do not permanently blacklist a profile for the whole application lifetime.

### 7. Keep camera reuse, but strengthen its health check

Do not remove shared-camera reuse completely unless tests prove it is unsafe.

Before reusing a shared capture:

- require several consecutive usable frames, not just one
- confirm the active profile metadata exists
- reject and rebuild the capture if the health probe fails

Preserve the current release-generation protection against stale release timers.

### 8. Improve diagnostics returned to the session layer

The current `read()` returns only a frame or `None`.

Introduce a small internal status mechanism so the session can distinguish:

- temporary frame miss
- camera recovering
- camera permanently unavailable

This may be implemented with:

- an internal enum/property
- a result object
- a recovery state queried by `VisionSession`

Do not break the public behavior unnecessarily.

At minimum, log recovery attempts and final recovery failure clearly.

Optional, only if it stays small and backward-compatible:

- send a user-facing feedback message such as “Camera signal lost. Reconnecting…”
- clear that message after frames resume

Do not terminate the WebSocket for a short recoverable frame interruption.

### 9. Do not upscale processing to 1920 × 1080

Keep the current CV processing resolution at 640 × 480 for this fix.

The webcam’s native 1080p capability does not mean the system should process every frame at 1080p.

Do not change YOLO, MediaPipe, movement rules, scoring, or hold validation as part of this task.

### 10. Preserve camera selection behavior

Current behavior must remain:

- `camera_index = null` means Auto-select
- explicit camera index means no silent fallback to another index
- Auto-select tries preferred index then fallback index
- camera discovery rejects unusable/blank devices
- selected index is persisted by `SettingsService`

Do not change this contract.

---

## Files expected to change

Primary:

- `backend/vision/camera.py`
- `backend/tests/test_camera_selection.py`

Possible, only if required for recovery feedback:

- `backend/api/websocket.py`
- `backend/schemas/feedback.py`
- `lib/data/models/practice_feedback.dart`
- `lib/features/practice/widgets/training_camera_workspace.dart`

Do not modify movement rule files.

Do not modify Firestore or leaderboard code.

---

## Required tests

Extend `backend/tests/test_camera_selection.py`.

Add focused tests for:

### Capture profile ordering

- external Windows camera prefers DirectShow + MJPG
- built-in Windows camera prefers default-format profiles first
- both MJPG and default formats are eventually attempted

### FPS request

- `CAP_PROP_FPS` is set to `TARGET_FPS`
- MJPG FOURCC is set before dimension/FPS requests when enabled

### Startup validation

- one valid frame is not enough
- required consecutive usable frames succeed
- a blank frame resets the consecutive counter
- startup timeout rejects an unstable profile

### Shared-camera reuse

- healthy shared capture is reused
- unstable shared capture is released and reopened
- stale release timer cannot close a newly recovered capture

### Runtime recovery

- persistent blank frames trigger recovery
- recovery retries the same explicit index
- explicit selection never switches to fallback index
- Auto-select may use fallback only after preferred recovery fails
- successful recovery resets blank streak
- failed recovery returns no frame without deadlocking

### Discovery

- blank phantom devices remain excluded
- stable external devices remain included
- discovery does not interrupt an active shared capture

Use fake captures and monkeypatching. Do not require physical camera hardware in automated tests.

---

## Manual validation checklist

Run the backend from the `backend` folder and test on Windows.

### Hikvision explicit selection

1. Select the Hikvision camera in Settings.
2. Start Normal Grip.
3. Confirm visible video and stable FPS.
4. Finish the movement.
5. Immediately start another movement.
6. Repeat across Easy, Medium, and Hard movements.
7. Confirm no persistent black screen.

### Rapid restart

1. Start a movement.
2. Stop it.
3. Restart within two seconds.
4. Repeat at least five times.
5. Confirm the external webcam remains usable.

### Temporary signal interruption

1. Start a movement with the Hikvision camera.
2. Briefly interrupt the camera by unplugging and reconnecting only if safe.
3. Confirm the backend logs recovery attempts.
4. Confirm the app either recovers or gives a clear camera-unavailable error.
5. Confirm it does not remain silently black forever.

### Built-in camera regression

1. Select the built-in camera explicitly.
2. Start multiple movements.
3. Confirm no new delay, black screen, or wrong fallback behavior.

### Auto-select

1. Connect both cameras.
2. Confirm the preferred camera is used.
3. Make the preferred camera unavailable.
4. Confirm fallback occurs only in Auto-select mode.

---

## Acceptance criteria

The task is complete when:

- the Hikvision webcam no longer remains on a persistent black screen during normal movement switching
- both MJPG and default capture formats are supported
- DirectShow and Media Foundation are both available as fallback profiles
- startup requires consecutive valid frames
- runtime blank-frame streaks trigger controlled camera recovery
- explicit camera selection never silently changes camera index
- Auto-select can recover or fall back appropriately
- target FPS is explicitly requested
- logs show actual selected backend, format, resolution, and FPS
- all existing camera-selection tests pass
- all newly added tests pass
- built-in camera behavior remains working
- no movement/scoring logic is changed

---

## Validation commands

From the repository root:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest tests/test_camera_selection.py -q
```

Then run the complete backend test suite:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Run Flutter tests only if Flutter files were changed:

```powershell
cd ..
flutter test
```

Also run static analysis if Dart files were modified:

```powershell
flutter analyze
```

---

## Required agent summary

At the end, report:

1. root cause addressed
2. files changed
3. capture profile order implemented
4. recovery behavior implemented
5. tests added or updated
6. commands run and results
7. any limitation still caused by the Hikvision driver or Windows
8. confirmation that work stayed on `main`
9. confirmation that no commit, push, branch, or PR was created
