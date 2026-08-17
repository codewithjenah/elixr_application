"""Greedy IoU identity tracker for a single prop class.

Simplified SORT without a Kalman filter: each current detection is matched to
the previous box with the highest IoU above ``PROP_TRACK_MIN_IOU``. Unmatched
detections receive a new incrementing ``track_id``. Tracks that go unmatched
for more than ``PROP_TRACK_MAX_MISSED_FRAMES`` are dropped.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from config import PROP_TRACK_MAX_MISSED_FRAMES, PROP_TRACK_MIN_IOU
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


@dataclass
class _Track:
    track_id: int
    detection: PropDetection
    missed_frames: int = 0


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

    def update(self, detections: list[PropDetection]) -> list[PropDetection]:
        """Match ``detections`` to live tracks and return copies with ``track_id``."""
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
                track_id = self._tracks[track_index].track_id
            else:
                track_id = self._next_id
                self._next_id += 1
            stamped = replace(detection, track_id=track_id)
            tracked.append(stamped)
            next_tracks.append(
                _Track(track_id=track_id, detection=stamped, missed_frames=0)
            )

        for track_index, track in enumerate(self._tracks):
            if track_index in used_tracks:
                continue
            missed = track.missed_frames + 1
            if missed <= self._max_missed_frames:
                next_tracks.append(
                    _Track(
                        track_id=track.track_id,
                        detection=track.detection,
                        missed_frames=missed,
                    )
                )

        self._tracks = next_tracks
        return tracked
