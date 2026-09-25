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
- Record effective processing FPS, preview FPS, YOLO confirmation rate, prop
  track changes, longest prop observation gap, Pose coverage, left/right Hand
  coverage, overlay capture-age mean/p95, overlay stale/generation rejection
  counts, visible overlay flicker (yes/no), rejection reason (if any), and
  assessment sequence duration.
- For finished Bottle rotation assessments, also record `rotation_required`,
  orientation and pair coverage, alignment coverage, rotation track stability,
  rotation evidence status, and both affected component confidences.
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
| [ ] PASS / [ ] FAIL | Brief bottle detector loss | Briefly occlude the prop near the toss apex, then reacquire it | Short real-observation gaps may remain valid within the existing prop limits; long loss is rejected. Predicted/coasted boxes provide preview continuity only and do not count as scoring evidence | YOLO confirmation rate, longest gap, prop track changes |
| [ ] PASS / [ ] FAIL | Different horizontal position/camera distance | Repeat the same motion offset in frame and at a moderate distance change | Body-relative normalization keeps a matching score when observability remains adequate | Pose/hand coverage, prop path score, effective FPS |
| [ ] PASS / [ ] FAIL | Marked Bottle flip reference | Put orange tape near the top/neck and yellow tape near the base/bottom; record three consistent projected flips | Template claims `prop_rotation=true` only with sufficient continuous, stable signed rotation evidence in every reference | Marker visibility on physical preview, prop track changes, saved capability |
| [ ] PASS / [ ] FAIL | Matching marked Bottle flip | Repeat the learned projected turn with both markers visible | Strong matching rotation evidence can earn the optional one-point bonus; movement and prop components still reflect their own observations | Rotation evidence status, bonus, component scores, signed turn behavior |
| [ ] PASS / [ ] FAIL | Temporary marker loss with Bottle detected | Obscure one tape marker during part of the flip while keeping the Bottle center detected | Assessment remains valid if all required base modalities remain observable; movement and prop scores remain based on their observations, with marker-visibility coaching | YOLO confirmation rate, orientation/pair coverage, rotation evidence status, component confidence |
| [ ] PASS / [ ] FAIL | Bottle track identity change | Force a reacquisition during a marked flip | Observations from different track IDs do not become one verified continuous rotation | Prop track changes, rotation track stability, rotation evidence status |
| [ ] PASS / [ ] FAIL | Shaker flip | Record and assess a Shaker toss using visible hands and prop trajectory | Scoring uses observable modalities; no Shaker rotation capability or turn-count claim appears | Saved `prop_rotation=false`, required modalities, prop coverage |
| [ ] PASS / [ ] FAIL | Behind-the-back occlusion | Perform a movement with the prop hidden behind the performer | A long Bottle or Shaker prop-observation gap remains invalid; no predicted box supplies assessment evidence | Longest prop observation gap, YOLO confirmation rate, rejection code |

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

## Explicit limitations

Orange top/neck and yellow base/bottom markers inside a current YOLO-confirmed
Bottle ROI provide a directed **2D projected** rotation trace. The system can
compare visible signed turns and progression; axis-aligned YOLO boxes alone
cannot supply orientation. Longitudinal roll, rotation into depth, complete
occlusion, motion blur, and frame-to-frame turn aliasing remain limitations.
Missing marker evidence prevents the optional rotation bonus; it does not prove
a successful flip or reduce movement and prop component scores. Missing prop-center evidence
still follows the strict prop-translation coverage and gap requirements.
Shaker rotation is unsupported. Long behind-the-back prop occlusion cannot be
validated from the current observations, and presentation-only coasted boxes
must not be counted as captured evidence.
