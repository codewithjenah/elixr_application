# Bartender's Grip Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize the four supplied Bartender's Grip references as a sideways extended-index neck/shoulder hold while rejecting normal, reverse, body, and off-bottle grips.

**Architecture:** Keep classification in the Python backend. Replace the shared fixed pinch check with bartender-specific, frame-scaled neck/shoulder geometry; add a bartender-only counter-clockwise MediaPipe scan of a bottle-guided crop when the primary scan has no upper-bottle hand candidate.

**Tech Stack:** Python 3, pytest, OpenCV, MediaPipe Tasks, existing FastAPI WebSocket pipeline.

## Global Constraints

- Treat all four supplied Bartender's Grip photos as valid positive references.
- Require the extended index specifically, with at least two other fingertips wrapping the bottle shoulder.
- Reject representative normal grips, reverse grips, body holds, and off-bottle pinches.
- Keep MediaPipe detection, presence, and tracking confidence at `0.5`.
- Enable the new ROI fallback only for the exact movement name `Bartender's Grip`.
- Preserve the existing clockwise fallback exclusively used by `Normal Grip`.
- Do not add dependencies or modify `requirements.txt`.
- Do not change Flutter/Dart files, scoring, hold timing, or the WebSocket response schema.
- Do not commit supplied personal photos or extracted photo landmarks.
- Modify only the four approved implementation files:
  - `backend/assessment/rules/bartenders_grip.py`
  - `backend/vision/hands_detector.py`
  - `backend/api/websocket.py`
  - `backend/tests/test_rules.py`
- Do not touch generated Windows files or unrelated build artifacts.

## File Map

- `backend/assessment/rules/bartenders_grip.py`: own all bartender-specific neck/shoulder zones, frame-scaled hand geometry, candidate selection, and feedback.
- `backend/vision/hands_detector.py`: own primary inference, Normal Grip rotation fallback, bartender bottle-ROI fallback, coordinate restoration, and result merging.
- `backend/api/websocket.py`: enable movement-specific fallback flags and pass the current primary bottle into hand detection.
- `backend/tests/test_rules.py`: hold deterministic rule, detector orchestration, coordinate, and session-wiring tests.
- `docs/superpowers/specs/2026-07-22-bartenders-grip-accuracy-design.md`: approved behavior reference; do not modify during implementation.

---

### Task 1: Bartender-specific neck/shoulder classification

**Files:**
- Modify: `backend/tests/test_rules.py:64-73`
- Add tests after: `backend/tests/test_rules.py:168`
- Replace: `backend/assessment/rules/bartenders_grip.py:1-41`

**Interfaces:**
- Consumes: `BottleDetection`, `HandLandmarks`, `HandsResult`, `Point2D`, and configured `FRAME_WIDTH`/`FRAME_HEIGHT`.
- Produces: unchanged `bartenders_grip.evaluate(...) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]`.
- Produces exact feedback:
  - success: `Good bartender's grip on the neck and shoulder.`
  - incomplete landmarks: `Keep your full gripping hand visible.`
  - wrong location: `Grip the bottle at the upper neck and shoulder.`
  - loose control: `Secure the neck between your thumb and index finger.`
  - wrong orientation: `Turn your hand sideways for a bartender's grip.`
  - curled index: `Extend your index finger along the bottle neck.`
  - incomplete wrap: `Wrap your other fingers around the bottle shoulder.`

- [ ] **Step 1: Add deterministic bartender hand helpers**

Add these helpers after `_evaluate_normal_grip()` in `backend/tests/test_rules.py`:

```python
def _bartender_hand(
    *,
    mirrored: bool = False,
    x_offset: float = 0.0,
    y_offset: float = 0.0,
    overrides: dict[int, Point2D] | None = None,
    missing: tuple[int, ...] = (),
) -> HandLandmarks:
    points = {
        0: Point2D(0.32, 0.48),
        1: Point2D(0.37, 0.47),
        2: Point2D(0.40, 0.46),
        3: Point2D(0.44, 0.455),
        4: Point2D(0.465, 0.455),
        5: Point2D(0.45, 0.45),
        6: Point2D(0.478, 0.453),
        7: Point2D(0.507, 0.456),
        8: Point2D(0.535, 0.46),
        9: Point2D(0.49, 0.47),
        10: Point2D(0.495, 0.475),
        11: Point2D(0.505, 0.482),
        12: Point2D(0.51, 0.49),
        13: Point2D(0.485, 0.485),
        14: Point2D(0.50, 0.495),
        15: Point2D(0.51, 0.503),
        16: Point2D(0.52, 0.51),
        17: Point2D(0.48, 0.50),
        18: Point2D(0.49, 0.51),
        19: Point2D(0.51, 0.52),
        20: Point2D(0.53, 0.53),
    }

    if mirrored:
        points = {
            index: Point2D(1.0 - point.x, point.y)
            for index, point in points.items()
        }

    points = {
        index: Point2D(
            point.x + x_offset,
            point.y + y_offset,
        )
        for index, point in points.items()
    }

    if overrides:
        points.update(overrides)
    for index in missing:
        points.pop(index, None)

    return HandLandmarks(
        points=points,
        handedness="Left" if mirrored else "Right",
    )


def _evaluate_bartenders_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Bartender's Grip",
        _bottle(),
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result
```

