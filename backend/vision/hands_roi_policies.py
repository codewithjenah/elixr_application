"""Benchmark-only Bartender ROI gating. Production HandsDetector stays immediate."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Optional, Protocol

from vision.grip_geometry import (
    BARTENDER_CONTACT_BOTTOM_FRACTION,
    bartender_contact_zone,
    bartender_control_point,
    point_in_zone,
)
from vision.hands_detector import (
    _bartender_crop_bounds,
    _has_bartender_candidate,
    _merge_hands,
)
from vision.hands_diagnostics import timing_stats
from vision.types import BottleDetection, HandsResult, Point2D

WASTE_NO_HAND = "roi_returned_no_hand"
WASTE_OUTSIDE_ZONE = "hand_outside_bartender_zone"
WASTE_DUPLICATE = "duplicate_unhelpful_hand"
WASTE_CROP_EXCLUDES = "crop_likely_excludes_hand"
WASTE_GEOMETRY_IMPOSSIBLE = "bottle_contact_geometry_impossible"
WASTE_OTHER = "other"

_DUPLICATE_PALM_DIST = 0.05


@dataclass(frozen=True)
class RoiDecision:
    eligible: bool
    run_roi: bool
    consecutive_eligible_misses: int


class RoiPolicy(Protocol):
    def decide(
        self, *, bottle_exists: bool, has_usable_candidate: bool
    ) -> RoiDecision: ...

    def observe(self, *, ran_roi: bool, recovered: bool) -> None: ...


class ImmediateRoiPolicy:
    """Reproduce production: ROI on every eligible frame (bottle, no candidate)."""

    def decide(
        self, *, bottle_exists: bool, has_usable_candidate: bool
    ) -> RoiDecision:
        eligible = bool(bottle_exists) and not has_usable_candidate
        return RoiDecision(
            eligible=eligible,
            run_roi=eligible,
            consecutive_eligible_misses=int(eligible),
        )

    def observe(self, *, ran_roi: bool, recovered: bool) -> None:
        return None


class ConsecutiveMissRoiPolicy:
    """Run ROI only after N consecutive eligible misses. n=2 is strategy B."""

    def __init__(self, n: int = 2):
        if n < 1:
            raise ValueError("n must be >= 1")
        self.n = n
        self._consecutive = 0

    def decide(
        self, *, bottle_exists: bool, has_usable_candidate: bool
    ) -> RoiDecision:
        if not bottle_exists:
            self._consecutive = 0
            return RoiDecision(
                eligible=False,
                run_roi=False,
                consecutive_eligible_misses=0,
            )
        if has_usable_candidate:
            self._consecutive = 0
            return RoiDecision(
                eligible=False,
                run_roi=False,
                consecutive_eligible_misses=0,
            )
        self._consecutive += 1
        return RoiDecision(
            eligible=True,
            run_roi=self._consecutive >= self.n,
            consecutive_eligible_misses=self._consecutive,
        )

    def observe(self, *, ran_roi: bool, recovered: bool) -> None:
        if ran_roi and recovered:
            self._consecutive = 0


class CooldownRoiPolicy:
    """After a wasted ROI attempt, skip the next eligible attempt."""

    def __init__(self):
        self._skip_next = False

    def decide(
        self, *, bottle_exists: bool, has_usable_candidate: bool
    ) -> RoiDecision:
        eligible = bool(bottle_exists) and not has_usable_candidate
        if not eligible:
            return RoiDecision(
                eligible=False,
                run_roi=False,
                consecutive_eligible_misses=0,
            )
        if self._skip_next:
            self._skip_next = False
            return RoiDecision(
                eligible=True,
                run_roi=False,
                consecutive_eligible_misses=1,
            )
        return RoiDecision(
            eligible=True,
            run_roi=True,
            consecutive_eligible_misses=1,
        )

    def observe(self, *, ran_roi: bool, recovered: bool) -> None:
        if ran_roi and not recovered:
            self._skip_next = True


@dataclass
class PolicyFrameOutcome:
    eligible: bool
    ran_roi: bool
    recovered: bool
    output: Optional[HandsResult]
    consecutive_eligible_misses: int = 0
    waste_reason: Optional[str] = None
    roi_seconds: float = 0.0


def evaluate_policy_frame(
    policy: RoiPolicy,
    *,
    primary: Optional[HandsResult],
    bottle: Optional[BottleDetection],
    frame_width: int,
    frame_height: int,
    roi_result: Optional[HandsResult] = None,
    roi_fn: Optional[Callable[[], tuple[Optional[HandsResult], float]]] = None,
    max_num_hands: int = 1,
) -> PolicyFrameOutcome:
    has_candidate = False
    if bottle is not None:
        has_candidate = _has_bartender_candidate(
            primary,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
    decision = policy.decide(
        bottle_exists=bottle is not None,
        has_usable_candidate=has_candidate,
    )
    recovered_hands: Optional[HandsResult] = None
    roi_seconds = 0.0
    ran_roi = bool(decision.run_roi)
    recovered = False
    waste_reason: Optional[str] = None
    output = primary
    if ran_roi:
        if roi_fn is not None:
            recovered_hands, roi_seconds = roi_fn()
        else:
            recovered_hands = roi_result
        output = _merge_hands(
            primary,
            recovered_hands,
            max_num_hands=max_num_hands,
        )
        if bottle is not None:
            recovered = _has_bartender_candidate(
                output,
                bottle,
                frame_width=frame_width,
                frame_height=frame_height,
            )
        if not recovered:
            waste_reason = classify_wasted_roi(
                primary=primary,
                recovered=recovered_hands,
                bottle=bottle,
                frame_width=frame_width,
                frame_height=frame_height,
            )
    policy.observe(ran_roi=ran_roi, recovered=recovered)
    return PolicyFrameOutcome(
        eligible=decision.eligible,
        ran_roi=ran_roi,
        recovered=recovered,
        output=output,
        consecutive_eligible_misses=decision.consecutive_eligible_misses,
        waste_reason=waste_reason,
        roi_seconds=roi_seconds,
    )


def _palm(hand) -> Optional[Point2D]:
    palm = hand.palm_center()
    if palm is not None:
        return palm
    if not hand.points:
        return None
    first = min(hand.points)
    return hand.points[first]


def _hands_are_duplicate(
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
) -> bool:
    if primary is None or recovered is None:
        return False
    if not primary.hands or not recovered.hands:
        return False
    for recovered_hand in recovered.hands:
        rec_palm = _palm(recovered_hand)
        if rec_palm is None:
            continue
        for primary_hand in primary.hands:
            prim_palm = _palm(primary_hand)
            if prim_palm is None:
                continue
            dist = (
                (rec_palm.x - prim_palm.x) ** 2
                + (rec_palm.y - prim_palm.y) ** 2
            ) ** 0.5
            if dist <= _DUPLICATE_PALM_DIST:
                return True
    return False


def _point_in_crop(
    point: Point2D,
    bounds: tuple[int, int, int, int],
    *,
    frame_width: int,
    frame_height: int,
) -> bool:
    left, top, right, bottom = bounds
    px = point.x * frame_width
    py = point.y * frame_height
    return left <= px <= right and top <= py <= bottom


def _primary_required_geometry_outside_crop(
    primary: Optional[HandsResult],
    bounds: tuple[int, int, int, int],
    *,
    frame_width: int,
    frame_height: int,
) -> bool:
    if primary is None or not primary.hands:
        return False
    for hand in primary.hands:
        control = bartender_control_point(hand)
        checked = []
        if control is not None:
            checked.append(control)
        for index in (4, 8):
            point = hand.points.get(index)
            if point is not None:
                checked.append(point)
        if not checked:
            continue
        if any(
            not _point_in_crop(
                point,
                bounds,
                frame_width=frame_width,
                frame_height=frame_height,
            )
            for point in checked
        ):
            return True
    return False


def classify_wasted_roi(
    *,
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
    bottle: Optional[BottleDetection],
    frame_width: int,
    frame_height: int,
    crop_bounds: Optional[tuple[int, int, int, int]] = None,
) -> str:
    if bottle is None:
        return WASTE_GEOMETRY_IMPOSSIBLE
    bounds = crop_bounds
    if bounds is None:
        bounds = _bartender_crop_bounds(
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
    if bounds is None:
        return WASTE_GEOMETRY_IMPOSSIBLE
    crop_excludes = _primary_required_geometry_outside_crop(
        primary,
        bounds,
        frame_width=frame_width,
        frame_height=frame_height,
    )
    if recovered is None or not recovered.hands:
        if crop_excludes:
            return WASTE_CROP_EXCLUDES
        return WASTE_NO_HAND
    zone = bartender_contact_zone(
        bottle,
        frame_width=frame_width,
        frame_height=frame_height,
        bottom_fraction=BARTENDER_CONTACT_BOTTOM_FRACTION,
    )
    if _has_bartender_candidate(
        recovered,
        bottle,
        frame_width=frame_width,
        frame_height=frame_height,
    ):
        return WASTE_OTHER
    if _hands_are_duplicate(primary, recovered):
        return WASTE_DUPLICATE
    controls = [bartender_control_point(hand) for hand in recovered.hands]
    if any(
        control is not None and not point_in_zone(control, zone)
        for control in controls
    ):
        return WASTE_OUTSIDE_ZONE
    if crop_excludes:
        return WASTE_CROP_EXCLUDES
    return WASTE_OTHER


def classify_immediate_recoveries(a_frames: list[dict]) -> dict[str, int]:
    """Bucket Immediate A recoveries by consecutive eligible miss and primary cause."""
    first = 0
    second = 0
    third = 0
    no_hand = 0
    outside = 0
    consecutive = 0
    previous_recovered = False
    recoveries = 0
    for frame in a_frames:
        eligible = bool(frame.get("bottle_present")) and not bool(
            frame.get("primary_usable")
        )
        if eligible:
            consecutive += 1
        else:
            consecutive = 0
        recovered_now = bool(frame.get("ran_roi") and frame.get("recovered"))
        if recovered_now and not previous_recovered:
            recoveries += 1
            if consecutive <= 1:
                first += 1
            elif consecutive == 2:
                second += 1
            else:
                third += 1
            if frame.get("primary_had_hand"):
                outside += 1
            else:
                no_hand += 1
        previous_recovered = recovered_now
        if recovered_now:
            consecutive = 0
    return {
        "a_recoveries": recoveries,
        "first_miss": first,
        "second_miss": second,
        "third_or_later": third,
        "primary_no_hand": no_hand,
        "primary_hand_outside_zone": outside,
    }


def measure_recovery_delay(
    a_frames: list[dict],
    b_frames: list[dict],
) -> dict[str, float]:
    """Compare gated recoveries against immediate (A) recoveries.

    Delay uses capture manifest relative_time_ms. Lost recoveries are not
    included in mean/max delay.
    """
    if len(a_frames) != len(b_frames):
        return {
            "a_recoveries": 0.0,
            "immediate_recoveries": 0.0,
            "delayed_recoveries": 0.0,
            "lost_recoveries": 0.0,
            "mean_recovery_delay_frames": 0.0,
            "mean_recovery_delay_ms": 0.0,
            "max_recovery_delay_frames": 0.0,
            "max_recovery_delay_ms": 0.0,
        }

    a_indices: list[int] = []
    previous_recovered = False
    for index, frame in enumerate(a_frames):
        recovered_now = bool(frame.get("ran_roi") and frame.get("recovered"))
        if recovered_now and not previous_recovered:
            a_indices.append(index)
        previous_recovered = recovered_now
    immediate = 0
    delayed = 0
    lost = 0
    delay_frames: list[int] = []
    delay_ms: list[float] = []

    for index in a_indices:
        b_frame = b_frames[index]
        if b_frame.get("ran_roi") and b_frame.get("recovered"):
            immediate += 1
            delay_frames.append(0)
            delay_ms.append(0.0)
            continue
        if b_frame.get("ran_roi") and not b_frame.get("recovered"):
            lost += 1
            continue

        found = False
        for later in range(index + 1, len(b_frames)):
            later_b = b_frames[later]
            if later_b.get("primary_usable"):
                lost += 1
                found = True
                break
            if later_b.get("ran_roi"):
                if later_b.get("recovered"):
                    delayed += 1
                    frames_delay = later - index
                    ms_delay = float(
                        later_b.get("relative_time_ms", 0)
                        - a_frames[index].get("relative_time_ms", 0)
                    )
                    delay_frames.append(frames_delay)
                    delay_ms.append(max(0.0, ms_delay))
                else:
                    lost += 1
                found = True
                break
        if not found:
            lost += 1

    preserved = immediate + delayed
    return {
        "a_recoveries": float(len(a_indices)),
        "immediate_recoveries": float(immediate),
        "preserved_recoveries": float(immediate),
        "delayed_recoveries": float(delayed),
        "lost_recoveries": float(lost),
        "mean_recovery_delay_frames": (
            sum(delay_frames) / preserved if preserved else 0.0
        ),
        "mean_recovery_delay_ms": (
            sum(delay_ms) / preserved if preserved else 0.0
        ),
        "max_recovery_delay_frames": float(max(delay_frames) if delay_frames else 0),
        "max_recovery_delay_ms": float(max(delay_ms) if delay_ms else 0.0),
    }


def first_miss_recovery_indices(a_frames: list[dict]) -> list[int]:
    consecutive = 0
    previous_recovered = False
    indices: list[int] = []
    for index, frame in enumerate(a_frames):
        eligible = bool(frame.get("bottle_present")) and not bool(
            frame.get("primary_usable")
        )
        consecutive = consecutive + 1 if eligible else 0
        recovered_now = bool(frame.get("ran_roi") and frame.get("recovered"))
        if recovered_now and not previous_recovered and consecutive <= 1:
            indices.append(index)
        previous_recovered = recovered_now
        if recovered_now:
            consecutive = 0
    return indices


def measure_recovery_delay_for_indices(
    a_frames: list[dict],
    b_frames: list[dict],
    indices: list[int],
) -> dict[str, float]:
    if len(a_frames) != len(b_frames):
        return measure_recovery_delay([], [])
    filtered_a = []
    filtered_b = []
    index_set = set(indices)
    for index, (a_frame, b_frame) in enumerate(zip(a_frames, b_frames)):
        a_copy = dict(a_frame)
        if index not in index_set:
            a_copy["ran_roi"] = False
            a_copy["recovered"] = False
        filtered_a.append(a_copy)
        filtered_b.append(b_frame)
    return measure_recovery_delay(filtered_a, filtered_b)


@dataclass
class StrategyReplay:
    label: str
    eligible: int = 0
    attempts: int = 0
    successes: int = 0
    failures: int = 0
    roi_samples_s: list[float] = field(default_factory=list)
    hands_samples_s: list[float] = field(default_factory=list)
    usable: list[bool] = field(default_factory=list)
    hand_counts: list[int] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)
    waste_reasons: list[str] = field(default_factory=list)


def summarize_strategy(replay: StrategyReplay) -> dict:
    from vision.hands_benchmark import continuity_metrics, usable_detection_rate

    roi = timing_stats(replay.roi_samples_s)
    hands = timing_stats(replay.hands_samples_s)
    usable_stats = usable_detection_rate(replay.usable)
    continuity = continuity_metrics(
        primary_hits=replay.usable,
        hand_counts=replay.hand_counts,
        landmark_available=replay.usable,
    )
    attempts = replay.attempts
    recovery_rate = replay.successes / attempts if attempts else 0.0
    wasted_rate = replay.failures / attempts if attempts else 0.0
    waste_counts: dict[str, int] = {}
    for reason in replay.waste_reasons:
        waste_counts[reason] = waste_counts.get(reason, 0) + 1
    return {
        "label": replay.label,
        "eligible_frames": float(replay.eligible),
        "attempts": float(replay.attempts),
        "successes": float(replay.successes),
        "failures": float(replay.failures),
        "recovery_rate": recovery_rate,
        "wasted_rate": wasted_rate,
        "roi_mean_ms": roi["mean_ms"],
        "roi_median_ms": roi["median_ms"],
        "roi_p95_ms": roi["p95_ms"],
        "usable_frames": float(sum(1 for item in replay.usable if item)),
        "usable_rate": usable_stats["usable_rate"],
        "longest_usable_miss_run": continuity["longest_primary_miss_run"],
        "miss_transitions": continuity["primary_miss_transitions"],
        "continuity": continuity["landmark_availability_continuity"],
        "hand_count_changes": continuity["hand_count_changes"],
        "hands_mean_ms": hands["mean_ms"],
        "hands_median_ms": hands["median_ms"],
        "hands_p95_ms": hands["p95_ms"],
        "hands_fps": hands["fps"],
        "total_roi_time_ms": sum(replay.roi_samples_s) * 1000.0,
        "waste_counts": waste_counts,
    }


def n2_recommendation(
    pass_a: dict,
    pass_b: dict,
    delay: dict,
    *,
    capture_valid: bool = True,
    first_miss_lost: int = 0,
    valid_hold_ok: bool = True,
    partial_occlusion_ok: bool = True,
) -> dict[str, object]:
    """Recommend N=2 only if every production-safety criterion holds."""
    attempts_a = float(pass_a.get("attempts", 0.0))
    attempts_b = float(pass_b.get("attempts", 0.0))
    attempt_drop = attempts_a - attempts_b
    attempt_drop_frac = attempt_drop / attempts_a if attempts_a else 0.0
    roi_a = float(pass_a.get("total_roi_time_ms", 0.0))
    roi_b = float(pass_b.get("total_roi_time_ms", 0.0))
    roi_drop = roi_a - roi_b
    roi_drop_frac = roi_drop / roi_a if roi_a else 0.0
    mean_a = float(pass_a.get("hands_mean_ms", 0.0))
    mean_b = float(pass_b.get("hands_mean_ms", 0.0))
    p95_a = float(pass_a.get("hands_p95_ms", 0.0))
    p95_b = float(pass_b.get("hands_p95_ms", 0.0))
    usable_a = float(pass_a.get("usable_rate", 0.0))
    usable_b = float(pass_b.get("usable_rate", 0.0))
    miss_a = float(pass_a.get("longest_usable_miss_run", 0.0))
    miss_b = float(pass_b.get("longest_usable_miss_run", 0.0))

    c_capture = bool(capture_valid)
    c1 = attempt_drop >= 3 and attempt_drop_frac >= 0.20
    c_roi_time = roi_drop >= 10.0 and roi_drop_frac >= 0.20
    c2 = (mean_a - mean_b) >= 3.0 or (p95_a - p95_b) >= 5.0
    c3 = (usable_a - usable_b) <= 0.01
    c4 = float(delay.get("lost_recoveries", 0.0)) == 0.0
    c5 = float(delay.get("max_recovery_delay_frames", 0.0)) <= 1.0
    c6 = (miss_b - miss_a) <= 1.0
    c_first = int(first_miss_lost) == 0
    c_hold = bool(valid_hold_ok)
    c_occ = bool(partial_occlusion_ok)
    use_n2 = all(
        (c_capture, c1, c_roi_time, c2, c3, c4, c5, c6, c_first, c_hold, c_occ)
    )
    return {
        "use_n2": use_n2,
        "capture_valid": c_capture,
        "attempts_materially_decrease": c1,
        "roi_time_materially_decreases": c_roi_time,
        "latency_materially_improves": c2,
        "usable_rate_ok": c3,
        "no_lost_recoveries": c4,
        "delay_ok_for_coaching": c5,
        "longest_miss_ok": c6,
        "first_miss_ok": c_first,
        "valid_hold_ok": c_hold,
        "partial_occlusion_ok": c_occ,
        "production_recommendation": (
            "N=2 IS SAFE FOR A PRODUCTION TRIAL" if use_n2 else "KEEP IMMEDIATE ROI"
        ),
    }
