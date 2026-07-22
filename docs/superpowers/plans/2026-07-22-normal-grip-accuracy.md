# Normal Grip Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize a full-hand overhand grip around the upper bottle neck for all four supplied reference orientations while rejecting body grips, reverse grips, and two-finger pinches.

**Architecture:** Keep classification in the Python backend. Replace whole-bottle-center proximity with bottle-relative neck, wrist-orientation, and fingertip-contact checks; add an opt-in rotated image-mode fallback to MediaPipe only when Normal Grip's primary hand scan misses.

**Tech Stack:** Python 3, pytest, OpenCV, MediaPipe Tasks, existing FastAPI WebSocket pipeline.

## Global Constraints

- Treat every supplied reference photo as a valid Normal Grip.
- Enable the rotated fallback only for the exact movement name `Normal Grip`.
- Keep MediaPipe detection and presence confidence at `0.5`; orientation fallback replaces threshold reduction.
- Do not add dependencies or change `requirements.txt`.
- Do not change Flutter/Dart files or the WebSocket response schema.
- Do not commit the supplied personal photos as test fixtures.
- Preserve the public `normal_grip.evaluate` and `HandsDetector.detect` return contracts.
- Do not touch the existing generated Windows plugin files.

## File Map

- `backend/assessment/rules/normal_grip.py`: own all Normal Grip neck geometry and feedback.
- `backend/vision/hands_detector.py`: own primary hand inference, opt-in rotated fallback inference, and coordinate restoration.
- `backend/api/websocket.py`: enable the fallback only for Normal Grip sessions.
- `backend/tests/test_rules.py`: hold deterministic rule, fallback-orchestration, coordinate, and session-wiring tests.
- `docs/superpowers/specs/2026-07-22-normal-grip-accuracy-design.md`: approved behavior reference; do not modify during implementation.

---

### Task 1: Neck-relative Normal Grip classification

**Files:**
- Modify: `backend/tests/test_rules.py:17-38`
- Modify: `backend/tests/test_rules.py:113-136`
- Replace: `backend/assessment/rules/normal_grip.py:1-34`

**Interfaces:**
- Consumes: `BottleDetection`, `HandLandmarks`, `HandsResult`, and configured `FRAME_WIDTH`/`FRAME_HEIGHT`.
- Produces: unchanged `normal_grip.evaluate` result type `tuple[RuleResult, Optional[Point2D], Optional[dict]]`.
- Produces these exact feedback strings:
  - success: `Bottle held securely with a full overhand neck grip.`
  - wrong location: `Move your hand to the upper bottle neck.`
  - wrong orientation: `Rotate your wrist into an overhand grip.`
  - incomplete wrap: `Wrap at least three fingers around the bottle neck.`
  - missing core landmarks: `Keep your full hand visible around the bottle neck.`

- [ ] **Step 1: Add reference-like and negative Normal Grip tests**

Add this helper after `_hands_near()` in `backend/tests/test_rules.py`:

```python
def _grip_hand(
    *,
    wrist: Point2D,
    middle_mcp: Point2D,
    fingertips: tuple[Point2D, Point2D, Point2D, Point2D],
    thumb_tip: Point2D | None = None,
    handedness: str = "Right",
) -> HandLandmarks:
    points = {0: wrist, 9: middle_mcp}
    points.update(
        {
            index: point
            for index, point in zip((8, 12, 16, 20), fingertips)
        }
    )
    if thumb_tip is not None:
        points[4] = thumb_tip
    return HandLandmarks(points=points, handedness=handedness)


def _evaluate_normal_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Normal Grip",
        _bottle(),
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result
```

Add these tests before `test_movement_requires_hands()`:

```python
@pytest.mark.parametrize(
    "hand",
    [
        _grip_hand(
            wrist=Point2D(0.43, 0.49),
            middle_mcp=Point2D(0.47, 0.43),
            fingertips=(
                Point2D(0.48, 0.44),
                Point2D(0.50, 0.45),
                Point2D(0.52, 0.47),
                Point2D(0.54, 0.48),
            ),
            handedness="Right",
        ),
        _grip_hand(
            wrist=Point2D(0.57, 0.49),
            middle_mcp=Point2D(0.53, 0.43),
            fingertips=(
                Point2D(0.52, 0.44),
                Point2D(0.50, 0.45),
                Point2D(0.48, 0.47),
                Point2D(0.46, 0.48),
            ),
            handedness="Left",
        ),
    ],
    ids=["right-side", "left-side"],
)
def test_normal_grip_accepts_reference_like_full_wrap(hand):
    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Bottle held securely with a full overhand neck grip."
    )


def test_normal_grip_rejects_hand_around_bottle_body():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.60),
        middle_mcp=Point2D(0.47, 0.54),
        fingertips=(
            Point2D(0.48, 0.55),
            Point2D(0.50, 0.56),
            Point2D(0.52, 0.58),
            Point2D(0.54, 0.59),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Move your hand to the upper bottle neck."


def test_normal_grip_rejects_reverse_wrist_orientation():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Rotate your wrist into an overhand grip."


def test_normal_grip_rejects_two_finger_pinch():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.49),
        middle_mcp=Point2D(0.47, 0.43),
        thumb_tip=Point2D(0.49, 0.44),
        fingertips=(
            Point2D(0.50, 0.44),
            Point2D(0.70, 0.65),
            Point2D(0.72, 0.70),
            Point2D(0.75, 0.75),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap at least three fingers around the bottle neck."
    )


def test_normal_grip_handles_missing_palm_landmarks():
    hand = HandLandmarks(
        points={0: Point2D(0.43, 0.49)},
        handedness="Right",
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == (
        "Keep your full hand visible around the bottle neck."
    )
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "normal_grip" -q
```

Expected: six failures. The current center-proximity rule returns positive for the body, reverse, and pinch cases, uses the old success message for both positive cases, and uses the generic missing-hand message for incomplete landmarks.

- [ ] **Step 3: Replace Normal Grip with neck-relative geometry**

Replace `backend/assessment/rules/normal_grip.py` with:

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
_MIN_OVERHAND_RISE = 0.01
_OVERHAND_RISE_RATIO = 0.20
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


def _is_overhand(hand: HandLandmarks) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None

    required_rise = max(
        _MIN_OVERHAND_RISE,
        _distance(wrist, middle_mcp) * _OVERHAND_RISE_RATIO,
    )
    return wrist.y - middle_mcp.y >= required_rise


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

    overhand = _is_overhand(hand)
    if overhand is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )
    if not overhand:
        return (
            RuleResult(
                feedback="Rotate your wrist into an overhand grip.",
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
                "Bottle held securely with a full overhand neck grip."
            ),
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        movement_state,
    )
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "normal_grip" -q
```

Expected: `6 passed`.

- [ ] **Step 5: Run the complete current backend test module**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `29 passed`.

- [ ] **Step 6: Commit the rule change**

Run from the repository root:

```powershell
git add backend/assessment/rules/normal_grip.py backend/tests/test_rules.py
git commit -m "feat: validate full overhand neck grip"
```

Expected: one commit containing only the rule and its tests.

---

### Task 2: Opt-in rotated hand-detection fallback

**Files:**
- Modify: `backend/tests/test_rules.py:1-14`
- Modify: `backend/tests/test_rules.py` after the Task 1 Normal Grip tests
- Replace: `backend/vision/hands_detector.py:1-55`
- Modify: `backend/api/websocket.py:57-63`

**Interfaces:**
- Produces: `HandsDetector(max_num_hands: int = 2, rotated_fallback: bool = False)`.
- Preserves: `HandsDetector.detect(frame: np.ndarray) -> Optional[HandsResult]`.
- Produces private orchestration seams `_detect_primary(frame)` and `_detect_rotated(frame)` for deterministic tests.
- Produces coordinate helper `_clockwise_point_to_original(point: Point2D) -> Point2D`.
- `VisionSession` passes `rotated_fallback=True` only for `movement == "Normal Grip"`.

- [ ] **Step 1: Add fallback orchestration, coordinate, and session-wiring tests**

Replace the initial `import pytest` line in `backend/tests/test_rules.py` with:

```python
import numpy as np
import pytest