- [ ] **Step 2: Add reference-like positive and strict negative tests**

Add these tests after the helpers:

```python
@pytest.mark.parametrize(
    "hand",
    [
        _bartender_hand(),
        _bartender_hand(mirrored=True),
    ],
    ids=["right-side", "left-side"],
)
def test_bartenders_grip_accepts_reference_like_side_hold(hand):
    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Good bartender's grip on the neck and shoulder."
    )


def test_bartenders_grip_rejects_body_hold():
    result = _evaluate_bartenders_grip(
        _bartender_hand(y_offset=0.10)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Grip the bottle at the upper neck and shoulder."
    )


def test_bartenders_grip_rejects_off_bottle_pinch():
    result = _evaluate_bartenders_grip(
        _bartender_hand(x_offset=0.10)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Grip the bottle at the upper neck and shoulder."
    )


def test_bartenders_grip_rejects_overly_open_thumb_index_control():
    hand = _bartender_hand(
        overrides={
            4: Point2D(0.43, 0.455),
            7: Point2D(0.53, 0.456),
            8: Point2D(0.57, 0.46),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Secure the neck between your thumb and index finger."
    )


def test_bartenders_grip_rejects_normal_clenched_index():
    hand = _bartender_hand(
        overrides={
            4: Point2D(0.49, 0.455),
            6: Point2D(0.50, 0.45),
            7: Point2D(0.48, 0.46),
            8: Point2D(0.49, 0.455),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Extend your index finger along the bottle neck."
    )


def test_bartenders_grip_rejects_vertical_normal_grip():
    hand = _bartender_hand(
        overrides={
            0: Point2D(0.49, 0.56),
            4: Point2D(0.49, 0.455),
            8: Point2D(0.51, 0.46),
            9: Point2D(0.50, 0.47),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Turn your hand sideways for a bartender's grip."
    )


def test_bartenders_grip_requires_two_other_fingers_on_shoulder():
    hand = _bartender_hand(
        overrides={
            12: Point2D(0.70, 0.70),
            16: Point2D(0.72, 0.72),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap your other fingers around the bottle shoulder."
    )


@pytest.mark.parametrize(
    "missing",
    [
        (4,),
        (6,),
        (16, 20),
    ],
    ids=["thumb", "index-chain", "other-fingertips"],
)
def test_bartenders_grip_handles_incomplete_landmarks(missing):
    result = _evaluate_bartenders_grip(
        _bartender_hand(missing=missing)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == "Keep your full gripping hand visible."
```

