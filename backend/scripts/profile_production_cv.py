"""Profile production VisionSession CV cost. Diagnostic only.

Uses the real camera, ONNX YOLO path, movement-scoped Hands/Pose, and
current fallback rules. Does not change detector settings.

Run from backend/:

    python scripts/profile_production_cv.py --list
    python scripts/profile_production_cv.py --movement "Normal Grip" --duration 30
    python scripts/profile_production_cv.py --movement "Shoulder Stall" --warmup 8 --duration 30
"""

from __future__ import annotations

import argparse
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from api.websocket import VisionSession
from assessment.hands_profile import hands_profile_for
from config import MOVEMENT_CONFIG, TARGET_FPS
from vision.camera import snapshot_capture_producer_telemetry
from vision.production_cv_profile import (
    OPTIONAL_NO_FALLBACK_MOVEMENT,
    REPRESENTATIVE_MOVEMENTS,
    begin_measurement,
    collect_session_snapshot,
    format_comparison_table,
    format_snapshot_report,
)

_POSE_CUES = {
    "Normal Grip": (
        "Hold a normal bottle grip at practice distance. Keep the bottle and "
        "the gripping hand visible. Move naturally; do not force fallback."
    ),
    "Bartender's Grip": (
        "Hold Bartender's Grip with the bottle and hand visible. Use a normal "
        "hold; do not occlude or hide the hand to force ROI fallback."
    ),
    "Claw Grip": (
        "Hold Claw Grip with the bottle and hand visible. Move naturally; do "
        "not rotate or hide the hand to force fallback every frame."
    ),
    "Double Hand Stall": (
        "Keep the bottle and both hands visible at practice distance. Stall "
        "or hold as you would in a normal Double Hand Stall session."
    ),
    "Shoulder Stall": (
        "Keep the bottle visible and your upper body in frame (both shoulders "
        "and at least one full arm). Hands detection stays disabled."
    ),
    "Reverse Grip": (
        "Optional no-fallback path: reverse bottle grip, bottle and one hand "
        "visible. No rotated/ROI fallback is configured for this movement."
    ),
}


def _print_list() -> None:
    print("Representative production detector paths:")
    for name, desc in REPRESENTATIVE_MOVEMENTS:
        print(f"  - {name}: {desc}")
    print(
        f"  - {OPTIONAL_NO_FALLBACK_MOVEMENT} (optional): "
        "YOLO + Hands max=1, no fallback "
        "(Normal Grip already includes rotated fallback)"
    )


def _run_loops(
    session: VisionSession,
    *,
    duration_s: float,
    stop: threading.Event,
    counters: dict[str, int],
) -> None:
    interval = 1.0 / TARGET_FPS if TARGET_FPS > 0 else 0.05
    last_preview_seq: int | None = None

    def preview_loop() -> None:
        nonlocal last_preview_seq
        while not stop.is_set():
            tick = time.perf_counter()
            message = session.render_preview()
            if message is not None:
                counters["preview"] += 1
                seq = int(getattr(message, "capture_sequence", 0) or 0)
                if last_preview_seq is not None and seq > last_preview_seq + 1:
                    counters["preview_drops"] += seq - last_preview_seq - 1
                if seq:
                    last_preview_seq = seq
            remaining = interval - (time.perf_counter() - tick)
            if remaining > 0:
                time.sleep(remaining)

    def ai_loop() -> None:
        while not stop.is_set():
            if session.lifecycle != "active":
                time.sleep(0.02)
                continue
            message = session.analyze_tick()
            if message is None:
                time.sleep(0)
                continue
            counters["ai"] += 1
            if getattr(message, "error_code", None) == "model_load_failed":
                counters["model_load_failed"] += 1
                stop.set()
                return
            time.sleep(0)

    preview_thread = threading.Thread(target=preview_loop, name="cv-profile-preview")
    ai_thread = threading.Thread(target=ai_loop, name="cv-profile-ai")
    preview_thread.start()
    ai_thread.start()
    deadline = time.perf_counter() + duration_s
    while time.perf_counter() < deadline and not stop.is_set():
        time.sleep(0.05)
    stop.set()
    preview_thread.join(timeout=2.0)
    ai_thread.join(timeout=2.0)


