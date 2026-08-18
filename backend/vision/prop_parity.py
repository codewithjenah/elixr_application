"""Compare YOLO detections across runtimes without changing thresholds."""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Literal, Sequence

import numpy as np

from vision.prop_detector import resolve_bottle_and_shaker_class_ids
from vision.prop_inference import RawDetection

IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png"})
STATUS_PASS = "PASS"
STATUS_MINOR_NUMERIC_DRIFT = "MINOR_NUMERIC_DRIFT"
STATUS_SEMANTIC_MISMATCH = "SEMANTIC_MISMATCH"

SemanticClass = Literal["bottle", "shaker"]
_DEFAULT_NAMES = {0: "flair_bottle", 1: "shaker_bottle"}
_MATCH_IOU_MIN = 0.50


@dataclass(frozen=True)
class ParityMismatch:
    kind: str
    detail: str


@dataclass
class ParityReport:
    passed: bool
    count_left: int
    count_right: int
    pairs: int
    mean_iou: float
    min_iou: float
    max_confidence_delta: float
    mismatches: list[ParityMismatch] = field(default_factory=list)
    status: str = STATUS_PASS
    unmatched_left: int = 0
    unmatched_right: int = 0
    bottle_count_left: int = 0
    bottle_count_right: int = 0
    shaker_count_left: int = 0
    shaker_count_right: int = 0
    mean_confidence_delta: float = 0.0
    threshold_crossings: int = 0


@dataclass(frozen=True)
class DirectoryParitySummary:
    images_tested: int
    images_with_bottle: int
    images_with_shaker: int
    images_with_both: int
    total_pytorch_detections: int
    total_onnx_detections: int
    semantic_mismatches: int
    threshold_crossings: int
    iou_failures: int
    max_confidence_delta: float
    mean_confidence_delta: float
    min_matched_iou: float
    passed: bool
    failure_images: tuple[str, ...] = ()


def box_iou(left: RawDetection, right: RawDetection) -> float:
    inter_x1 = max(left.x1, right.x1)
    inter_y1 = max(left.y1, right.y1)
    inter_x2 = min(left.x2, right.x2)
    inter_y2 = min(left.y2, right.y2)
    inter_w = max(0.0, inter_x2 - inter_x1)
    inter_h = max(0.0, inter_y2 - inter_y1)
    inter = inter_w * inter_h
    if inter <= 0:
        return 0.0
    area_left = max(0.0, left.x2 - left.x1) * max(0.0, left.y2 - left.y1)
    area_right = max(0.0, right.x2 - right.x1) * max(0.0, right.y2 - right.y1)
    union = area_left + area_right - inter
    if union <= 0:
        return 0.0
    return inter / union


def threshold_crossing_mismatch(
    left_conf: float,
    right_conf: float,
    *,
    threshold: float,
) -> bool:
    return (left_conf >= threshold) != (right_conf >= threshold)


def _class_ids(names: object) -> tuple[int, int, dict[int, str]]:
    return resolve_bottle_and_shaker_class_ids(names)


def semantic_class_for(class_id: int, names: object | None = None) -> SemanticClass:
    mapping = names if names is not None else _DEFAULT_NAMES
    bottle_id, shaker_id, _resolved = _class_ids(mapping)
    if class_id == bottle_id:
        return "bottle"
    if class_id == shaker_id:
        return "shaker"
    raise KeyError(f"class_id {class_id} is not a resolved bottle or shaker class")


def threshold_for_class_id(
    class_id: int,
    *,
    names: object | None = None,
    bottle_conf: float,
    shaker_conf: float,
) -> float:
    if semantic_class_for(class_id, names) == "shaker":
        return shaker_conf
    return bottle_conf


def _detection_sort_key(
    detection: RawDetection,
) -> tuple[float, float, float, float, float, int]:
    return (
        -float(detection.confidence),
        float(detection.x1),
        float(detection.y1),
        float(detection.x2),
        float(detection.y2),
        int(detection.class_id),
    )


