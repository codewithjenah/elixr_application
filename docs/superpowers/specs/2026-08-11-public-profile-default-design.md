# Public-by-default profile with Lock profile toggle

**Date:** 2026-08-11  
**Status:** Approved for implementation

## Problem

ELIXR currently creates every `public_profiles/{userId}` root as `visibility: private` and labels the Settings control "Public profile" (ON = public). That is a deliberate fail-closed default, but it conflicts with the product's social layer: leaderboard profile navigation, visitor tracking, and achievement showcase become dead ends for almost every new account until the owner finds Settings → Privacy.

## Decision

1. **New accounts** seed their public profile root as `visibility: public`.
2. **Existing accounts** keep their current visibility. No migration, no silent widening.
3. Settings control becomes **Lock profile** (ON = private / locked).
4. **Parser and Firestore rules stay fail-closed to `private`** for missing or unknown visibility values.

## Non-goals

- No Firestore rules or index changes.
- No backfill of existing private roots to public.
- No new `visibility_set_by_user` marker field.
- No change to allowed Firestore values (`public` | `private`) or field name (`visibility`).

## Behavior

### New account creation

On successful `AuthService.register`, before achievement projection sync, the client best-effort seeds:

`public_profiles/{uid}` with `visibility: public`

Seeding is idempotent: `_ensureRootDocument` returns immediately when the document already exists, so it never overwrites an existing visibility choice.

If seeding fails (network, rules, etc.), registration still succeeds. Later repair paths may create a **private** root (fail-closed). The owner can unlock via Settings → Privacy.

### Repair / backfill paths

`ensurePublicProfile`, `syncClaimedAchievementProjections`, and `updatePublicIdentity` continue to create missing roots as **private**. These run for legacy accounts that may never have touched Privacy settings; creating them as public would silently widen privacy.

### Settings UI

| Control | ON means | OFF means |
|---------|----------|-----------|
| Lock profile | `visibility: private` | `visibility: public` |

Copy states that locked profiles hide detailed stats, claimed achievements, completed movements, and practice history from other players, while basic leaderboard identity remains visible either way.

### Owner-facing copy

- Profile header badge: `Locked` (was `Private`) when visibility is private.
- Visitor empty state: `This profile is locked` (aligned body copy).
- Privacy Policy: disclose that detailed profile activity is visible to other signed-in players by default and can be locked in Settings → Privacy.

## Architecture

```text
AuthService.register
  → AuthRepository.register
  → seedNewAccountPublicProfile (initialVisibility: public)
  → scheduleClaimedAchievementProjectionSync
       → sync / ensure paths (initialVisibility: private if root missing)

PrivacySection
  → updateVisibility(public|private)  // unchanged storage contract
```

### Repository contract

- `_ensureRootDocument(..., {required ProfileVisibility initialVisibility})`
- `seedNewAccountPublicProfile(...)` → creates root with `public` if missing
- Existing ensure/sync/update callers pass `private`

### Pure payload builder

`PublicProfileRootCreation.fields(...)` builds the create payload so unit tests can assert `visibility` without a live Firestore.

## Security / privacy invariants

1. Missing or malformed `visibility` still parses and rules-evaluates as private.
2. Existing documents are never rewritten by seed or ensure for visibility alone.
3. Leaderboard identity remains readable regardless of lock state (unchanged).
4. Protected profile details (`details/summary`, sessions, achievements, visits) remain gated by `canReadProtectedPublicProfile` (owner OR public).

## Acceptance criteria

- [ ] New registration seeds a public profile root when Firestore is available.
- [ ] Existing private profiles remain private after app update.
- [ ] Repair paths still create private roots when a root is missing.
- [ ] Settings shows Lock profile with inverted toggle semantics.
- [ ] Header badge and locked-profile empty state use Locked copy.
- [ ] Privacy Policy discloses default public detailed profile visibility.
- [ ] Unit/widget tests cover seed vs repair visibility and Lock toggle.
- [ ] Parser fail-closed tests remain unchanged and green.

## Risks

- If seed fails and a later repair creates a private root, a new account looks locked until the user toggles. Acceptable fail-closed tradeoff.
- Users who expected private-by-default must discover Lock profile. Mitigated by Privacy Policy disclosure and Settings → Privacy placement.
