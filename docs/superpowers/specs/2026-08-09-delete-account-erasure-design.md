# Delete Account (RA 10173 Right-to-Erasure)

**Date:** 2026-08-09  
**Status:** Implemented  
**Branch constraint:** Work on current `main` only; no branch creation or switching.  
**Compliance intent:** Philippine Data Privacy Act (RA 10173) right-to-erasure for per-user ELIXR data held in Firebase Auth, Firestore, and Storage.

## Problem

ELIXR stores identifiable training and profile data across many Firestore collections plus a Storage avatar. There is no in-app path for a user to permanently erase that data and their Auth account. Several collections intentionally forbid `delete` (and some forbid `list`), so a naive client wipe would fail mid-way and risk orphaned documents or an Auth account deleted before data purge completes.

## Goals

1. Let a signed-in user permanently delete their account from Settings → Security after password re-auth and explicit confirmation.
2. Purge all known per-user Firestore documents/subcollections and the Storage profile image **before** deleting the Firebase Auth user.
3. Update `firestore.rules` only as needed for **self-erasure** (owner/viewer deleting their own rows), without loosening create/update or cross-user write paths.
4. On success, clear `AuthService` state the same way `logout()` does, then land on login with a one-shot confirmation message.
5. On any purge failure, surface a clear error, leave the Auth account intact, and keep retry idempotent where practical.

## Non-goals

- Cloud Functions / Admin SDK server-side purge.
- Changing how data is written during normal app use (claims, awards, boards, public profiles).
- Weakening leaderboard/claim/board immutability for anyone other than the deleting owner.
- Opening `daily_quest_boards` to list/query (`allow list: if false` stays).
- Broader GDPR tooling, retention schedules, or soft-delete / tombstones.
- Persistent `authStateChanges()` subscription rewrite (out of scope; deletion uses explicit cleanup).

## Decisions locked in design

| Topic | Decision |
| --- | --- |
| Architecture | Client purge inside `AuthRepository.deleteAccount`; `AuthService.deleteAccount` orchestrates + UI-facing cleanup |
| Re-auth | Existing `_refreshRecentLogin` via `signInWithEmailAndPassword` (not `reauthenticateWithCredential`) |
| Daily quest boards | Enumerate Manila day-key IDs from `users/{uid}.created_at` → today; do **not** query; keep `list: false` |
| Feedbacks | Cascade by `session_id`; delete feedbacks **while sessions still exist**, then delete sessions |
| Profile visits outbound | Collection-group query; rules must allow **list and delete** when `viewerId == auth.uid` |
| Success messaging | One-shot `AuthService.takeAccountDeletedMessage()` (mirror `takePendingEmailChangeSuccessMessage()`), not a login query param |
| Storage missing object | Already treated as success in `ProfileImageRepository.deleteProfileImage` (`object-not-found`) |

## Files in scope

| File | Role |
| --- | --- |
| `lib/data/repositories/auth_repository.dart` | `AuthRepositoryBase.deleteAccount` + implementation: re-auth, chunked purge, Storage, Auth `delete()` last; may accept/inject `ProfileImageRepositoryBase` |
| `lib/services/auth_service.dart` | `deleteAccount`, post-success cleanup + `takeAccountDeletedMessage()` |
| `lib/features/settings/sections/security_section.dart` | Destructive Delete Account UI + confirm dialog |
| `lib/features/auth/login_screen.dart` | Consume one-shot deleted-account message after navigation |
| `firestore.rules` | Narrow self-erasure `delete` (and visits `list`) deltas |
| `firestore.indexes.json` | Add a `fieldOverrides` entry for collection-group `visitors.viewer_id` (single-field COLLECTION_GROUP scope); not a composite `indexes` entry |
| `storage.rules` | No change expected (owner delete already allowed under `users/{uid}/profile/`) |

Tests: `test/services/auth_delete_account_test.dart`, `test/features/settings/` (new or extended), append cases in `firestore-tests/rules.test.mjs`.

---

## 1. Architecture and flow

```
Settings Security UI
  → AuthService.deleteAccount(password)
      → AuthRepository.deleteAccount(password)
          1. Require currentUser + email
          2. _refreshRecentLogin(email, password)  // signInWithEmailAndPassword
          3. Purge Firestore (chunked WriteBatch ≤ 500 ops)
          4. Delete Storage avatar (via ProfileImageRepository)
          5. Firebase Auth User.delete()  // ONLY if purge succeeded
      → On success (AuthService):
          - Set one-shot _accountDeletedMessage
          - Clear _currentUser
          - await clearCurrentUser()   // local persisted-user cache
          - notifyListeners()
      → UI: context.go('/login')
  → LoginScreen: takeAccountDeletedMessage() → show success once
```

