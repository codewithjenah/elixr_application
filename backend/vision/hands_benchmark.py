"""Reusable Hands benchmark helpers. No production detector defaults change here."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional

import numpy as np

from vision.hands_timestamp import relative_captured_at, relative_time_ms
from vision.types import BottleDetection, HandsResult, Point2D


@dataclass(frozen=True)
class TimedCaptureFrame:
    """One replay frame with the original capture timeline."""

    filename: str
    sequence: int
    captured_at_monotonic: float
    relative_time_ms: int
    movement_label: str = ""
    scene_tag: str = ""
    bottle: Optional[dict[str, float]] = None


def production_hands_defaults() -> dict[str, object]:
    """Inspect HandsDetector constructor defaults. Does not instantiate models."""
    import inspect

    from vision.hands_detector import HandsDetector

    signature = inspect.signature(HandsDetector.__init__)
    return {
        "max_num_hands": signature.parameters["max_num_hands"].default,
        "rotated_fallback": signature.parameters["rotated_fallback"].default,
        "bartender_roi_fallback": signature.parameters["bartender_roi_fallback"].default,
        "timestamp_clock": signature.parameters["timestamp_clock"].default,
    }


def fallback_ab_replay(
    frames: list[np.ndarray],
    *,
    bottles: list[Optional[BottleDetection]],
    captured_at: list[Optional[float]],
    max_num_hands: int,
    rotated_fallback: bool,
    bartender_roi_fallback: bool,
) -> dict:
    """Same-frame A/B payload. Only fallback enable/disable differs for pass B."""
    kwargs_a = {
        "max_num_hands": max_num_hands,
        "rotated_fallback": rotated_fallback,
        "bartender_roi_fallback": bartender_roi_fallback,
    }
    kwargs_b = {
        "max_num_hands": max_num_hands,
        "rotated_fallback": False,
        "bartender_roi_fallback": False,
    }
    return {
        "frames_a": frames,
        "frames_b": frames,
        "bottles_a": bottles,
        "bottles_b": bottles,
        "captured_at_a": captured_at,
        "captured_at_b": captured_at,
        "kwargs_a": kwargs_a,
        "kwargs_b": kwargs_b,
    }


def freeze_bottle(bottle: Optional[BottleDetection]) -> Optional[BottleDetection]:
    if bottle is None:
        return None
    return BottleDetection(
        x1=bottle.x1,
        y1=bottle.y1,
        x2=bottle.x2,
        y2=bottle.y2,
        confidence=bottle.confidence,
        track_id=bottle.track_id,
        yolo_confirmed=bottle.yolo_confirmed,
    )


def freeze_bottles(
    bottles: list[Optional[BottleDetection]],
) -> list[Optional[BottleDetection]]:
    return [freeze_bottle(bottle) for bottle in bottles]


def bottle_to_manifest(bottle: Optional[BottleDetection]) -> Optional[dict[str, float]]:
    if bottle is None:
        return None
    return {
        "x1": float(bottle.x1),
        "y1": float(bottle.y1),
        "x2": float(bottle.x2),
        "y2": float(bottle.y2),
        "confidence": float(bottle.confidence),
        "track_id": -1.0 if bottle.track_id is None else float(bottle.track_id),
        "yolo_confirmed": 1.0 if bottle.yolo_confirmed else 0.0,
    }


def bottle_from_manifest(raw: Optional[dict]) -> Optional[BottleDetection]:
    if not raw:
        return None
    track_raw = raw.get("track_id", -1)
    track_id = None if track_raw is None or float(track_raw) < 0 else int(track_raw)
    return BottleDetection(
        x1=int(raw["x1"]),
        y1=int(raw["y1"]),
        x2=int(raw["x2"]),
        y2=int(raw["y2"]),
        confidence=float(raw.get("confidence", 0.0)),
        track_id=track_id,
        yolo_confirmed=bool(raw.get("yolo_confirmed", True)),
    )


def recovered_frames_due_to_fallback(
    usable_with_fallback: list[bool],
    usable_without_fallback: list[bool],
) -> int:
    if len(usable_with_fallback) != len(usable_without_fallback):
        return 0
    return sum(
        1
        for with_fb, without_fb in zip(
            usable_with_fallback,
            usable_without_fallback,
        )
        if with_fb and not without_fb
    )


def usable_detection_rate(usable: list[bool]) -> dict[str, float]:
    if not usable:
        return {"usable_rate": 0.0, "no_hand_rate": 0.0}
    hits = sum(1 for item in usable if item)
    n = len(usable)
    return {
        "usable_rate": hits / n,
        "no_hand_rate": (n - hits) / n,
    }


def result_signature(result: Optional[HandsResult]) -> tuple[int, int]:
    """(hand_count, landmark_point_count) for agreement checks."""
    if result is None or not result.hands:
        return (0, 0)
    landmark_count = 0
    for hand in result.hands:
        landmark_count += sum(1 for point in hand.points.values() if point is not None)
    return (len(result.hands), landmark_count)


def landmark_availability(result: Optional[HandsResult]) -> bool:
    count, landmarks = result_signature(result)
    return count > 0 and landmarks > 0


def classify_scene(
    result: Optional[HandsResult],
    bottle: Optional[BottleDetection] = None,
    *,
    frame_width: int = 640,
    frame_height: int = 480,
) -> str:
    """Coarse scene bucket for reporting. Occlusion is bbox overlap, not CV truth."""
    n_hands, _ = result_signature(result)
    if n_hands <= 0:
        return "no_hand"
    occluded = False
    if bottle is not None and result is not None:
        for hand in result.hands:
            palm = hand.palm_center()
            if palm is None:
                continue
            px = palm.x * frame_width
            py = palm.y * frame_height
            if bottle.x1 <= px <= bottle.x2 and bottle.y1 <= py <= bottle.y2:
                occluded = True
                break
    if n_hands >= 2:
        return "two_hands"
    if occluded:
        return "hand_occluded_by_bottle"
    if bottle is not None:
        return "one_hand_and_bottle"
    return "one_hand"


def agreement_rates(
    signatures_a: list[tuple[int, int]],
    signatures_b: list[tuple[int, int]],
) -> dict[str, float]:
    if not signatures_a or len(signatures_a) != len(signatures_b):
        return {
            "frames": 0.0,
            "detection_count_agree": 0.0,
            "landmark_availability_agree": 0.0,
        }
    count_agree = 0
    landmark_agree = 0
    for left, right in zip(signatures_a, signatures_b):
        if left[0] == right[0]:
            count_agree += 1
        left_avail = left[0] > 0 and left[1] > 0
        right_avail = right[0] > 0 and right[1] > 0
        if left_avail == right_avail:
            landmark_agree += 1
    n = len(signatures_a)
    return {
        "frames": float(n),
        "detection_count_agree": count_agree / n,
        "landmark_availability_agree": landmark_agree / n,
    }


def load_image_frames(directory: Path) -> list[np.ndarray]:
    import cv2

    if not directory.is_dir():
        raise FileNotFoundError(f"Image directory not found: {directory}")
    paths = sorted(
        [
            path
            for path in directory.iterdir()
            if path.suffix.lower() in {".jpg", ".jpeg", ".png"}
        ]
    )
    frames: list[np.ndarray] = []
    for path in paths:
        frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if frame is None:
            raise FileNotFoundError(f"Failed to read image: {path}")
        frames.append(frame)
    if not frames:
        raise FileNotFoundError(f"No JPEG/PNG frames in {directory}")
    return frames


def synthetic_scene_frames(
    *,
    height: int = 480,
    width: int = 640,
) -> dict[str, np.ndarray]:
    """Deterministic stand-ins. They are not real hands; used when camera is absent."""
    rng = np.random.default_rng(20260818)
    no_hand = np.zeros((height, width, 3), dtype=np.uint8)
    clutter = rng.integers(0, 40, size=(height, width, 3), dtype=np.uint8)
    one_blob = np.full((height, width, 3), 18, dtype=np.uint8)
    one_blob[180:320, 240:360] = (40, 70, 190)
    two_blob = one_blob.copy()
    two_blob[180:320, 400:520] = (40, 70, 190)
    occluded = one_blob.copy()
    occluded[200:360, 250:370] = (18, 48, 210)
    return {
        "no_hand": no_hand,
        "clutter": clutter,
        "one_hand_and_bottle": one_blob,
        "two_hands": two_blob,
        "hand_occluded_by_bottle": occluded,
    }


def cycle_frames(frames: list[np.ndarray], count: int) -> list[np.ndarray]:
    if not frames:
        raise ValueError("frames must not be empty")
    return [frames[index % len(frames)] for index in range(count)]


def continuity_metrics(
    *,
    primary_hits: list[bool],
    hand_counts: list[int],
    landmark_available: list[bool],
) -> dict[str, float]:
    """Tracker continuity stats. Legitimate no-hand intervals are still counted."""
    if not primary_hits:
        return {
            "primary_miss_transitions": 0.0,
            "longest_primary_miss_run": 0.0,
            "hand_count_changes": 0.0,
            "landmark_availability_continuity": 0.0,
        }

    miss_transitions = 0
    longest_miss = 0
    current_miss = 0
    for index, hit in enumerate(primary_hits):
        if hit:
            current_miss = 0
            continue
        current_miss += 1
        longest_miss = max(longest_miss, current_miss)
        if index == 0 or primary_hits[index - 1]:
            miss_transitions += 1

    hand_count_changes = 0
    for previous, current in zip(hand_counts, hand_counts[1:]):
        if previous != current:
            hand_count_changes += 1

    availability_pairs = 0
    availability_matches = 0
    for previous, current in zip(landmark_available, landmark_available[1:]):
        availability_pairs += 1
        if previous == current:
            availability_matches += 1
    continuity = (
        availability_matches / availability_pairs if availability_pairs else 0.0
    )
    return {
        "primary_miss_transitions": float(miss_transitions),
        "longest_primary_miss_run": float(longest_miss),
        "hand_count_changes": float(hand_count_changes),
        "landmark_availability_continuity": continuity,
    }


def _palm_or_first_point(hand) -> Optional[Point2D]:
    palm = hand.palm_center()
    if palm is not None:
        return palm
    if not hand.points:
        return None
    first_index = min(hand.points)
    return hand.points[first_index]


def _match_hands(previous, current):
    remaining = list(enumerate(current.hands))
    pairs = []
    for prev_hand in previous.hands:
        prev_palm = _palm_or_first_point(prev_hand)
        if prev_palm is None or not remaining:
            continue
        best_index = 0
        best_dist = float("inf")
        for offset, (original_index, curr_hand) in enumerate(remaining):
            curr_palm = _palm_or_first_point(curr_hand)
            if curr_palm is None:
                continue
            dist = (
                (prev_palm.x - curr_palm.x) ** 2
                + (prev_palm.y - curr_palm.y) ** 2
            ) ** 0.5
            if dist < best_dist:
                best_dist = dist
                best_index = offset
        _, matched = remaining.pop(best_index)
        pairs.append((prev_hand, matched))
    return pairs


def landmark_jitter_metrics(
    results: list[Optional[HandsResult]],
) -> dict[str, float]:
    """Mean/p95 per-landmark displacement between consecutive detected frames.

    Frames where a hand disappears are skipped. They are not treated as jitter.
    """
    displacements: list[float] = []
    pairs = 0
    for previous, current in zip(results, results[1:]):
        if previous is None or current is None:
            continue
        if not previous.hands or not current.hands:
            continue
        matched = _match_hands(previous, current)
        if not matched:
            continue
        pairs += 1
        frame_displacements: list[float] = []
        for prev_hand, curr_hand in matched:
            shared = set(prev_hand.points) & set(curr_hand.points)
            for index in shared:
                prev_pt = prev_hand.points[index]
                curr_pt = curr_hand.points[index]
                frame_displacements.append(
                    (
                        (prev_pt.x - curr_pt.x) ** 2
                        + (prev_pt.y - curr_pt.y) ** 2
                    ) ** 0.5
                )
        if frame_displacements:
            displacements.append(
                sum(frame_displacements) / len(frame_displacements)
            )
    if not displacements:
        return {
            "pairs": float(pairs),
            "mean_displacement": 0.0,
            "p95_displacement": 0.0,
        }
    # percentile_ms expects seconds; displacements are already unitless.
    ordered = sorted(displacements)
    p95_index = min(len(ordered) - 1, max(0, int(round(0.95 * (len(ordered) - 1)))))
    return {
        "pairs": float(pairs),
        "mean_displacement": sum(displacements) / len(displacements),
        "p95_displacement": ordered[p95_index],
    }


def save_capture_manifest(
    path: Path,
    frames: list[TimedCaptureFrame],
) -> None:
    payload = {
        "schema": "elixr.hands_capture_manifest.v1",
        "frames": [asdict(frame) for frame in frames],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


SCENE_TAGS = (
    "valid_hold",
    "partial_occlusion",
    "entering_contact_zone",
    "leaving_contact_zone",
    "primary_visible_outside_zone",
    "no_hand",
    "no_bottle",
)


def parse_scene_tag_spec(spec: str) -> list[tuple[str, int, int]]:
    """Parse 'tag:start-end,tag:start-end' using 1-based inclusive frame numbers."""
    ranges: list[tuple[str, int, int]] = []
    if not spec.strip():
        return ranges
    for part in spec.split(","):
        chunk = part.strip()
        if not chunk:
            continue
        if ":" not in chunk or "-" not in chunk:
            raise ValueError(
                f"Invalid scene tag spec {chunk!r}; expected tag:start-end"
            )
        tag, span = chunk.split(":", 1)
        tag = tag.strip()
        start_text, end_text = span.split("-", 1)
        start = int(start_text.strip())
        end = int(end_text.strip())
        if tag not in SCENE_TAGS:
            raise ValueError(
                f"Unknown scene tag {tag!r}; allowed: {', '.join(SCENE_TAGS)}"
            )
        if start < 1 or end < start:
            raise ValueError(f"Invalid frame range {start}-{end}")
        ranges.append((tag, start, end))
    return ranges


def parse_tag_range_args(values: list[str] | tuple[str, ...] | str) -> list[tuple[str, int, int]]:
    """Parse --tag-range START:END=tag. 0-start means frame 1. Inclusive 1-based ends."""
    if isinstance(values, str):
        chunks = [values]
    else:
        chunks = list(values)
    ranges: list[tuple[str, int, int]] = []
    for raw in chunks:
        for part in str(raw).split(","):
            chunk = part.strip()
            if not chunk:
                continue
            if "=" not in chunk or ":" not in chunk.split("=", 1)[0]:
                raise ValueError(
                    f"Invalid --tag-range {chunk!r}; expected start:end=tag"
                )
            span, tag = chunk.split("=", 1)
            tag = tag.strip()
            start_text, end_text = span.split(":", 1)
            start = int(start_text.strip())
            end = int(end_text.strip())
            if start == 0:
                start = 1
            if tag not in SCENE_TAGS:
                raise ValueError(
                    f"Unknown scene tag {tag!r}; allowed: {', '.join(SCENE_TAGS)}"
                )
            if start < 1 or end < start:
                raise ValueError(f"Invalid frame range {start}-{end}")
            ranges.append((tag, start, end))
    return ranges


def _longest_false_run(flags: list[bool]) -> int:
    longest = 0
    current = 0
    for flag in flags:
        if flag:
            current = 0
            continue
        current += 1
        longest = max(longest, current)
    return longest


def evaluate_capture_quality(
    records: list[TimedCaptureFrame],
    bottles: list[Optional[BottleDetection]],
    primary_hand_present: list[bool],
    *,
    tags_supplied: bool,
    min_frames: int = 180,
    min_bottle_rate: float = 0.90,
) -> dict:
    """Clip quality for a production decision. Does not infer missing human tags."""
    n = len(records)
    measured = n
    bottle_flags = [bottle is not None for bottle in bottles]
    if len(bottle_flags) != n:
        bottle_flags = bottle_flags[:n] + [False] * max(0, n - len(bottle_flags))
    hand_flags = list(primary_hand_present)
    if len(hand_flags) != n:
        hand_flags = hand_flags[:n] + [False] * max(0, n - len(hand_flags))
    bottle_present = sum(1 for flag in bottle_flags if flag)
    hand_present = sum(1 for flag in hand_flags if flag)
    tag_counts: dict[str, int] = {tag: 0 for tag in SCENE_TAGS}
    tagged = 0
    for record in records:
        if record.scene_tag:
            tagged += 1
            if record.scene_tag in tag_counts:
                tag_counts[record.scene_tag] += 1
            else:
                tag_counts[record.scene_tag] = tag_counts.get(record.scene_tag, 0) + 1
    span_ms = records[-1].relative_time_ms - records[0].relative_time_ms if n else 0
    deltas_s = []
    if n >= 2:
        deltas_s = [
            max(0.0, later.captured_at_monotonic - earlier.captured_at_monotonic)
            for earlier, later in zip(records, records[1:])
        ]
    from vision.hands_diagnostics import timing_stats

    interval = timing_stats(deltas_s)
    bottle_rate = bottle_present / n if n else 0.0
    hand_rate = hand_present / n if n else 0.0
    empty_tag_share = 0.0
    if n:
        empty_tag_share = (
            tag_counts.get("no_bottle", 0) + tag_counts.get("no_hand", 0)
        ) / n
    reasons: list[str] = []
    notes: list[str] = []
    if not tags_supplied:
        notes.append("Human scene tags were not supplied.")
    if n < min_frames:
        reasons.append(
            f"captured frames {n} < {min_frames} required for a dedicated clip"
        )
    if bottle_rate < min_bottle_rate:
        reasons.append(
            f"bottle-present {bottle_rate:.1%} < {min_bottle_rate:.0%} of measured frames"
        )
    if empty_tag_share > 0.20:
        reasons.append("clip is mostly tagged no_bottle/no_hand")
    if bottle_rate < 0.50:
        reasons.append("clip is mostly no-bottle")
    if tags_supplied and tag_counts.get("valid_hold", 0) < 30:
        reasons.append("valid grip scenes are not meaningfully represented")
    if not tags_supplied:
        reasons.append(
            "human scene tags missing; cannot confirm continuous Bartender's Grip"
        )
    valid = not reasons
    return {
        "total_captured_frames": n,
        "measured_frames": measured,
        "span_ms": span_ms,
        "interval_mean_ms": interval["mean_ms"],
        "interval_median_ms": interval["median_ms"],
        "interval_p95_ms": interval["p95_ms"],
        "bottle_present_frames": bottle_present,
        "bottle_present_rate": bottle_rate,
        "primary_hand_present_frames": hand_present,
        "primary_hand_present_rate": hand_rate,
        "tag_counts": tag_counts,
        "tagged_frames": tagged,
        "longest_no_bottle_run": _longest_false_run(bottle_flags),
        "longest_no_hand_run": _longest_false_run(hand_flags),
        "tags_supplied": tags_supplied,
        "notes": notes,
        "invalid_reasons": reasons,
        "valid_for_production_decision": valid,
    }


def apply_scene_tags(
    frames: list[TimedCaptureFrame],
    ranges: list[tuple[str, int, int]],
) -> list[TimedCaptureFrame]:
    """Annotate human scene tags. Does not infer tags from detector output."""
    updated: list[TimedCaptureFrame] = []
    for index, frame in enumerate(frames, start=1):
        tag = frame.scene_tag
        for name, start, end in ranges:
            if start <= index <= end:
                tag = name
        updated.append(
            TimedCaptureFrame(
                filename=frame.filename,
                sequence=frame.sequence,
                captured_at_monotonic=frame.captured_at_monotonic,
                relative_time_ms=frame.relative_time_ms,
                movement_label=frame.movement_label,
                scene_tag=tag,
                bottle=frame.bottle,
            )
        )
    return updated


def load_capture_manifest(path: Path) -> list[TimedCaptureFrame]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    frames = []
    for raw in payload.get("frames", []):
        frames.append(
            TimedCaptureFrame(
                filename=str(raw["filename"]),
                sequence=int(raw["sequence"]),
                captured_at_monotonic=float(raw["captured_at_monotonic"]),
                relative_time_ms=int(raw["relative_time_ms"]),
                movement_label=str(raw.get("movement_label", "")),
                scene_tag=str(raw.get("scene_tag", "")),
                bottle=raw.get("bottle"),
            )
        )
    return frames
