"""User-triggered Bartender capture. Diagnostic/benchmark only."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Optional

BARTENDER_READY_PROMPT = """
----------------------------------------
Bartender's Grip Benchmark Capture
----------------------------------------

Position yourself for Bartender's Grip.

Make sure:
- the bottle is clearly visible
- your hand is clearly visible
- you are holding the actual Bartender's Grip
- your hand is near the intended bartender contact area
- your body/hand is already in position

Press ENTER when you are ready to begin.
Press Ctrl+C to cancel.
""".strip()

DOUBLE_HAND_READY_PROMPT = """
----------------------------------------
Double Hand Stall Benchmark Capture
----------------------------------------

Position yourself for Double Hand Stall.

Make sure:
- the bottle is clearly visible
- both hands are clearly visible
- you are holding the actual Double Hand Stall position
- there is natural small movement
- occasional partial hand overlap/occlusion is OK
- both hands stay in frame most of the time

Do not start until you are already in position.

Press ENTER when you are ready to begin.
Press Ctrl+C to cancel.
""".strip()


class CaptureCancelled(Exception):
    """User cancelled before a complete capture."""


@dataclass
class CaptureSessionResult:
    cancelled: bool
    run_benchmark: bool
    started_saving: bool
    countdown_completed: bool
    frames: list = field(default_factory=list)
    records: list = field(default_factory=list)
    camera_released: bool = False
    message: str = ""


def make_owned_camera_hooks(
    *,
    camera_factory: Callable[[], object],
    capture_frames_fn: Callable[..., tuple],
    after_open: Optional[Callable[[object], None]] = None,
) -> tuple[Callable[[], bool], Callable[..., tuple], Callable[[], None]]:
    """Bind one camera instance to open/capture/release callbacks.

    The camera is owned as soon as ``camera_factory`` returns. ``release`` is
    idempotent and is a no-op when construction never succeeded.
    """
    state: dict = {"camera": None, "released": False}

    def open_camera() -> bool:
        camera = state["camera"]
        if camera is None:
            camera = camera_factory()
            state["camera"] = camera
        opened = bool(camera.open())
        if not opened:
            return False
        if after_open is not None:
            after_open(camera)
        return True

    def capture_frames(**kwargs):
        return capture_frames_fn(camera=state["camera"], **kwargs)

    def release() -> None:
        if state["released"]:
            return
        state["released"] = True
        camera = state["camera"]
        state["camera"] = None
        if camera is None:
            return
        releaser = getattr(camera, "release", None)
        if callable(releaser):
            releaser()

    return open_camera, capture_frames, release


def wait_for_capture_ready(*, input_fn: Callable[..., str] = input) -> None:
    """Block until ENTER. No timeout."""
    input_fn()


def run_capture_countdown(
    *,
    sleep_fn: Callable[[float], None],
    print_fn: Callable[[str], None] = print,
    seconds_per_step: float = 1.0,
) -> None:
    print_fn("Starting capture in...")
    for value in ("3", "2", "1"):
        print_fn(value)
        sleep_fn(seconds_per_step)
    print_fn("CAPTURING")


def run_user_triggered_bartender_capture(
    *,
    count: int,
    timeout_s: float,
    input_fn: Callable[..., str],
    sleep_fn: Callable[[float], None],
    print_fn: Callable[..., None],
    open_camera_fn: Callable[[], bool],
    capture_frames_fn: Callable[..., tuple[list, list]],
    release_fn: Callable[[], None],
    close_detectors_fn: Optional[Callable[[], None]] = None,
    progress_every: int = 30,
    ready_prompt: Optional[str] = None,
) -> CaptureSessionResult:
    """Open camera, wait for ENTER, countdown, then save frames."""
    started_saving = False
    countdown_completed = False
    released = False

    def _release(*, close_detectors: bool = True) -> None:
        nonlocal released
        if released:
            return
        released = True
        release_fn()
        if close_detectors and close_detectors_fn is not None:
            close_detectors_fn()

    try:
        print_fn(ready_prompt or BARTENDER_READY_PROMPT)
        if not open_camera_fn():
            _release()
            return CaptureSessionResult(
                cancelled=True,
                run_benchmark=False,
                started_saving=False,
                countdown_completed=False,
                camera_released=True,
                message="Capture cancelled. Benchmark was not run.",
            )
        try:
            wait_for_capture_ready(input_fn=input_fn)
        except KeyboardInterrupt:
            _release()
            print_fn("Capture cancelled. Benchmark was not run.")
            return CaptureSessionResult(
                cancelled=True,
                run_benchmark=False,
                started_saving=False,
                countdown_completed=False,
                camera_released=True,
                message="Capture cancelled. Benchmark was not run.",
            )
        run_capture_countdown(sleep_fn=sleep_fn, print_fn=print_fn)
        countdown_completed = True
        started_saving = True
        try:
            frames, records = capture_frames_fn(
                count=count,
                timeout_s=timeout_s,
                progress_every=progress_every,
                print_fn=print_fn,
            )
        except KeyboardInterrupt:
            _release()
            print_fn("Capture cancelled. Benchmark was not run.")
            return CaptureSessionResult(
                cancelled=True,
                run_benchmark=False,
                started_saving=started_saving,
                countdown_completed=countdown_completed,
                camera_released=True,
                message="Capture cancelled. Benchmark was not run.",
            )
        print_fn("Capture complete.")
        _release(close_detectors=False)
        complete = len(frames) >= count
        return CaptureSessionResult(
            cancelled=False,
            run_benchmark=complete,
            started_saving=True,
            countdown_completed=True,
            frames=frames,
            records=records,
            camera_released=True,
            message="Capture complete." if complete else (
                "Capture incomplete. Benchmark was not run."
            ),
        )
    except Exception:
        _release()
        raise
    finally:
        if not released:
            _release()
