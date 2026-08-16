"""Temporal hold confirmation for active practice sessions."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

from config import (
    HOLD_CONFIRMATION_SECONDS,
    HOLD_MAX_FRAME_GAP_SECONDS,
    HOLD_MIN_POSITIVE_RATIO,
    HOLD_UNKNOWN_GRACE_SECONDS,
)


@dataclass(frozen=True)
class HoldSnapshot:
    hold_progress: float = 0.0
    hold_duration_ms: int = 0
    hold_confirmed: bool = False
    positive_frame_ratio: float = 0.0
    # Backend-authoritative confirmation target (ms). 0 when inactive.
    hold_target_ms: int = 0


class HoldValidator:
    """Accumulates hold time during active sessions with ratio tolerance.

    Isolated non-positive/non-stable frames pause accumulation and count
    against ``HOLD_MIN_POSITIVE_RATIO`` over a rolling window. A sustained
    invalid stretch longer than the dropout budget resets the attempt.

    ``unknown`` posture is a third path: pause immediately with no credit and
    no negative sample, then reset the hold segment only after
    ``HOLD_UNKNOWN_GRACE_SECONDS``. Resetting the segment is not a technique
    fail.
    """

    def __init__(
        self,
        *,
        confirmation_seconds: float = HOLD_CONFIRMATION_SECONDS,
        max_frame_gap_seconds: float = HOLD_MAX_FRAME_GAP_SECONDS,
        min_positive_ratio: float = HOLD_MIN_POSITIVE_RATIO,
        unknown_grace_seconds: float = HOLD_UNKNOWN_GRACE_SECONDS,
    ) -> None:
        self._confirmation_seconds = confirmation_seconds
        self._max_frame_gap_seconds = max_frame_gap_seconds
        self._min_positive_ratio = min_positive_ratio
        self._unknown_grace_seconds = unknown_grace_seconds
        self._activated = False
        self._confirmed = False
        self._accumulated_seconds = 0.0
        self._last_timestamp: float | None = None
        self._last_was_valid = False
        self._consecutive_invalid_seconds = 0.0
        self._consecutive_unknown_seconds = 0.0
        self._samples: deque[tuple[float, bool]] = deque()

    @property
    def is_confirmed(self) -> bool:
        return self._confirmed

    def activate(self) -> None:
        """Begin a fresh hold attempt for a newly activated session."""
        self.reset()
        self._activated = True

    def reset(self) -> None:
        self._confirmed = False
        self._accumulated_seconds = 0.0
        self._last_timestamp = None
        self._last_was_valid = False
        self._consecutive_invalid_seconds = 0.0
        self._consecutive_unknown_seconds = 0.0
        self._samples.clear()

    def update(
        self,
        *,
        feedback_type: str,
        posture_status: str,
        session_active: bool,
        timestamp: float,
    ) -> HoldSnapshot:
        """Update hold state for one evaluated active frame."""
        if not session_active or not self._activated:
            return HoldSnapshot()  # hold_target_ms remains 0 when inactive

        if self._confirmed:
            return self._confirmed_snapshot()

        if (
            self._last_timestamp is not None
            and timestamp - self._last_timestamp > self._max_frame_gap_seconds
        ):
            self._reset_segment()
            self._last_timestamp = None
            self._last_was_valid = False

        is_valid = feedback_type == "positive" and posture_status == "stable"
        is_unknown = posture_status == "unknown"
        if is_unknown:
            if self._last_timestamp is not None:
                delta = timestamp - self._last_timestamp
                if delta > 0:
                    self._consecutive_unknown_seconds += min(
                        delta,
                        self._max_frame_gap_seconds,
                    )
            self._consecutive_invalid_seconds = 0.0
            self._last_timestamp = timestamp
            self._last_was_valid = False
            if self._consecutive_unknown_seconds > self._unknown_grace_seconds:
                self._reset_segment()
                self._last_timestamp = None
            return self._build_snapshot()

        if not is_valid:
            self._consecutive_unknown_seconds = 0.0
            if self._last_timestamp is not None:
                delta = timestamp - self._last_timestamp
                if delta > 0:
                    self._consecutive_invalid_seconds += min(
                        delta,
                        self._max_frame_gap_seconds,
                    )
            self._last_timestamp = timestamp
            self._last_was_valid = False
            if self._consecutive_invalid_seconds > self._dropout_budget_seconds():
                self._reset_segment()
                self._last_timestamp = None
                return self._build_snapshot()
            self._record_sample(timestamp, False)
            return self._build_snapshot()

        self._consecutive_invalid_seconds = 0.0
        self._consecutive_unknown_seconds = 0.0
        self._record_sample(timestamp, True)
        if self._last_timestamp is not None and self._last_was_valid:
            delta = timestamp - self._last_timestamp
            if delta > 0:
                self._accumulated_seconds += min(
                    delta,
                    self._max_frame_gap_seconds,
                )

        self._last_timestamp = timestamp
        self._last_was_valid = True

        ratio = self._positive_frame_ratio()
        if (
            self._accumulated_seconds >= self._confirmation_seconds
            and ratio >= self._min_positive_ratio
        ):
            self._confirmed = True

        return self._build_snapshot()

    def _dropout_budget_seconds(self) -> float:
        return (1.0 - self._min_positive_ratio) * self._confirmation_seconds

    def _record_sample(self, timestamp: float, is_valid: bool) -> None:
        self._samples.append((timestamp, is_valid))
        cutoff = timestamp - self._confirmation_seconds
        while self._samples and self._samples[0][0] < cutoff:
            self._samples.popleft()

    def _reset_segment(self) -> None:
        self._accumulated_seconds = 0.0
        self._consecutive_invalid_seconds = 0.0
        self._consecutive_unknown_seconds = 0.0
        self._last_was_valid = False
        self._samples.clear()

    def _positive_frame_ratio(self) -> float:
        if not self._samples:
            return 0.0
        positive = sum(1 for _, is_valid in self._samples if is_valid)
        return positive / len(self._samples)

    def _hold_target_ms(self) -> int:
        return int(round(self._confirmation_seconds * 1000))

    def _build_snapshot(self) -> HoldSnapshot:
        duration_ms = int(round(self._accumulated_seconds * 1000))
        if self._confirmed:
            progress = 1.0
        elif self._confirmation_seconds <= 0:
            progress = 0.0
        else:
            progress = min(
                1.0,
                self._accumulated_seconds / self._confirmation_seconds,
            )

        return HoldSnapshot(
            hold_progress=progress,
            hold_duration_ms=duration_ms,
            hold_confirmed=self._confirmed,
            positive_frame_ratio=self._positive_frame_ratio(),
            hold_target_ms=self._hold_target_ms(),
        )

    def _confirmed_snapshot(self) -> HoldSnapshot:
        duration_ms = int(round(self._confirmation_seconds * 1000))
        return HoldSnapshot(
            hold_progress=1.0,
            hold_duration_ms=max(
                duration_ms,
                int(round(self._accumulated_seconds * 1000)),
            ),
            hold_confirmed=True,
            positive_frame_ratio=self._positive_frame_ratio(),
            hold_target_ms=self._hold_target_ms(),
        )
