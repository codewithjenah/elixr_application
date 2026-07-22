# Reverse Grip Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize a full-hand reverse (pinky-up / thumb-down) wrap around the upper bottle neck for either hand while rejecting Normal Grip overhands, bartender pinches, and body holds.

**Architecture:** Keep classification in the Python backend. Replace whole-bottle-center proximity and palm-below-center checks with the same neck-relative geometry as Normal Grip, plus mirrored underhand wrist/MCP and explicit pinky-above-thumb discriminators. No detector fallback in this pass.

**Tech Stack:** Python 3, pytest, existing FastAPI WebSocket pipeline, MediaPipe hand landmarks (already supplied by the session).

## Global Constraints

- Treat every supplied reverse-grip reference photo as a valid Reverse Grip.
- Do not enable rotated hand fallback for Reverse Grip.
- Do not add dependencies or change `requirements.txt`.
- Do not change Flutter/Dart files or the WebSocket response schema.
- Do not commit the supplied personal photos as test fixtures.
- Preserve the public `reverse_grip.evaluate` return contract `tuple[RuleResult, Optional[Point2D], Optional[dict]]`.
- Do not touch generated Windows plugin files.
- Do not change Normal Grip or Bartender's Grip definitions.
- Authorized files only: `backend/assessment/rules/reverse_grip.py`, `backend/tests/test_rules.py`.

## File Map

- `backend/assessment/rules/reverse_grip.py`: own all Reverse Grip neck geometry, reverse orientation checks, and feedback.
- `backend/tests/test_rules.py`: hold deterministic reverse rule positives/negatives; reuse existing `_grip_hand` helper.
- `docs/superpowers/specs/2026-07-22-reverse-grip-accuracy-design.md`: approved behavior reference; do not modify during implementation.

---

### Task 1: Neck-relative Reverse Grip classification

**Files:**
- Modify: `backend/tests/test_rules.py` (add `_evaluate_reverse_grip` and reverse tests after the Normal Grip tests)
- Replace: `backend/assessment/rules/reverse_grip.py`

**Interfaces:**
- Consumes: `BottleDetection`, `HandLandmarks`, `HandsResult`, and configured `FRAME_WIDTH`/`FRAME_HEIGHT`.
- Produces: unchanged `reverse_grip.evaluate` result type `tuple[RuleResult, Optional[Point2D], Optional[dict]]`.
- Produces these exact feedback strings:
  - success: `Bottle held securely with a full reverse neck grip.`
  - wrong location: `Move your hand to the upper bottle neck.`
  - wrong wrist/MCP: `Rotate your wrist into a reverse grip.`
  - wrong pinky/thumb order: `Point your pinky toward the bottle mouth and thumb toward the base.`
  - incomplete wrap: `Wrap at least three fingers around the bottle neck.`
  - missing core landmarks: `Keep your full hand visible around the bottle neck.`

- [ ] **Step 1: Add reverse grip helper and failing tests**

Add this helper after `_evaluate_normal_grip` in `backend/tests/test_rules.py`:

```python
def _evaluate_reverse_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Reverse Grip",
        _bottle(),
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result
```

Add these tests after `test_normal_grip_handles_missing_palm_landmarks` and before `test_clockwise_point_is_restored_to_original_coordinates`:

