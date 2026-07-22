# Reverse Grip Accuracy Design

## Context

The current Reverse Grip rule accepts a hand when its palm is within `0.15`
normalized frame units of the center of the full bottle bounding box, then
requires the palm to sit at or below that center (`palm.y >= bottle_center.y -
0.02`). That logic does not match the supplied reverse-grip references:

- contact is on the upper neck/shoulder, not the bottle center;
- the defining orientation is pinky toward the bottle mouth and thumb toward
  the base (ice-pick / inverted fist), not merely “palm under center”;
- the rule cannot reject a Normal Grip overhand wrap or a bartender-style
  two-finger pinch when those hands land near the box center.

Normal Grip already uses neck-relative geometry and an overhand wrist/MCP
check. Reverse Grip should mirror that structure with the opposite orientation
discriminator.

## Goal

Classify a Reverse Grip as a full-hand wrap around the upper bottle neck for
either hand, with pinky toward the bottle mouth and thumb toward the base, for
the framing/orientations represented by the supplied reverse-grip photos.

Reject representative Normal Grip overhand holds, Bartender's Grip pinches,
and mid/lower bottle-body holds.

## Non-goals

- Training or adding a grip-classification model.
- Changing Flutter scoring, hold timing, feedback parsing, or the WebSocket
  schema.
- Changing the definitions of Normal Grip or Bartender's Grip.
- Adding a rotated MediaPipe hand fallback for Reverse Grip (revisit only if
  manual photo checks show primary hand detection misses).
- Committing the supplied personal photos or extracted photo landmarks.
- Adding dependencies.
- Extracting a shared grip-geometry module across all three grips in this
  pass.

## Reverse-Specific Rule

`backend/assessment/rules/reverse_grip.py` will own the rule logic. It mirrors
the Normal Grip neck geometry and fingertip wrap, then requires reverse
orientation instead of overhand.

### Candidate selection

For each hand with a palm center, select the hand whose palm is nearest a neck
anchor at the horizontal center of the bottle and 25% down from the top of the
bottle box.

### Contact zone

The upper-neck contact zone matches Normal Grip:

- vertically from above the bottle by the greater of `0.02` normalized frame
  units or 5% of bottle height, to 50% down the bottle height;
- horizontally from the bottle's left edge minus the greater of `0.04`
  normalized frame units or 75% of bottle width, to its right edge plus the
  same margin.

This includes the neck and shoulder positions shown in the reverse references
while rejecting grips around the lower body.

### Required geometry

The selected hand must satisfy these checks in order:

1. Landmarks 0 (wrist) and 9 (middle MCP) must exist. Missing core landmarks
   produce warning/`unknown` feedback rather than an exception.
2. The palm center must be inside the upper-neck contact zone.
3. Underhand wrist/MCP orientation: landmark 9 must be below landmark 0 by at
   least the greater of `0.01` normalized frame units or 20% of their 2D
   distance. This is the mirror of Normal Grip's overhand rise check.
4. Pinky-up / thumb-down: landmarks 20 (pinky tip) and 4 (thumb tip) must both
   exist, and pinky tip must be higher on the bottle than thumb tip by at
   least the greater of `0.01` normalized frame units or 15% of their 2D
   distance (`pinky.y + margin <= thumb.y` in image coordinates where `y`
   increases downward). This is the primary reverse discriminator chosen from
   the references.
5. Count fingertips 8, 12, 16, and 20 inside the contact zone. At least three
   must be present and inside it. This matches Normal Grip's full-fist wrap
   and rejects a two-finger bartender pinch.

### Feedback

Checks return the first applicable correction:

1. bottle missing: retain the existing bottle-visible error;
2. hand missing: retain the existing hand-visible warning;
3. no usable palm / missing wrist or middle MCP / missing pinky or thumb tip:
   `Keep your full hand visible around the bottle neck.`;
4. palm outside the contact zone:
   `Move your hand to the upper bottle neck.`;
5. failed underhand wrist/MCP orientation:
   `Rotate your wrist into a reverse grip.`;
6. failed pinky-up / thumb-down order:
   `Point your pinky toward the bottle mouth and thumb toward the base.`;
7. fewer than three engaged fingertips:
   `Wrap at least three fingers around the bottle neck.`;
8. all checks pass:
   `Bottle held securely with a full reverse neck grip.`

Warnings for missing landmarks use posture status `unknown`. Incorrect
geometry uses `unstable`; success uses positive feedback and `stable`.

## Data Flow

The existing flow remains unchanged. No detector fallback is enabled for
Reverse Grip in this design:

`camera frame -> bottle detector -> hand detector -> Reverse Grip rule ->
existing scorer/annotator -> existing WebSocket response -> Flutter display`

No response schema or Dart code changes are required.

## Testing

Tests will be written before production changes.

Deterministic rule tests in `backend/tests/test_rules.py` will cover:

- a reference-like right-hand reverse neck wrap (positive/`stable`);
- a mirrored/left-side reverse neck wrap (positive/`stable`);
- rejection of a Normal Grip overhand neck wrap;
- rejection when the palm is around the bottle body instead of its neck;
- rejection of a two-finger pinch with other fingertips outside the neck zone;
- rejection when pinky/thumb order is wrong despite underhand wrist/MCP;
- rejection when wrist/MCP is overhand despite pinky-up / thumb-down;
- graceful handling of incomplete hand landmarks (warning/`unknown`).

Tests use synthetic bottle boxes and hand landmarks, so they are deterministic
and do not require model downloads or personal image fixtures. After unit
tests pass, the supplied reverse-grip photos will be used for manual
validation. Complete image-to-rule validation also requires the project's
untracked `best.pt` bottle model.

Existing Normal Grip tests and session wiring tests must remain passing.
Reverse Grip continues to leave the Normal Grip rotated fallback disabled.

## Implementation Scope

The approved implementation may modify these files:

- `backend/assessment/rules/reverse_grip.py`
- `backend/tests/test_rules.py`

No Flutter, detector, dependency, generated Windows, or unrelated refactoring
changes are authorized in this pass.

## Success Criteria

- Reference-derived reverse geometry passes the rule for either hand.
- Representative Normal Grip, bartender pinch, and body-hold cases do not
  receive positive/`stable` Reverse Grip feedback.
- Existing Normal Grip behavior and backend tests remain passing.
- No new dependency, schema change, rotated fallback, or committed personal
  image is introduced.
