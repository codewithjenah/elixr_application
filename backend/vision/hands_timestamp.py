"""MediaPipe VIDEO timestamp mapping for HandsDetector.

Production HandsDetector still defaults to a fake ``+= 33`` clock. Capture
timestamps come from ``CapturedFrame.captured_at_monotonic`` (monotonic
seconds). Integer milliseconds can collide when frames are closer than 1 ms
or when the same captured frame is presented twice, so every strategy must
return strictly increasing timestamps on one landmarker instance.

Reset only when the HandLandmarker is recreated. Do not reset on readiness
→ active reuse of the same detector.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Protocol


class HandsTimestampClock(Protocol):
    """Strategy used by HandsDetector VIDEO ``detect_for_video`` calls."""

    def next_ms(self, captured_at_monotonic: float | None = None) -> int:
        """Return the next strictly increasing integer-ms timestamp."""

    def reset(self) -> None:
        """Clear clock state after landmarker close/recreation."""


def relative_captured_at(
    captured_at_monotonic: float,
    origin_monotonic: float,
) -> float:
    """Replay-portable seconds relative to the first captured frame."""
    return captured_at_monotonic - origin_monotonic


def relative_time_ms(
    captured_at_monotonic: float,
    origin_monotonic: float,
) -> int:
    elapsed_ms = (captured_at_monotonic - origin_monotonic) * 1000.0
    if elapsed_ms != elapsed_ms:  # NaN
        return 0
    return max(0, int(round(elapsed_ms)))


@dataclass
class Synthetic33TimestampClock:
    """Current production VIDEO clock: previous timestamp + 33 ms per call."""

    last_timestamp_ms: int = 0

    def next_ms(self, captured_at_monotonic: float | None = None) -> int:
        del captured_at_monotonic
        self.last_timestamp_ms += 33
        return self.last_timestamp_ms

    def reset(self) -> None:
        self.last_timestamp_ms = 0


@dataclass
class CaptureMonotonicTimestampClock:
    """Integer-ms clock from ``time.monotonic()`` capture seconds.

    ``candidate_ms = round(captured_at_monotonic * 1000)``. Collisions and
    backward jumps become ``last_timestamp_ms + 1``. Does not use wall clock
    ``time.time()`` and does not use ``sequence * 33``.
    """

    last_timestamp_ms: int | None = None

    def next_ms(self, captured_at_monotonic: float | None = None) -> int:
        if (
            captured_at_monotonic is None
            or captured_at_monotonic != captured_at_monotonic
        ):
            candidate = (
                0 if self.last_timestamp_ms is None else self.last_timestamp_ms + 1
            )
        else:
            candidate = int(round(captured_at_monotonic * 1000.0))
        if self.last_timestamp_ms is not None and candidate <= self.last_timestamp_ms:
            candidate = self.last_timestamp_ms + 1
        self.last_timestamp_ms = candidate
        return candidate

    def reset(self) -> None:
        self.last_timestamp_ms = None


@dataclass
class VideoTimestampClock:
    """Origin-relative monotonic integer-ms clock for portable replay.

    MediaPipe requires timestamps that strictly increase between adjacent VIDEO
    calls on the same landmarker instance. Capture time is ``time.monotonic()``
    seconds; this helper stores elapsed ms from the first sample.
    """

    origin_monotonic: float | None = None
    last_timestamp_ms: int | None = None

    def next_ms(self, captured_at_monotonic: float) -> int:
        if self.origin_monotonic is None:
            self.origin_monotonic = captured_at_monotonic
        elapsed_ms = (captured_at_monotonic - self.origin_monotonic) * 1000.0
        if elapsed_ms != elapsed_ms:  # NaN
            candidate = 0 if self.last_timestamp_ms is None else self.last_timestamp_ms + 1
        elif elapsed_ms < 0:
            candidate = 0 if self.last_timestamp_ms is None else self.last_timestamp_ms + 1
        else:
            candidate = int(round(elapsed_ms))
        if self.last_timestamp_ms is None:
            candidate = max(0, candidate)
        elif candidate <= self.last_timestamp_ms:
            candidate = self.last_timestamp_ms + 1
        self.last_timestamp_ms = candidate
        return candidate

    def reset(self) -> None:
        """Use after landmarker close/recreation. Do not reset on activate reuse."""
        self.origin_monotonic = None
        self.last_timestamp_ms = None


def default_timestamp_clock(
    timestamp_clock: Optional[HandsTimestampClock] = None,
) -> HandsTimestampClock:
    if timestamp_clock is None:
        return Synthetic33TimestampClock()
    return timestamp_clock
