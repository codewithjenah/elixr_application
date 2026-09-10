# ELX-010 startup diagnostics

Measurement-only instrumentation for the delay a trainee sees before the live
preview becomes usable, plus the later machine-vs-human stages of startup.
This does **not** change camera ownership, preview-before-model-warm-up,
readiness, or activation.

No camera frames, JPEG bytes, Base64 preview data, evidence images, Firebase
user identifiers, or trainee names are stored.

## Milestone definitions

Durations are milliseconds between two monotonic marks **in the same process**.
Dart and Python clocks are never subtracted from each other. Records are joined
by `session_id` after each side has already computed its own durations.

| Duration | Observer | Start mark | End mark | Notes |
| --- | --- | --- | --- | --- |
| `connection` | Client | `WebSocketService.connect` start | socket ready | Null if this attempt reused an already-open socket (`ws_already_connected`) |
| `prepare` | Client | `prepare` send | matching `command_ack` | Includes backend camera open plus network |
| `prepare` | Backend | session origin | prepare gate / ack | Camera open plus session setup |
| `camera_open` | Backend | `CameraCapture.open` start | `open()` return | New handle or shared-camera reuse |
| `first_usable_frame` | Backend | camera open start | first non-blank startup-probe frame | Black frames are rejected and do not count |
| `first_jpeg_encode` | Backend | camera open start | first preview JPEG encode | Live path is `render_preview`. The preview mailbox keeps only the latest unsent JPEG, so this frame may never be sent |
| `first_jpeg_send` | Backend | camera open start | first `preview_frame` WebSocket send | First **sent** preview; `capture_sequence` may be later than the first encode |
| `client_first_preview` | Client | Start action (`beginPracticeAttempt`) | first current-session JPEG received | Trainee-perceived preview delay. Includes decode. Prepare ack is **not** this event |
| `detector_warmup` | Backend | readiness AI warm-up start | warm-up complete | YOLO + required MediaPipe load; after first preview |
| `readiness_stable` | Both | `begin_readiness` | first `readiness_stable` | **User-dependent** (position/visibility), not machine-only |
| `activate_ack` | Both | `activate` send / receive | accepted matching ack | Does **not** include waiting for the trainee to press Start |

Missing or not-reached milestones are JSON `null`. They are never coerced to
`0`. A measured `0` is allowed only when both marks exist.

Repeated preview frames, duplicate acks, reconnect leftovers, and stale
`session_id` values cannot overwrite the original mark for the current sample.

## Cold vs warm

Inspected runtime (not assumed):

- **Camera, process-level:** `CameraCapture` keeps a shared `VideoCapture` and
  releases it only after `CAMERA_RELEASE_DEBOUNCE_S` (2.0s). A later `prepare`
  in that window can reuse the handle (`camera_start_class=warm_camera`).
- **Models, session-level:** `VisionSession` constructs a new `PropDetector`.
  YOLO weights load in `_warm_readiness_locked` / `ensure_ready`. That ONNX or
  PyTorch session is abandoned with the `VisionSession` object;
  `VisionSession.close` does not retain it. MediaPipe Hands and Pose are
  constructed during warm-up and closed in `VisionSession.close`. ELIXR does
  **not** keep initialized model objects across sessions.

Therefore:

| `start_class` | Meaning |
| --- | --- |
| `cold` | New camera handle and consecutive usable-frame probe. Models loaded for this session. |
| `warm_camera` | Shared camera reused. Models still loaded from scratch. |
| `warm_model` | **Not produced** by the current runtime. Do not label a run “warm model”. |

OS disk cache or ONNX Runtime internals may make a second load faster. That is
not ELIXR-retained initialized model state.

## How to run the diagnostic

On each Windows pilot machine, use the same camera selection and a guided
practice movement that needs Hands or Pose so detector warm-up is in the path.

1. From a developer checkout, start the backend (`backend/run.ps1`).
2. Optionally set a stable device label:

   ```powershell
   $env:ELIXR_PILOT_DEVICE_ID = "pilot-1"
   ```

3. Leave `ELIXR_STARTUP_DIAGNOSTICS` unset (enabled for normal backend runs;
   disabled automatically under pytest). Set `ELIXR_STARTUP_DIAGNOSTICS=0` to
   disable file output.
4. `flutter run -d windows` from the repository root.
5. Connect, then start a practice session. Wait until the first preview is
   visible. For guided practice continue through readiness and activation if
   you need those durations.
6. Stop the session. Backend writes
   `backend/logs/startup_diagnostics/samples.jsonl`. Flutter writes
   `logs/startup_diagnostics/client_samples.jsonl` (cwd is usually the repo
   during `flutter run`). Override both with `ELIXR_STARTUP_DIAGNOSTICS_DIR`.

### Cold vs warm_camera collection

- **Cold:** restart the backend process (or wait more than two seconds after
  stop so the shared camera is released), then start one session.
- **warm_camera:** stop a session and start another within two seconds. Models
  still reload.

Target 20 repetitions per condition when practical. Always report `n` with
every percentile.

## How to generate the summary

From `backend/`:

```powershell
.\.venv\Scripts\python.exe scripts\startup_diagnostics_report.py --write-summary
```

The script joins client and backend samples by `session_id`, groups by
`pilot_device_id`, `start_class`, and `session_mode`, and prints `n` / p50 /
p95 / min / max. It writes `summary.md` into the diagnostics directory
(gitignored).

Do not mix guided, Free Practice, and freestyle rows in one percentile group.
Free Practice skips async detector warm-up; playground freestyle skips the
readiness gate. The recommended matrix is guided practice with Hands or Pose.

## Collecting on another Windows machine

1. Use the same repository revision and the same camera/session settings.
2. Set `ELIXR_PILOT_DEVICE_ID` to `pilot-2` or `pilot-3`.
3. Repeat the cold and warm_camera procedure above.
4. Copy only the JSONL files (not logs that may contain other local paths) onto
   the machine that runs the aggregator, or run the aggregator in place.

Do not commit generated JSONL or `summary.md`.

## Client-observed vs backend-observed

- **Client-observed:** connection, prepare send→ack, first preview received,
  readiness-stable (from feedback), activate send→ack.
- **Backend-observed:** camera open, first usable frame, JPEG encode/send,
  detector warm-up, readiness-stable (from tracker), activate receive→ack.

Backend camera identity is a hashed DevicePath (or `opencv_fallback` /
`unstable`). Prepare does not re-enumerate DirectShow devices to fetch a
friendly name; that would add discovery time to the measurement. Flutter may
annotate a display name from the already-loaded settings camera list.

The trainee-visible “camera is up” time is `client_first_preview`.

## Interpreting p50 / p95

Percentiles use nearest-rank:

`index = round(p/100 * (n-1))`, clamped to `[0, n-1]`.

An empty set is `null`, never `0`. Every aggregate line includes `n`.
p95 with `n < 20` is still computed but is a weak estimate; show `n`.

Do not treat `readiness_stable` as a camera/model performance number. It
includes trainee position/visibility plus the client Ready beat (~500 ms)
before auto `confirm_readiness`. Do not treat time spent waiting to press
Start, or countdown overlay time, as `activate_ack`.

`prepare` (ack after camera open) is shorter than `client_first_preview`
(first JPEG on screen). Use both; they are different events.

Do not recommend optimizations until the collected samples show which duration
dominates `client_first_preview` versus later stages.

## Three-device status

ELX-010 implementation can ship with the collection workflow verified on the
current development machine. The benchmark is **not complete** until cold and
`warm_camera` measurements exist for at least three real pilot Windows devices.
Uncollected device rows stay pending. Do not invent values.
