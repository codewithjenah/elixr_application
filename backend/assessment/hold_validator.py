"""Temporal hold confirmation for active practice sessions."""

from __future__ import annotations

from dataclasses import dataclass

from config import (
    HOLD_CONFIRMATION_SECONDS,
    HOLD_MAX_FRAME_GAP_SECONDS,
    HOLD_MIN_POSITIVE_RATIO,
)


@dataclass(frozen=True)
class HoldSnapshot:
    hold_progress: float = 0.0
    hold_duration_ms: int = 0
    hold_confirmed: bool = False
    positive_frame_ratio: float = 0.0


class HoldValidator:
    """Accumulates continuous positive/stable hold time during active sessions."""

    def __init__(
        self,
        *,
        confirmation_seconds: float = HOLD_CONFIRMATION_SECONDS,
        max_frame_gap_seconds: float = HOLD_MAX_FRAME_GAP_SECONDS,
        min_positive_ratio: float = HOLD_MIN_POSITIVE_RATIO,
    ) -> None:
        self._confirmation_seconds = confirmation_seconds
        self._max_frame_gap_seconds = max_frame_gap_seconds
        self._min_positive_ratio = min_positive_ratio
        self._activated = False
        self._confirmed = False
        self._accumulated_seconds = 0.0
        self._last_timestamp: float | None = None
        self._segment_positive_frames = 0
        self._segment_total_frames = 0

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
        self._segment_positive_frames = 0
        self._segment_total_frames = 0

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
            return HoldSnapshot()

        if self._confirmed:
            return self._confirmed_snapshot()

        if (
            self._last_timestamp is not None
            and timestamp - self._last_timestamp > self._max_frame_gap_seconds
        ):
            self._reset_segment()
            self._last_timestamp = None

        is_valid = feedback_type == "positive" and posture_status == "stable"
        if not is_valid:
            self._reset_segment()
            self._last_timestamp = None
            return self._build_snapshot()

        self._segment_total_frames += 1
        self._segment_positive_frames += 1
        if self._last_timestamp is not None:
            delta = timestamp - self._last_timestamp
            if delta > 0:
                self._accumulated_seconds += min(
                    delta,
                    self._max_frame_gap_seconds,
                )

        self._last_timestamp = timestamp

        ratio = self._positive_frame_ratio()
        if (
            self._accumulated_seconds >= self._confirmation_seconds
            and ratio >= self._min_positive_ratio
        ):
            self._confirmed = True

        return self._build_snapshot()

    def _reset_segment(self) -> None:
        self._accumulated_seconds = 0.0
        self._segment_positive_frames = 0
        self._segment_total_frames = 0

    def _positive_frame_ratio(self) -> float:
        if self._segment_total_frames == 0:
            return 0.0
        return self._segment_positive_frames / self._segment_total_frames

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
        )
