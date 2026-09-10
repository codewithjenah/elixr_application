"""Session-correlated startup diagnostics (not steady-state CV PERF).

Complements ``PipelineTimings``, which measures per-interval frame-stage
averages after the session is already running. This module records
milestone-once startup durations for one ``session_id``.

Durations are computed from monotonic timestamps in this process only.
Never subtract a Dart monotonic timestamp from these values.

Cold/warm semantics (ELIXR runtime, not OS caches):

* ``camera_start_class=warm_camera`` — this session reused the process-level shared
  ``VideoCapture`` (``CAMERA_RELEASE_DEBOUNCE_S`` has not released it).
* ``camera_start_class=cold`` — this session opened a new capture handle and
  ran the consecutive-usable-frame startup probe.
* ``model_start_class`` is always ``cold`` for a new ``VisionSession``.
  YOLO (ONNX/PyTorch) is constructed per ``VisionSession`` and loaded during
  asynchronous readiness warm-up; ``VisionSession.close`` does not keep that
  ``InferenceSession``. MediaPipe Hands/Pose are created during warm-up and
  closed in ``VisionSession.close``. A second prepare in the same process is
  **not** a warm model start.

``start_class`` used for aggregation is ``cold`` or ``warm_camera``.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import platform
import socket
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol

from runtime_paths import is_frozen, writable_data_root

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1
OBSERVER_BACKEND = "backend"
OBSERVER_CLIENT = "client"

# Milestone names stored as monotonic marks. Missing marks stay absent.
MARK_ORIGIN = "origin"
MARK_CAMERA_OPEN_START = "camera_open_start"
MARK_FIRST_USABLE = "first_usable"
MARK_CAMERA_OPEN_END = "camera_open_end"
MARK_FIRST_JPEG_ENCODE = "first_jpeg_encode"
MARK_FIRST_JPEG_SEND = "first_jpeg_send"
MARK_WARMUP_START = "warmup_start"
MARK_WARMUP_END = "warmup_end"
MARK_READINESS_START = "readiness_start"
MARK_READINESS_STABLE = "readiness_first_stable"
MARK_ACTIVATE_START = "activate_start"
MARK_ACTIVATE_ACK = "activate_ack"
MARK_PREPARE_END = "prepare_end"

DURATION_PREPARE = "prepare"
DURATION_CAMERA_OPEN = "camera_open"
DURATION_FIRST_USABLE_FRAME = "first_usable_frame"
DURATION_FIRST_JPEG_ENCODE = "first_jpeg_encode"
DURATION_FIRST_JPEG_SEND = "first_jpeg_send"
DURATION_DETECTOR_WARMUP = "detector_warmup"
DURATION_READINESS_STABLE = "readiness_stable"
DURATION_ACTIVATE_ACK = "activate_ack"
DURATION_CONNECTION = "connection"
DURATION_CLIENT_FIRST_PREVIEW = "client_first_preview"

_DURATION_KEYS = (
    DURATION_CONNECTION,
    DURATION_PREPARE,
    DURATION_CAMERA_OPEN,
    DURATION_FIRST_USABLE_FRAME,
    DURATION_FIRST_JPEG_ENCODE,
    DURATION_FIRST_JPEG_SEND,
    DURATION_CLIENT_FIRST_PREVIEW,
    DURATION_DETECTOR_WARMUP,
    DURATION_READINESS_STABLE,
    DURATION_ACTIVATE_ACK,
)

# Must never appear in a persisted diagnostic record.
_FORBIDDEN_PAYLOAD_TOKENS = (
    "frame_jpeg_base64",
    "evidence_jpeg_base64",
    "jpeg_bytes",
    "preview_bytes",
    "image_bytes",
    "base64",
)

START_CLASS_COLD = "cold"
START_CLASS_WARM_CAMERA = "warm_camera"
MODEL_CACHE_SESSION_SCOPED = "session_scoped"

PERCENTILE_DEFINITION = (
    "nearest-rank: index = round(p/100 * (n-1)), clamped to [0, n-1]; "
    "empty sample set yields null, never 0"
)

Clock = Callable[[], float]


class DiagnosticSink(Protocol):
    def write(self, record: Mapping[str, Any]) -> None:
        """Persist one complete sample. Must not be used on the frame loop."""


class MemorySink:
    """In-memory sink for tests. Records whether write() was invoked."""

    def __init__(self) -> None:
        self.records: list[dict[str, Any]] = []
        self.write_calls = 0

    def write(self, record: Mapping[str, Any]) -> None:
        self.write_calls += 1
        self.records.append(dict(record))


class RaisingSink:
    """Sink that fails if write() is called. Used to prove hot-path silence."""

    def write(self, record: Mapping[str, Any]) -> None:
        raise AssertionError(
            "startup diagnostics must not persist during the frame loop"
        )


def persistence_enabled() -> bool:
    flag = os.getenv("ELIXR_STARTUP_DIAGNOSTICS", "").strip().lower()
    if flag in {"0", "false", "no", "off"}:
        return False
    if flag in {"1", "true", "yes", "on"}:
        return True
    return "PYTEST_CURRENT_TEST" not in os.environ


def default_diagnostics_dir() -> Path:
    override = os.getenv("ELIXR_STARTUP_DIAGNOSTICS_DIR", "").strip()
    if override:
        return Path(override)
    if is_frozen():
        return writable_data_root() / "logs" / "startup_diagnostics"
    return Path(__file__).resolve().parents[1] / "logs" / "startup_diagnostics"


class JsonlFileSink:
    """Append-only JSONL writer. Invoke only from finalize(), never per frame."""

    def __init__(self, directory: Path | None = None) -> None:
        self._directory = directory or default_diagnostics_dir()

    def write(self, record: Mapping[str, Any]) -> None:
        self._directory.mkdir(parents=True, exist_ok=True)
        path = self._directory / "samples.jsonl"
        line = json.dumps(record, ensure_ascii=True, separators=(",", ":"))
        with path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")


def hashed_pilot_device_id() -> str:
    override = os.getenv("ELIXR_PILOT_DEVICE_ID", "").strip()
    if override:
        return override[:64]
    host = socket.gethostname() or "unknown-host"
    return hashlib.sha256(host.encode("utf-8")).hexdigest()[:12]


def collect_environment_metadata() -> dict[str, Any]:
    """Machine comparison fields. No user/Firebase/trainee identifiers."""
    return {
        "pilot_device_id": hashed_pilot_device_id(),
        "os_name": platform.system(),
        "os_release": platform.release(),
        "os_version": (platform.version() or "")[:80],
        "machine": platform.machine(),
        "cpu_count": os.cpu_count(),
        "python_version": platform.python_version(),
    }


def infer_identity_stable_from_device_id(device_id: str | None) -> bool:
    """Classify stability from the id string without enumerating cameras.

    DirectShow DevicePath ids are treated as stable. ``opencv:N`` and
    ``dshow-name:`` identities are not physical device ids.
    """
    if not device_id:
        return False
    if device_id.startswith("opencv:") or device_id.startswith("dshow-name:"):
        return False
    lowered = device_id.lower()
    if device_id.startswith("\\\\?\\") or device_id.startswith("\\\\") or "#vid_" in lowered:
        return True
    return False


def camera_diagnostic_identity(
    device_id: str | None,
    *,
    identity_stable: bool | None = None,
    display_name: str | None = None,
) -> dict[str, Any]:
    """Stable camera label without treating opencv:N as a physical identity."""
    stable = (
        identity_stable
        if identity_stable is not None
        else infer_identity_stable_from_device_id(device_id)
    )
    if not device_id:
        return {
            "camera_diagnostic_id": "auto-select",
            "identity_stable": False,
            "camera_display_name": display_name,
        }
    if device_id.startswith("opencv:"):
        return {
            "camera_diagnostic_id": "opencv_fallback",
            "identity_stable": False,
            "camera_display_name": display_name,
        }
    if stable is not True:
        return {
            "camera_diagnostic_id": "unstable",
            "identity_stable": False,
            "camera_display_name": display_name,
        }
    digest = hashlib.sha256(device_id.encode("utf-8")).hexdigest()[:16]
    return {
        "camera_diagnostic_id": digest,
        "identity_stable": True,
        "camera_display_name": display_name,
    }


def duration_ms(start: float | None, end: float | None) -> int | None:
    """Elapsed milliseconds, or None if either mark is missing.

    A measured 0 ms is allowed only when both marks exist. Missing work is
    never coerced to 0.
    """
    if start is None or end is None:
        return None
    elapsed = end - start
    if elapsed < 0:
        return None
    return int(round(elapsed * 1000.0))


def percentile(samples: list[float], pct: float) -> float | None:
    """Deterministic nearest-rank percentile. Empty → None, never 0."""
    if not samples:
        return None
    if pct < 0 or pct > 100:
        raise ValueError("percentile must be in 0..100")
    ordered = sorted(samples)
    index = int(round((pct / 100.0) * (len(ordered) - 1)))
    index = min(len(ordered) - 1, max(0, index))
    return float(ordered[index])


def summarize_metric(samples: list[float]) -> dict[str, float | int | None]:
    present = [value for value in samples if value is not None]
    return {
        "n": len(present),
        "p50": percentile(present, 50) if present else None,
        "p95": percentile(present, 95) if present else None,
        "min": min(present) if present else None,
        "max": max(present) if present else None,
    }


def classify_start(*, camera_reused: bool | None) -> tuple[str, str, str]:
    """Return (start_class, camera_start_class, model_start_class)."""
    camera_class = START_CLASS_WARM_CAMERA if camera_reused else START_CLASS_COLD
    # Models are session-scoped; ELIXR does not cache initialized detectors.
    model_class = START_CLASS_COLD
    start_class = camera_class if camera_reused else START_CLASS_COLD
    return start_class, camera_class, model_class


def _iter_keys(value: Any):
    if isinstance(value, Mapping):
        for key, child in value.items():
            yield str(key)
            yield from _iter_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from _iter_keys(child)


def record_contains_image_payload(record: Mapping[str, Any]) -> bool:
    keys = {key.lower() for key in _iter_keys(record)}
    if keys.intersection(_FORBIDDEN_PAYLOAD_TOKENS):
        return True
    blob = json.dumps(record, default=str)
    # Long base64 bodies are never legitimate in this schema.
    return "frame_jpeg_base64" in blob or "evidence_jpeg_base64" in blob


@dataclass
class StartupDiagnostics:
    """One correlated startup sample. Marks are recorded at most once."""

    session_id: str
    clock: Clock = time.monotonic
    sink: DiagnosticSink | None = None
    observer: str = OBSERVER_BACKEND
    session_mode: str | None = None
    movement: str | None = None

    _marks: dict[str, float] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _camera_reused: bool | None = None
    _status: str = "partial"
    _failed_milestone: str | None = None
    _error_code: str | None = None
    _environment: dict[str, Any] = field(default_factory=dict)
    _camera_identity: dict[str, Any] = field(default_factory=dict)
    _yolo_runtime: str | None = None
    _yolo_provider: str | None = None
    _recorded_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
    )
    _finalized: bool = False
    _persist_calls: int = 0
    _mark_attempts: dict[str, int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self._environment:
            self._environment = collect_environment_metadata()

    @property
    def persist_calls(self) -> int:
        return self._persist_calls

    @property
    def finalized(self) -> bool:
        return self._finalized

    def mark_attempts(self, name: str) -> int:
        with self._lock:
            return int(self._mark_attempts.get(name, 0))

    def mark(self, name: str) -> bool:
        return self.mark_at(name, self.clock())

    def mark_at(self, name: str, timestamp: float) -> bool:
        """Record ``name`` once. Later calls are ignored. Never persists."""
        with self._lock:
            self._mark_attempts[name] = self._mark_attempts.get(name, 0) + 1
            if name in self._marks:
                return False
            self._marks[name] = float(timestamp)
            return True

    def has_mark(self, name: str) -> bool:
        with self._lock:
            return name in self._marks

    def timestamp(self, name: str) -> float | None:
        with self._lock:
            return self._marks.get(name)

    def fail(self, milestone: str, error_code: str) -> None:
        with self._lock:
            if self._failed_milestone is None:
                self._failed_milestone = milestone
                self._error_code = error_code
                self._status = "failed"

    def set_camera_reused(self, reused: bool) -> None:
        with self._lock:
            if self._camera_reused is None:
                self._camera_reused = bool(reused)

    def set_session_mode(self, mode: str | None) -> None:
        if mode:
            self.session_mode = mode

    def set_movement(self, movement: str | None) -> None:
        if movement:
            self.movement = movement

    def set_camera_identity(self, identity: Mapping[str, Any]) -> None:
        with self._lock:
            if not self._camera_identity:
                self._camera_identity = dict(identity)

    def set_yolo_runtime(self, runtime: str | None, provider: str | None) -> None:
        with self._lock:
            if runtime and self._yolo_runtime is None:
                self._yolo_runtime = runtime
            if provider and self._yolo_provider is None:
                self._yolo_provider = provider

    def ingest_camera_timings(
        self,
        *,
        open_started_at: float | None,
        first_usable_at: float | None,
        open_completed_at: float | None,
        reused_shared: bool,
        success: bool,
        error_code: str | None = None,
    ) -> None:
        """Copy camera-open timestamps recorded by CameraCapture (same process)."""
        if open_started_at is not None:
            self.mark_at(MARK_CAMERA_OPEN_START, open_started_at)
        if first_usable_at is not None:
            self.mark_at(MARK_FIRST_USABLE, first_usable_at)
        if open_completed_at is not None:
            self.mark_at(MARK_CAMERA_OPEN_END, open_completed_at)
        self.set_camera_reused(reused_shared)
        if not success:
            self.fail("camera_open", error_code or "camera_unavailable")

    def _duration(self, start_name: str, end_name: str) -> int | None:
        return duration_ms(self.timestamp(start_name), self.timestamp(end_name))

    def durations_ms(self) -> dict[str, int | None]:
        camera_origin = MARK_CAMERA_OPEN_START
        if self.timestamp(camera_origin) is None:
            camera_origin = MARK_ORIGIN
        return {
            DURATION_CONNECTION: None,
            DURATION_PREPARE: self._duration(MARK_ORIGIN, MARK_PREPARE_END),
            DURATION_CAMERA_OPEN: self._duration(
                MARK_CAMERA_OPEN_START, MARK_CAMERA_OPEN_END
            ),
            DURATION_FIRST_USABLE_FRAME: self._duration(
                camera_origin, MARK_FIRST_USABLE
            ),
            DURATION_FIRST_JPEG_ENCODE: self._duration(
                camera_origin, MARK_FIRST_JPEG_ENCODE
            ),
            DURATION_FIRST_JPEG_SEND: self._duration(
                camera_origin, MARK_FIRST_JPEG_SEND
            ),
            DURATION_CLIENT_FIRST_PREVIEW: None,
            DURATION_DETECTOR_WARMUP: self._duration(
                MARK_WARMUP_START, MARK_WARMUP_END
            ),
            DURATION_READINESS_STABLE: self._duration(
                MARK_READINESS_START, MARK_READINESS_STABLE
            ),
            DURATION_ACTIVATE_ACK: self._duration(
                MARK_ACTIVATE_START, MARK_ACTIVATE_ACK
            ),
        }

    def to_record(self) -> dict[str, Any]:
        with self._lock:
            reused = self._camera_reused
            status = self._status
            failed = self._failed_milestone
            error_code = self._error_code
            environment = dict(self._environment)
            camera_identity = dict(self._camera_identity)
            yolo_runtime = self._yolo_runtime
            yolo_provider = self._yolo_provider
            recorded_at = self._recorded_at

        start_class, camera_class, model_class = classify_start(
            camera_reused=reused
        )
        if status != "failed":
            # Success requires first JPEG send (preview usable). Warm-up may
            # still be in flight; that remains a valid successful preview start.
            if self.has_mark(MARK_FIRST_JPEG_SEND) or self.has_mark(
                MARK_FIRST_JPEG_ENCODE
            ):
                status = "success"
            else:
                status = "partial"

        record: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "observer": self.observer,
            "session_id": self.session_id,
            "recorded_at": recorded_at,
            "start_class": start_class,
            "camera_start_class": camera_class,
            "model_start_class": model_class,
            "model_cache": MODEL_CACHE_SESSION_SCOPED,
            "session_mode": self.session_mode,
            "movement": self.movement,
            "status": status,
            "failed_milestone": failed,
            "error_code": error_code,
            "durations_ms": self.durations_ms(),
            "environment": environment,
            "camera": camera_identity,
            "yolo_runtime": yolo_runtime,
            "yolo_provider": yolo_provider,
        }
        return record

    def finalize(self) -> dict[str, Any]:
        """Serialize once. Safe to call from session teardown, not per frame."""
        with self._lock:
            if self._finalized:
                record = None
            else:
                self._finalized = True
                record = "pending"
        if record is None:
            return self.to_record()
        payload = self.to_record()
        if self.sink is not None:
            try:
                self.sink.write(payload)
                with self._lock:
                    self._persist_calls += 1
            except Exception:
                logger.exception(
                    "Failed to persist startup diagnostics session_id=%s",
                    self.session_id,
                )
        return payload


def default_sink() -> DiagnosticSink | None:
    if not persistence_enabled():
        return None
    return JsonlFileSink()


def aggregate_records(
    records: list[Mapping[str, Any]],
) -> dict[str, Any]:
    """Group by pilot device, start_class, and session_mode; emit count + p50/p95."""
    grouped: dict[tuple[str, str, str], list[Mapping[str, Any]]] = {}
    for record in records:
        env = record.get("environment") or {}
        device = str(env.get("pilot_device_id") or "unknown-device")
        start_class = str(record.get("start_class") or START_CLASS_COLD)
        session_mode = str(record.get("session_mode") or "unknown-mode")
        grouped.setdefault((device, start_class, session_mode), []).append(record)

    groups: list[dict[str, Any]] = []
    for (device, start_class, session_mode), items in sorted(grouped.items()):
        metrics: dict[str, Any] = {}
        for key in _DURATION_KEYS:
            samples: list[float] = []
            for item in items:
                durations = item.get("durations_ms") or {}
                value = durations.get(key)
                if isinstance(value, (int, float)):
                    samples.append(float(value))
            metrics[key] = summarize_metric(samples)
        groups.append(
            {
                "pilot_device_id": device,
                "start_class": start_class,
                "session_mode": session_mode,
                "sample_count": len(items),
                "metrics": metrics,
            }
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "percentile_definition": PERCENTILE_DEFINITION,
        "model_cache": MODEL_CACHE_SESSION_SCOPED,
        "cold_warm_definition": {
            "cold": (
                "New VideoCapture open plus consecutive usable-frame probe. "
                "YOLO/MediaPipe are loaded for this VisionSession."
            ),
            "warm_camera": (
                "Shared camera handle reused inside CAMERA_RELEASE_DEBOUNCE_S. "
                "Models are still loaded from scratch for the new session."
            ),
            "warm_model": (
                "Not produced by current ELIXR runtime. Detectors are not "
                "retained across VisionSession.close()."
            ),
        },
        "groups": groups,
    }


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            payload = json.loads(text)
            if isinstance(payload, dict):
                records.append(payload)
    return records


def merge_backend_and_client(
    backend: Mapping[str, Any] | None,
    client: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """Join already-computed durations by session_id. Never mix raw clocks."""
    if backend is None and client is None:
        raise ValueError("at least one sample is required")
    session_id = (backend or client or {}).get("session_id")
    merged: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "session_id": session_id,
        "observer": "merged",
        "durations_ms": {key: None for key in _DURATION_KEYS},
    }
    for source in (backend, client):
        if not source:
            continue
        for field_name in (
            "recorded_at",
            "start_class",
            "camera_start_class",
            "model_start_class",
            "model_cache",
            "session_mode",
            "movement",
            "status",
            "failed_milestone",
            "error_code",
            "environment",
            "camera",
            "yolo_runtime",
            "yolo_provider",
        ):
            if merged.get(field_name) in (None, {}, "") and source.get(field_name) not in (
                None,
                {},
                "",
            ):
                merged[field_name] = source.get(field_name)
        durations = source.get("durations_ms") or {}
        for key in _DURATION_KEYS:
            if merged["durations_ms"][key] is None and durations.get(key) is not None:
                merged["durations_ms"][key] = durations.get(key)

    # Client samples always emit start_class=cold; only the backend observes
    # shared VideoCapture reuse.
    if backend:
        for key in (
            "start_class",
            "camera_start_class",
            "model_start_class",
            "model_cache",
        ):
            value = backend.get(key)
            if value not in (None, "", {}):
                merged[key] = value

    merged_env = dict(merged.get("environment") or {})
    client_env = (client or {}).get("environment") or {}
    backend_env = (backend or {}).get("environment") or {}
    if client_env.get("pilot_device_id"):
        merged_env["pilot_device_id"] = client_env["pilot_device_id"]
    elif backend_env.get("pilot_device_id"):
        merged_env["pilot_device_id"] = backend_env["pilot_device_id"]
    if merged_env:
        merged["environment"] = merged_env
    return merged
