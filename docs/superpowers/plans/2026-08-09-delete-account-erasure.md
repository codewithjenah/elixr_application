# Delete Account (RA 10173) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (this session) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in user permanently erase their Firebase Auth identity and all known per-user Firestore/Storage data from Settings → Security, with fail-safe ordering and RA 10173-oriented self-erasure rules.

**Architecture:** `AuthService.deleteAccount` → `AuthRepository.deleteAccount` (re-auth via `_refreshRecentLogin`, chunked Firestore purge, Storage avatar, Auth `delete()` last). Explicit `AuthService` cleanup + `takeAccountDeletedMessage()`. Narrow `firestore.rules` self-delete deltas; `fieldOverrides` for `visitors.viewer_id` collection-group.

**Tech Stack:** Flutter Windows, Fluent UI, Firebase Auth/Firestore/Storage, `@firebase/rules-unit-testing`, `flutter_test`.

## Global Constraints

- Work on current `main` only — do not create/switch branches.
- Do not commit unless the user explicitly asks.
- Never Auth-delete if Firestore/Storage purge failed.
- Delete feedbacks while sessions still exist; then delete sessions.
- Do not enable `daily_quest_boards` list; enumerate board IDs by Manila day key.
- Re-auth only via `signInWithEmailAndPassword` (`_refreshRecentLogin`).
- Success message via `takeAccountDeletedMessage()`, not login query params.
- Skip git commit steps in this plan unless the user requests a commit.

## File map

| File | Responsibility |
| --- | --- |
| `firestore.rules` | Self-erasure delete (+ visits list for viewer) |
| `firestore.indexes.json` | `fieldOverrides` for `visitors.viewer_id` COLLECTION_GROUP |
| `firestore-tests/rules.test.mjs` | Rules cases for self-delete / cross-user deny |
| `lib/core/utils/manila_day_key.dart` | Pure Manila `yyyyMMdd` + board id enumeration helpers |
| `lib/data/repositories/auth_repository.dart` | `deleteAccount` + purge |
| `lib/services/auth_service.dart` | Orchestration + cleanup + one-shot message |
| `lib/features/settings/sections/security_section.dart` | Destructive UI + confirm dialog |
| `lib/features/auth/login_screen.dart` | Show one-shot success message |
| `test/services/auth_delete_account_test.dart` | Service behavior |
| `test/core/utils/manila_day_key_test.dart` | Day-key / board id helpers |
| `test/features/settings/settings_delete_account_test.dart` | Widget/dialog flow |
| All `AuthRepositoryBase` stubs in tests | Add `deleteAccount` |

---

### Task 1: Firestore rules + fieldOverrides + rules tests

**Files:**
- Modify: `firestore.rules`
- Modify: `firestore.indexes.json`
- Modify: `firestore-tests/rules.test.mjs`

**Interfaces:**
- Produces: owner/self `delete` on listed collections; visits `list`+`delete` for viewer; boards `list` still false

- [ ] **Step 1:** Apply rules deltas from spec §3.
- [ ] **Step 2:** Add `fieldOverrides` for `visitors` / `viewer_id` with `COLLECTION_GROUP` queryScope (ASC + DESC entries as Firebase requires for single-field overrides).
- [ ] **Step 3:** Append `describe('account self-erasure deletes', …)` cases covering owner allow, cross-user deny, boards list still fails, feedbacks delete with live session, visits viewer list+delete.
- [ ] **Step 4:** Run `cd firestore-tests; npm test` — expect PASS.

---

### Task 2: Manila day-key helper (TDD)

**Files:**
- Create: `lib/core/utils/manila_day_key.dart`
- Create: `test/core/utils/manila_day_key_test.dart`

**Interfaces:**
- Produces:
  - `String manilaDayKey(DateTime utcInstant)`
  - `List<String> enumerateDailyQuestBoardIds({required String userId, required DateTime createdAt, required DateTime now})`
  - Fallback start: `2024-01-01` Manila when createdAt missing (caller passes fallback)

- [ ] **Step 1:** Write failing tests for known UTC→Manila day keys and board id list length/endpoints.
- [ ] **Step 2:** Implement minimal helpers.
- [ ] **Step 3:** `flutter test test/core/utils/manila_day_key_test.dart` — PASS.

---

### Task 3: AuthService.deleteAccount (TDD against fake repo)

**Files:**
- Modify: `lib/data/repositories/auth_repository.dart` (add abstract `deleteAccount`)
- Modify: `lib/services/auth_service.dart`
- Create: `test/services/auth_delete_account_test.dart`
- Update: every `AuthRepositoryBase` stub with `deleteAccount`

**Interfaces:**
- Produces:
  - `Future<void> AuthRepositoryBase.deleteAccount({required String password})`
  - `Future<void> AuthService.deleteAccount({required String password})`
  - `String? AuthService.takeAccountDeletedMessage()`

- [ ] **Step 1:** Failing service tests: success clears user + clearCurrentUser + one-shot message; failure leaves user; message single-consume.
- [ ] **Step 2:** Implement service + abstract method + stub updates.
- [ ] **Step 3:** `flutter test test/services/auth_delete_account_test.dart` — PASS.

---

### Task 4: AuthRepository.deleteAccount purge implementation

**Files:**
- Modify: `lib/data/repositories/auth_repository.dart`
- Inject/use `FirebaseFirestore` + `ProfileImageRepositoryBase`

**Interfaces:**
- Consumes: manila helpers, ProfileImageRepository.deleteProfileImage, `_refreshRecentLogin`
- Produces: ordered purge per spec §2; Auth delete last

- [ ] **Step 1:** Implement chunked batch deletes (≤500), feedback-before-session order, board enumeration, visits owner + collectionGroup, storage, then `user.delete()`.
- [ ] **Step 2:** Clear errors on purge failure before Auth delete.
- [ ] **Step 3:** Smoke via analyze; repository-level unit tests optional if hard to mock Firebase (service tests cover orchestration).

---

### Task 5: Settings UI + login message

**Files:**
- Modify: `lib/features/settings/sections/security_section.dart`
- Modify: `lib/features/auth/login_screen.dart`
- Create: `test/features/settings/settings_delete_account_test.dart`

**Interfaces:**
- Consumes: `AuthService.deleteAccount`, `takeAccountDeletedMessage`
- UI: `ElixDialog.show` with `AppColors.error`, password TextBox obscure toggle mirroring `promptCurrentPassword`, confirm checkbox, then `context.go('/login')`

- [ ] **Step 1:** Widget tests for destructive affordance + dialog gate.
- [ ] **Step 2:** Implement UI + login post-frame success dialog.
- [ ] **Step 3:** `flutter test test/features/settings/settings_delete_account_test.dart` — PASS.

---

### Task 6: Full verification

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `cd firestore-tests; npm test`
- [ ] Update spec status to Approved/Implemented as appropriate
- [ ] Do **not** commit unless user asks

## Spec coverage checklist

| Spec section | Task |
| --- | --- |
| Architecture / re-auth | 3–4 |
| Purge order + boards enum | 2, 4 |
| Rules + fieldOverrides | 1 |
| AuthService cleanup + message | 3 |
| Settings UI | 5 |
| Tests | 1, 2, 3, 5, 6 |