from api import websocket as websocket_api
from vision import hands_detector as hands_detector_module
```

Keep the existing assessment and `vision.types` imports below them.

Add this test double after `_evaluate_normal_grip()`:

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
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_rotated(self, frame):
        self.fallback_calls += 1
        return self._fallback_result
```

Add these tests after the Task 1 Normal Grip tests:

```python
def test_clockwise_point_is_restored_to_original_coordinates():
    restored = hands_detector_module._clockwise_point_to_original(
        Point2D(0.20, 0.25)
    )

    assert restored.x == pytest.approx(0.25)
    assert restored.y == pytest.approx(0.80)


def test_hand_detector_uses_rotated_fallback_after_primary_miss():
    expected = _hands_near()
    detector = _StubHandsDetector(
        rotated_fallback=True,
        primary_result=None,
        fallback_result=expected,
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is expected
    assert detector.fallback_calls == 1


def test_hand_detector_does_not_fallback_after_primary_hit():
    expected = _hands_near()
    detector = _StubHandsDetector(
        rotated_fallback=True,
        primary_result=expected,
        fallback_result=None,
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is expected
    assert detector.fallback_calls == 0


def test_hand_detector_skips_rotated_fallback_when_disabled():
    detector = _StubHandsDetector(
        rotated_fallback=False,
        primary_result=None,
        fallback_result=_hands_near(),
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is None
    assert detector.fallback_calls == 0


def test_only_normal_grip_session_enables_rotated_fallback(monkeypatch):
    fallback_settings = []

    class RecordingHandsDetector:
        def __init__(self, *, rotated_fallback: bool = False):
            fallback_settings.append(rotated_fallback)

    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        RecordingHandsDetector,
    )

    websocket_api.VisionSession("Normal Grip")
    websocket_api.VisionSession("Reverse Grip")

    assert fallback_settings == [True, False]
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "rotated_fallback or clockwise_point" -q
```

Expected: five failures because the point-restoration helper, fallback orchestration, constructor flag, and Normal Grip session wiring do not exist yet.

- [ ] **Step 3: Implement primary and rotated fallback detection**

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
from vision.types import HandLandmarks, HandsResult, Point2D

logger = logging.getLogger(__name__)


def _clockwise_point_to_original(point: Point2D) -> Point2D:
    return Point2D(x=point.y, y=1.0 - point.x)


