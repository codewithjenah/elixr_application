# Python Vision Backend Instructions

These instructions apply to `backend/**` and supplement the repository root `AGENTS.md`.

## Current backend stack

Use Python 3.11 for the current pinned dependency set unless the dependency pins are intentionally reconciled and validated in a clean environment.


- FastAPI and Uvicorn.
- Pydantic response schemas.
- OpenCV camera capture and JPEG encoding.
- Ultralytics YOLO with the selected prop model under `backend/models/`.
- ONNX Runtime CPU (optional DirectML) for the exported `best.onnx` artifact.
- MediaPipe Hand and Pose landmarker task assets.
- Movement-specific rule modules.
- Pytest rule-engine, camera, and session-lifecycle tests. (`pytest` is not currently listed in `backend/requirements.txt`.)

## Runtime ownership

The backend owns:

- The physical webcam.
- CV model loading and inference.
- Landmark extraction.
- Movement evaluation.
- Session scoring.
- Frame annotation.
- WebSocket feedback production.

Keep Flutter independent of these implementation details except for the documented transport schema.

## Async and concurrency

- Never run blocking OpenCV, YOLO, or MediaPipe work directly on the FastAPI event loop.
- Preserve cancellation behavior for the per-session frame task.
- Ensure a cancelled frame operation is awaited before releasing detectors or camera resources.
- Keep one controlled shared-camera owner and respect the existing lock/debounced release behavior.
- Avoid unbounded task creation, queues, or frame accumulation. Prefer dropping/skipping work to increasing latency.
- If changing target FPS or frame skipping, measure processing time and confirm teardown remains responsive.
- `VisionSession.analyze_tick` and lifecycle mutations (`begin_readiness`,
  `confirm_readiness`, `activate`, `close`) share one exclusive AI-state lock.
  At most one AI inference is in flight. Lifecycle methods wait for that
  inference; WebSocket handlers must run those waits with `asyncio.to_thread`
  so preview can continue. Preview rendering must not take this lock.
- Camera capture-producer contention metrics (read duration, publish interval,
  loop gap, blank/fail counts, backend, `CAP_PROP_FPS`) are aggregated per
  telemetry interval and must not be logged per frame.

## Camera lifecycle

- Run the backend with `backend/` as the working directory unless model paths are made explicit and tested.
- Explicit selection uses a discovered `camera_device_id` from `GET /cameras` / `vision.camera_devices`. Physical identity is stable only when `identity_stable` is `true`; `opencv:N` fallback IDs are tied to ephemeral runtime indices. Runtime OpenCV or DirectShow indices are ephemeral implementation details.
- Keep legacy `camera_index` parsing in `parse_camera_selection` only for migration when `camera_device_id` is absent.
- `CAMERA_INDEX` and `CAMERA_FALLBACK_INDEX` influence Auto-select try order only; they are not stable physical-camera identities.
- Preserve lightweight `GET /cameras` discovery separately from strict session startup. Discovery uses bounded probing (`DISCOVERY_PROBE_TIMEOUT_S`, `DISCOVERY_MAX_INDEX`, `DISCOVERY_PROBE_REQUIRED_CONSECUTIVE`) and `DISCOVERY_CACHE_TTL_S` caching with single-flight coordination.
- Session startup requires consecutive usable frames (`_STARTUP_REQUIRED_CONSECUTIVE_FRAMES`, `_STARTUP_TIMEOUT_S`). A camera that opens but returns black frames is not healthy.
- Do not assume all cameras share resolution, FPS, or warm-up behavior. Do not hard-code vendor-specific behavior.
- Preserve shared-camera locking, Windows capture-profile fallback, black-frame rejection, blank-frame recovery, and debounced release (`CAMERA_RELEASE_DEBOUNCE_S`).
- WebSocket lifecycle: version-1 `prepare` / `begin_readiness` / `confirm_readiness` /
  `activate` / `stop` require `protocol_version`, `request_id`, and `session_id`, and receive
  a correlated `command_ack` only after the backend completes the corresponding
  work. `prepare` opens the camera and streams preview
  (`session_state: preparing`) without detectors or scoring.
  `begin_readiness` (guided practice) loads detectors on the same session,
  streams `session_state: readying` with observability checklist fields, and
  must not call movement technique evaluation, `RubricTracker.record`, or
  `HoldValidator.update`. It is idempotent when already readying and rejected
  before prepare or after activation. `confirm_readiness` locks stable readiness
  before countdown; `activate` from `readying` requires prior confirmation.
  `prepared→active` without readiness remains for Free Practice. `activate`
  transitions prepared or confirmed-readying to active inference/scoring without
  reopening the camera and reuses detectors loaded during readiness when present. Legacy `start` (no protocol
  version) still combines prepare+activate; Free Practice keeps prepare →
  activate without readiness. `stop` cancels the session task and schedules
  camera release. Stale `session_id` values must not stop or activate a newer
  session. Malformed JSON and invalid v1 commands return structured errors
  without closing a healthy connection.
