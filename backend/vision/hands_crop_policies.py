"""Benchmark-only Bartender ROI crop geometries. Production crop is unchanged."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from vision.hands_detector import (
    _bartender_crop_bounds,
    _counterclockwise_crop_point_to_frame,
    _has_bartender_candidate,
)
from vision.hands_roi_policies import (
    WASTE_CROP_EXCLUDES,
    WASTE_DUPLICATE,
    WASTE_NO_HAND,
    WASTE_OUTSIDE_ZONE,
    classify_wasted_roi,
)
from vision.types import BottleDetection, HandsResult, Point2D

VALID_RECOVERY = "valid_bartender_recovery"


@dataclass(frozen=True)
class CropGeometry:
    name: str
    width_factor: float
    top_fraction: float
    bottom_fraction: float
    full_frame: bool = False
    diagnostic_ceiling: bool = False
    uses_production_formula: bool = False
    formula: str = ""


CROP_A = CropGeometry(
    name="A",
    width_factor=2.5,
    top_fraction=0.05,
    bottom_fraction=0.65,
    uses_production_formula=True,
    formula=(
        "PRODUCTION: crop_w = bottle_w * 2.5; "
        "left/right = center_x +/- crop_w/2 clipped to [0, W]; "
        "top = y1 - bottle_h * 0.05 clipped to 0; "
        "bottom = y1 + bottle_h * 0.65 clipped to H; "
        "no resize; rotate ROTATE_90_COUNTERCLOCKWISE; "
        "restore via counterclockwise crop->frame."
    ),
)

CROP_B = CropGeometry(
    name="B",
    width_factor=3.125,
    top_fraction=0.08,
    bottom_fraction=0.95,
    formula=(
        "BENCHMARK B: same formula as A with "
        "width_factor=3.125 (+25% vs 2.5), "
        "top_fraction=0.08 (more room above bottle), "
        "bottom_fraction=0.95 (extends toward lower bottle/wrist); "
        "same clip, no resize, same CCW rotation and restore."
    ),
)

CROP_C = CropGeometry(
    name="C",
    width_factor=3.75,
    top_fraction=0.18,
    bottom_fraction=1.25,
    formula=(
        "BENCHMARK C: same formula as A with "
        "width_factor=3.75 (+50% vs 2.5), "
        "top_fraction=0.18, "
        "bottom_fraction=1.25 (includes below-bottle region); "
        "same clip, no resize, same CCW rotation and restore."
    ),
)

CROP_D = CropGeometry(
    name="D",
    width_factor=0.0,
    top_fraction=0.0,
    bottom_fraction=0.0,
    full_frame=True,
    diagnostic_ceiling=True,
    formula=(
        "DIAGNOSTIC CEILING ONLY: left,top,right,bottom = 0,0,W,H; "
        "full-frame IMAGE with the same ROTATE_90_COUNTERCLOCKWISE "
        "and coordinate restore as bartender ROI. Not a production candidate."
    ),
)

CROP_VARIANTS = (CROP_A, CROP_B, CROP_C)
CROP_VARIANTS_WITH_D = (CROP_A, CROP_B, CROP_C, CROP_D)


def crop_bounds_for(
    geometry: CropGeometry,
    bottle: Optional[BottleDetection],
    frame_width: int,
    frame_height: int,
) -> Optional[tuple[int, int, int, int]]:
    if geometry.full_frame:
        if frame_width <= 0 or frame_height <= 0:
            return None
        return (0, 0, frame_width, frame_height)
    if bottle is None:
        return None
    if geometry.uses_production_formula:
        return _bartender_crop_bounds(
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
    return _bounds_with_factors(
        bottle,
        frame_width=frame_width,
        frame_height=frame_height,
        width_factor=geometry.width_factor,
        top_fraction=geometry.top_fraction,
        bottom_fraction=geometry.bottom_fraction,
    )


def _bounds_with_factors(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
    width_factor: float,
    top_fraction: float,
    bottom_fraction: float,
) -> Optional[tuple[int, int, int, int]]:
    bottle_width = bottle.x2 - bottle.x1
    bottle_height = bottle.y2 - bottle.y1
    if bottle_width <= 0 or bottle_height <= 0:
        return None
    center_x = (bottle.x1 + bottle.x2) / 2.0
    crop_width = bottle_width * width_factor
    left = max(0, round(center_x - crop_width / 2.0))
    right = min(frame_width, round(center_x + crop_width / 2.0))
    top = max(0, round(bottle.y1 - bottle_height * top_fraction))
    bottom = min(
        frame_height,
        round(bottle.y1 + bottle_height * bottom_fraction),
    )
    if right <= left or bottom <= top:
        return None
    return left, top, right, bottom


def restore_crop_point(
    point: Point2D,
    bounds: tuple[int, int, int, int],
    *,
    frame_width: int,
    frame_height: int,
) -> Point2D:
    return _counterclockwise_crop_point_to_frame(
        point,
        bounds,
        frame_width=frame_width,
        frame_height=frame_height,
    )


def run_bartender_roi_crop(detector, frame: np.ndarray, bounds) -> Optional[HandsResult]:
    """IMAGE ROI on an explicit crop. Rotation/restore match production."""
    if bounds is None:
        return None
    left, top, right, bottom = bounds
    crop = frame[top:bottom, left:right]
    if crop.size == 0:
        return None
    rotated_crop = cv2.rotate(crop, cv2.ROTATE_90_COUNTERCLOCKWISE)
    raw_result = detector._image_landmarker().detect(
        detector._to_mp_image(rotated_crop)
    )
    crop_hands = detector._to_hands_result(raw_result)
    if crop_hands is None:
        return None
    frame_height, frame_width = frame.shape[:2]
    restored = []
    for hand in crop_hands.hands:
        points = {
            index: restore_crop_point(
                point,
                bounds,
                frame_width=frame_width,
                frame_height=frame_height,
            )
            for index, point in hand.points.items()
        }
        restored.append(type(hand)(points=points, handedness=hand.handedness))
    return type(crop_hands)(hands=restored)


def eligible_frame_indices(
    primaries: list[Optional[HandsResult]],
    bottles: list[Optional[BottleDetection]],
    *,
    frame_width: int,
    frame_height: int,
) -> list[int]:
    indices: list[int] = []
    for index, (primary, bottle) in enumerate(zip(primaries, bottles)):
        if bottle is None:
            continue
        if _has_bartender_candidate(
            primary,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        ):
            continue
        indices.append(index)
    return indices


def compare_recoveries(
    *,
    a_ids: tuple[int, ...] | list[int],
    variant_ids: tuple[int, ...] | list[int],
) -> dict:
    a_set = set(a_ids)
    v_set = set(variant_ids)
    preserved = sorted(a_set & v_set)
    lost = sorted(a_set - v_set)
    additional = sorted(v_set - a_set)
    return {
        "preserved": preserved,
        "lost_vs_a": lost,
        "additional": additional,
        "lost_count": len(lost),
        "additional_count": len(additional),
        "preserved_all_a": len(lost) == 0,
    }


def classify_roi_outcome(
    *,
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
    bottle: Optional[BottleDetection],
    frame_width: int,
    frame_height: int,
    crop_bounds: Optional[tuple[int, int, int, int]],
) -> dict:
    valid = False
    if bottle is not None:
        valid = _has_bartender_candidate(
            recovered,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
    if valid:
        return {
            "valid_recovery": True,
            "hand_returned": True,
            "reason": VALID_RECOVERY,
        }
    reason = classify_wasted_roi(
        primary=primary,
        recovered=recovered,
        bottle=bottle,
        frame_width=frame_width,
        frame_height=frame_height,
        crop_bounds=crop_bounds,
    )
    hand_returned = recovered is not None and bool(recovered.hands)
    mapped = reason
    if reason == WASTE_DUPLICATE:
        mapped = "duplicate_unhelpful_hand"
    elif reason == WASTE_NO_HAND:
        mapped = "roi_returned_no_hand"
    elif reason == WASTE_OUTSIDE_ZONE:
        mapped = "hand_outside_bartender_zone"
    elif reason == WASTE_CROP_EXCLUDES:
        mapped = "crop_likely_excludes_hand"
    return {
        "valid_recovery": False,
        "hand_returned": hand_returned,
        "reason": mapped,
    }


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


def crop_containment(
    primary: Optional[HandsResult],
    bounds: Optional[tuple[int, int, int, int]],
    *,
    frame_width: int,
    frame_height: int,
) -> dict:
    empty = {
        "status": "no_primary_hand",
        "landmark_fraction": 0.0,
        "wrist_contained": False,
        "thumb_contained": False,
        "index_contained": False,
        "bbox_overlap": 0.0,
        "landmark_count": 0,
        "contained_count": 0,
    }
    if primary is None or not primary.hands or bounds is None:
        return empty
    hand = primary.hands[0]
    if not hand.points:
        return empty
    contained = 0
    xs: list[float] = []
    ys: list[float] = []
    for point in hand.points.values():
        xs.append(point.x * frame_width)
        ys.append(point.y * frame_height)
        if _point_in_crop(
            point, bounds, frame_width=frame_width, frame_height=frame_height
        ):
            contained += 1
    total = len(hand.points)
    fraction = contained / total if total else 0.0
    if fraction >= 1.0:
        status = "fully_inside"
    elif fraction <= 0.0:
        status = "completely_outside"
    elif fraction < 0.5:
        status = "mostly_outside"
    else:
        status = "partially_inside"
    left, top, right, bottom = bounds
    hand_left, hand_right = min(xs), max(xs)
    hand_top, hand_bottom = min(ys), max(ys)
    inter_left = max(left, hand_left)
    inter_top = max(top, hand_top)
    inter_right = min(right, hand_right)
    inter_bottom = min(bottom, hand_bottom)
    inter_w = max(0.0, inter_right - inter_left)
    inter_h = max(0.0, inter_bottom - inter_top)
    hand_area = max(0.0, (hand_right - hand_left) * (hand_bottom - hand_top))
    overlap = (inter_w * inter_h / hand_area) if hand_area > 0 else 0.0
    wrist = hand.points.get(0)
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    return {
        "status": status,
        "landmark_fraction": fraction,
        "wrist_contained": bool(
            wrist is not None
            and _point_in_crop(
                wrist, bounds, frame_width=frame_width, frame_height=frame_height
            )
        ),
        "thumb_contained": bool(
            thumb is not None
            and _point_in_crop(
                thumb, bounds, frame_width=frame_width, frame_height=frame_height
            )
        ),
        "index_contained": bool(
            index is not None
            and _point_in_crop(
                index, bounds, frame_width=frame_width, frame_height=frame_height
            )
        ),
        "bbox_overlap": overlap,
        "landmark_count": total,
        "contained_count": contained,
    }


def summarize_crop_areas(
    bottles: list[Optional[BottleDetection]],
    geometry: CropGeometry,
    *,
    frame_width: int,
    frame_height: int,
) -> dict:
    widths: list[float] = []
    heights: list[float] = []
    areas: list[float] = []
    frame_area = float(frame_width * frame_height)
    for bottle in bottles:
        if bottle is None and not geometry.full_frame:
            continue
        bounds = crop_bounds_for(
            geometry, bottle, frame_width, frame_height
        )
        if bounds is None:
            continue
        left, top, right, bottom = bounds
        width = float(right - left)
        height = float(bottom - top)
        widths.append(width)
        heights.append(height)
        areas.append(width * height)
    count = len(areas) or 1
    mean_area = sum(areas) / count if areas else 0.0
    return {
        "mean_width": (sum(widths) / count) if widths else 0.0,
        "mean_height": (sum(heights) / count) if heights else 0.0,
        "mean_area": mean_area,
        "area_fraction": (mean_area / frame_area) if frame_area else 0.0,
    }


def select_debug_examples(events: list[dict], limit: int = 8) -> list[dict]:
    preferred = ("a_success", "b_or_c_only", "all_fail", "crop_excludes")
    chosen: list[dict] = []
    seen_kinds: set[str] = set()
    for kind in preferred:
        for event in events:
            if event.get("kind") != kind:
                continue
            if kind in seen_kinds and len(chosen) >= len(preferred):
                continue
            if kind not in seen_kinds:
                chosen.append(event)
                seen_kinds.add(kind)
                break
    if len(chosen) < limit:
        for event in events:
            if event in chosen:
                continue
            chosen.append(event)
            if len(chosen) >= limit:
                break
    return chosen[:limit]


def write_crop_debug_image(
    frame: np.ndarray,
    bottle: Optional[BottleDetection],
    crops: dict[str, Optional[tuple[int, int, int, int]]],
    output_path: Path,
) -> None:
    canvas = frame.copy()
    if bottle is not None:
        cv2.rectangle(
            canvas,
            (int(round(bottle.x1)), int(round(bottle.y1))),
            (int(round(bottle.x2)), int(round(bottle.y2))),
            (0, 220, 0),
            2,
        )
    colors = {
        "A": (0, 0, 255),
        "B": (0, 220, 255),
        "C": (255, 180, 0),
        "D": (200, 200, 200),
    }
    for name, bounds in crops.items():
        if bounds is None:
            continue
        left, top, right, bottom = bounds
        color = colors.get(name, (255, 255, 255))
        cv2.rectangle(canvas, (left, top), (right, bottom), color, 2)
        cv2.putText(
            canvas,
            name,
            (left + 4, max(16, top + 16)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            color,
            1,
            cv2.LINE_AA,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), canvas)


def recommend_crop_trial(
    *,
    a_successes: int,
    b_successes: int,
    c_successes: int,
    b_lost: int,
    c_lost: int,
    b_additional: int,
    c_additional: int,
    a_recovery_rate: float,
    b_recovery_rate: float,
    c_recovery_rate: float,
    d_successes: Optional[int] = None,
    eligible: int = 0,
    b_unhelpful: int = 0,
    c_unhelpful: int = 0,
) -> dict:
    """Classify whether any experimental crop is worth a live trial."""
    def _material(lost: int, additional: int, rate: float, unhelpful: int) -> bool:
        return (
            lost == 0
            and additional >= 3
            and (rate - a_recovery_rate) >= 0.15
            and unhelpful <= 1
        )

    material_b = _material(b_lost, b_additional, b_recovery_rate, b_unhelpful)
    material_c = _material(c_lost, c_additional, c_recovery_rate, c_unhelpful)
    ceiling_rate = (
        (d_successes / eligible) if d_successes is not None and eligible else None
    )
    ceiling_still_poor = ceiling_rate is not None and ceiling_rate < 0.25
    if material_b or material_c:
        best = "B"
        if material_c and (not material_b or c_additional > b_additional):
            best = "C"
        return {
            "decision": "CANDIDATE CROP FOUND — SAFE FOR LIVE PRODUCTION TRIAL",
            "best": best,
            "root": "crop geometry",
            "live_trial": True,
        }
    if ceiling_still_poor:
        root = "both" if max(b_successes, c_successes) > a_successes else "MediaPipe limitation"
        return {
            "decision": "CROP NOT THE MAIN PROBLEM",
            "best": "A",
            "root": root,
            "live_trial": False,
        }
    if max(b_successes, c_successes) <= a_successes:
        return {
            "decision": "KEEP CURRENT CROP",
            "best": "A",
            "root": "current crop already adequate",
            "live_trial": False,
        }
    return {
        "decision": "KEEP CURRENT CROP",
        "best": "A",
        "root": "both",
        "live_trial": False,
    }
