"""Compare raw YOLO detections across runtimes without changing thresholds."""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass, field

from vision.prop_inference import RawDetection


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


def _class_threshold(
    class_id: int,
    *,
    bottle_conf: float,
    shaker_conf: float,
) -> float:
    if class_id == 1:
        return shaker_conf
    return bottle_conf


def _pair_by_iou(
    left: list[RawDetection],
    right: list[RawDetection],
) -> list[tuple[RawDetection, RawDetection, float]]:
    remaining_right = list(right)
    pairs: list[tuple[RawDetection, RawDetection, float]] = []
    for item in left:
        if not remaining_right:
            break
        best_index = 0
        best_iou = -1.0
        for index, candidate in enumerate(remaining_right):
            iou = box_iou(item, candidate)
            if iou > best_iou:
                best_iou = iou
                best_index = index
        matched = remaining_right.pop(best_index)
        pairs.append((item, matched, max(0.0, best_iou)))
    return pairs


def compare_raw_detections(
    left: list[RawDetection],
    right: list[RawDetection],
    *,
    conf_abs: float = 0.02,
    iou_min: float = 0.90,
    bottle_conf: float = 0.40,
    shaker_conf: float = 0.40,
) -> ParityReport:
    mismatches: list[ParityMismatch] = []
    if len(left) != len(right):
        mismatches.append(
            ParityMismatch(
                "count",
                f"detection count {len(left)} vs {len(right)}",
            )
        )
    elif Counter(item.class_id for item in left) != Counter(
        item.class_id for item in right
    ):
        mismatches.append(
            ParityMismatch(
                "class",
                f"class bags {Counter(item.class_id for item in left)} vs "
                f"{Counter(item.class_id for item in right)}",
            )
        )

    by_class_left: dict[int, list[RawDetection]] = defaultdict(list)
    by_class_right: dict[int, list[RawDetection]] = defaultdict(list)
    for item in left:
        by_class_left[item.class_id].append(item)
    for item in right:
        by_class_right[item.class_id].append(item)

    ious: list[float] = []
    conf_deltas: list[float] = []
    pairs = 0
    class_ids = sorted(set(by_class_left) | set(by_class_right))
    for class_id in class_ids:
        class_pairs = _pair_by_iou(
            by_class_left.get(class_id, []),
            by_class_right.get(class_id, []),
        )
        for left_box, right_box, iou in class_pairs:
            pairs += 1
            ious.append(iou)
            conf_delta = abs(left_box.confidence - right_box.confidence)
            conf_deltas.append(conf_delta)
            threshold = _class_threshold(
                class_id,
                bottle_conf=bottle_conf,
                shaker_conf=shaker_conf,
            )
            if threshold_crossing_mismatch(
                left_box.confidence,
                right_box.confidence,
                threshold=threshold,
            ):
                mismatches.append(
                    ParityMismatch(
                        "threshold",
                        (
                            f"class={class_id} conf {left_box.confidence:.4f} vs "
                            f"{right_box.confidence:.4f} crosses {threshold}"
                        ),
                    )
                )
            if iou < iou_min:
                mismatches.append(
                    ParityMismatch(
                        "iou",
                        f"class={class_id} iou={iou:.4f} < {iou_min}",
                    )
                )
            elif conf_delta > conf_abs:
                mismatches.append(
                    ParityMismatch(
                        "confidence",
                        f"class={class_id} conf delta={conf_delta:.4f} > {conf_abs}",
                    )
                )

    mean_iou = sum(ious) / len(ious) if ious else 1.0
    min_iou = min(ious) if ious else 1.0
    max_conf = max(conf_deltas) if conf_deltas else 0.0
    return ParityReport(
        passed=not mismatches,
        count_left=len(left),
        count_right=len(right),
        pairs=pairs,
        mean_iou=mean_iou,
        min_iou=min_iou,
        max_confidence_delta=max_conf,
        mismatches=mismatches,
    )


def summarize_parity(report: ParityReport) -> str:
    mismatch_kinds = ",".join(item.kind for item in report.mismatches) or "none"
    return (
        f"passed={report.passed} pairs={report.pairs} "
        f"count={report.count_left}/{report.count_right} "
        f"mean_iou={report.mean_iou:.4f} min_iou={report.min_iou:.4f} "
        f"max_conf_delta={report.max_confidence_delta:.4f} "
        f"mismatches={mismatch_kinds}"
    )
