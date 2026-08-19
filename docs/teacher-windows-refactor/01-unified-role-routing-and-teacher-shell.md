# Phase 1 — Unified role routing and Teacher shell

**Status:** Planned  
**Sequence:** `01` of `01 → 02 → 03 → 04 → 05 → 06 → 07 → 08`  
**Prerequisite:** none (first phase). Read [00-master-plan.md](00-master-plan.md) first.

## Implementing agent instructions

- Re-read current `main`, [AGENTS.md](../../AGENTS.md), [lib/AGENTS.md](../../lib/AGENTS.md), the master plan, and this file before editing.
- Work only on existing `main`. Do not create another branch.
- Implement **only this phase**. Stop if you find yourself adding groups, leaderboards, movements, video, or template scoring.
- Do not delete [teacher_app/](../../teacher_app/).
- Update this document’s Status and Completion report when done.
- Report tests actually run versus `Not verified`.
- If a later phase’s prerequisite is missing, that is expected; do not implement it here.

---

## 1. Status

Planned

## 2. Goal

Introduce role-aware routing in the existing Windows Flutter application so one sign-in flow sends Trainees to the current trainee experience and Teachers to a dedicated Fluent Teacher shell, with an explicit Teacher registration path and no casual role changes.

## 3. User-visible outcome

- Shared `/login` for both roles.
- `/register` remains Trainee registration.
- A dedicated Teacher registration route (recommended: `/register/teacher`) creates `users.role = Teacher` only.
- After login, Teachers see a Teacher shell (Dashboard / Groups / Students / Leaderboard / Movements / Settings-Profile). Destinations beyond routing/shell chrome are **placeholders** (“Coming soon”) except Settings/Profile basics needed to log out, view role, and open legal docs.
- Teachers never see trainee practice onboarding, `/practice` lesson gates, Live Practice, or the trainee sidebar catalog.
- Non-Teacher accounts cannot enter the Teacher shell. Non-Teacher login on a Teacher-only action is rejected with a clear message (reuse teacher_app copy: “This account is not registered as a Teacher.”).
- Teachers must verify email before the Teacher shell (parity with teacher_app). Trainees keep current Windows login (no new email gate).
- `teacher_app` still runs on Android as today.

## 4. Verified current repo behavior

Re-verify line numbers at implementation time.

- Windows [lib/core/router/app_router.dart](../../lib/core/router/app_router.dart) redirects authenticated users from auth routes to `/dashboard` with **no role check**. A Teacher who signs into Windows today enters the trainee `AppShell`.
- [lib/core/widgets/app_shell.dart](../../lib/core/widgets/app_shell.dart) shows [OnboardingOverlay](../../lib/features/onboarding/onboarding_overlay.dart) when `TutorialProgressService.onboardingComplete` is false. That overlay is trainee practice/camera onboarding.
- Authenticated `/practice` redirects to a lesson if the movement lesson is incomplete.
- [lib/services/auth_service.dart](../../lib/services/auth_service.dart) `register` always passes `defaultRole: AppConstants.defaultRole` (`Trainee`). Login does not reject Teachers.
- [packages/elixr_core/lib/repositories/auth_repository.dart](../../packages/elixr_core/lib/repositories/auth_repository.dart) defaults `createMissingProfile: true` (can synthesize a Trainee profile). teacher_app `TeacherAuthController` uses `createMissingProfile: false` and signs out on missing profile.
- teacher_app [teacher_router.dart](../../teacher_app/lib/core/router/teacher_router.dart) + [teacher_routes.dart](../../teacher_app/lib/core/router/teacher_routes.dart): login/register/forgot/verify-email/legal/roster/ranking/students. Email verification required (`unverifiedTeacher`).
- [firestore.rules](../../firestore.rules) `users/{userId}`: create `role in ['Trainee','Teacher']`; update must not change `role`.
- Dart `User.roleAdmin` exists; rules will not create `Admin`. Do not map Admin → Teacher.
- Trainee Settings is `SettingsScreen.show` overlay, not a GoRoute ([lib/features/settings/settings_screen.dart](../../lib/features/settings/settings_screen.dart)).
- Root CI does not run `teacher_app/test` or `packages/elixr_core/test`.