- [ ] **Step 3: Run focused tests and verify RED**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "bartenders_grip" -q
```

Expected: 11 failures. The current fixed pinch rule rejects both valid wide, hand-relative grips and does not produce the new location, orientation, index-extension, wrapping, or incomplete-landmark feedback.

- [ ] **Step 4: Replace the generic pinch rule with bartender geometry**

Replace `backend/assessment/rules/bartenders_grip.py` with:

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

_CONTROL_ANCHOR_FRACTION = 0.35
_CONTACT_BOTTOM_FRACTION = 0.60
_WRAP_BOTTOM_FRACTION = 0.75
_HORIZONTAL_MARGIN_FRACTION = 0.25
_TOP_MARGIN_FRACTION = 0.05
_MIN_HORIZONTAL_MARGIN = 0.03
_MIN_TOP_MARGIN = 0.02
_MAX_CONTROL_GAP_RATIO = 0.45
_MIN_SIDEWAYS_RATIO = 1.10
_MIN_INDEX_EXTENSION = 0.70
_INDEX_CHAIN = (5, 6, 7, 8)
_OTHER_FINGERTIPS = (12, 16, 20)
_REQUIRED_OTHER_FINGERTIPS = 2

ContactZone = tuple[float, float, float, float]


def _pixel_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(
        (a.x - b.x) * FRAME_WIDTH,
        (a.y - b.y) * FRAME_HEIGHT,
    )


def _control_point(hand: HandLandmarks) -> Optional[Point2D]:
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if thumb is None or index is None:
        return None
    return Point2D(
        x=(thumb.x + index.x) / 2.0,
        y=(thumb.y + index.y) / 2.0,
    )


def _control_anchor(bottle: BottleDetection) -> Point2D:
    bottle_height = bottle.y2 - bottle.y1
    return Point2D(
        x=((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH,
        y=(
            bottle.y1
            + bottle_height * _CONTROL_ANCHOR_FRACTION
        ) / FRAME_HEIGHT,
    )


def _contact_zone(
    bottle: BottleDetection,
    *,
    bottom_fraction: float,
) -> ContactZone:
    left = bottle.x1 / FRAME_WIDTH
    top = bottle.y1 / FRAME_HEIGHT
    right = bottle.x2 / FRAME_WIDTH
    bottle_width = (bottle.x2 - bottle.x1) / FRAME_WIDTH
    bottle_height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _HORIZONTAL_MARGIN_FRACTION,
    )
    top_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _TOP_MARGIN_FRACTION,
    )
    bottom = top + bottle_height * bottom_fraction

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


def _nearest_hand_to_control_anchor(
    hands: HandsResult,
    anchor: Point2D,
) -> Optional[HandLandmarks]:
    nearest: Optional[HandLandmarks] = None
    nearest_distance = float("inf")

    for hand in hands.hands:
        control = _control_point(hand)
        if control is None:
            continue
        distance = _pixel_distance(control, anchor)
        if distance < nearest_distance:
            nearest = hand
            nearest_distance = distance

    return nearest


def _index_extension(hand: HandLandmarks) -> Optional[float]:
    points = [hand.points.get(index) for index in _INDEX_CHAIN]
    if any(point is None for point in points):
        return None

    complete = [point for point in points if point is not None]
    path_length = sum(
        _pixel_distance(a, b)
        for a, b in zip(complete, complete[1:])
    )
    if path_length <= 0:
        return None

    return _pixel_distance(complete[0], complete[-1]) / path_length


def _warning(feedback: str, posture_status: str) -> RuleResult:
    return RuleResult(
        feedback=feedback,
        feedback_type="warning",
        posture_status=posture_status,
    )


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

    hand = _nearest_hand_to_control_anchor(
        hands,
        _control_anchor(bottle),
    )
    if hand is None:
        return (
            _warning(
                "Keep your full gripping hand visible.",
                "unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    wrist = hand.points.get(0)
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    middle_mcp = hand.points.get(9)
    index_extension = _index_extension(hand)
    other_tips = [
        hand.points.get(index)
        for index in _OTHER_FINGERTIPS
    ]

    if (
        wrist is None
        or thumb is None
        or index is None
        or middle_mcp is None
        or index_extension is None
        or sum(point is not None for point in other_tips)
        < _REQUIRED_OTHER_FINGERTIPS
    ):
        return (
            _warning(
                "Keep your full gripping hand visible.",
                "unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    hand_scale = _pixel_distance(wrist, middle_mcp)
    if hand_scale <= 0:
        return (
            _warning(
                "Keep your full gripping hand visible.",
                "unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    control = _control_point(hand)
    assert control is not None

    contact_zone = _contact_zone(
        bottle,
        bottom_fraction=_CONTACT_BOTTOM_FRACTION,
    )
    if not _is_in_zone(control, contact_zone):
        return (
            _warning(
                "Grip the bottle at the upper neck and shoulder.",
                "unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if _pixel_distance(thumb, index) > (
        hand_scale * _MAX_CONTROL_GAP_RATIO
    ):
        return (
            _warning(
                "Secure the neck between your thumb and index finger.",
                "unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    horizontal = abs(middle_mcp.x - wrist.x) * FRAME_WIDTH
    vertical = abs(middle_mcp.y - wrist.y) * FRAME_HEIGHT
    if horizontal < vertical * _MIN_SIDEWAYS_RATIO:
        return (
            _warning(
                "Turn your hand sideways for a bartender's grip.",
                "unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if index_extension < _MIN_INDEX_EXTENSION:
        return (
            _warning(
                "Extend your index finger along the bottle neck.",
                "unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    wrap_zone = _contact_zone(
        bottle,
        bottom_fraction=_WRAP_BOTTOM_FRACTION,
    )
    wrapped_fingers = sum(
        _is_in_zone(point, wrap_zone)
        for point in other_tips
    )
    if wrapped_fingers < _REQUIRED_OTHER_FINGERTIPS:
        return (
            _warning(
                "Wrap your other fingers around the bottle shoulder.",
                "unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        RuleResult(
            feedback="Good bartender's grip on the neck and shoulder.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        movement_state,
    )
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "bartenders_grip" -q
```

Expected: `11 passed`.

- [ ] **Step 6: Run the complete backend rule test module**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `45 passed`.

- [ ] **Step 7: Commit the rule and tests**

Run from the repository root:

```powershell
git add backend/assessment/rules/bartenders_grip.py backend/tests/test_rules.py
git commit -m "feat: validate bartender neck grip"
```

Expected: one commit containing only the bartender rule and its deterministic tests.

---

### Task 2: Bottle-guided bartender hand fallback

**Files:**
- Modify: `backend/tests/test_rules.py:75-94`
- Add tests after: `backend/tests/test_rules.py:331`
- Replace: `backend/vision/hands_detector.py:1-124`

**Interfaces:**
- Produces: `HandsDetector(max_num_hands: int = 2, rotated_fallback: bool = False, bartender_roi_fallback: bool = False)`.
- Produces: `HandsDetector.detect(frame: np.ndarray, bottle: Optional[BottleDetection] = None) -> Optional[HandsResult]`.
- Preserves: `_detect_primary(frame)` and `_detect_rotated(frame)` behavior.
- Produces: `_detect_bartender_roi(frame, bottle)` for deterministic orchestration tests.
- Produces coordinate helper `_counterclockwise_crop_point_to_frame(...)`.
- Recovered hands are ordered before unrelated primary hands and capped at `max_num_hands`.

