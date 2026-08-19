# Phase 3 — Teacher Dashboard, Students, and progress

**Status:** Complete after Phase 3 historical-provenance backfill (2026-08-19); Flutter/planner checks passed; Firestore emulator 205/206 with one unrelated daily-quest flake; production backfill and manual checklist remain **Not verified**  
**Sequence:** `03` of `01 → 02 → 03 → 04 → 05 → 06 → 07 → 08`  
**Prerequisite:** Phase 2 complete.

## Implementing agent instructions

- Re-read current `main`, [AGENTS.md](../../AGENTS.md), [00-master-plan.md](00-master-plan.md), Phase 2 handoff, and this file before editing.
- Work only on existing `main`. Do not create another branch.
- Implement **only this phase**. Do not implement leaderboard tabs, assignments, video, or template scoring.
- Do not delete [teacher_app/](../../teacher_app/).
- Reuse `elixr_core` progress/coaching repositories; do not copy teacher_app Material widgets.
- Update this document’s Status and Completion report when done.

---

## 1. Status

**Complete after Phase 3 historical-provenance backfill (2026-08-19).** Group-backed create was already correct. Teacher list queries are discriminant-scoped (`group_id` or `authorization_source`). Historical notes created before `authorization_source` existed are omitted from the legacy LIST until a controlled Admin backfill stamps `authorization_source: "legacy_link"`. Production backfill was **not** executed. Phase 4 was not started.

## 2. Goal

Give Teachers a Fluent Dashboard, a Students list with filter/search, a student detail surface that respects the five authorization layers, and coaching notes — including explicit empty states when Progress Access is absent and when Public Profile Privacy is locked.

## 3. User-visible outcome

- **Dashboard:** active groups, deduplicated approved students, pending join queue, per-group approved/pending counts.
- **Students:** aggregated roster with search, group filter, and status filter (default emphasizes approved).
- **Student detail:** classroom gate first; Progress Access via `watchTeacherLinks`; sanitized progress only when both gates pass; private-profile badge without blocking classroom identity or progress when consent exists.
- **Coaching:** selected Group controls Group-backed history and new notes; legacy approved-link notes remain on `teacher_app` via provenance-scoped list.

## 4. Verified current behavior

- `GroupRepository.watchTeacherMemberships({ teacherId })` — teacher-scoped, `created_at` DESC.
- Windows student detail uses teacher-wide link stream (not per-link GET) for Progress Access compatibility.
- Windows Group-backed coaching history queries `teacher_id` + `trainee_id` + `group_id` + `created_at`/`__name__` DESC.
- Legacy `fetchForTeacher` (no `groupId`) queries `authorization_source == 'legacy_link'` so it cannot mix Group-backed notes.
- `CoachingNote.groupId` optional and immutable; new Group-backed notes do not write `authorization_source`.
- `TeacherProgressRepository` provided in `lib/app.dart`.
- Phase 4+ placeholders (Leaderboard, Movements) unchanged.

## 5. Actual files created

- `lib/features/teacher/dashboard/teacher_dashboard_controller.dart`
- `lib/features/teacher/dashboard/teacher_dashboard_screen.dart`
- `lib/features/teacher/students/teacher_student_models.dart`
- `lib/features/teacher/students/teacher_students_controller.dart`
- `lib/features/teacher/students/teacher_students_screen.dart`
- `lib/features/teacher/students/teacher_student_detail_controller.dart`
- `lib/features/teacher/students/teacher_student_detail_screen.dart`
- `lib/features/teacher/students/teacher_student_coaching_section.dart`
- `test/features/teacher/teacher_phase3_test_support.dart`
- `test/features/teacher/dashboard/teacher_dashboard_controller_test.dart`
- `test/features/teacher/students/teacher_students_controller_test.dart`
- `test/features/teacher/students/teacher_student_detail_controller_test.dart`
- `test/features/teacher/students/teacher_student_detail_screen_test.dart` (correction pass)
- `test/features/teacher/students/teacher_student_coaching_section_test.dart` (correction pass)
- `packages/elixr_core/test/repositories/firebase_coaching_note_repository_test.dart` (correction pass + historical backfill visibility)
- `scripts/backfill_legacy_coaching_provenance.dart` (pointer)
- `scripts/legacy_coaching_provenance/` (planner, Admin CLI, planner tests)

## 6. Actual files modified

See the original Phase 3 implementation plus this correction pass: coaching repository contract, Firebase/in-memory fetch, Windows coaching section, `firestore.rules`, `firestore.indexes.json`, `firestore-tests/rules.test.mjs`, coaching model validation, and this document.

## 7. Rules / index changes