### Why explicit AuthService cleanup is required

`AuthService` does **not** keep a persistent `authStateChanges()` subscription. `_currentUser` is set imperatively (login/register/profile updates/`logout`). Calling only `fb.User.delete()` would leave `isAuthenticated == true`, so the router would not redirect and subsequent Firebase calls would fail opaquely. After a successful repository delete, `AuthService` must perform the same local cleanup as `logout()` (and additionally set the one-shot success message **before** clearing state so login can read it).

### Contract participants

- **Firebase Auth** — identity; deleted last.
- **Cloud Firestore** — all listed collections; rules must permit self-delete.
- **Firebase Storage** — `users/{uid}/profile/*` via existing repository.
- **Local persisted user cache** — cleared via `clearCurrentUser()`.
- **go_router** — reacts to `AuthService.isAuthenticated` after `notifyListeners()`.

---

## 2. Purge scope and order

All Firestore deletes use chunked `WriteBatch` commits (max **500** operations per batch). Abort the whole `deleteAccount` call on the first hard failure **before** Auth deletion.

### Ordered steps

1. **Load session IDs** for `user_id == uid` (do not delete sessions yet).
2. **Delete `feedbacks`** whose `session_id` is in that set (chunk `in` queries / batches as needed).
   - Must happen **while parent `sessions` docs still exist**, because feedback read/delete rules use `get(sessions/{session_id}).data.user_id` without a null-safe missing-doc path.
3. **Delete `sessions`** for `user_id == uid`.
4. **Delete `leaderboard_processed_sessions`** where `user_id == uid`.
5. **Delete `daily_quest_boards`** by **deterministic IDs only**:
   - `boardId = uid + '_' + manilaDayKey` for each Manila calendar day from the user’s `created_at` (inclusive) through today (inclusive).
   - Reuse the same Asia/Manila day-key idea as rules (`yyyyMMdd`, UTC+8).
   - If `created_at` is missing/unparseable, fall back to enumerating from **2024-01-01** Asia/Manila through today (bounded, complete enough for this product’s lifetime without enabling `list`).
   - Deleting a non-existent board ID is an intentional no-op for retry/idempotency, but it is **not** automatically authorized. Rules require the board document ID to match the authenticated user’s canonical shape `<authUid>_<yyyyMMdd>` (exactly 8 trailing digits). When the document is missing (`resource == null`), that canonical-ID check alone permits the no-op delete; when the document exists, `resource.data.user_id == request.auth.uid` is still required. Arbitrary missing-document deletes are denied.
   - **Do not** change `allow list: if false` on boards.
6. **Delete `daily_quest_claims`** where `user_id == uid`.
7. **Delete `achievement_claims`** where `user_id == uid`.
8. **Delete `user_cosmetics/{uid}`** (direct doc).
9. **Delete `leaderboard/{uid}`** (direct doc).
10. **Delete `public_profiles/{uid}`** subcollections, then root:
    - `details/summary`
    - `sessions/*`
    - `achievements/*`
    - then `public_profiles/{uid}`
11. **Delete `profile_visits`:**
    - Owner tree: `profile_visits/{uid}/visitors/*`
    - Outbound visitor rows: collection-group query on `visitors` where `viewer_id == uid` (requires rules `list` for viewer).
    - Indexing: this is a **single equality** filter, so enable it via a `fieldOverrides` entry with `collectionGroup: "visitors"`, `fieldPath: "viewer_id"`, and an index config whose `queryScope` is `COLLECTION_GROUP` — **not** a new composite entry in the `indexes` array (`fieldOverrides` is currently `[]`).
12. **Delete `users/{uid}`**.
13. **Delete Storage avatar** using `profile_picture_storage_path` when present (and/or list+delete under `users/{uid}/profile/` if needed for completeness). Rely on existing `object-not-found` → success behavior.
14. **Firebase Auth `User.delete()`** — only after steps 1–13 succeed.

### Idempotent retry