def _pair_by_iou(
    left: list[RawDetection],
    right: list[RawDetection],
    *,
    min_iou: float,
) -> tuple[
    list[tuple[RawDetection, RawDetection, float]],
    list[RawDetection],
    list[RawDetection],
]:
    left_sorted = sorted(left, key=_detection_sort_key)
    remaining = sorted(right, key=_detection_sort_key)
    used = [False] * len(remaining)
    pairs: list[tuple[RawDetection, RawDetection, float]] = []
    unmatched_left: list[RawDetection] = []
    for item in left_sorted:
        best_index: int | None = None
        best_iou = -1.0
        for index, candidate in enumerate(remaining):
            if used[index]:
                continue
            iou = box_iou(item, candidate)
            if iou < min_iou:
                continue
            better_iou = iou > best_iou
            tied = iou == best_iou and best_index is not None
            better_tie = tied and _detection_sort_key(candidate) < _detection_sort_key(
                remaining[best_index]
            )
            if best_index is None or better_iou or better_tie:
                best_iou = iou
                best_index = index
        if best_index is None:
            unmatched_left.append(item)
            continue
        used[best_index] = True
        matched = remaining[best_index]
        pairs.append((item, matched, box_iou(item, matched)))
    unmatched_right = [
        candidate for index, candidate in enumerate(remaining) if not used[index]
    ]
    return pairs, unmatched_left, unmatched_right


def _semantic_counts(
    detections: Sequence[RawDetection],
    names: object,
) -> Counter[str]:
    counts: Counter[str] = Counter()
    for item in detections:
        counts[semantic_class_for(item.class_id, names)] += 1
    return counts


