"""Designed MediaPipe VIDEO timestamp mapping. Not wired into HandsDetector.

Production HandsDetector still uses a fake ``+= 33`` clock. This helper is the
safe conversion from ``CapturedFrame.captured_at_monotonic`` so a later change
can feed actual analyzed-frame timing without timestamp collisions.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class VideoTimestampClock:
    """Monotonic integer-ms clock for MediaPipe ``detect_for_video``.

    MediaPipe requires timestamps that strictly increase between adjacent VIDEO
    calls on the same landmarker instance. Capture time is ``time.monotonic()``
    seconds; integer milliseconds can collide when frames are closer than 1 ms
    or when the same captured frame is presented twice.
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