- [ ] **Step 1: Extend detector stubs for movement-specific fallbacks**

Replace `_StubHandsDetector` in `backend/tests/test_rules.py` and add the bartender stub immediately after it:

```python
class _StubHandsDetector(hands_detector_module.HandsDetector):
    def __init__(
        self,
        *,
        rotated_fallback: bool,
        primary_result,
        fallback_result,
    ):
        self._rotated_fallback = rotated_fallback
        self._bartender_roi_fallback = False
        self._max_num_hands = 2
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_rotated(self, frame):
        self.fallback_calls += 1
        return self._fallback_result


class _StubBartenderHandsDetector(
    hands_detector_module.HandsDetector
):
    def __init__(
        self,
        *,
        primary_result,
        fallback_result,
        max_num_hands: int = 2,
    ):
        self._rotated_fallback = False
        self._bartender_roi_fallback = True
        self._max_num_hands = max_num_hands
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_bartender_roi(self, frame, bottle):
        self.fallback_calls += 1
        return self._fallback_result
```

- [ ] **Step 2: Add coordinate, trigger, merge, and boundary tests**

Add these tests after the existing Normal Grip fallback tests:

```python
def test_counterclockwise_crop_point_is_restored_to_frame():
    restored = (
        hands_detector_module
        ._counterclockwise_crop_point_to_frame(
            Point2D(0.20, 0.25),
            (100, 50, 300, 250),
            frame_width=640,
            frame_height=480,
        )
    )

    assert restored.x == pytest.approx(0.390625)
    assert restored.y == pytest.approx(0.1875)


def test_bartender_roi_skips_near_primary_hand():
    expected = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=expected,
        fallback_result=None,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is expected
    assert detector.fallback_calls == 0


def test_bartender_roi_runs_after_primary_miss():
    expected = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=None,
        fallback_result=expected,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is not None
    assert result.hands[0] is expected.hands[0]
    assert detector.fallback_calls == 1


def test_bartender_roi_prioritizes_recovery_and_caps_hands():
    primary = HandsResult(
        hands=[
            _hand_near(0.80, 0.80),
            _hand_near(0.20, 0.80),
        ]
    )
    recovered = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=recovered,
        max_num_hands=2,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is not None
    assert len(result.hands) == 2
    assert result.hands[0] is recovered.hands[0]
    assert result.hands[1] is primary.hands[0]
    assert detector.fallback_calls == 1


def test_bartender_roi_skips_fallback_without_bottle():
    primary = HandsResult(hands=[_hand_near(0.80, 0.80)])
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=_hands_near(),
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        None,
    )

    assert result is primary
    assert detector.fallback_calls == 0


def test_bartender_roi_miss_preserves_primary_result():
    primary = HandsResult(hands=[_hand_near(0.80, 0.80)])
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=None,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is primary
    assert detector.fallback_calls == 1


def test_bartender_crop_rejects_zero_width_bottle():
    invalid = BottleDetection(
        x1=100,
        y1=100,
        x2=100,
        y2=200,
        confidence=0.9,
    )

    assert (
        hands_detector_module._bartender_crop_bounds(
            invalid,
            frame_width=640,
            frame_height=480,
        )
        is None
    )
```

- [ ] **Step 3: Run fallback tests and verify RED**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "bartender_roi or counterclockwise_crop" -q
```

Expected: seven failures. The current `detect()` signature does not accept a bottle, and the detector has no counter-clockwise crop mapping, ROI scan, distant-hand recovery, recovered-hand priority, or crop validation.

- [ ] **Step 4: Implement the bottle-guided fallback**

Replace `backend/vision/hands_detector.py` with:

```python
import logging
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from vision.model_assets import ensure_hand_model
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
)

logger = logging.getLogger(__name__)

_CONTACT_BOTTOM_FRACTION = 0.60
_HORIZONTAL_MARGIN_FRACTION = 0.25
_TOP_MARGIN_FRACTION = 0.05
_MIN_HORIZONTAL_MARGIN = 0.03
_MIN_TOP_MARGIN = 0.02
_BARTENDER_CROP_WIDTH_FACTOR = 2.5
_BARTENDER_CROP_TOP_FRACTION = 0.05
_BARTENDER_CROP_BOTTOM_FRACTION = 0.65

ContactZone = tuple[float, float, float, float]
CropBounds = tuple[int, int, int, int]


def _clockwise_point_to_original(point: Point2D) -> Point2D:
    return Point2D(x=point.y, y=1.0 - point.x)


def _counterclockwise_point_to_original(
    point: Point2D,
) -> Point2D:
    return Point2D(x=1.0 - point.y, y=point.x)