```python
@pytest.mark.parametrize(
    "hand",
    [
        _grip_hand(
            wrist=Point2D(0.43, 0.43),
            middle_mcp=Point2D(0.47, 0.49),
            thumb_tip=Point2D(0.46, 0.49),
            fingertips=(
                Point2D(0.48, 0.48),
                Point2D(0.50, 0.46),
                Point2D(0.52, 0.44),
                Point2D(0.54, 0.42),
            ),
            handedness="Right",
        ),
        _grip_hand(
            wrist=Point2D(0.57, 0.43),
            middle_mcp=Point2D(0.53, 0.49),
            thumb_tip=Point2D(0.54, 0.49),
            fingertips=(
                Point2D(0.52, 0.48),
                Point2D(0.50, 0.46),
                Point2D(0.48, 0.44),
                Point2D(0.46, 0.42),
            ),
            handedness="Left",
        ),
    ],
    ids=["right-side", "left-side"],
)
def test_reverse_grip_accepts_reference_like_full_wrap(hand):
    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Bottle held securely with a full reverse neck grip."
    )


def test_reverse_grip_rejects_hand_around_bottle_body():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.58),
        middle_mcp=Point2D(0.47, 0.64),
        thumb_tip=Point2D(0.46, 0.64),
        fingertips=(
            Point2D(0.48, 0.63),
            Point2D(0.50, 0.61),
            Point2D(0.52, 0.59),
            Point2D(0.54, 0.57),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Move your hand to the upper bottle neck."


def test_reverse_grip_rejects_normal_overhand_wrap():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.49),
        middle_mcp=Point2D(0.47, 0.43),
        thumb_tip=Point2D(0.46, 0.42),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Rotate your wrist into a reverse grip."


def test_reverse_grip_rejects_wrong_pinky_thumb_order():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        thumb_tip=Point2D(0.46, 0.42),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Point your pinky toward the bottle mouth and thumb toward the base."
    )


def test_reverse_grip_rejects_two_finger_pinch():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        thumb_tip=Point2D(0.46, 0.49),
        fingertips=(
            Point2D(0.48, 0.48),
            Point2D(0.70, 0.65),
            Point2D(0.72, 0.70),
            Point2D(0.54, 0.42),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap at least three fingers around the bottle neck."
    )


def test_reverse_grip_handles_missing_palm_landmarks():
    hand = HandLandmarks(
        points={0: Point2D(0.43, 0.43)},
        handedness="Right",
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == (
        "Keep your full hand visible around the bottle neck."
    )


def test_reverse_grip_handles_missing_pinky_or_thumb():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        fingertips=(
            Point2D(0.48, 0.48),
            Point2D(0.50, 0.46),
            Point2D(0.52, 0.44),
            Point2D(0.54, 0.42),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == (
        "Keep your full hand visible around the bottle neck."
    )
```

- [ ] **Step 2: Run the new reverse tests to verify they fail**

Run:

```bash
cd backend
python -m pytest tests/test_rules.py -k "reverse_grip_" -v
```

Expected: FAIL — current Reverse Grip still uses center proximity / palm-below-center and does not emit the new feedback strings.

- [ ] **Step 3: Replace `reverse_grip.py` with neck-relative reverse classification**

Replace the full contents of `backend/assessment/rules/reverse_grip.py` with:

```python
import math
from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
)
from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_NECK_ANCHOR_FRACTION = 0.25
_NECK_ZONE_BOTTOM_FRACTION = 0.50
_NECK_ZONE_TOP_MARGIN_FRACTION = 0.05
_NECK_ZONE_HORIZONTAL_MARGIN_FRACTION = 0.75
_MIN_TOP_MARGIN = 0.02
_MIN_HORIZONTAL_MARGIN = 0.04
_MIN_UNDERHAND_DROP = 0.01
_UNDERHAND_DROP_RATIO = 0.20
_MIN_PINKY_THUMB_SEPARATION = 0.01
_PINKY_THUMB_SEPARATION_RATIO = 0.15
_FINGERTIP_INDICES = (8, 12, 16, 20)
_REQUIRED_FINGERTIPS = 3

ContactZone = tuple[float, float, float, float]


def _distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _neck_anchor(bottle: BottleDetection) -> Point2D:
    bottle_height = bottle.y2 - bottle.y1
    return Point2D(
        x=((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH,
        y=(
            bottle.y1 + bottle_height * _NECK_ANCHOR_FRACTION
        ) / FRAME_HEIGHT,
    )


def _neck_contact_zone(bottle: BottleDetection) -> ContactZone:
    left = bottle.x1 / FRAME_WIDTH
    top = bottle.y1 / FRAME_HEIGHT
    right = bottle.x2 / FRAME_WIDTH
    bottle_width = (bottle.x2 - bottle.x1) / FRAME_WIDTH
    bottle_height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _NECK_ZONE_HORIZONTAL_MARGIN_FRACTION,
    )
    top_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _NECK_ZONE_TOP_MARGIN_FRACTION,
    )
    bottom = top + bottle_height * _NECK_ZONE_BOTTOM_FRACTION

    return (
        left - horizontal_margin,
        top - top_margin,
        right + horizontal_margin,
        bottom,
    )


def _is_in_zone(
    point: Optional[Point2D],
    zone: ContactZone,
) -> bool:
    if point is None:
        return False
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom


def _nearest_hand_to_anchor(
    hands: HandsResult,
    anchor: Point2D,
) -> tuple[Optional[HandLandmarks], Optional[Point2D]]:
    nearest_hand: Optional[HandLandmarks] = None
    nearest_palm: Optional[Point2D] = None
    nearest_distance = float("inf")

    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        distance = _distance(palm, anchor)
        if distance < nearest_distance:
            nearest_hand = hand
            nearest_palm = palm
            nearest_distance = distance

    return nearest_hand, nearest_palm


def _is_underhand(hand: HandLandmarks) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None

    required_drop = max(
        _MIN_UNDERHAND_DROP,
        _distance(wrist, middle_mcp) * _UNDERHAND_DROP_RATIO,
    )
    return middle_mcp.y - wrist.y >= required_drop


def _is_pinky_above_thumb(hand: HandLandmarks) -> Optional[bool]:
    thumb_tip = hand.points.get(4)
    pinky_tip = hand.points.get(20)
    if thumb_tip is None or pinky_tip is None:
        return None

    required_separation = max(
        _MIN_PINKY_THUMB_SEPARATION,
        _distance(thumb_tip, pinky_tip) * _PINKY_THUMB_SEPARATION_RATIO,
    )
    return pinky_tip.y + required_separation <= thumb_tip.y


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    hands_check = check_hands_visible(hands)
    if hands_check:
        return hands_check, prev_hip_center, movement_state

    assert bottle is not None
    assert hands is not None

    hand, palm = _nearest_hand_to_anchor(hands, _neck_anchor(bottle))
    if hand is None or palm is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    contact_zone = _neck_contact_zone(bottle)
    if not _is_in_zone(palm, contact_zone):
        return (
            RuleResult(
                feedback="Move your hand to the upper bottle neck.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    underhand = _is_underhand(hand)
    if underhand is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )
    if not underhand:
        return (
            RuleResult(
                feedback="Rotate your wrist into a reverse grip.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    pinky_above_thumb = _is_pinky_above_thumb(hand)
    if pinky_above_thumb is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )
    if not pinky_above_thumb:
        return (
            RuleResult(
                feedback=(
                    "Point your pinky toward the bottle mouth "
                    "and thumb toward the base."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    engaged_fingertips = sum(
        _is_in_zone(hand.points.get(index), contact_zone)
        for index in _FINGERTIP_INDICES
    )
    if engaged_fingertips < _REQUIRED_FINGERTIPS:
        return (
            RuleResult(
                feedback=(
                    "Wrap at least three fingers around the bottle neck."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        RuleResult(
            feedback=(
                "Bottle held securely with a full reverse neck grip."
            ),
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        movement_state,
    )
```

- [ ] **Step 4: Run reverse tests to verify they pass**

Run:

```bash
cd backend
python -m pytest tests/test_rules.py -k "reverse_grip_" -v
```

Expected: PASS for all `reverse_grip_` tests.

- [ ] **Step 5: Run the full rules module and confirm Normal Grip is unchanged**

Run:

```bash
cd backend
python -m pytest tests/test_rules.py -v
```

Expected: PASS for the full module, including existing Normal Grip and session wiring tests. `test_evaluate_movement_runs` for Reverse Grip may now warn on `_hands_near()` (overhand-ish centered hand) instead of passing; that is acceptable as long as `feedback_type` remains one of `positive`/`warning`/`error`.

- [ ] **Step 6: Commit**

```bash
git add backend/assessment/rules/reverse_grip.py backend/tests/test_rules.py
git commit -m "feat: classify reverse grip by neck geometry"
```

---

## Plan Self-Review

1. **Spec coverage:** Goal, neck zone, underhand wrist/MCP, pinky-up/thumb-down, ≥3 fingertips, ordered feedback, synthetic tests, no fallback, two-file scope — all covered by Task 1.
2. **Placeholder scan:** No TBD/TODO; full test and implementation code included.
3. **Type consistency:** `evaluate` signature and feedback strings match the design doc.
