# Phase 7 — Template-scored dynamic assessment (Wrist Stall vertical slice)

**Status:** Planned  
**Sequence:** `07` of `01 → 02 → 03 → 04 → 05 → 06 → 07 → 08`  
**Prerequisite:** Phase 6 complete enough that Teacher-reviewed custom movements work, **and** Phase 5 `assignment_attempts` + revision `spec` exist. If missing, **STOP**. Do not score into `sessions`.

## Implementing agent instructions

- Re-read current `main`, [AGENTS.md](../../AGENTS.md), [backend/AGENTS.md](../../backend/AGENTS.md), [00-master-plan.md](00-master-plan.md), Phase 6 handoff, and this file before editing.
- Work only on existing `main`. Do not create another branch.
- Implement **only this phase**. Official 12 rule modules stay intact. First merge is **Bottle + Wrist only** (`balance_stall.wrist_v1`). Do **not** add shaker, Grip, or prop-on-prop behavior in that first change.
- Teacher Movement Builder **Live Test** must use the **existing local Python CV backend** (same process as Trainee practice). No Flutter webcam. No second Teacher backend.
- Template-scored Teacher movements **never** award global XP. Persist to `assignment_attempts`.
- Do not implement [docs/dynamic-movements-proposal.md](../dynamic-movements-proposal.md) Basic Toss / throw_catch.
- Do not delete [teacher_app/](../../teacher_app/).
- Update this document’s Status and Completion report when done.

---

## 1. Status

Planned

## 2. Goal

Add a versioned, validated `AssessmentSpec` for Teacher-created movements; ship a Balance/Stall vertical slice (**Wrist Stall** as a new Teacher-created movement, not an official catalog member); reuse YOLO + MediaPipe + HoldValidator + Assessment V2; let Teachers Live Test via the existing Python backend; fall back to Teacher-reviewed when the spec is unsupported.

## 3. User-visible outcome

- Teacher Movement Builder: pick template family **Balance/Stall → Wrist Stall**. First supported vertical slice is **Bottle + Wrist only**. Teacher chooses presentation fields (title, laterality) — **not** raw CV thresholds, **not** shaker/Grip/prop-on-prop in this change.
- **Live Test:** Teacher runs a short local session on the **same** local Python backend. Result is **ephemeral** (U6): no `sessions`, no XP, no required `assignment_attempts`. No `leaderboard` writes.
- Trainee assigned a `template_scored` `balance_stall.wrist_v1` revision is automatically assessed; scores go **only** to `assignment_attempts`.
- Classroom/template scores are **controlled-client capstone data**. Do **not** describe them as tamper-proof against a hostile modified client. This limitation **does not affect global XP** because Teacher-created results are isolated from `sessions` / `leaderboard`.
- Unsupported specs: builder warns and saves as `teacher_reviewed`.
- Official Movements screen still shows only the 12 official names.

## 4. Verified current repo behavior

- All 12 official movements are hold-shaped; completion via [hold_validator.py](../../backend/assessment/hold_validator.py) and [scoring.py](../../backend/assessment/scoring.py) RubricTracker (0..3 / 0..12).
- [common_checks.py](../../backend/assessment/rules/common_checks.py) has stall proximity, stability, `pose_wrist_point()` for geometry — **not** a Wrist Stall movement.
- Calibration: [calibration.py](../../backend/assessment/calibration.py); ELIXR owns scales/thresholds in `backend/config.py`.
- `validate_movement_name` rejects unknown official names. Phase 7 must add a **parallel** validated custom-spec path (e.g. `prepare` with `assessment_spec_id` / `revision_id`) rather than injecting free-form names into the official map.
- No `eval`, no teacher-authored Python.
- [docs/dynamic-movements-proposal.md](../dynamic-movements-proposal.md) is throw/catch — **out of scope**.

## 5. Dependencies / prerequisites

- Phase 5 revision documents with `assessment_mode` + `spec` JSON.
- Phase 4 XP gate (so a mistaken `sessions` write still cannot award custom names).
- Phase 6 camera record path is separate; Live Test uses **practice/scoring** lifecycle (`prepare` → readiness → `activate` → `stop`), not submission recording.

## 6. In scope

- `AssessmentSpec` schema version `1` + Pydantic on backend + Dart parse/validate.
- Capability validator: supported template IDs vs fallback.
- Generic primitives **only** as needed for Wrist Stall (contact region, upright prop, hold duration using **ELIXR constants**, not teacher thresholds).
- New evaluator registered for locked template id **`balance_stall.wrist_v1`**.
- Flutter Teacher Live Test screen talking to existing WebSocket.
- Trainee template-scored attempts → `assignment_attempts` with rubric + `awards_global_xp: false`.
- Tests: validator rejects extra keys, executable expressions, threshold overrides, shaker/grip primitives.
- **Stop after Wrist Stall (Bottle).** Grip / prop-on-prop / shaker are **out of this first change set** and need a later human-approved follow-on (not a Phase 7 stretch in the same merge).