class HandsDetector:
    def __init__(
        self,
        max_num_hands: int = 2,
        rotated_fallback: bool = False,
    ):
        self._model_path = ensure_hand_model()
        self._max_num_hands = max_num_hands
        self._rotated_fallback = rotated_fallback
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

    @staticmethod
    def _to_mp_image(frame: np.ndarray) -> mp.Image:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        return mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

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
                point = Point2D(x=landmark.x, y=landmark.y)
                if rotated:
                    point = _clockwise_point_to_original(point)
                points[idx] = point

            hands.append(
                HandLandmarks(points=points, handedness=label)
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
        if self._fallback_landmarker is None:
            self._fallback_landmarker = self._create_landmarker(
                vision.RunningMode.IMAGE
            )

        rotated_frame = cv2.rotate(
            frame,
            cv2.ROTATE_90_CLOCKWISE,
        )
        result = self._fallback_landmarker.detect(
            self._to_mp_image(rotated_frame)
        )
        return self._to_hands_result(result, rotated=True)

    def detect(self, frame: np.ndarray) -> Optional[HandsResult]:
        hands = self._detect_primary(frame)
        if hands is not None or not self._rotated_fallback:
            return hands
        return self._detect_rotated(frame)

    def close(self) -> None:
        self._landmarker.close()
        if self._fallback_landmarker is not None:
            self._fallback_landmarker.close()
```

- [ ] **Step 4: Enable the fallback only for Normal Grip sessions**

In `backend/api/websocket.py`, replace the `HandsDetector` construction in `VisionSession.__init__` with:

```python
self.hands_detector = HandsDetector(
    rotated_fallback=movement == "Normal Grip"
)
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -k "rotated_fallback or clockwise_point" -q
```

Expected: `5 passed`.

- [ ] **Step 6: Validate the fallback against all four supplied photos**

Run from `backend/`:

```powershell
@'
import cv2

from vision.hands_detector import HandsDetector

paths = [
    r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-96f66559-4c5d-4794-995a-959991ead22a.png",
    r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-2b0fab08-bb03-4835-a14f-f71f07bcf28e.png",
    r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-9d9b78f6-3828-42bb-88eb-28c1927c9dfb.png",
    r"C:\Users\Jiro\.cursor\projects\c-Users-Jiro-Documents-CapstoneProjects-System-elixr-app-elixr-application\assets\c__Users_Jiro_AppData_Roaming_Cursor_User_workspaceStorage_4eba8fb9cebb2cfca1f3d2a171dc8b72_images_image-4ba5d008-e3a1-46d2-b185-7b1530ca2a6f.png",
]

detector = HandsDetector(rotated_fallback=True)
try:
    for index, path in enumerate(paths, 1):
        frame = cv2.imread(path)
        result = detector.detect(frame)
        count = 0 if result is None else len(result.hands)
        print(f"{index}:{count}")
        assert count >= 1
finally:
    detector.close()
'@ | python -
```

Expected:

```text
1:1
2:1
3:1
4:1
```

- [ ] **Step 7: Run the complete backend test module**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `34 passed`.

- [ ] **Step 8: Commit the fallback and wiring**

Run from the repository root:

```powershell
git add backend/vision/hands_detector.py backend/api/websocket.py backend/tests/test_rules.py
git commit -m "feat: recover sideways normal grip hands"
```

Expected: one commit containing only fallback detection, Normal Grip wiring, and their tests.

---

### Task 3: Final verification

**Files:**
- Verify only: `backend/assessment/rules/normal_grip.py`
- Verify only: `backend/vision/hands_detector.py`
- Verify only: `backend/api/websocket.py`
- Verify only: `backend/tests/test_rules.py`

**Interfaces:**
- Verifies all interfaces and constraints produced by Tasks 1 and 2.
- Produces no source changes unless a verification command exposes a defect.

- [ ] **Step 1: Run all backend rule tests from a clean process**

Run from `backend/`:

```powershell
python -m pytest tests/test_rules.py -q
```

Expected: `34 passed`.

- [ ] **Step 2: Compile the changed Python packages**

Run from `backend/`:

```powershell
python -m compileall -q assessment api vision
```

Expected: exit code `0` with no syntax errors.

- [ ] **Step 3: Check patch formatting**

Run from the repository root:

```powershell
git diff --check HEAD~2..HEAD
```

Expected: exit code `0` with no output.

- [ ] **Step 4: Confirm only authorized files changed**

Run from the repository root:

```powershell
git status --short
```

Expected: no uncommitted backend or Dart changes. The user's pre-existing generated Windows plugin modifications may remain and must not be staged, reverted, or committed.

- [ ] **Step 5: Record the model-boundary limitation in the handoff**

State that hand detection was validated against all four supplied photos, while complete bottle-plus-rule inference could not be replayed from the photos because `best.pt` is not present in the repository. Do not claim end-to-end image classification without that model.