def _counterclockwise_crop_point_to_frame(
    point: Point2D,
    bounds: CropBounds,
    *,
    frame_width: int,
    frame_height: int,
) -> Point2D:
    left, top, right, bottom = bounds
    crop_point = _counterclockwise_point_to_original(point)
    return Point2D(
        x=(
            left + crop_point.x * (right - left)
        ) / frame_width,
        y=(
            top + crop_point.y * (bottom - top)
        ) / frame_height,
    )


def _control_point(hand: HandLandmarks) -> Optional[Point2D]:
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if thumb is None or index is None:
        return None
    return Point2D(
        x=(thumb.x + index.x) / 2.0,
        y=(thumb.y + index.y) / 2.0,
    )


def _bartender_contact_zone(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> ContactZone:
    left = bottle.x1 / frame_width
    top = bottle.y1 / frame_height
    right = bottle.x2 / frame_width
    bottle_width = (bottle.x2 - bottle.x1) / frame_width
    bottle_height = (bottle.y2 - bottle.y1) / frame_height

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _HORIZONTAL_MARGIN_FRACTION,
    )
    top_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _TOP_MARGIN_FRACTION,
    )

    return (
        left - horizontal_margin,
        top - top_margin,
        right + horizontal_margin,
        top + bottle_height * _CONTACT_BOTTOM_FRACTION,
    )


def _is_in_zone(point: Point2D, zone: ContactZone) -> bool:
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom


def _has_bartender_candidate(
    hands: Optional[HandsResult],
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> bool:
    if hands is None:
        return False

    zone = _bartender_contact_zone(
        bottle,
        frame_width=frame_width,
        frame_height=frame_height,
    )
    return any(
        control is not None and _is_in_zone(control, zone)
        for hand in hands.hands
        for control in [_control_point(hand)]
    )


def _bartender_crop_bounds(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> Optional[CropBounds]:
    bottle_width = bottle.x2 - bottle.x1
    bottle_height = bottle.y2 - bottle.y1
    if bottle_width <= 0 or bottle_height <= 0:
        return None

    center_x = (bottle.x1 + bottle.x2) / 2.0
    crop_width = bottle_width * _BARTENDER_CROP_WIDTH_FACTOR
    left = max(0, round(center_x - crop_width / 2.0))
    right = min(
        frame_width,
        round(center_x + crop_width / 2.0),
    )
    top = max(
        0,
        round(
            bottle.y1
            - bottle_height * _BARTENDER_CROP_TOP_FRACTION
        ),
    )
    bottom = min(
        frame_height,
        round(
            bottle.y1
            + bottle_height * _BARTENDER_CROP_BOTTOM_FRACTION
        ),
    )

    if right <= left or bottom <= top:
        return None
    return left, top, right, bottom


def _merge_hands(
    primary: Optional[HandsResult],
    recovered: Optional[HandsResult],
    *,
    max_num_hands: int,
) -> Optional[HandsResult]:
    if recovered is None or not recovered.hands:
        return primary

    primary_hands = [] if primary is None else primary.hands
    merged = (recovered.hands + primary_hands)[:max_num_hands]
    return HandsResult(hands=merged)


class HandsDetector:
    def __init__(
        self,
        max_num_hands: int = 2,
        rotated_fallback: bool = False,
        bartender_roi_fallback: bool = False,
    ):
        self._model_path = ensure_hand_model()
        self._max_num_hands = max_num_hands
        self._rotated_fallback = rotated_fallback
        self._bartender_roi_fallback = bartender_roi_fallback
        self._landmarker = self._create_landmarker(
            vision.RunningMode.VIDEO
        )
        self._fallback_landmarker: Optional[
            vision.HandLandmarker
        ] = None
        self._timestamp_ms = 0

    def _create_landmarker(
        self,
        running_mode: vision.RunningMode,
    ) -> vision.HandLandmarker:
        options = vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(
                model_asset_path=str(self._model_path)
            ),
            running_mode=running_mode,
            num_hands=self._max_num_hands,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        return vision.HandLandmarker.create_from_options(options)

    def _image_landmarker(self) -> vision.HandLandmarker:
        if self._fallback_landmarker is None:
            self._fallback_landmarker = self._create_landmarker(
                vision.RunningMode.IMAGE
            )
        return self._fallback_landmarker

    @staticmethod
    def _to_mp_image(frame: np.ndarray) -> mp.Image:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        return mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb,
        )

    @staticmethod
    def _to_hands_result(
        result,
        *,
        rotated: bool = False,
    ) -> Optional[HandsResult]:
        if not result.hand_landmarks:
            return None

        hands: list[HandLandmarks] = []
        handedness = result.handedness or []

        for i, hand_lms in enumerate(result.hand_landmarks):
            label = "Unknown"
            if i < len(handedness) and handedness[i]:
                label = handedness[i][0].category_name

            points: dict[int, Point2D] = {}
            for idx, landmark in enumerate(hand_lms):
                point = Point2D(
                    x=landmark.x,
                    y=landmark.y,
                )
                if rotated:
                    point = _clockwise_point_to_original(point)
                points[idx] = point

            hands.append(
                HandLandmarks(
                    points=points,
                    handedness=label,
                )
            )

        return HandsResult(hands=hands)

    def _detect_primary(
        self,
        frame: np.ndarray,
    ) -> Optional[HandsResult]:
        self._timestamp_ms += 33
        result = self._landmarker.detect_for_video(
            self._to_mp_image(frame),
            self._timestamp_ms,
        )
        return self._to_hands_result(result)

    def _detect_rotated(
        self,
        frame: np.ndarray,
    ) -> Optional[HandsResult]:
        rotated_frame = cv2.rotate(
            frame,
            cv2.ROTATE_90_CLOCKWISE,
        )
        result = self._image_landmarker().detect(
            self._to_mp_image(rotated_frame)
        )
        return self._to_hands_result(result, rotated=True)

    def _detect_bartender_roi(
        self,
        frame: np.ndarray,
        bottle: BottleDetection,
    ) -> Optional[HandsResult]:
        frame_height, frame_width = frame.shape[:2]
        bounds = _bartender_crop_bounds(
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        )
        if bounds is None:
            return None

        left, top, right, bottom = bounds
        crop = frame[top:bottom, left:right]
        if crop.size == 0:
            return None

        rotated_crop = cv2.rotate(
            crop,
            cv2.ROTATE_90_COUNTERCLOCKWISE,
        )
        raw_result = self._image_landmarker().detect(
            self._to_mp_image(rotated_crop)
        )
        crop_hands = self._to_hands_result(raw_result)
        if crop_hands is None:
            return None

        restored: list[HandLandmarks] = []
        for hand in crop_hands.hands:
            points = {
                index: _counterclockwise_crop_point_to_frame(
                    point,
                    bounds,
                    frame_width=frame_width,
                    frame_height=frame_height,
                )
                for index, point in hand.points.items()
            }
            restored.append(
                HandLandmarks(
                    points=points,
                    handedness=hand.handedness,
                )
            )

        return HandsResult(hands=restored)

    def detect(
        self,
        frame: np.ndarray,
        bottle: Optional[BottleDetection] = None,
    ) -> Optional[HandsResult]:
        hands = self._detect_primary(frame)

        if hands is None and self._rotated_fallback:
            hands = self._detect_rotated(frame)

        if not self._bartender_roi_fallback or bottle is None:
            return hands

        frame_height, frame_width = frame.shape[:2]
        if _has_bartender_candidate(
            hands,
            bottle,
            frame_width=frame_width,
            frame_height=frame_height,
        ):
            return hands

        recovered = self._detect_bartender_roi(frame, bottle)
        return _merge_hands(
            hands,
            recovered,
            max_num_hands=self._max_num_hands,
        )

    def close(self) -> None:
        self._landmarker.close()
        if self._fallback_landmarker is not None:
            self._fallback_landmarker.close()
```

- [ ] **Step 5: Run fallback tests and verify GREEN**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "bartender_roi or counterclockwise_crop" -q
```

Expected: `7 passed`.

- [ ] **Step 6: Re-run existing Normal Grip fallback tests**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "rotated_fallback or clockwise_point" -q
```

Expected: `5 passed`. The existing clockwise coordinate and orchestration behavior remains unchanged.

- [ ] **Step 7: Run the complete backend rule test module**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `52 passed`.

- [ ] **Step 8: Commit the fallback and tests**

Run from the repository root:

```powershell
git add backend/vision/hands_detector.py backend/tests/test_rules.py
git commit -m "feat: recover bartender grip hands"
```

Expected: one commit containing only hand fallback code and deterministic tests.

---

### Task 3: Bartender-only session wiring

**Files:**
- Modify: `backend/tests/test_rules.py:332-349`
- Add test after the fallback wiring test in: `backend/tests/test_rules.py`
- Modify: `backend/api/websocket.py:57-61`
- Modify: `backend/api/websocket.py:136-142`

**Interfaces:**
- `VisionSession("Normal Grip")` constructs `HandsDetector(rotated_fallback=True, bartender_roi_fallback=False)`.
- `VisionSession("Bartender's Grip")` constructs `HandsDetector(rotated_fallback=False, bartender_roi_fallback=True)`.
- Other movements construct both fallbacks disabled.
- `VisionSession.process_frame()` calls `hands_detector.detect(frame, bottle=bottle)`.

- [ ] **Step 1: Replace the fallback wiring test**

Replace `test_only_normal_grip_session_enables_rotated_fallback` with:

```python
def test_session_enables_only_its_grip_fallback(monkeypatch):
    fallback_settings = []

    class RecordingHandsDetector:
        def __init__(
            self,
            *,
            rotated_fallback: bool = False,
            bartender_roi_fallback: bool = False,
        ):
            fallback_settings.append(
                (rotated_fallback, bartender_roi_fallback)
            )

    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        RecordingHandsDetector,
    )

    websocket_api.VisionSession("Normal Grip")
    websocket_api.VisionSession("Bartender's Grip")
    websocket_api.VisionSession("Reverse Grip")

    assert fallback_settings == [
        (True, False),
        (False, True),
        (False, False),
    ]