## 7. Explicit non-goals

- Official catalog addition of Wrist Stall.
- Teacher-defined numeric thresholds, formulas, `eval`, JS/Python snippets.
- Throw/catch / Basic Toss.
- Global XP.
- Flutter camera.
- Second CV backend.
- Deleting `teacher_app`.
- Shaker, Grip, or prop-on-prop templates in the first Wrist Stall change.
- Changing official 12 rule files except shared helpers **reuse** (allowed) or accidental edits (forbidden).

## 8. Architecture / runtime flow

```mermaid
flowchart LR
  builder[Teacher Movement Builder]
  live[Live Test]
  py[Existing local Python backend]
  yolo[YOLO plus MediaPipe]
  spec[Validated AssessmentSpec evaluator]
  result[Test result not global XP]
  builder --> live --> py --> yolo --> spec --> result
```

Trainee scored path:

```mermaid
flowchart LR
  trainee[Trainee Assigned Movements]
  py2[Same Python backend]
  attempt[assignment_attempts]
  trainee --> py2 --> attempt
```

**Prepare contract (conceptual):** protocol v1 remains; add optional fields such as `assignment_attempt_id`, `movement_revision_id`, `assessment_spec` **hash** (backend loads spec from a trusted source — **do not** accept arbitrary spec JSON from the client on `prepare` without signing/allowlisting). Recommended: backend fetches revision from Firestore **or** Flutter sends spec only after local validator, and backend **re-validates** with Pydantic and ignores unknown fields / rejects threshold overrides. Capstone constraint: Python today has **no** Firebase. Therefore:

**Trust model (required wording):** classroom/template scores are written by the Windows client after local Python inference. That is appropriate for the **controlled capstone** environment. Do **not** describe template scores as tamper-proof against a hostile modified client. Isolation from `sessions` / `leaderboard` still protects **global XP**.

Live Test: same prepare path with `live_test: true`; Flutter **must not** call `recordCompletedSession`.

## 9. Data models and persisted schema affected

`teacher_movements/.../revisions.spec` example shape (illustrative):

```json
{
  "schema_version": 1,
  "template_id": "balance_stall.wrist_v1",
  "prop": "bottle",
  "target": "wrist",
  "laterality": "either"
}
```

Forbidden keys: `threshold`, `thresholds`, `eval`, `formula`, `code`, `python`, `hold_seconds` (hold uses ELIXR `HOLD_CONFIRMATION_SECONDS` unless a **named enum** like `default` is allowed with no numeric override).

First slice **locks** `template_id` to `balance_stall.wrist_v1` and `prop` to `bottle`. Do not accept `shaker` or other targets in this change.

`assignment_attempts` rubric fields aligned with Assessment V2 (`rubric_technique` etc. or nested `rubric` map) + `performance_level`. Still `awards_global_xp: false`.

Do not add Wrist Stall to `coachingMovementNames` or `enabled_scored_movements.json`.

## 10. Authentication / authorization / privacy rules

- Live Test is local; no extra Firebase reads of trainee evidence.
- Trainee scored attempts: same Classroom Authorization create rules as Phase 5.
- Teachers read classroom rubric via attempt metadata (Classroom Authorization / frozen teacher_id). Video still Assignment Submission Authorization if a clip exists (Phase 6). Template-scored may not need video.
- Public Profile Privacy does not hide classroom rubric from assigning Teacher.

## 11. Cross-layer contracts affected

- WS `prepare` fields + `command_ack` + feedback `assessment` payload for custom spec sessions.
- Pydantic models in `backend/schemas/`.
- Dart parsers.
- README protocol notes.
- Rule engine dispatch for template_id **without** removing official `_RULES` entries.
- Possibly `session_id` lifecycle reused for Live Test but **must not** save official `sessions` rows.

## 12. Existing files that must be inspected

- [backend/assessment/rule_engine.py](../../backend/assessment/rule_engine.py)
- [backend/assessment/rules/hand_stall.py](../../backend/assessment/rules/hand_stall.py)
- [backend/assessment/rules/common_checks.py](../../backend/assessment/rules/common_checks.py)
- [backend/assessment/hold_validator.py](../../backend/assessment/hold_validator.py)
- [backend/assessment/scoring.py](../../backend/assessment/scoring.py)
- [backend/assessment/calibration.py](../../backend/assessment/calibration.py)
- [backend/config.py](../../backend/config.py)
- [backend/schemas/commands.py](../../backend/schemas/commands.py)
- [backend/tests/test_cross_layer_movement_consistency.py](../../backend/tests/test_cross_layer_movement_consistency.py)
- [lib/services/websocket_service.dart](../../lib/services/websocket_service.dart)
- [lib/data/models/ws_protocol.dart](../../lib/data/models/ws_protocol.dart)
- Phase 5 movement builder UI

## 13. Likely files to modify / create / delete