## 5. Dependencies / prerequisites

- None from later phases.
- Shared Firebase project already used by both apps.
- Fluent UI + go_router already in the Windows app.

## 6. In scope

- Role-based `GoRouter` redirect after authentication.
- Explicit Teacher registration UI/route in the Windows app.
- Teacher email-verification screen/gate before Teacher shell.
- Teacher Fluent shell with six destinations; later features stubbed.
- Teacher Settings/Profile: account identity, role (read-only), legal links, log out. Do not mount trainee Practice preferences / camera settings as if the Teacher were about to train.
- Guard: Teacher `AuthRepository` sessions must **not** auto-create a Trainee profile (`createMissingProfile: false` or equivalent role-aware path).
- Tests for routing, registration role, non-Teacher rejection, onboarding skip, missing-profile fail-closed.
- Keep `teacher_app` compiling and behavior-compatible.

## 7. Explicit non-goals

- Groups, membership, invites (Phase 2).
- Teacher Dashboard data, Students list, coaching writes (Phase 3).
- Leaderboard tabs / XP gate (Phase 4).
- Movements, assignments, `assignment_attempts` (Phase 5).
- Video, Storage review paths (Phase 6).
- AssessmentSpec / Live Test (Phase 7).
- Deleting `teacher_app` (Phase 8).
- Changing Trainee register/login/onboarding except isolating Teachers from it.
- Enabling in-app role switching.
- Importing teacher_app Material widgets into Windows.
- Python/WebSocket changes.

## 8. Architecture / runtime flow

```mermaid
flowchart TD
  login[Shared /login]
  regT[/register Trainee]
  regC[/register/teacher]
  verify[Teacher email verify]
  trainee[Trainee AppShell]
  teacher[Teacher shell]
  login -->|role Trainee| trainee
  login -->|role Teacher unverified| verify
  login -->|role Teacher verified| teacher
  regT --> trainee
  regC --> verify
  trainee --> onboard[Trainee OnboardingOverlay allowed]
  teacher --> noOnboard[No trainee onboarding]
```

Recommended router sketch:

- Public: `/login`, `/register`, `/register/teacher`, `/forgot-password`, legal.
- Teacher-only: `/verify-email` (or `/teacher/verify-email`), then shell routes `/teacher/dashboard`, `/teacher/groups`, `/teacher/students`, `/teacher/leaderboard`, `/teacher/movements`, `/teacher/settings`.
- Trainee-only: existing `/dashboard`, `/practice`, `/join-coach`, etc.
- Redirect: if `isTeacher` and location is a trainee shell/practice path → Teacher home. If `isTrainee` and location is `/teacher/...` → trainee dashboard.
- `JoinLinkService` pending codes: **Trainees only**. Teachers with a pending join code should not be sent to `/join-coach`.

Teacher shell chrome: Fluent navigation pane or sidebar modeled on `ElixSidebar`, with Teacher destinations only. Placeholder pages: title + “Available in a later ELIXR Teacher phase” — no fake data.

## 9. Data models and persisted schema affected

- `users/{uid}.role` — already exists; set only at Teacher register (`Teacher`).
- Privacy consent fields on register — reuse `elixr_core` legal helpers as teacher_app does.
- No new Firestore collections in Phase 1.
- Optional: no schema change to `public_profiles` seed for Teachers (Teachers are not ordinary players). Do not seed Teacher accounts into the social player loop unless already happening as a side effect of `AuthService.register`; **do not** call trainee achievement projection / public-profile seed for Teacher registration.

## 10. Authentication / authorization / privacy rules