- Preview-only preparation must not load YOLO/MediaPipe detectors, evaluate movement rules, or record rubric changes.
- Readiness lives in `assessment/readiness.py` and checks camera/prop/landmark
  observability only (not palm openness, grip orientation, proximity, or
  steadiness). Pose-required movements include `upper_body_visible` (both
  shoulders plus one complete arm chain). Guided readiness loads only the
  landmark detectors required by `readiness_needs_hands` / `readiness_needs_pose`
  (Hands-only grips/stalls never construct Pose; Pose-only stalls never
  construct Hands). Calibration samples the already-running modality — palm
  length or shoulder width — and must not start an extra detector solely for
  scale. The locked scale multiplies proximity/stability thresholds during
  active evaluation.
  Stabilization uses per-item consecutive pass/fail frames plus a monotonic
  global `READINESS_STABLE_DURATION_S`. `confirm_readiness` freezes the
  approved snapshot through countdown. Stable snapshots older than
  `READINESS_SNAPSHOT_MAX_AGE_S` are rejected with `readiness_stale`
  (recoverable).
- Await in-flight frame work before releasing camera and detector resources on stop, cancellation, or disconnect.
- Return machine-readable fatal errors such as `camera_unavailable`, `selected_camera_unavailable`, `invalid_camera_device_id`, `invalid_camera_index`, `session_not_prepared`, `model_load_failed`, `pipeline_init_failed`, and `pipeline_error`.
- Camera changes require tests for Auto-select, `identity_stable` native IDs and `opencv:N` fallback IDs, legacy migration, unavailable saved devices, slow warm-up, reconnects, stop, disconnect, and prepare/activate boundaries where relevant.

## Model and detector behavior

- `PropDetector` and `DualPropDetector` share one combined YOLO model at
  `backend/models/best.pt` (PyTorch fallback) and, when selected,
  `backend/models/best.onnx` (ONNX Runtime). Class IDs are resolved from the
  model's declared names; class zero must not be assumed for every prop.
  `YOLO_RUNTIME` is `auto` | `pytorch` | `onnx_cpu` | `onnx_dml`. `auto`
  keeps PyTorch when `best.pt` is present. ONNX CPU is opt-in via
  `onnx_cpu`. DirectML is explicit-only and must not be required by Linux CI.
- Keep model load failures distinguishable from ordinary “no bottle detected” results.
- Do not download or replace model assets silently.
- Avoid caching fast-changing hand landmarks; stale landmarks create ghost-hand artifacts.
- Cached bottle detections are permitted only within the deliberate YOLO frame-skip strategy.
- Close MediaPipe task objects deterministically.

## Assessment rules

- Put movement-specific logic in `assessment/rules/<movement>.py`.
- Reuse geometry and posture helpers from shared modules rather than copying threshold math.
- Return a typed `RuleResult` with a valid feedback type and posture status.
- Missing required landmarks or props must return `posture_status="unknown"` with a visibility/environment code and no `criterion_results`. Never treat unobservable landmarks as `unstable` technique.
- Keep state explicit through the movement-state dictionary or a new typed structure; do not use hidden module globals for per-session state.
- Add a movement to all required registries/configuration layers, including Flutter's catalog when it is user-selectable.
- Threshold changes require positive, boundary, and negative synthetic tests.

## Rubric assessment (Assessment V2)

- Keep each criterion within `0..3` and the derived total within `0..12`.
- Derive `performance_level` from total only (beginning / developing / competent / proficient / mastered).
- Map feedback codes to rubric criteria via `feedback_codes.criterion_for`; visibility/environment codes must not reduce the rubric.
- Do not derive the rubric from UI-only state or from frame counts.
- Treat feedback severity (`positive` / `warning` / `error`) as coaching only — not as a direct score delta.

## WebSocket schema

Primary contract documentation lives in the root `README.md` (protocol version 1).

`schemas.feedback.FeedbackMessage` remains the feedback payload. Version-1
sessions also stamp `protocol_version`, `message_type: "feedback"`, and
`session_id`. Camera JPEGs use `schemas.feedback.PreviewFrameMessage`
(`message_type: "preview_frame"`) so preview can update independently of AI
scoring. Inbound commands use `schemas.commands`; acknowledgments and
uncorrelated failures use `schemas.protocol` (`command_ack`, `protocol_error`).

When the contract changes:

- Update every creation site in the backend.
- Update Dart parsing (`ws_protocol.dart`, `PracticeFeedback`) and defaults.
- Preserve error payloads that may not contain frame bytes.
- Use stable machine-readable `error_code` values for fatal conditions and
  command rejections.
- Keep human feedback suitable for display but do not require clients to parse
  human text to identify errors.
- Isolate legacy commands (no `protocol_version`) from strict version-1
  validation so legacy permissiveness cannot weaken v1.

## Error handling and logging

- Log internal exceptions with stack traces on the backend.
- Send safe, actionable client messages without leaking local paths, credentials, or sensitive internals.
- Do not transform model failure into an empty detection result when session startup depends on the model.
- Avoid broad exception swallowing in the frame loop.
- Keep expected cancellation separate from operational failure.

## Testing

Prefer deterministic tests with synthetic detections and landmarks.

From the repository root:

```powershell
backend\.venv\Scripts\python.exe -m pytest -q backend\tests
backend\.venv\Scripts\python.exe -m compileall backend\api backend\assessment backend\schemas backend\vision backend\main.py backend\config.py
```

A physical camera and model inference belong in a documented manual integration check, not ordinary unit tests.