```

- [ ] **Step 2: Add a process-frame bottle forwarding test**

Add this test immediately after the wiring test:

```python
def test_session_passes_primary_bottle_to_hand_detector(
    monkeypatch,
):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    bottle = _bottle()
    seen_bottles = []

    class StubCamera:
        def read(self):
            return frame

        def release(self):
            pass

    class StubBottleDetector:
        def __init__(self, *, enabled: bool):
            self.enabled = enabled

        def ensure_ready(self):
            pass

        def detect(self, current_frame):
            assert current_frame is frame
            return [bottle]

    class StubHandsDetector:
        def __init__(self, **kwargs):
            pass

        def detect(self, current_frame, bottle=None):
            assert current_frame is frame
            seen_bottles.append(bottle)
            return _hands_near()

        def close(self):
            pass

    monkeypatch.setattr(
        websocket_api,
        "CameraCapture",
        StubCamera,
    )
    monkeypatch.setattr(
        websocket_api,
        "BottleDetector",
        StubBottleDetector,
    )
    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        StubHandsDetector,
    )
    monkeypatch.setattr(
        websocket_api,
        "annotate_frame",
        lambda current_frame, *args, **kwargs: current_frame,
    )

    session = websocket_api.VisionSession("Bartender's Grip")
    try:
        message = session.process_frame()
    finally:
        session.close()

    assert message is not None
    assert seen_bottles == [bottle]
```

- [ ] **Step 3: Run session tests and verify RED**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "session_enables_only or session_passes_primary_bottle" -q
```

Expected: two failures. Bartender sessions do not yet enable the ROI flag, and `process_frame()` does not pass the bottle to hand detection.

- [ ] **Step 4: Enable the exact movement-specific fallback flags**

In `VisionSession.__init__` in `backend/api/websocket.py`, replace the current `HandsDetector` construction with:

```python
self.hands_detector = HandsDetector(
    rotated_fallback=movement == "Normal Grip",
    bartender_roi_fallback=movement == "Bartender's Grip",
)
```

- [ ] **Step 5: Pass the primary bottle into current-frame hand detection**

In `VisionSession.process_frame()`, replace:

```python
if movement_requires_hands(self.movement):
    hands = self.hands_detector.detect(frame)
else:
    hands = None
```

with:

```python
if movement_requires_hands(self.movement):
    hands = self.hands_detector.detect(
        frame,
        bottle=bottle,
    )
else:
    hands = None
```

- [ ] **Step 6: Run session tests and verify GREEN**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "session_enables_only or session_passes_primary_bottle" -q
```

Expected: `2 passed`.

- [ ] **Step 7: Run the complete backend rule test module**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `53 passed`.

- [ ] **Step 8: Commit session wiring**

Run from the repository root:

```powershell
git add backend/api/websocket.py backend/tests/test_rules.py
git commit -m "feat: wire bartender grip fallback"
```

Expected: one commit containing only session wiring and its tests.

---

### Task 4: Reference validation and final verification

**Files:**
- Verify only: `backend/assessment/rules/bartenders_grip.py`
- Verify only: `backend/vision/hands_detector.py`
- Verify only: `backend/api/websocket.py`
- Verify only: `backend/tests/test_rules.py`

**Interfaces:**
- Validates all interfaces and constraints produced by Tasks 1-3.
- Produces no source changes unless verification exposes a defect.

- [ ] **Step 1: Validate all four bartender references with external photos and manual bottle boxes**

Run from `backend/`:

```powershell
@'
import cv2

from assessment.rules import bartenders_grip
from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.hands_detector import HandsDetector
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
)

items = [
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-d2271876-58d6-4088-a34e-ce4051f8a240.png",
        (292, 270, 438, 834),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-a7085077-fbc7-4183-8c49-0b499ebf2fa0.png",
        (280, 236, 485, 1004),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-dcd29a41-448d-44cf-ac58-4625525da217.png",
        (300, 353, 490, 1008),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-911a1a02-6f78-499a-a9ca-ea707de2053f.png",
        (288, 278, 495, 1010),
    ),
]


def letterbox_geometry_for_rule(box, width, height, hands):
    scale = min(FRAME_WIDTH / width, FRAME_HEIGHT / height)
    offset_x = (FRAME_WIDTH - width * scale) / 2.0
    offset_y = (FRAME_HEIGHT - height * scale) / 2.0
    x1, y1, x2, y2 = box
    bottle = BottleDetection(
        x1=round(offset_x + x1 * scale),
        y1=round(offset_y + y1 * scale),
        x2=round(offset_x + x2 * scale),
        y2=round(offset_y + y2 * scale),
        confidence=0.9,
    )
    if hands is None:
        return bottle, None

    transformed = []
    for hand in hands.hands:
        points = {
            index: Point2D(
                x=(
                    offset_x + point.x * width * scale
                ) / FRAME_WIDTH,
                y=(
                    offset_y + point.y * height * scale
                ) / FRAME_HEIGHT,
            )
            for index, point in hand.points.items()
        }
        transformed.append(
            HandLandmarks(
                points=points,
                handedness=hand.handedness,
            )
        )
    return bottle, HandsResult(hands=transformed)