- **Rules:** `teacher_coaching_notes` list is split, fail-closed:
  - Trainee receive: `trainee_id == auth`
  - Group-backed Teacher: `teacher_id == auth` + `group_id` present + `hasClassroomAuthorization`
  - Legacy Teacher: `teacher_id == auth` + `authorization_source == 'legacy_link'` + `approvedCoachingLink`
  - Account erasure list unchanged
- Create: Group-backed notes must have `group_id` and must not include `authorization_source`. New legacy notes must write `authorization_source: 'legacy_link'` and must not include `group_id`. Historical notes without either field remain GET/update/delete readable via live approved link. They are not returned by the provenance-scoped legacy LIST until the controlled Admin backfill stamps `authorization_source: "legacy_link"`. No client-side rewrite on Teacher list reads. No mixed `teacher_id`+`trainee_id` list query. No `allow list: if isSignedIn()`.
- `group_id` and `authorization_source` are immutable on update.
- Helpers `isCoachingAuthor`, `approvedClassroomCoaching`, `approvedCoachingLink`, `hasClassroomAuthorization` were not loosened.
- **Indexes added (existing coaching indexes retained):**
  - `teacher_id ASC, trainee_id ASC, group_id ASC, created_at DESC, __name__ DESC`
  - `teacher_id ASC, trainee_id ASC, authorization_source ASC, created_at DESC, __name__ DESC`

## 8. Tests

- Dashboard / Students / student-detail controller tests preserved.
- Widget: waitingForAccess copy, private-profile badge, unauthorized UID, progress ready/empty/withdrawn, Group coaching + selected-group reload.
- Repository: FakeFirebaseFirestore Group A/B scoping, pagination, legacy provenance write, historical-note visibility only after provenance stamp, create/update/delete `group_id`.
- Planner: `scripts/legacy_coaching_provenance` eligibility, skip buckets, idempotence, batch chunking.
- Firestore emulator: exact production Teacher Group-backed and legacy collection queries (not getDoc-only). Rules unchanged in this backfill pass.

## 9. Verification commands (executed)

```powershell
dart format --output=none --set-exit-if-changed lib test packages/elixr_core/lib packages/elixr_core/test  # 0 changed
flutter analyze   # 0 errors; 15 pre-existing infos/warnings (exit 1)
flutter test      # 1190 passed
cd packages\elixr_core; flutter test   # 80 passed
cd ..\..\teacher_app; flutter test     # 95 passed
cd firestore-tests; npm test           # 205 passed, 1 failed (Temurin JRE 21)
  # failure: daily_quest_boards "board is fully immutable after creation"
  # (Manila-day offset flake; unrelated to coaching). Coaching suite passed.
cd scripts\legacy_coaching_provenance; dart test  # 9 passed
flutter build windows                  # succeeded (elixr_application.exe)
```

## 10. Manual verification still required

- [ ] Live Dashboard counts match production groups/memberships.
- [ ] Students search/filter in UI.
- [ ] Group-only trainee without Progress Access → waiting state.
- [ ] Progress Access grant/withdrawal live behavior.
- [ ] Private profile badge + progress when consented.
- [ ] Unauthorized UID drill-down.
- [ ] Group-only coaching note on Trainee `/coaching`.
- [ ] Legacy link coaching unchanged against live `teacher_app`.
- [ ] Coaching does not create links or grant consent.
- [ ] Deployed rules/indexes for Group-backed Teacher list queries.

## 11. Completion report

```
Phase 3 completion + correction pass + historical provenance backfill
- States implemented: loadingClassroom, unauthorized, pending, relationshipRemoved,
  waitingForAccess, loadingProgress, ready, empty, accessWithdrawn, connectionRequired, error
- Coaching rules: Classroom Authorization OR approved link: yes
- Teacher list queries are discriminant-scoped (group_id or authorization_source): yes
- Silent link creation: no
- Optional group_id on coaching notes: yes
- Historical legacy LIST visibility: controlled Admin backfill of authorization_source only
- firestore.rules / firestore.indexes.json: unchanged in the backfill pass
- teacher_app fetchForTeacher(teacherId, traineeId) unchanged
- Commands run: see section 9
- Not verified: manual checklist section 10; production backfill not executed
- Phase 4 not started
```

## 12. Handoff requirements for Phase 4

1. Teachers can list members with Classroom Authorization.
2. Progress vs wait vs unauthorized states exist on Windows student detail.
3. Student detail route `/teacher/students/:traineeId` ready for leaderboard drill-down when authorized.
4. Group-only coaching works without silent consent links; Teacher history queries include `group_id`.
5. `teacher_app/` intact; Phase 4 not started.

## 13. Phase 3 correction pass (2026-08-19)

