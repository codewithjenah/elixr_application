# Firestore rules deployment investigation — 2026-09-26

## Baseline and scope

- Branch: `main`; starting HEAD: `e376e1db871423597f2772e79e776325491128b4`.
- Starting `git status --short`: empty. No branch change or commit was made.
- Source before: 197,308 UTF-8 bytes, 4,862 lines (a trailing newline is not an extra line).
- Source after: 197,424 UTF-8 bytes, 4,863 lines. This change reduces inherited helper scope, not source size.
- All 355 helper function bodies and every `allow` expression, keyed by its fully resolved match path, compare identically to HEAD after whitespace normalization. Static inspection also checked capture bindings and helper visibility.
- Firebase configuration, indexes, persisted fields, authentication, Storage rules, Flutter, backend, and existing assignment-attempt predicates are unchanged.

## Evidence and structural findings

The existing ignored @firebase-rules-debug.txt records this sequence on September 26 at 06:06 UTC:

| Endpoint | Result |
| --- | --- |
| IAM `projects/elixr-app-2026:testIamPermissions` | 200 |
| Firestore `projects/elixr-app-2026/databases/(default)` | 200 |
| Rules `projects/elixr-app-2026:test` | 200; CLI reports successful compilation |
| Rules `projects/elixr-app-2026/rulesets` | POST 200 |
| Rules `projects/elixr-app-2026/releases/cloud.firestore` | PATCH 400 `INVALID_ARGUMENT` |
| Rules `projects/elixr-app-2026/releases` | fallback POST 409 `ALREADY_EXISTS` |

This is a release activation failure, not evidence of invalid rule syntax or failed authentication. The saved log inspected here does not establish the separately reported historical 503 attempts. The local @firestore-debug.log is an emulator startup log, not a remote deployment log.