for index, (path, box) in enumerate(items, 1):
    frame = cv2.imread(path)
    height, width = frame.shape[:2]
    raw_bottle = BottleDetection(
        x1=box[0],
        y1=box[1],
        x2=box[2],
        y2=box[3],
        confidence=0.9,
    )
    detector = HandsDetector(bartender_roi_fallback=True)
    try:
        hands = detector.detect(frame, bottle=raw_bottle)
    finally:
        detector.close()

    rule_bottle, rule_hands = letterbox_geometry_for_rule(
        box,
        width,
        height,
        hands,
    )
    result, _, _ = bartenders_grip.evaluate(
        rule_bottle,
        None,
        rule_hands,
        None,
    )
    count = 0 if hands is None else len(hands.hands)
    print(
        f"{index}:hands={count},"
        f"type={result.feedback_type},"
        f"status={result.posture_status}"
    )
    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
'@ | python -
```

Expected:

```text
1:hands=1,type=positive,status=stable
2:hands=1,type=positive,status=stable
3:hands=1,type=positive,status=stable
4:hands=2,type=positive,status=stable
```

The exact hand count may be greater if MediaPipe returns another visible hand, but every result must be positive/stable.

- [ ] **Step 2: Reject the prior four Normal Grip references**

Run from `backend/`:

```powershell
@'
import cv2

from assessment.rules import bartenders_grip
from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.hands_detector import HandsDetector
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
)

items = [
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-96f66559-4c5d-4794-995a-959991ead22a.png",
        (300, 411, 426, 901),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-2b0fab08-bb03-4835-a14f-f71f07bcf28e.png",
        (264, 287, 423, 920),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-9d9b78f6-3828-42bb-88eb-28c1927c9dfb.png",
        (262, 333, 410, 912),
    ),
    (
        r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-4ba5d008-e3a1-46d2-b185-7b1530ca2a6f.png",
        (281, 211, 444, 854),
    ),
]


def letterbox_geometry_for_rule(box, width, height, hands):
    scale = min(FRAME_WIDTH / width, FRAME_HEIGHT / height)
    offset_x = (FRAME_WIDTH - width * scale) / 2.0
    offset_y = (FRAME_HEIGHT - height * scale) / 2.0
    x1, y1, x2, y2 = box
    bottle = BottleDetection(
        x1=round(offset_x + x1 * scale),
        y1=round(offset_y + y1 * scale),
        x2=round(offset_x + x2 * scale),
        y2=round(offset_y + y2 * scale),
        confidence=0.9,
    )
    if hands is None:
        return bottle, None

    transformed = []
    for hand in hands.hands:
        points = {
            index: Point2D(
                x=(
                    offset_x + point.x * width * scale
                ) / FRAME_WIDTH,
                y=(
                    offset_y + point.y * height * scale
                ) / FRAME_HEIGHT,
            )
            for index, point in hand.points.items()
        }
        transformed.append(
            HandLandmarks(
                points=points,
                handedness=hand.handedness,
            )
        )
    return bottle, HandsResult(hands=transformed)


for index, (path, box) in enumerate(items, 1):
    frame = cv2.imread(path)
    height, width = frame.shape[:2]
    detector = HandsDetector(rotated_fallback=True)
    try:
        hands = detector.detect(frame)
    finally:
        detector.close()

    rule_bottle, rule_hands = letterbox_geometry_for_rule(
        box,
        width,
        height,
        hands,
    )
    result, _, _ = bartenders_grip.evaluate(
        rule_bottle,
        None,
        rule_hands,
        None,
    )
    print(
        f"{index}:"
        f"type={result.feedback_type},"
        f"status={result.posture_status},"
        f"feedback={result.feedback}"
    )
    assert result.feedback_type != "positive"
    assert result.posture_status != "stable"
'@ | python -
```

Expected: all four print warning/non-stable results.

- [ ] **Step 3: Run the complete backend rule test module from a clean process**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `53 passed`.

- [ ] **Step 4: Compile the changed backend packages**

Run from `backend/`:

```powershell
python -m compileall -q assessment api vision
```

Expected: exit code `0` with no syntax errors.

- [ ] **Step 5: Check implementation patch formatting**

Run from the repository root:

```powershell
git diff --check HEAD~3..HEAD
```

Expected: exit code `0` with no output.

- [ ] **Step 6: Confirm only authorized implementation files changed**

Run from the repository root:

```powershell
git status --short
```

Expected: no uncommitted backend or Dart changes. The user's pre-existing generated Windows plugin and build artifacts may remain and must not be staged, reverted, or committed.

- [ ] **Step 7: Record the model-boundary limitation in the handoff**

State that all four supplied bartender photos passed hand recovery and rule classification with manually supplied bottle boxes, and all four prior Normal Grip photos were rejected. Do not claim full camera-to-result inference unless the project's custom `best.pt` bottle model is available and used during validation.