### Coaching list query — before

Windows `fetchForTeacher` queried `teacher_id` + `trainee_id` + `orderBy created_at/__name__` with no `group_id`. Firestore cannot prove every matching Group-backed document has Classroom Authorization for a specific Group. Exact getDoc after create did not prove the production collection query.

### Coaching list query — after

- Group context (`groupId != null`): `teacher_id`, `trainee_id`, `group_id`, `created_at DESC`, `__name__ DESC`.
- Legacy (`groupId` omitted, `teacher_app` compatible): `teacher_id`, `trainee_id`, `authorization_source == 'legacy_link'`, same orderBy. Does not return Group-backed notes.
- Broad `teacher_id` + `trainee_id` without a discriminant remains denied.

### Provenance field

`authorization_source: 'legacy_link'` is required because Firestore cannot query “`group_id` is absent” as a safe list discriminant. Group-backed notes continue to use `group_id` only. New legacy creates write provenance at create time.

Historical notes created before that field existed would otherwise stay invisible on `teacher_app` `fetchForTeacher(teacherId, traineeId)` (no `groupId`). They remain GET/update/delete accessible under a live approved link. Visibility on the legacy LIST is restored by a **controlled Admin backfill** (§14), not by relaxing list rules and not by rewriting documents during normal Teacher list reads.

### Explicit confirmations

- Group-only Teacher coaching history query works
- Unrelated Teacher denied
- Another Group does not leak notes
- Legacy coaching remains compile-compatible; new legacy lists use provenance
- No silent `teacher_student_links` creation
- No Progress/Evidence side effects
- Progress Access gate preserved
- Private profile behavior preserved
- No raw sessions access
- Achievements unchanged
- `teacher_app/` intact
- Phase 4 not started

## 14. Historical legacy provenance backfill (2026-08-19)

### Why provenance is necessary

Firestore rules authorize the query shape, they do not filter result rows after the fact. A Teacher list of `teacher_id` + `trainee_id` only can mix Group-backed notes, new legacy-link notes, and historical notes that have different authorization proofs. The production queries stay split:

- Group-backed: `teacher_id` + `trainee_id` + `group_id`
- Legacy: `teacher_id` + `trainee_id` + `authorization_source == "legacy_link"`

### Compatibility gap

Documents created before `authorization_source` existed have no `group_id` and no `authorization_source`. Exact GET/update/delete may still succeed under a live approved `teacher_student_link`. The legacy LIST does not return them, so `teacher_app` history looked empty for those notes.

### Strategy

Do **not** restore the mixed list query. Do **not** add `allow list: if isSignedIn()`. Do **not** rewrite notes during normal Flutter list reads.

Give eligible historical notes the explicit field `authorization_source: "legacy_link"` via a privileged Admin script. After that stamp, the existing provenance-scoped query returns them. Group-backed notes are never converted. No Group provenance is inferred. No links are created.

### Eligibility (all required)

- document has no `group_id`
- document has no `authorization_source`
- `teacher_id` and `trainee_id` are valid participant ids and are not equal
- deterministic `teacher_student_links/{teacherId}_{traineeId}` exists
- link `teacher_id` matches the note
- link `trainee_id` matches the note
- link `status == approved`

Then set **only** `authorization_source = "legacy_link"`. Do not alter `teacher_id`, `trainee_id`, `teacher_display_name`, `body`, `movement_name`, `created_at`, or `updated_at`.

### Commands (from `scripts/legacy_coaching_provenance`)

Requires Application Default Credentials or `--credentials=<service-account.json>`. Never commit credentials.

Dry run (default, no Firestore writes):

```powershell
cd scripts\legacy_coaching_provenance
dart pub get
dart test
npm install
node backfill.mjs --dry-run --project=elixr-app-2026
```

Write (human-approved only; **not** executed in this pass):

```powershell
cd scripts\legacy_coaching_provenance
node backfill.mjs --write --project=elixr-app-2026
```

Write mode batches updates (400 per batch, under the 500 Firestore limit), is idempotent, does not delete documents, and reports per-document failures. Eligibility is planned in Dart (`lib/legacy_coaching_provenance_planner.dart`) and applied by the Admin Node runner (`backfill.mjs`); keep those checks aligned.

### Safety

- Privileged Admin path only (`firebase-admin` in this scripts package). No new client mutation rule. The repository had no existing Admin migrator; this scripts-only package is that path.
- `firestore.rules` query split unchanged.
- `firestore.indexes.json` unchanged.
- `teacher_app` still calls `fetchForTeacher(teacherId:, traineeId:)` with no `groupId`.
- Production backfill: **Not verified** (not executed).
- Phase 4 not started.
