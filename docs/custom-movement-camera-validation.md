# Custom movement real-camera validation

This checklist validates the generic, reference-matched custom-movement path
with a physical camera and training bottle or shaker. It is intentionally
separate from automated tests: every status remains unchecked until a person
performs the scenario on the target Windows hardware.

## Before testing

- Use one selected physical camera through the normal ELIXR camera setting.
- Record all three references in the same session and note the selected prop.
- Keep the backend log. Capture the bounded `CUSTOM_CAPTURE_DIAGNOSTICS` entry
  for each accepted or rejected reference and assessment.
- Record effective processing FPS, YOLO confirmation rate, prop track changes,
  longest prop observation gap, Pose coverage, left/right Hand coverage,
  rejection reason (if any), and assessment sequence duration.
- Do not save raw frames for diagnostics.

## Camera matrix

| Status | Scenario | Reference setup | Expected behavior | Diagnostic evidence to inspect |
|---|---|---|---|---|
| [ ] PASS / [ ] FAIL | Static grip/reference | Hold a stable one-hand grip for all three references | Template is valid with prop translation and the consistently visible hand; static Pose is not made mandatory | Prop coverage is sufficient; required hand side matches references; `prop_rotation=false` |
| [ ] PASS / [ ] FAIL | Slow hand transfer | Transfer the prop slowly between visible hands | Both hands are required only if both are reliably observed across all references; assessment accepts a matching transfer | Left/right coverage and track-change count |
| [ ] PASS / [ ] FAIL | One-handed toss and same-hand catch | Keep the unused hand outside frame | One-hand template builds and assesses without requiring the unused hand | Required side, YOLO confirmation rate, longest prop gap |
| [ ] PASS / [ ] FAIL | Cross-hand toss/catch | Release with one hand and catch with the other | Left/right semantics remain distinct; matching cross-hand order scores above a wrong-hand/wrong-order attempt | Both hand coverages, release/catch events, track changes |
| [ ] PASS / [ ] FAIL | Deliberately incorrect trajectory | Perform a clearly different lateral/vertical prop path | Attempt remains observable but receives a materially lower prop-path/total score | Sequence duration and component scores |
| [ ] PASS / [ ] FAIL | Moderately different speed | Repeat the demonstrated motion faster and slower without changing its order/path | DTW tolerates moderate timing variation without losing the movement phases | Effective FPS, duration ratio, timing and path scores |
| [ ] PASS / [ ] FAIL | Brief bottle detector loss | Briefly occlude the prop near the toss apex, then reacquire it | A reasonable short loss preserves identity when prediction supports it; a long/unrelated detection is rejected or gets a new identity | YOLO confirmation rate, longest gap, prop track changes |
| [ ] PASS / [ ] FAIL | Different horizontal position/camera distance | Repeat the same motion offset in frame and at a moderate distance change | Body-relative normalization keeps a matching score when observability remains adequate | Pose/hand coverage, prop path score, effective FPS |

## Failure attribution

- Low YOLO confirmation rate with otherwise healthy FPS points first to model,
  lighting, blur, scale, or occlusion.
- Frequent prop track changes with acceptable YOLO confirmation points to
  association/gating rather than detector absence.
- Healthy prop metrics but low left/right Hand coverage points to Hands input.
- Healthy prop/Hands metrics but low Pose coverage points to Pose framing.
- A rejected reference with adequate detector coverage points to template
  validation (frame count, timestamps, modality coverage, or track gap).
- A valid capture with poor matching scores points to sequence alignment or
  performance mismatch; compare component scores and sequence duration.

## Explicit limitation

Exact bottle orientation, 180/360 rotation, and spin count are unsupported.
Axis-aligned YOLO boxes cannot supply those measurements, and templates must
continue to report `prop_rotation=false` until an orientation/keypoint model is
designed and validated.
