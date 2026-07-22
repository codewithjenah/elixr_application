# Bartender's Grip Accuracy Design

## Context

The current Bartender's Grip rule delegates to the generic `check_pinch_grip`
helper. It accepts a hand when the thumb and index tips are no more than `0.06`
normalized frame units apart and their midpoint is near the center of the full
bottle box.

That logic does not match the supplied references:

- the intended contact is at the upper neck/shoulder, not the bottle center;
- the thumb-index gap changes with hand size and slightly exceeds the fixed
  threshold in one valid reference;
- the rule does not distinguish the intended sideways, partially open
  bartender hold from a normal clenched grip, reverse grip, body hold, or pinch
  beside the bottle;
- MediaPipe misses the gripping hand in reference 3 and detects an unrelated
  lowered hand in reference 4.

Diagnostic image-mode scans at the existing `0.5` confidence found that a
counter-clockwise scan recovers reference 3. A counter-clockwise scan of a
bottle-relative upper-region crop recovers the gripping hand in reference 4.

## Goal

Recognize either-handed Bartender's Grip examples in all four supplied
orientations as a sideways hold with the thumb and extended index controlling
the bottle neck and at least two other fingers wrapping the shoulder.

Reject representative normal grips, reverse grips, bottle-body holds, and
pinches that are not on the bottle.

## Non-goals

- Training or adding a grip-classification model.
- Changing the existing Normal Grip or Reverse Grip definitions.
- Lowering MediaPipe confidence thresholds.
- Changing Flutter code, scoring, hold timing, or the WebSocket schema.
- Adding dependencies.
- Committing the supplied personal photos or extracted photo landmarks.

## Bartender-Specific Rule

`backend/assessment/rules/bartenders_grip.py` will own the rule instead of
calling the shared generic pinch helper.

### Candidate selection

For each hand with thumb-tip and index-tip landmarks, calculate its control
point as their midpoint. Select the hand whose control point is nearest an
anchor at the horizontal center of the bottle and 35% down from the top of the
bottle box.

The contact zone is:

- horizontally from the bottle's left edge minus the greater of `0.03`
  normalized frame units or 25% of bottle width, to its right edge plus the
  same margin;
- vertically from above the bottle by the greater of `0.02` normalized frame
  units or 5% of bottle height, to 60% down the bottle height.

This includes the neck and shoulder positions shown in the references while
rejecting grips around the lower body.

The remaining-finger wrap zone uses the same horizontal bounds and top as the
contact zone, but extends to 75% down the bottle height.

### Required geometry

All Euclidean distances and direction comparisons convert normalized points to
frame-scaled coordinates first (`x * FRAME_WIDTH`, `y * FRAME_HEIGHT`). This
prevents frame aspect ratio from changing the result.

The selected hand must satisfy these checks in order:

1. Landmarks 0 (wrist), 4 (thumb tip), 8 (index tip), and 9 (middle MCP) must
   exist, and the wrist-to-middle-MCP distance must be non-zero.
2. The thumb/index control point must be inside the neck/shoulder contact zone.
3. Thumb-index distance must be no more than 45% of the wrist-to-middle-MCP
   distance. This replaces the frame-scale-dependent fixed pinch threshold.
4. The hand axis must be primarily sideways:
   its frame-scaled horizontal displacement must be at least `1.10` times its
   frame-scaled vertical displacement.
5. Calculate index extension as straight index-MCP-to-tip distance divided by
   the index-MCP-to-PIP-to-DIP-to-tip path length. The complete index chain
   must exist and its extension ratio must be `0.70` or greater.
6. At least two of the middle, ring, and little fingertips (landmarks 12, 16,
   and 20) must exist and be inside the remaining-finger wrap zone.

The sideways-axis and index-extension checks jointly distinguish the supplied
bartender references from the prior normal-grip references. A sideways but
clenched fist fails index extension; an open but vertically aligned normal or
reverse hold fails orientation.

### Feedback

Checks return the first applicable correction:

1. bottle missing: retain the existing bottle-visible error;
2. hand missing: retain the existing hand-visible warning;
3. an incomplete index chain, fewer than two other fingertips, or missing core
   landmarks:
   `Keep your full gripping hand visible.`;
4. control point outside the contact zone:
   `Grip the bottle at the upper neck and shoulder.`;
5. thumb/index gap too large:
   `Secure the neck between your thumb and index finger.`;