[Firebase's documented limits](https://firebase.google.com/docs/firestore/quotas#security_rules) distinguish source size from compiled size. Source size alone does not establish compliance with the compiled limit. The [Firebase maintainer's comment on issue 10819](https://github.com/firebase/firebase-tools/issues/10819#issuecomment-5108267473) attributes that project's similar failure to backend handling of rule complexity. This supports a hypothesis for ELIXR; it does not prove ELIXR has the same internal backend cause.

The database scope contains 76 helpers. Shared authentication, paths, rubric/score validation, achievement mappings, Manila dates, classroom membership, assignment audience, Activity rubric validation, and official movement catalog helpers have cross-feature callers. Moving these into one child would break other callers or duplicate validators, so they remain shared. Large feature-local sections already contain leaderboard, session, assignment-attempt, custom-movement, group/membership, and chat validators.

Confirmed inheritance hotspot: nested revision and assignment subcollection matches inherited large parent-only creation/update validators. Five child matches now use explicit full paths. Eight private helper definitions moved to the match that calls them. No expression was simplified by removing a security condition.

| Match suffix | Available helpers before | Available helpers after |
| --- | ---: | ---: |
| `teacher_movements/{movementId}/revisions/{revisionId}` | 86 | 80 |
| `custom_movements/{movementId}/revisions/{revisionId}` | 84 | 79 |
| `group_assignments/{assignmentId}/assignment_recipients/{traineeId}` | 90 | 77 |
| `group_assignments/{assignmentId}/assignment_deadline_overrides/{traineeId}` | 92 | 78 |
| `group_assignments/{assignmentId}/learning_materials/{materialId}` | 90 | 76 |

Counts include each match's own helpers and inherited helpers. The database-level count and total definitions are unchanged. This removes 52 unnecessary helper exposures across these five scopes; it is not a measurement of compiled bytes or a guarantee about Firebase's optimizer.

Other inspected complexity remains intentional: Activity rubric checks expand across three to five criteria; custom templates validate schema/version-dependent lists; assignment attempts have transition-specific identity and metadata validation; leaderboard rules distinguish legacy percentages from rubric totals. The history at `f3cee7fd` and `e376e1db` introduced guarded assignment dispatch, centralized immutable identity checks, and server-owned practice pointers. Those changes remain intact.

## Verified files and runtime participants

- @firestore.rules — all moved functions, full paths, callers, and allow expressions reviewed.
- @firebase.json — Firestore points to `firestore.rules` and `firestore.indexes.json`; emulator ports remain unchanged.
- @.firebaserc — default project is `elixr-app-2026`.
- @firestore.indexes.json — reviewed; assignment recipients retain collection/collection-group indexes; no query change requires an index edit.
- @firestore-tests/package.json — established full suite uses Firebase CLI 13.35.1 and serial Node test files.
- @firestore-tests/assignments_v1.test.mjs — added deadline privacy/membership/write lifecycle and recipient path-identity cases; existing teacher revision tests cover atomic publication and ownership.
- @firestore-tests/assignments_v6.test.mjs — existing canonical submission, review, cleanup, and immutable identity flows.
- @firestore-tests/custom_movements_v1.test.mjs — added private revision reads, immutable deletion, missing atomic linkage, wrong parent, and deeper-path denial checks.
- @firestore-tests/template_retirement.test.mjs and @firestore-tests/learning_materials_v1.test.mjs — existing movement and server-only subcollection boundaries.
- @lib/data/repositories/firebase_teacher_movement_repository.dart and @lib/data/repositories/firebase_custom_movement_repository.dart — root/revision batch writes still target the same paths and use server timestamps.
- @lib/data/repositories/firebase_classroom_assignment_repository.dart — recipient reads and deadline create/update/delete paths and field mapping agree with the unchanged contracts.

## Verification

- `node --check firestore-tests/assignments_v1.test.mjs`: passed.
- `node --check firestore-tests/custom_movements_v1.test.mjs`: passed.
- `git diff --check`: passed (Git also emits its existing LF/CRLF checkout notice).
- Independent read-only security review: no actionable findings; unchanged ownership, captures, document access semantics, and collection-group overlap.
- Targeted emulator command, run from `firestore-tests`:

  ```powershell
  npx --yes firebase-tools@13.35.1 emulators:exec --project demo-elixr --only firestore,storage "node --test --test-concurrency=1 assignments_v1.test.mjs assignments_v6.test.mjs custom_movements_v1.test.mjs template_retirement.test.mjs learning_materials_v1.test.mjs"
  ```

  Passed: 145 tests, 18 suites, zero failures/skips. Local compilation is exercised by loading the rules into the Firestore emulator. Log: `%TEMP%/elixr-rules-targeted-20260926.log`.

- Full established `npm test`, run from `firestore-tests`: exit 0; 505 tests, 61 suites, zero failures/skips. This includes core session/leaderboard, roster, groups, announcements, assignments, custom movements, challenges, retirement, chat, directory, Storage, and learning-material suites. Log: `%TEMP%/elixr-rules-full-20260926.log`.

## Remote deployment result: activation remains blocked

Executed once from the repository root with installed Firebase CLI 15.30.2:

```powershell
firebase deploy --only firestore:rules --project elixr-app-2026 --debug
```

Exit code: 1. Full console/debug output is preserved at `C:/Users/Jiro/AppData/Local/Temp/elixr-rules-deploy-20260926.log`; Firebase also generated the ignored root @firebase-debug.log. The pre-existing @firebase-rules-debug.txt was preserved. Local logs are not committed.

Exact Rules API results on 2026-09-26, all under `https://firebaserules.googleapis.com/v1/`:

| UTC time | Method and endpoint | Result |
| --- | --- | --- |
| 10:03:21.649 | POST `projects/elixr-app-2026:test` | 200; compiled successfully |
| 10:03:27.924 | POST `projects/elixr-app-2026/rulesets` | 200 |
| 10:03:30.764 | PATCH `projects/elixr-app-2026/releases/cloud.firestore` | 400 `INVALID_ARGUMENT`: Request contains an invalid argument. |
| 10:03:31.216 | POST `projects/elixr-app-2026/releases` | 409 `ALREADY_EXISTS`: Requested entity already exists |

IAM permission checks and the default Firestore database lookup also returned 200. No 503 occurred during this attempt. Compilation and ruleset creation succeeded, but successful release activation was not observed. Deployment is **not successful**.

The upstream/project-specific Rules release activation blocker remains after the structural reduction. The exact internal cause still requires Firebase backend diagnostics; the generic 400 does not prove a particular compiled-size threshold. Per the requested stop condition, no further speculative rule changes, repeated deployment attempts, or release/ruleset deletions were made. Firebase support can use the project ID, UTC timestamps, and preserved debug log to investigate.

Attempted source SHA-256: `7de981bfb2f21f700251198fd5ecff573c9d99a1e05fcf7e028a62d4585db1dc`.

## Limits

No manual Flutter UI or camera checks were performed: this is a rules-only change. **Not verified:** compiled ruleset byte size, Firebase's internal failure cause, successful remote activation, and manual application behavior. No releases or rulesets were deleted as a workaround. No production documents were modified by the emulator tests. The requested successful remote deployment remains incomplete; local implementation, security review, and both test runs are complete.
