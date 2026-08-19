# Phase 3 — Teacher Dashboard, Students, and progress

**Status:** Complete (automated verification passed; manual checklist not verified)  
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

**Complete** — automated tests and Windows build passed on 2026-08-19. Manual production checklist items remain **Not verified**.

## 2. Goal

Give Teachers a Fluent Dashboard, a Students list with filter/search, a student detail surface that respects the five authorization layers, and coaching notes — including explicit empty states when Progress Access is absent and when Public Profile Privacy is locked.

## 3. User-visible outcome

- **Dashboard:** active groups, deduplicated approved students, pending join queue, per-group approved/pending counts.
- **Students:** aggregated roster with search, group filter, and status filter (default emphasizes approved).
- **Student detail:** classroom gate first; Progress Access via `watchTeacherLinks`; sanitized progress only when both gates pass; private-profile badge without blocking classroom identity or progress when consent exists.
- **Coaching:** Group-backed notes via optional immutable `group_id`; legacy approved-link notes unchanged.

## 4. Verified current behavior

- `GroupRepository.watchTeacherMemberships({ teacherId })` — teacher-scoped, `created_at` DESC.
- Windows student detail uses teacher-wide link stream (not per-link GET) for Progress Access compatibility.
- `CoachingNote.groupId` optional; Firestore rules prove Classroom Authorization via exact membership path when present.
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

## 6. Actual files modified

- `packages/elixr_core/lib/repositories/group_repository.dart`
- `packages/elixr_core/lib/repositories/firebase_group_repository.dart`
- `packages/elixr_core/lib/repositories/in_memory_group_repository.dart`
- `packages/elixr_core/lib/models/coaching_note.dart`
- `packages/elixr_core/lib/repositories/coaching_note_repository.dart`
- `packages/elixr_core/lib/repositories/firebase_coaching_note_repository.dart`
- `packages/elixr_core/lib/repositories/in_memory_coaching_note_repository.dart`
- `packages/elixr_core/test/repositories/group_repository_test.dart`
- `packages/elixr_core/test/models/coaching_note_test.dart`
- `lib/app.dart`
- `lib/core/router/app_route_paths.dart`
- `lib/core/router/app_router.dart`
- `firestore.rules`
- `firestore.indexes.json`
- `firestore-tests/rules.test.mjs`
- `firestore-tests/groups_v1.test.mjs`
- `test/core/shell/teacher_shell_test.dart`
- `test/features/teacher/teacher_groups_controller_test.dart`

## 7. Rules / index changes

- **Rules:** `teacher_coaching_notes` — Group-backed create/read/update/delete via `hasClassroomAuthorization(group_id, trainee_id)` when `group_id` present; legacy `approvedCoachingLink` when absent; split `get` rules to avoid OR evaluation errors; `group_id` immutable on update.
- **Index:** `group_memberships` composite `teacher_id ASC, created_at DESC`.

## 8. Tests

- Dashboard controller: metrics, dedupe, archived exclusion, stream error, unrelated teacher exclusion.
- Students controller: aggregation, filters, search, inactive states.
- Student detail controller: classroom gate, waitingForAccess, progress load/withdrawal, private profile badge, pagination preserve.
- `elixr_core` group + coaching model tests.
- Firestore emulator: group-backed coaching (no link), pending denied, spoof denied, `group_id` immutable, teacher membership query scope.
- Widget: `teacher_shell_test` updated for real Dashboard + `GroupRepository` provider.

## 9. Verification commands (executed)

```powershell
dart format lib test packages/elixr_core/lib packages/elixr_core/test
flutter analyze   # 0 errors; pre-existing infos/warnings only
flutter test      # 1183 passed
cd packages\elixr_core; flutter test   # 71 passed
cd ..\..\teacher_app; flutter test     # passed
cd firestore-tests; npm test           # passed (JDK 21 via Android Studio JBR)
flutter build windows                  # succeeded
```

## 10. Manual verification still required

- [ ] Live Dashboard counts match production groups/memberships.
- [ ] Students search/filter in UI.
- [ ] Group-only trainee without Progress Access → waiting state.
- [ ] Progress Access grant/withdrawal live behavior.
- [ ] Private profile badge + progress when consented.
- [ ] Unauthorized UID drill-down.
- [ ] Group-only coaching note on Trainee `/coaching`.
- [ ] Legacy link coaching unchanged.
- [ ] Coaching does not create links or grant consent.

## 11. Completion report

```
Phase 3 completion
- States implemented: loadingClassroom, unauthorized, pending, relationshipRemoved,
  waitingForAccess, loadingProgress, ready, empty, accessWithdrawn, connectionRequired, error
- Coaching rules changed to Classroom Authorization OR approved link: yes
- Silent link creation: no
- Optional group_id on coaching notes: yes (rules provability)
- Commands run: see section 9
- Not verified: manual checklist section 10
```

## 12. Handoff requirements for Phase 4

1. Teachers can list members with Classroom Authorization.
2. Progress vs wait vs unauthorized states exist on Windows student detail.
3. Student detail route `/teacher/students/:traineeId` ready for leaderboard drill-down when authorized.
4. Group-only coaching works without silent consent links.
5. `teacher_app/` intact; Phase 4 not started.