6. hand axis not sideways:
   `Turn your hand sideways for a bartender's grip.`;
7. index finger not sufficiently extended:
   `Extend your index finger along the bottle neck.`;
8. fewer than two other fingertips in the wrap zone:
   `Wrap your other fingers around the bottle shoulder.`;
9. all checks pass:
   `Good bartender's grip on the neck and shoulder.`

Warnings for missing landmarks use posture status `unknown`. Incorrect geometry
uses `unstable`; success uses positive feedback and `stable`.

## Bottle-Guided Hand Fallback

The whole-frame video scan remains the primary path. The existing clockwise
fallback remains exclusive to Normal Grip.

`HandsDetector` will add a `bartender_roi_fallback: bool = False` constructor
option and an optional bottle argument to
`detect(frame, bottle: Optional[BottleDetection] = None)`. Existing callers
that pass only a frame retain the current behavior. `VisionSession` enables
the new option only for the exact movement name `Bartender's Grip`; Normal
Grip continues to enable only `rotated_fallback`.

For the exact movement name `Bartender's Grip`, `VisionSession` will pass the
current highest-confidence bottle to `HandsDetector`. The bartender fallback
runs only when:

- a bottle exists; and
- the primary result has no hand whose thumb/index control point is inside the
  rule's neck/shoulder contact zone.

The fallback will:

1. Build a crop centered on the bottle with width 2.5 times bottle width,
   clamped to the frame.
2. Use a vertical crop from 5% of bottle height above the box to 65% down its
   height, also clamped to the frame.
3. Rotate the crop 90 degrees counter-clockwise.
4. Scan it with the lazily-created image-mode hand landmarker at the existing
   `0.5` confidence settings.
5. Convert a returned rotated point `(x_rotated, y_rotated)` to crop
   coordinates `(1 - y_rotated, x_rotated)`, then map it from the crop into
   full-frame normalized coordinates.
6. Prioritize the recovered hand and merge it with any unrelated primary hand,
   capped at the detector's configured maximum hand count.

An absent bottle, invalid crop, or fallback miss returns the primary result.
Current-frame landmarks are never cached.

## Data Flow

`camera frame -> bottle detector -> primary hand scan -> conditional bartender
crop scan -> Bartender's Grip rule -> existing scorer/annotator -> existing
WebSocket response -> Flutter display`

No response contract changes.

## Testing

Tests will be written before production changes.

Deterministic rule tests will cover:

- reference-like right- and left-side bartender holds;
- a valid wider thumb/index gap that the old fixed threshold rejected;
- a normal clenched grip;
- a vertically aligned normal grip;
- a reverse/body hold below the contact zone;
- a pinch outside the bottle contact zone;
- an overly open thumb/index gap;
- a curled index despite other extended fingers;
- too few remaining fingertips around the shoulder;
- missing core landmarks or an incomplete index chain.

Detector and session tests will cover:

- no fallback after a primary hand is found near the upper bottle;
- fallback after a complete primary miss;
- fallback when the primary result contains only an unrelated distant hand;
- counter-clockwise crop-coordinate restoration;
- recovered-hand priority and maximum-hand capping;
- bartender-only session wiring;
- preservation of the existing Normal Grip fallback behavior.

Verification will include:

- focused red/green pytest runs for each behavior;
- the complete backend test module;
- Python package compilation;
- patch-format checks;
- manual hand-recovery validation against all four supplied bartender photos;
- manual rejection checks against the prior normal-grip photo set.

The photos remain external diagnostic inputs. End-to-end image classification
cannot be claimed without the project's untracked `best.pt` bottle model.

## Implementation Scope

The approved implementation may modify these four files:

- `backend/assessment/rules/bartenders_grip.py`
- `backend/vision/hands_detector.py`
- `backend/api/websocket.py`
- `backend/tests/test_rules.py`

No Flutter, dependency, generated Windows, or unrelated refactoring changes are
authorized.

## Success Criteria

- All four supplied bartender references recover the gripping hand.
- Reference-derived bartender geometry passes the rule for either hand.
- Representative normal, reverse, body, and off-bottle pinch cases do not
  receive positive/stable Bartender's Grip feedback.
- Fallback inference is skipped when the primary hand is already near the
  bottle's upper region.
- Existing Normal Grip behavior and backend tests remain passing.
- No new dependency, schema change, or committed personal image is introduced.