def compare_raw_detections(
    left: list[RawDetection],
    right: list[RawDetection],
    *,
    conf_abs: float = 0.02,
    iou_min: float = 0.90,
    bottle_conf: float = 0.40,
    shaker_conf: float = 0.40,
    names: object | None = None,
    match_iou_min: float = _MATCH_IOU_MIN,
) -> ParityReport:
    mapping = names if names is not None else _DEFAULT_NAMES
    mismatches: list[ParityMismatch] = []
    left_counts = _semantic_counts(left, mapping)
    right_counts = _semantic_counts(right, mapping)
    if len(left) != len(right):
        mismatches.append(
            ParityMismatch(
                "count",
                f"detection count {len(left)} vs {len(right)}",
            )
        )
    if left_counts != right_counts:
        mismatches.append(
            ParityMismatch(
                "class",
                f"class bags {dict(left_counts)} vs {dict(right_counts)}",
            )
        )

    by_class_left: dict[str, list[RawDetection]] = defaultdict(list)
    by_class_right: dict[str, list[RawDetection]] = defaultdict(list)
    for item in left:
        by_class_left[semantic_class_for(item.class_id, mapping)].append(item)
    for item in right:
        by_class_right[semantic_class_for(item.class_id, mapping)].append(item)

    ious: list[float] = []
    conf_deltas: list[float] = []
    pairs = 0
    unmatched_left = 0
    unmatched_right = 0
    threshold_crossings = 0
    for semantic in ("bottle", "shaker"):
        class_pairs, left_unmatched, right_unmatched = _pair_by_iou(
            by_class_left.get(semantic, []),
            by_class_right.get(semantic, []),
            min_iou=match_iou_min,
        )
        unmatched_left += len(left_unmatched)
        unmatched_right += len(right_unmatched)
        for item in left_unmatched:
            mismatches.append(
                ParityMismatch(
                    "unmatched",
                    (
                        f"unmatched pytorch {semantic} conf={item.confidence:.4f} "
                        f"box=({item.x1:.1f},{item.y1:.1f},{item.x2:.1f},{item.y2:.1f})"
                    ),
                )
            )
        for item in right_unmatched:
            mismatches.append(
                ParityMismatch(
                    "unmatched",
                    (
                        f"unmatched onnx {semantic} conf={item.confidence:.4f} "
                        f"box=({item.x1:.1f},{item.y1:.1f},{item.x2:.1f},{item.y2:.1f})"
                    ),
                )
            )
        for left_box, right_box, iou in class_pairs:
            pairs += 1
            ious.append(iou)
            conf_delta = abs(left_box.confidence - right_box.confidence)
            conf_deltas.append(conf_delta)
            threshold = threshold_for_class_id(
                left_box.class_id,
                names=mapping,
                bottle_conf=bottle_conf,
                shaker_conf=shaker_conf,
            )
            if threshold_crossing_mismatch(
                left_box.confidence,
                right_box.confidence,
                threshold=threshold,
            ):
                threshold_crossings += 1
                mismatches.append(
                    ParityMismatch(
                        "threshold",
                        (
                            f"class={semantic} conf {left_box.confidence:.4f} vs "
                            f"{right_box.confidence:.4f} crosses {threshold}"
                        ),
                    )
                )
            if iou < iou_min:
                mismatches.append(
                    ParityMismatch(
                        "iou",
                        f"class={semantic} iou={iou:.4f} < {iou_min}",
                    )
                )
            elif conf_delta > conf_abs:
                mismatches.append(
                    ParityMismatch(
                        "confidence",
                        f"class={semantic} conf delta={conf_delta:.4f} > {conf_abs}",
                    )
                )

    mean_iou = sum(ious) / len(ious) if ious else 1.0
    min_iou = min(ious) if ious else 1.0
    max_conf = max(conf_deltas) if conf_deltas else 0.0
    mean_conf = sum(conf_deltas) / len(conf_deltas) if conf_deltas else 0.0
    kinds = {item.kind for item in mismatches}
    semantic_fail = bool(kinds & {"count", "class", "threshold", "unmatched", "iou"})
    if semantic_fail:
        status = STATUS_SEMANTIC_MISMATCH
        passed = False
    elif "confidence" in kinds:
        status = STATUS_MINOR_NUMERIC_DRIFT
        passed = True
    else:
        status = STATUS_PASS
        passed = True
    return ParityReport(
        passed=passed,
        count_left=len(left),
        count_right=len(right),
        pairs=pairs,
        mean_iou=mean_iou,
        min_iou=min_iou,
        max_confidence_delta=max_conf,
        mismatches=mismatches,
        status=status,
        unmatched_left=unmatched_left,
        unmatched_right=unmatched_right,
        bottle_count_left=left_counts.get("bottle", 0),
        bottle_count_right=right_counts.get("bottle", 0),
        shaker_count_left=left_counts.get("shaker", 0),
        shaker_count_right=right_counts.get("shaker", 0),
        mean_confidence_delta=mean_conf,
        threshold_crossings=threshold_crossings,
    )


def summarize_parity(report: ParityReport) -> str:
    mismatch_kinds = ",".join(item.kind for item in report.mismatches) or "none"
    return (
        f"passed={report.passed} status={report.status} pairs={report.pairs} "
        f"count={report.count_left}/{report.count_right} "
        f"mean_iou={report.mean_iou:.4f} min_iou={report.min_iou:.4f} "
        f"max_conf_delta={report.max_confidence_delta:.4f} "
        f"mismatches={mismatch_kinds}"
    )


def discover_parity_images(directory: Path) -> list[Path]:
    path = Path(directory)
    if not path.exists() or not path.is_dir():
        raise FileNotFoundError(f"Image directory not found: {path}")
    images = sorted(
        item
        for item in path.iterdir()
        if item.is_file() and item.suffix.lower() in IMAGE_EXTENSIONS
    )
    if not images:
        raise FileNotFoundError(f"No .jpg/.jpeg/.png images in {path}")
    return images


