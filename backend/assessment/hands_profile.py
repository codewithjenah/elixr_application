"""Authoritative Hands construction profile used by production VisionSession.

Fallback movement sets are production-facing. Semantic max-hands is derived
from ``MOVEMENT_CONFIG`` via ``movement_max_hands`` so the count cannot drift
from the movement registry.
"""

from __future__ import annotations

from dataclasses import dataclass

from assessment.readiness import readiness_needs_hands, readiness_needs_pose
from assessment.rule_engine import (
    movement_is_prop_detection_only,
    movement_max_hands,
    movement_requires_hands,
    movement_requires_pose,
)
from config import MOVEMENT_CONFIG

# Session construction in api.websocket.VisionSession uses these exact sets.
HANDS_ROTATED_FALLBACK_MOVEMENTS = frozenset({"Normal Grip", "Claw Grip"})
HANDS_BARTENDER_ROI_MOVEMENTS = frozenset({"Bartender's Grip"})

# Rule modules that bind ``hands`` but do not read landmarks (pose geometry only).
# Forearm/Elbow explicitly discard hands; Reverse Forearm / Shoulder never read them.
RULE_IGNORES_HANDS = frozenset(
    {
        "Forearm Stall",
        "Elbow Stall",
        "Reverse Forearm Stall",
        "Shoulder Stall",
        "Arm Stall",
        "Upper Forearm Stall",
        "Free Practice",
    }
)

# Derived view of MOVEMENT_CONFIG["max_hands"] for tests and diagnostics.
SEMANTIC_MAX_HANDS: dict[str, int] = {
    name: movement_max_hands(name) for name in MOVEMENT_CONFIG
}


@dataclass(frozen=True)
class HandsMovementProfile:
    movement: str
    readiness_needs_hands: bool
    active_scheduled_hands: bool
    rule_uses_hands: bool
    semantic_max_hands: int
    rotated_fallback: bool
    bartender_roi_fallback: bool
    readiness_needs_pose: bool
    active_needs_pose: bool


def hands_profile_for(movement: str) -> HandsMovementProfile:
    prop_only = movement_is_prop_detection_only(movement)
    return HandsMovementProfile(
        movement=movement,
        readiness_needs_hands=readiness_needs_hands(movement),
        active_scheduled_hands=(
            not prop_only and movement_requires_hands(movement)
        ),
        rule_uses_hands=movement not in RULE_IGNORES_HANDS,
        semantic_max_hands=movement_max_hands(movement),
        rotated_fallback=(
            not prop_only and movement in HANDS_ROTATED_FALLBACK_MOVEMENTS
        ),
        bartender_roi_fallback=(
            not prop_only and movement in HANDS_BARTENDER_ROI_MOVEMENTS
        ),
        readiness_needs_pose=readiness_needs_pose(movement),
        active_needs_pose=(
            not prop_only and movement_requires_pose(movement)
        ),
    )


def all_hands_profiles() -> tuple[HandsMovementProfile, ...]:
    return tuple(hands_profile_for(name) for name in MOVEMENT_CONFIG)