- Role immutability already in rules — do not loosen.
- UI routing is not a security control. Teachers must not gain Trainee-only writes via UI; existing owner rules remain.
- Teacher email verification: invite creation already requires `hasVerifiedEmail()` in rules. Gating the shell prevents a confusing unverified Teacher home.
- Public Profile Privacy, Classroom Authorization, Progress Access, General Evidence Access, and Assignment Submission Authorization are **not implemented** in this phase; do not invent flags on `users`.
- Do not grant Teachers ordinary-player public-profile detail reads (`isOrdinaryPlayer` is Trainee-only). Leave that for later phases.

## 11. Cross-layer contracts affected

- Flutter routing contract (paths). Prefer `/teacher/...` prefix so trainee `/dashboard` stays stable.
- `AuthService` / `AuthRepository` register `defaultRole` parameter already exists.
- No WebSocket, Python, Storage, or leaderboard contract changes.
- teacher_app continues to register Teachers independently until Phase 8; both must write the same `role: Teacher` string.

## 12. Existing files that must be inspected

- [lib/core/router/app_router.dart](../../lib/core/router/app_router.dart)
- [lib/core/widgets/app_shell.dart](../../lib/core/widgets/app_shell.dart)
- [lib/core/widgets/elix_sidebar.dart](../../lib/core/widgets/elix_sidebar.dart)
- [lib/services/auth_service.dart](../../lib/services/auth_service.dart)
- [lib/features/auth/login_screen.dart](../../lib/features/auth/login_screen.dart)
- [lib/features/auth/register_screen.dart](../../lib/features/auth/register_screen.dart)
- [lib/core/constants/app_constants.dart](../../lib/core/constants/app_constants.dart)
- [lib/app.dart](../../lib/app.dart)
- [packages/elixr_core/lib/models/user.dart](../../packages/elixr_core/lib/models/user.dart)
- [packages/elixr_core/lib/repositories/auth_repository.dart](../../packages/elixr_core/lib/repositories/auth_repository.dart)
- [packages/elixr_core/lib/legal/legal_documents.dart](../../packages/elixr_core/lib/legal/legal_documents.dart)
- teacher_app auth: `teacher_auth_controller.dart`, `register_screen.dart`, `login_screen.dart`, `verify_email_screen.dart`, `teacher_router.dart`, `teacher_routes.dart`
- Tests: `test/features/auth/register_screen_test.dart`, teacher_app `teacher_auth_controller_test.dart`, `teacher_router_test.dart`, `register_screen_test.dart`
- [firestore.rules](../../firestore.rules) users match (read-only unless a test needs a comment; prefer no rules change)

## 13. Likely files to modify / create / delete

**Modify:** `app_router.dart`, `auth_service.dart`, `login_screen.dart` (link to Teacher register), `app.dart` (providers), maybe `auth_repository.dart` if a dedicated `registerTeacher` wrapper is cleaner than a flag.

**Create:** Teacher shell widget + placeholder destination pages; Teacher register screen (Fluent, do not copy Material file wholesale); Teacher verify-email screen; router redirect tests; Teacher onboarding-skip tests.

**Delete:** nothing. Especially not `teacher_app/`.

## 14. Backward compatibility / migration strategy

- Existing Trainee accounts unchanged.
- Existing Teacher accounts (created via teacher_app) must land in the Windows Teacher shell after login + verified email.
- Missing Firestore profile: fail closed for Teacher-intent sessions (sign out), matching teacher_app — never synthesize Trainee.
- Deep links `elixr://join` remain Trainee-only.
- Do not migrate Android users off teacher_app in this phase.

## 15. Step-by-step implementation order