**Create:** `backend/assessment/specs/` (Pydantic AssessmentSpec, capability validator, wrist evaluator), Dart spec models, Teacher Live Test screen, tests.

**Modify:** `websocket.py` prepare/evaluate branch for spec sessions; Flutter practice/assignment runner to persist `assignment_attempts` instead of `sessions` when `origin == teacher_created`.

**Delete:** nothing in official rule modules; nothing in `teacher_app`.

## 14. Backward compatibility / migration strategy

- Official 12 paths unchanged: missing spec ⇒ existing `evaluate_movement(name)`.
- Existing Teacher-reviewed revisions stay `teacher_reviewed`.
- Unsupported stored `template_scored` revisions keep falling back to Teacher-reviewed. Grip/prop-on-prop remain future work.

## 15. Step-by-step implementation order

1. Pydantic `AssessmentSpec` v1 + tests (reject thresholds/eval/unknown keys).
2. Capability validator: **only** `balance_stall.wrist_v1` + `prop: bottle` supported; else unsupported.
3. Wrist evaluator reusing stall helpers + HoldValidator + RubricTracker; synthetic landmark tests (bottle/wrist only).
4. WS prepare branch: validate spec, do not register as official catalog name.
5. Flutter: Builder + Live Test using existing WebSocketService; assert no XP calls.
6. Trainee assignment run → `assignment_attempts` only.
7. Confirm official 12 consistency tests still pass.
8. **Stop.** Do not add shaker, Grip, or prop-on-prop in this change.
9. Update this file.

## 16. Acceptance criteria

1. `balance_stall.wrist_v1` (Bottle + Wrist) can be Live Tested via **the same** local Python backend.
2. Scores persist only to `assignment_attempts`; Live Test is ephemeral (no `sessions`, no XP).
3. Results never increase `leaderboard.total_xp`. Template scores are **not** claimed tamper-proof.
4. Official 12 evaluators unchanged in behavior (characterization tests still pass).
5. Spec cannot carry teacher raw thresholds or executable code; shaker/grip rejected.
6. Unsupported specs fallback to Teacher-reviewed.
7. Python still sole webcam owner including Live Test teardown.
8. `teacher_app` intact.

## 17. Required tests

- Pydantic: golden Wrist spec; rejects `thresholds`, `eval`, extra primitives.
- Wrist evaluator: positive / boundary / missing landmarks (`unknown`, not `unstable`).
- Rubric bounds 0..3 / 0..12.
- WS: invalid spec → protocol error; valid spec → feedback assessment.
- Flutter: Live Test does not call `recordCompletedSession`.
- Cross-layer official 12 fixture still length 12.
- FPS/hold: reuse existing hold tests patterns; no frame-count scoring.

## 18. Verification commands

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd packages\elixr_core; flutter test
backend\.venv\Scripts\python.exe -m pytest -q backend\tests
backend\.venv\Scripts\python.exe -m compileall backend\api backend\assessment backend\schemas backend\vision backend\main.py backend\config.py
flutter build windows
```

## 19. Manual verification checklist

- [ ] Teacher Live Test Wrist Stall: preview, readiness, score, stop, camera released.
- [ ] Trainee assignment: result on Teacher student/assignment UI; global XP unchanged.
- [ ] Official Hand Stall still works.
- [ ] Builder rejects a hacked spec with a numeric threshold if the UI is bypassed (or backend rejects).

## 20. Performance / storage / privacy risks

- Live Test must not leak trainee videos (none).
- Do not block asyncio on inference (`asyncio.to_thread` remains).
- Hostile spec JSON / forged rubric writes: validator + `assignment_attempts` rules are the control; **capstone client-trusted**. Global XP remains isolated.

## 21. Explicit “Do not” list

- Do not `eval` or run teacher code.
- Do not let teachers set `HOLD_*` or proximity floats.
- Do not add Wrist Stall to official 12.
- Do not implement Basic Toss.
- Do not write template scores to `sessions`.
- Do not add a Teacher-only Python service.
- Do not add Flutter `camera` dependency.
- Do not delete `teacher_app`.
- Do not expand shaker / Grip / prop-on-prop in this Wrist Stall change set.
- Do not claim classroom/template scores are tamper-proof.

## 22. Completion report template

```
Phase 7 completion
- template_id shipped: balance_stall.wrist_v1
- Prop: bottle only
- Live Test uses existing Python: yes
- Tamper-proof claim avoided: yes
- Live Test uses existing Python: yes/no
- XP isolation:
- Official 12 tests:
- Commands run:
- Not verified (camera accuracy):
```

## 23. Handoff requirements for Phase 8

1. Teacher-reviewed (Phase 6) and template-scored Wrist Stall (Phase 7) both exist.
2. Feature list vs teacher_app can be compared (Android roster vs Windows Groups, etc.).
3. No remaining required Teacher behavior lives **only** in `teacher_app` except Android packaging.
4. `teacher_app/` still present until Phase 8 gates pass.