- Firestore deletes of already-missing **path-owned** docs (`users/{uid}`, `leaderboard/{uid}`, `user_cosmetics/{uid}`, `public_profiles/{uid}` and owned subdocs) are safe because ownership is authorized from the path (`isOwner`), not `resource.data`.
- Firestore deletes of already-missing **`daily_quest_boards/{boardId}`** docs are safe **only** when `boardId` is the caller’s canonical `<uid>_<yyyyMMdd>` ID (see rules helper `isCanonicalOwnDailyQuestBoardId`). A missing board belonging to another user remains denied.
- Query-driven deletes (sessions, feedbacks, claims, markers, visits) only target documents that currently exist in query results, so a retry simply sees fewer rows.
- Storage missing objects are already ignored by `ProfileImageRepository`.
- Auth delete runs only after a successful purge; a mid-purge failure leaves the user signed in so they can retry.
- Mid-purge failures surface a clean user-facing erasure message; debug builds log the failing purge stage plus Firebase plugin/code/message without putting those internals in the dialog.

---

## 3. Firestore rules deltas

Narrow self-erasure only. Create/update invariants for awards, claims, boards, and cosmetics stay unchanged.

| Path | Change |
| --- | --- |
| `feedbacks/{id}` | Add `allow delete` when signed-in and `get(sessions/{resource.data.session_id}).data.user_id == auth.uid` (mirror read ownership). |
| `leaderboard/{userId}` | `allow delete: if isOwner(userId)` (was `false`). |
| `leaderboard_processed_sessions/{sessionId}` | `allow delete` when `resource.data.user_id == auth.uid` (update stays `false`). |
| `daily_quest_boards/{boardId}` | `allow delete` when `isCanonicalOwnDailyQuestBoardId(boardId)` and (`resource == null` **or** `resource.data.user_id == auth.uid`); **`list` remains `false`**. Canonical ID = `<authUid>_<yyyyMMdd>`. |
| `daily_quest_claims/{claimId}` | `allow delete` when `resource.data.user_id == auth.uid`. |
| `achievement_claims/{claimId}` | `allow delete` when `resource.data.user_id == auth.uid`. |
| `user_cosmetics/{userId}` | `allow delete: if isOwner(userId)`. |
| `public_profiles/{userId}` | `allow delete: if isOwner(userId)`. |
| `public_profiles/.../details/summary` | `allow delete: if isOwner(userId)`. |
| `public_profiles/.../sessions/{sessionId}` | `allow delete: if isOwner(userId)`. |
| `public_profiles/.../achievements/{achievementId}` | `allow delete: if isOwner(userId)`. |
| `profile_visits/{profileOwnerId}/visitors/{viewerId}` | Keep owner `list` via `isOwner(profileOwnerId)`. `allow delete` if owner **or** `viewerId == auth.uid`. |
| `/{path=**}/visitors/{viewerId}` | Add recursive-wildcard `allow list` when `resource.data.viewer_id == auth.uid` so collection-group erasure queries are allowed (rules_version 2). |

Already sufficient (no change expected for delete permission):

- `users/{userId}` — `write` includes delete for owner.
- `sessions/{sessionId}` — owner may already delete.

Do **not** allow cross-user deletion. Do **not** open board listing.

---

## 4. AuthService post-delete cleanup and messaging

### `deleteAccount`

```text
await _repository.deleteAccount(password: password);
_accountDeletedMessage = 'Your account and associated data have been permanently deleted.';
_clearPendingEmailChange(clearError: true); // same hygiene as logout
_currentUser = null;
await _repository.clearCurrentUser();
notifyListeners();
```

(Exact success copy may be tuned; keep it clear and non-alarming.)

### `takeAccountDeletedMessage()`

Mirror `takePendingEmailChangeSuccessMessage()`:

- Returns the pending string once, then clears it to `null`.
- Login screen (or shell that hosts login) calls it after arriving unauthenticated and shows success via existing dialog/InfoBar patterns (`ElixDialog.success` preferred for consistency with email-change success).

### Navigation

UI navigates to `/login` after `deleteAccount` returns successfully. Do **not** rely on Auth stream auto-sign-out. Do **not** use `?accountDeleted=1` as the primary success channel (superseded by the one-shot getter).

---

## 5. Settings UI

### Placement

`lib/features/settings/sections/security_section.dart`, below the change-password card: a **separate** destructive group (error-tinted border/icon using `AppColors.error`, visually distinct from primary password UI).

### Confirm dialog

Build with `ElixDialog.show<T>()` (same shell as `SettingsDiscardConfirm`: Cancel + primary action). Do **not** call `ElixDialog.promptCurrentPassword` — that helper lacks the deletion bullet list and confirm-gate checkbox.