1. Write failing router tests: Teacher → `/teacher/dashboard`; Trainee → `/dashboard`; Teacher hitting `/practice` redirects away; Trainee hitting `/teacher/dashboard` redirects away.
2. Write failing register tests: Teacher register persists `roleTeacher`; Trainee register still `roleTrainee`.
3. Write failing test: Teacher authenticated does not trigger `OnboardingOverlay`.
4. Write failing test: unverified Teacher cannot enter shell.
5. Implement AuthService/register path and missing-profile fail-closed for Teachers.
6. Implement routes + Teacher shell chrome + placeholders + Settings/Profile basics.
7. Wire login screen “Create Teacher account” affordance without replacing Trainee register.
8. Run verification commands below.
9. Confirm `teacher_app` still analyzes/tests locally.
10. Update this file Status + completion report.

## 16. Acceptance criteria

1. One Windows login; role-based destination.
2. Teacher registration is a separate explicit flow; role cannot be changed in Settings.
3. Trainee onboarding/practice routes do not run for Teachers.
4. Email verification required for Teacher shell; not newly required for Trainees.
5. Teacher shell lists the six destinations; unimplemented ones are placeholders.
6. `createMissingProfile` cannot mint a Trainee doc for a Teacher-intent login.
7. `teacher_app` is unmodified or only given a comment/doc pointer if absolutely required — **prefer zero teacher_app edits**. If an edit seems required, stop and document why rather than expanding scope.
8. No Firestore collection additions.
9. No Python/WebSocket changes.

## 17. Required tests

- Widget/router: role redirects; placeholder destinations render; Teacher Settings logout.
- Auth unit: `defaultRole` Teacher vs Trainee; missing profile; non-Teacher rejected from Teacher shell controller if extracted.
- Register widget: legal consent still required (parity with both apps).
- Onboarding: Teacher user + incomplete tutorials → overlay **not** shown.
- Join-link: Teacher + pending code does not go to `/join-coach`.
- `elixr_core` email-verified token tests still pass.

## 18. Verification commands

From repository root:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Also (not in root CI today — still run):

```powershell
cd packages\elixr_core; flutter test
cd ..\..\teacher_app; flutter test
```

Windows startup/routing risk: `flutter build windows` if native/startup files change; otherwise list as `Not verified`.

No pytest required unless accidentally touched.

## 19. Manual verification checklist

- [ ] Register Trainee → trainee dashboard + onboarding still possible.
- [ ] Register Teacher → verify-email → Teacher shell, no camera onboarding.
- [ ] Existing teacher_app Teacher account logs into Windows → Teacher shell.
- [ ] Trainee login rejected from any hand-entered `/teacher/...` URL.
- [ ] Teacher cannot open Live Practice from UI.
- [ ] teacher_app Android login/register still works (`Not verified` if no device).

## 20. Performance / storage / privacy risks

- Loading trainee tutorial/camera services for Teachers wastes work and can touch camera lifecycle — do not register practice WebSocket services on the Teacher shell.
- Accidental public-profile seed for Teachers may expose Teacher names on social directory — skip trainee seed on Teacher register.

## 21. Explicit “Do not” list

- Do not delete `teacher_app`.
- Do not implement Groups/Students/Leaderboard/Movements features beyond placeholders.
- Do not add Flutter camera plugins.
- Do not allow role toggle after create.
- Do not send Teachers through `OnboardingOverlay`.
- Do not set `createMissingProfile: true` on Teacher login.
- Do not change Firestore role immutability.
- Do not start Phase 2 collections.
- Do not copy Material teacher_app screens.
- Do not “fix” unrelated trainee bugs.

## 22. Completion report template

```
Phase 1 completion
- Behavior implemented:
- Files changed and why:
- Commands run and results:
- Manual checks:
- Assumptions:
- Limitations / risks:
- Not completed:
- Not verified:
- teacher_app still present: yes
```

## 23. Handoff requirements for Phase 2

Phase 2 may start only if:

1. Teacher and Trainee shells are distinct on `main`.
2. Teacher registration writes immutable `Teacher` role.
3. Teachers do not hit trainee onboarding/practice.
4. Placeholders exist for Groups (Phase 2 will fill them).
5. This file’s completion report is filled.
6. `teacher_app/` still exists.