def aggregate_directory_parity(
    results: Iterable[tuple[str, ParityReport]],
) -> DirectoryParitySummary:
    rows = list(results)
    images_with_bottle = 0
    images_with_shaker = 0
    images_with_both = 0
    total_left = 0
    total_right = 0
    semantic_mismatches = 0
    threshold_crossings = 0
    iou_failures = 0
    conf_deltas: list[float] = []
    ious: list[float] = []
    failures: list[str] = []
    for name, report in rows:
        bottles = max(report.bottle_count_left, report.bottle_count_right)
        shakers = max(report.shaker_count_left, report.shaker_count_right)
        if bottles:
            images_with_bottle += 1
        if shakers:
            images_with_shaker += 1
        if bottles and shakers:
            images_with_both += 1
        total_left += report.count_left
        total_right += report.count_right
        if report.status == STATUS_SEMANTIC_MISMATCH:
            semantic_mismatches += 1
        threshold_crossings += report.threshold_crossings
        iou_failures += sum(1 for item in report.mismatches if item.kind == "iou")
        if report.pairs:
            conf_deltas.append(report.mean_confidence_delta)
            ious.append(report.min_iou)
        if not report.passed or report.status == STATUS_SEMANTIC_MISMATCH:
            failures.append(name)
    mean_conf = sum(conf_deltas) / len(conf_deltas) if conf_deltas else 0.0
    max_conf = max((report.max_confidence_delta for _, report in rows), default=0.0)
    min_iou = min(ious) if ious else 1.0
    passed = (
        semantic_mismatches == 0 and iou_failures == 0 and threshold_crossings == 0
    )
    return DirectoryParitySummary(
        images_tested=len(rows),
        images_with_bottle=images_with_bottle,
        images_with_shaker=images_with_shaker,
        images_with_both=images_with_both,
        total_pytorch_detections=total_left,
        total_onnx_detections=total_right,
        semantic_mismatches=semantic_mismatches,
        threshold_crossings=threshold_crossings,
        iou_failures=iou_failures,
        max_confidence_delta=max_conf,
        mean_confidence_delta=mean_conf,
        min_matched_iou=min_iou,
        passed=passed,
        failure_images=tuple(failures),
    )


def summarize_directory_parity(summary: DirectoryParitySummary) -> str:
    overall = "PASS" if summary.passed else "FAIL"
    lines = [
        f"images tested={summary.images_tested}",
        f"images containing bottle={summary.images_with_bottle}",
        f"images containing shaker={summary.images_with_shaker}",
        f"images containing both={summary.images_with_both}",
        (
            f"total PyTorch detections={summary.total_pytorch_detections} "
            f"total ONNX detections={summary.total_onnx_detections}"
        ),
        f"semantic mismatches={summary.semantic_mismatches}",
        f"threshold-crossing mismatches={summary.threshold_crossings}",
        f"box IoU failures={summary.iou_failures}",
        f"max confidence delta={summary.max_confidence_delta:.4f}",
        f"mean confidence delta={summary.mean_confidence_delta:.4f}",
        f"minimum matched IoU={summary.min_matched_iou:.4f}",
        f"overall={overall}",
    ]
    if summary.failure_images:
        lines.append("per-image failures:")
        lines.extend(f"  {name}" for name in summary.failure_images)
    return "\n".join(lines)


def write_parity_frame(output_dir: Path, index: int, frame: np.ndarray) -> Path:
    import cv2

    directory = Path(output_dir)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{index:03d}.jpg"
    if not cv2.imwrite(str(path), frame):
        raise RuntimeError(f"Failed to write parity frame: {path}")
    return path


def capture_parity_frames(
    *,
    read_frame: Callable[[], np.ndarray | None],
    output_dir: Path,
    count: int,
    start_index: int = 1,
) -> list[Path]:
    if count <= 0:
        raise ValueError("count must be >= 1")
    saved: list[Path] = []
    for offset in range(count):
        frame = read_frame()
        if frame is None:
            raise RuntimeError("camera returned no frame")
        saved.append(write_parity_frame(output_dir, start_index + offset, frame))
    return saved