def run_profile(
    *,
    movement: str,
    duration_s: float,
    warmup_s: float,
    prompt: bool,
) -> int:
    if movement not in MOVEMENT_CONFIG:
        print(f"Unknown movement: {movement}", file=sys.stderr)
        return 2
    profile = hands_profile_for(movement)
    cue = _POSE_CUES.get(
        movement,
        "Use a normal practice pose for this movement. Keep required "
        "landmarks and the bottle visible. Do not force adversarial misses.",
    )
    print("ELIXR production CV profiler (diagnosis only)")
    print(f"Movement: {movement}")
    print(
        f"requires_hands={profile.active_scheduled_hands} "
        f"requires_pose={profile.active_needs_pose} "
        f"hands_max={profile.semantic_max_hands} "
        f"rotated_fallback={profile.rotated_fallback} "
        f"bartender_roi={profile.bartender_roi_fallback}"
    )
    print(f"Warmup: {warmup_s:.0f}s  Measure: {duration_s:.0f}s")
    print()
    print(cue)
    print()
    if prompt:
        try:
            input("Press ENTER when you are in position (Ctrl+C to cancel)... ")
        except EOFError:
            print("No TTY; continuing without prompt.")

    session = VisionSession(movement)
    if not session.start():
        print("ERROR: Camera unavailable.", file=sys.stderr)
        return 1
    ok, error = session.activate()
    if not ok:
        print(f"ERROR: activate failed ({error})", file=sys.stderr)
        session.close()
        return 1

    stop = threading.Event()
    try:
        print(f"Warmup {warmup_s:.0f}s (model/MediaPipe/ONNX first-call cost)...")
        warmup_counters = {"preview": 0, "ai": 0, "preview_drops": 0, "model_load_failed": 0}
        _run_loops(session, duration_s=warmup_s, stop=stop, counters=warmup_counters)
        if warmup_counters["model_load_failed"]:
            print("ERROR: model_load_failed during warmup.", file=sys.stderr)
            return 1

        stop = threading.Event()
        begin_measurement(session)
        snapshot_capture_producer_telemetry(reset=True)
        print(f"Measuring {duration_s:.0f}s. Stay in a normal practice pose...")
        measure_counters = {
            "preview": 0,
            "ai": 0,
            "preview_drops": 0,
            "model_load_failed": 0,
        }
        started = time.perf_counter()
        _run_loops(
            session,
            duration_s=duration_s,
            stop=stop,
            counters=measure_counters,
        )
        elapsed = time.perf_counter() - started
        if measure_counters["model_load_failed"]:
            print("ERROR: model_load_failed during measurement.", file=sys.stderr)
            return 1
        capture = snapshot_capture_producer_telemetry(reset=False)
        snap = collect_session_snapshot(
            session,
            elapsed_s=elapsed,
            preview_frames=measure_counters["preview"],
            ai_frames=measure_counters["ai"],
            warmup_s=warmup_s,
            measured_s=elapsed,
            preview_drops=measure_counters["preview_drops"],
            capture=capture,
        )
        print()
        print(format_snapshot_report(snap))
        print()
        print(format_comparison_table([snap]))
        print()
        print(
            "Paste this report back for bottleneck ranking. "
            "Do not change CV settings until all representative movements "
            "have been measured."
        )
        return 0
    finally:
        stop.set()
        session.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Profile production VisionSession CV cost (diagnosis only).",
    )
    parser.add_argument("--movement", help="Catalog movement name")
    parser.add_argument(
        "--duration",
        type=float,
        default=30.0,
        help="Steady-state measurement seconds (default 30)",
    )
    parser.add_argument(
        "--warmup",
        type=float,
        default=8.0,
        help="Unmeasured warmup seconds after activate (default 8)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List representative movements and detector paths",
    )
    parser.add_argument(
        "--no-prompt",
        action="store_true",
        help="Skip the in-position ENTER prompt",
    )
    args = parser.parse_args(argv)
    if args.list:
        _print_list()
        return 0
    if not args.movement:
        parser.error("--movement is required unless --list is set")
    if args.duration <= 0 or args.warmup < 0:
        parser.error("--duration must be > 0 and --warmup must be >= 0")
    return run_profile(
        movement=args.movement,
        duration_s=args.duration,
        warmup_s=args.warmup,
        prompt=not args.no_prompt,
    )


if __name__ == "__main__":
    raise SystemExit(main())
