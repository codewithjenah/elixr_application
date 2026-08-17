"""Greedy IoU identity tracker for a single prop class.

Simplified SORT without a Kalman filter: each current detection is matched to
the previous box with the highest IoU above ``PROP_TRACK_MIN_IOU``. Unmatched
detections receive a new incrementing ``track_id``. Unmatched previous tracks
are kept only when this tick's detection count is less than the previous
live-track count (true miss or occlusion). When YOLO returns as many or more
boxes, unmatched tracks are retired immediately so an identity jump cannot
leave a ghost box. Tracks that stay unmatched for more than
``PROP_TRACK_MAX_MISSED_FRAMES`` are also dropped. ``update()`` returns only
detections present in the current input; ``live_detections()`` also includes
still-alive unmatched tracks coasted by last-known velocity.

Each track also keeps the last two YOLO-confirmed ``(timestamp, bbox)``
observations so skipped frames can coast the box by last-known velocity
instead of freezing it in place.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, replace

from config import (
    PROP_TRACK_MAX_MISSED_FRAMES,
    PROP_TRACK_MIN_IOU,
    TARGET_FPS,
    YOLO_FRAME_SKIP,
)
from vision.types import PropDetection


def box_iou(a: PropDetection, b: PropDetection) -> float:
    """Intersection-over-union of two axis-aligned boxes."""
    inter_x1 = max(a.x1, b.x1)
    inter_y1 = max(a.y1, b.y1)
    inter_x2 = min(a.x2, b.x2)
    inter_y2 = min(a.y2, b.y2)
    inter_w = max(0, inter_x2 - inter_x1)
    inter_h = max(0, inter_y2 - inter_y1)
    inter = inter_w * inter_h
    if inter == 0:
        return 0.0

    area_a = max(0, a.x2 - a.x1) * max(0, a.y2 - a.y1)
    area_b = max(0, b.x2 - b.x1) * max(0, b.y2 - b.y1)
    union = area_a + area_b - inter
    if union <= 0:
        return 0.0
    return inter / union


def max_extrapolation_lead_s() -> float:
    """Upper bound on coasting time: 2x ``YOLO_FRAME_SKIP`` frame-times."""
    return 2.0 * YOLO_FRAME_SKIP / TARGET_FPS


@dataclass(frozen=True)
class _Observation:
    timestamp: float
    detection: PropDetection


@dataclass
class _Track:
    track_id: int
    detection: PropDetection
    missed_frames: int = 0
    observations: tuple[_Observation, ...] = ()
    just_created: bool = False


class PropTracker:
    """Assign stable ``track_id`` values to detections of one object class."""

    def __init__(
        self,
        *,
        min_iou: float = PROP_TRACK_MIN_IOU,
        max_missed_frames: int = PROP_TRACK_MAX_MISSED_FRAMES,
    ) -> None:
        self._min_iou = min_iou
        self._max_missed_frames = max_missed_frames
        self._next_id = 1
        self._tracks: list[_Track] = []

    def reset(self) -> None:
        self._next_id = 1
        self._tracks = []

    def update(
        self,
        detections: list[PropDetection],
        timestamp: float | None = None,
    ) -> list[PropDetection]:
        """Match ``detections`` to live tracks and return copies with ``track_id``.

        ``timestamp`` is the YOLO-confirmation time (``time.monotonic()`` when
        omitted) stored for skipped-frame velocity extrapolation.
        """
        now = time.monotonic() if timestamp is None else timestamp
        previous_n = len(self._tracks)
        yolo_n = len(detections)
        pairs: list[tuple[float, int, int]] = []
        for track_index, track in enumerate(self._tracks):
            for det_index, detection in enumerate(detections):
                iou = box_iou(track.detection, detection)
                if iou >= self._min_iou:
                    pairs.append((iou, track_index, det_index))

        pairs.sort(key=lambda item: (-item[0], item[1], item[2]))
        used_tracks: set[int] = set()
        used_detections: set[int] = set()
        det_to_track_index: dict[int, int] = {}
        for _, track_index, det_index in pairs:
            if track_index in used_tracks or det_index in used_detections:
                continue
            used_tracks.add(track_index)
            used_detections.add(det_index)
            det_to_track_index[det_index] = track_index

        next_tracks: list[_Track] = []
        tracked: list[PropDetection] = []
        for det_index, detection in enumerate(detections):
            track_index = det_to_track_index.get(det_index)
            if track_index is not None:
                previous = self._tracks[track_index]
                track_id = previous.track_id
                just_created = False
                stamped = replace(
                    detection, track_id=track_id, yolo_confirmed=True
                )
                observations = (
                    previous.observations + (_Observation(now, stamped),)
                )[-2:]
            else:
                track_id = self._next_id
                self._next_id += 1
                just_created = True
                stamped = replace(
                    detection, track_id=track_id, yolo_confirmed=True
                )
                observations = (_Observation(now, stamped),)
            tracked.append(stamped)
            next_tracks.append(
                _Track(
                    track_id=track_id,
                    detection=stamped,
                    missed_frames=0,
                    observations=observations,
                    just_created=just_created,
                )
            )

        # Identity jump: YOLO returned as many or more boxes than last time, so
        # previous objects were matched or replaced. Keep unmatched tracks only
        # on a true miss (fewer boxes), and never grow past max(yolo_n, previous_n).
        if yolo_n < previous_n:
            unmatched_budget = previous_n - yolo_n
            for track_index, track in enumerate(self._tracks):
                if unmatched_budget <= 0:
                    break
                if track_index in used_tracks:
                    continue
                missed = track.missed_frames + 1
                if missed > self._max_missed_frames:
                    continue
                next_tracks.append(
                    _Track(
                        track_id=track.track_id,
                        detection=track.detection,
                        missed_frames=missed,
                        observations=track.observations,
                        just_created=False,
                    )
                )
                unmatched_budget -= 1

        self._tracks = next_tracks
        return tracked

    def live_detections(self, now: float) -> list[PropDetection]:
        """Return this-tick YOLO matches plus still-alive unmatched tracks.

        Matched or newly created tracks have ``yolo_confirmed=True``. Tracks
        that were not matched this frame but remain within
        ``max_missed_frames`` are included with ``yolo_confirmed=False`` and
        coasted by last-known velocity, only when this tick had fewer YOLO
        boxes than the previous live-track count. Call after ``update()``.
        """
        lead_cap = max_extrapolation_lead_s()
        live: list[PropDetection] = []
        for track in self._tracks:
            if track.missed_frames == 0:
                live.append(replace(track.detection, yolo_confirmed=True))
                continue
            unmatched = replace(track.detection, yolo_confirmed=False)
            live.append(self._coast_detection(unmatched, track, now, lead_cap))
        return live

    def extrapolate(
        self,
        detections: list[PropDetection],
        now: float,
        *,
        max_lead_s: float | None = None,
    ) -> list[PropDetection]:
        """Coast each tracked box by last-known velocity up to ``now``.

        Returns the cached ``detections`` unchanged when a track has fewer than
        two YOLO-confirmed observations, was just created, or has no usable
        velocity. Lead time is clamped to ``2 * YOLO_FRAME_SKIP`` frame-times
        so a stalled detector cannot run away.
        """
        lead_cap = max_extrapolation_lead_s() if max_lead_s is None else max_lead_s
        tracks = {track.track_id: track for track in self._tracks}
        predicted: list[PropDetection] = []
        for detection in detections:
            track = tracks.get(detection.track_id) if detection.track_id is not None else None
            predicted.append(self._coast_detection(detection, track, now, lead_cap))
        return predicted

    def _coast_detection(
        self,
        detection: PropDetection,
        track: _Track | None,
        now: float,
        lead_cap: float,
    ) -> PropDetection:
        if track is None or track.just_created or len(track.observations) < 2:
            return detection

        previous, latest = track.observations[-2], track.observations[-1]
        sample_dt = latest.timestamp - previous.timestamp
        if sample_dt <= 0:
            return detection

        prev_center = previous.detection.center
        last_center = latest.detection.center
        vx = (last_center.x - prev_center.x) / sample_dt
        vy = (last_center.y - prev_center.y) / sample_dt
        elapsed = max(0.0, now - latest.timestamp)
        lead = min(elapsed, lead_cap)
        if lead <= 0:
            return detection
        # Predict from the last YOLO-confirmed box so an already-coasted
        # input (grace-period live_detections stored in the skip-frame cache)
        # is not translated a second time.
        base = latest.detection
        return replace(
            detection,
            x1=int(round(base.x1 + vx * lead)),
            y1=int(round(base.y1 + vy * lead)),
            x2=int(round(base.x2 + vx * lead)),
            y2=int(round(base.y2 + vy * lead)),
        )
