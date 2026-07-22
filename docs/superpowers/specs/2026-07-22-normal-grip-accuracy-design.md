# Normal Grip Accuracy Design

## Context

The current Normal Grip rule accepts a hand when its palm is within `0.15` normalized frame units of the center of the full bottle bounding box. The four supplied reference photos instead show a full-hand overhand wrap around the bottle's upper neck. This makes the current center-based check systematically offset from the intended grip and unable to reject bartender pinches or reverse grips.

MediaPipe detects the hand in reference photos 1, 2, and 4 with its existing confidence settings. It misses photo 3 at confidence thresholds from `0.5` down to `0.2`, but detects a 90-degree-clockwise copy with `0.984` confidence. The fallback must therefore address orientation rather than lower confidence.

## Goal

Classify a Normal Grip as a full-hand overhand wrap around the upper bottle neck, for either hand and for the framing/orientations represented by all four supplied photos.

## Non-goals

- Training or adding a grip-classification model.
- Restoring full-body pose requirements.
- Changing Flutter feedback parsing, scoring, or hold timing.
- Changing the definitions of Bartender's Grip or Reverse Grip.
- Committing the supplied photos, which include personal imagery, as repository fixtures.

## Design

### Hand-detection fallback

`HandsDetector` will accept an optional `rotated_fallback` constructor flag, disabled by default. `VisionSession` will enable it only when the selected movement is `Normal Grip`.

The existing video-mode scan remains the primary path. When it returns no hand:

1. Lazily create a separate image-mode MediaPipe hand landmarker with the existing `0.5` confidence settings.
2. Rotate the frame 90 degrees clockwise and scan it once.
3. Convert each returned normalized point `(x_rotated, y_rotated)` to original-frame coordinates `(y_rotated, 1 - x_rotated)`.
4. Return normal `HandsResult` data so rules and annotation need no special handling.

The separate image-mode instance prevents a rotated fallback frame from contaminating the primary video tracker's state. It is closed with the primary detector. There is no fallback cost when the primary scan succeeds, and no extra model is created until the first miss.

### Neck-relative Normal Grip rule

The rule will retain the existing bottle-visible and hand-visible guards, then:

1. Define the neck anchor at the horizontal center of the bottle bounding box and 25% down from its top.
2. Choose the hand whose palm center is nearest that anchor. Handedness does not affect acceptance.
3. Build an expanded upper-neck contact zone:
   - vertical range: from above the box by the greater of `0.02` normalized frame units or 5% of bottle height, to 50% down its height;
   - horizontal range: bottle width plus a margin of the greater of `0.04` normalized frame units or 75% of bottle width on each side.
4. Require the palm center to be inside that zone.
5. Require landmarks 0 (wrist) and 9 (middle-finger MCP). Landmark 9 must be above landmark 0 by at least the greater of `0.01` normalized frame units or 20% of their 2D distance. This is the overhand check shown consistently in all four references.
6. Count fingertips 8, 12, 16, and 20 inside the contact zone. At least three must be present and inside it. This tolerates one noisy or occluded finger while rejecting a two-finger bartender pinch.

Checks run in that order so feedback gives the most useful correction:

- palm outside zone: move the hand to the upper neck;
- failed wrist/MCP orientation: rotate to an overhand grip;
- fewer than three engaged fingertips: wrap more fingers around the neck;
- all checks pass: stable, positive Normal Grip feedback.

Missing wrist or middle-MCP landmarks produce warning/unknown feedback rather than an exception. A missing fingertip counts as not engaged; the rule still passes when the other three fingertips are in the contact zone.

## Data flow

The existing flow remains unchanged apart from the opt-in fallback:

`camera frame -> bottle detector -> hand detector (+ fallback on miss) -> Normal Grip rule -> existing scorer/annotator -> existing WebSocket response -> Flutter display`

No response schema or Dart code changes are required.

## Testing

Tests will be written before implementation.

The existing backend test module will add:

- a reference-like right-hand Normal Grip positive;
- a mirrored/left-side Normal Grip positive;
- rejection when the hand is around the bottle body instead of its neck;
- rejection of reverse wrist/MCP orientation;
- rejection of a two-finger pinch with the other fingertips outside the neck zone;
- graceful handling of incomplete hand landmarks;
- exact clockwise-rotation coordinate restoration.

Tests use synthetic bottle boxes and hand landmarks, so they are deterministic and do not require model downloads or personal image fixtures. After unit tests pass, the four supplied photos will be used for manual hand-detector validation. Complete image-to-rule validation also requires the project's untracked `best.pt` bottle model.

## Success criteria

- References 1, 2, and 4 remain detectable on the primary scan.
- Reference 3 is recovered by the rotated fallback without lowering confidence.
- Reference-like synthetic left- and right-side grips pass the new rule.
- Body grips, reverse orientations, and two-finger pinches do not receive positive/stable Normal Grip feedback.
- Existing backend tests pass.
- No new dependency or Flutter change is introduced.