- `iconColor` / `headerAccentColor`: **`AppColors.error`** (not `AppColors.warning`).
- Content: irreversible warning + bullet list of erased categories (profile & account, sessions & feedback, leaderboard/XP, quests/achievements/cosmetics, public profile & visits, avatar).
- Password field (required): mirror the `TextBox` + obscure/reveal suffix toggle used in `ElixDialog.promptCurrentPassword` (`lib/core/widgets/elix_dialog.dart`, ~lines 152–174) for visual/UX consistency.
- Explicit confirm gate (checkbox or equivalent) before enabling primary action.
- Primary label: destructive “Delete account”.
- While in flight: disable controls + progress; on failure show `ElixDialog.error` and remain on Settings signed-in.

---

## 6. Error handling

| Failure | Behavior |
| --- | --- |
| Wrong password / re-auth timeout | Throw mapped auth message; no purge |
| Mid-purge Firestore/Storage error | Throw clear erasure-failed message; **do not** Auth-delete |
| Auth delete fails after purge | Surface error; data may already be gone — message should say contact/support or retry sign-in carefully (document as known edge case in implementation notes) |
| Retry after partial purge | Safe for Firestore + Storage not-found; continue deleting remaining docs |

Never treat a failed purge as success. Never delete Auth first.

---

## 7. Test plan

### `test/services/auth_delete_account_test.dart`

Using the existing fake/`AuthRepositoryBase` patterns from other `auth_*_test.dart` files:

- Happy path: service calls repository, then clears `_currentUser`, calls `clearCurrentUser`, exposes one-shot message via `takeAccountDeletedMessage()`.
- Message is single-consume (second take returns null).
- Repository failure: service does **not** clear auth state / does not set success message.
- (Repository-level fakes or focused unit tests as practical): re-auth invoked; Auth delete not called when purge fails; feedback-before-session ordering encoded in the purge collaborator/fake call order where tested.

### `test/features/settings/`

Mirror existing settings widget test setup:

- Destructive Delete Account affordance present in Security section.
- Dialog requires password + confirm gate before enabling delete.
- Uses error accent (not warning-only discard styling).
- On mocked success: navigates toward login / leaves authenticated shell as expected.
- On mocked failure: stays put and surfaces error.

### `firestore-tests/rules.test.mjs`

Append cases to the **single** existing rules suite (do not split per collection):

- Owner **can** delete own docs in formerly `delete: false` collections listed above.
- Other users **cannot** delete those docs.
- `daily_quest_boards`: owner can delete an **existing** own board; owner can delete a **nonexistent** canonical own board (idempotent purge); other users cannot delete existing or nonexistent boards belonging to someone else; **list still denied**.
- `feedbacks`: owner (via live session) can delete; delete denied for non-owner.
- `profile_visits` visitors: viewer can **list/query** and **delete** own outbound rows; non-viewer non-owner denied.

### Verification commands (before calling done)

```powershell
flutter analyze
flutter test
cd firestore-tests; npm test
```

`npm test` runs `firebase emulators:exec --project demo-elixr --only firestore "node --test rules.test.mjs"` per `firestore-tests/package.json`.

---

## 8. Acceptance

- Authenticated user can erase their account from Settings → Security after password + explicit confirm.
- After success: local auth state cleared, login reachable, one-shot confirmation shown once.
- Firestore/Storage per-user data for that uid is removed per the ordered purge list (boards via day-key enumeration).
- Failed purge never deletes Auth.
- Rules allow only self-erasure deletes; board list remains locked; visits viewer can list+delete own outbound rows.
- `flutter test` and firestore rules suite pass for the new coverage.

## 9. Risks and limitations

- Client-side erasure is appropriate for this controlled capstone; a hostile modified client is out of scope (same posture as leaderboard notes in root `AGENTS.md`).
- Very long-lived accounts with huge session/feedback counts need reliable batch chunking and may take noticeable time; UI should show progress/disabled state.
- Auth-delete failure after a completed purge is rare but leaves a credential with little/no Firestore data; surface clearly.
- Board enumeration depends on correct Manila day-key alignment with rules; tests should cover ID construction helpers if extracted.
- Collection-group `visitors.viewer_id` needs the `fieldOverrides` COLLECTION_GROUP scope entry deployed with rules/indexes before production use.

## Not verified in this spec phase

- Live Firebase project purge against production/emulator end-to-end.
- Windows desktop manual UX pass.
- Index deployment.