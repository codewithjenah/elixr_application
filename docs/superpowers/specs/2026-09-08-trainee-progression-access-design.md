# Trainee progression and access policy

**Date:** 2026-09-08  
**Status:** Implementation-plan ready  
**Branch:** `main` only

## Problem

ELIXR already has XP/levels, twelve official movements with prop variants, tutorials, guided practice, Daily Quests, leaderboard progression, teacher-created official assignments, and a Just Dance-style Playground foundation. These systems are not connected by one canonical progression/access model.

Personal content is not gated by level. Tutorials and Playground setlists are movement-name-only. Official teacher assignments do not persist an exact prop (`allowed_prop` is forbidden on official create today). Assignment access and personal progression must remain separate so classroom instruction does not become a permanent unlock.

## Goals

1. One canonical personal unlock progression for exact movement + prop variants from Level 1 through Level 16.
2. Personal practice requires level unlock **and** exact-variant tutorial completion.
3. Teachers can assign any official supported movement + prop regardless of trainee personal level.
4. Valid assignment-scoped access may grant tutorial/practice above personal level without leaking into Playground, recommendations, or personal calendar selection.
5. Preserve existing XP/level formula, CV assessment, movement identities, and Firestore authorization posture (strengthen official prop pinning; do not weaken recipient checks).

## Non-goals

- New XP formula, currency, shop, energy, hearts, paid unlocks, or streak freezes
- Duplicate movement records (e.g. "Hand Stall Shaker")
- New official movements beyond the existing twelve identities
- Broad teacher/dashboard redesign
- Backend CV assessment changes unless an exact movement + prop contract mismatch requires it
- Deploying Firestore rules or Cloud Functions unless explicitly requested later
- Router-owned Firestore/XP fetching

## Architecture (Approach 1)

```text
authoritative XP / tutorial / assignment state
        ↓
   PracticeVariant (stable identity)
        ↓ resolve against official catalog
   PracticeCatalogStep / Movement + TrainingProp
        ↓
   ProgressionAccessPolicy → access result
        ↓
   router / UI consumes result
```

### PracticeVariant

Stable domain and persistence identity:

- `movementName` (official catalog name string)
- `trainingProp` (`TrainingProp` / protocol value)

Used by tutorial progress, Playground setlists, progression milestones, recommendations, calendar selection, and assignment prop matching.

Must **not** embed a full `Movement` model so persisted data stays decoupled from catalog object shape.

### PracticeCatalogStep

Resolved runtime representation already present in `movements.dart`:

- `Movement movement`
- `TrainingProp prop`

Resolve `PracticeVariant` → catalog step; reject unknown movement or unsupported prop.

### ProgressionAccessPolicy

Single source of truth for:

- required personal level
- level-unlocked state
- tutorial completion for exact variant
- personal tutorial access
- personal practice access
- Playground eligibility
- personal recommendation eligibility
- personal training-plan eligibility
- teacher assignment-scoped bypass

The policy is **pure**: it receives already-resolved inputs and does not fetch XP, tutorial storage, or assignment authorization.

Canonical evaluation shapes (names follow repo style):

```text
evaluatePersonal(
  variant,
  currentLevel,        // null/unknown → personal loading
  tutorialCompleted,   // null/unknown → personal loading
)

evaluateAssignment(
  variant,
  assignmentGrant,     // authenticated authorization result; unknown → assignment loading
  tutorialCompleted,   // null/unknown → assignment loading
)
```

`assignmentGrant` already represents the authenticated assignment authorization outcome (exists, accessible, trainee is intended recipient, movement/prop match). The policy does not re-derive Firestore membership.

Widgets and router **render/consume** access results. They do not scatter `level >= X` checks and do not fetch assignment authorization or XP inside redirect logic.

### Access result (distinct contexts)

Exact enum naming follows repo conventions. Semantics must distinguish personal vs assignment contexts (not a boolean override on personal access). Loading is **context-specific**:

| Result | Meaning |
|---|---|
| `personalLoading` | Personal decision blocked only because XP/level or tutorial state required for that decision is unknown |
| `assignmentLoading` | Assignment decision blocked only because assignment authorization or tutorial state required for that decision is unknown |
| `invalid` | Unknown/unsupported variant, unauthorized assignment, or mismatched movement/prop |
| `personalLocked` | Below required personal level |
| `personalLearn` | Level unlocked; exact tutorial incomplete |
| `personalReady` | Level unlocked; exact tutorial complete (practice / Playground / personal plan eligible) |
| `assignmentLearn` | Valid assignment-scoped access; exact tutorial incomplete |
| `assignmentReady` | Valid assignment-scoped access; exact tutorial complete |

Personal surfaces (Movements, Playground, personal recommendations, personal calendar) evaluate only personal inputs. They must **never** wait on assignment authorization. Opening Movements or Playground cannot get stuck because assignment data is still loading.

Assignment surfaces evaluate assignment inputs independently of personal level.

While a context is loading, gated actions for **that** context fail closed (no flash unlocked→relocked; no optimistic practice start).

`Practiced` remains a **presentation** overlay on personal readiness when qualifying personal session history exists. It does not change access gates.

## Authoritative XP and level

- Formula remains `GamificationRules` (`xpPerSession = 25`, `xpPerLevel = 250`, `levelForXp = totalXp ~/ 250 + 1`).
- Authoritative trainee XP is `leaderboard/{userId}.total_xp` via existing leaderboard models/repositories.
- Level 17+ continues for XP, profile, leaderboard, achievements, and future cosmetics with **no** new official movement content.
- Do not award XP for unlocks, opening tutorials, Playground combos, or setlist transitions.

## Progression catalog (exactly 16 milestones)

Validate every entry against `lib/core/constants/movements.dart` (`movement` exists; prop ∈ `supportedProps`).

| Level | Movement | Prop |
|---:|---|---|
| 1 | Normal Grip | Bottle |
| 2 | Bartender's Grip | Bottle |
| 3 | Reverse Grip | Bottle |
| 4 | Claw Grip | Bottle |
| 5 | Hand Stall | Bottle |
| 6 | Hand Stall | Cocktail Shaker |
| 7 | One Finger Stall | Bottle |
| 8 | One Finger Stall | Cocktail Shaker |
| 9 | Forearm Stall | Bottle |
| 10 | Forearm Stall | Cocktail Shaker |
| 11 | Elbow Stall | Bottle |
| 12 | Elbow Stall | Cocktail Shaker |
| 13 | Reverse Forearm Stall | Bottle |
| 14 | Shoulder Stall | Bottle |
| 15 | Double Hand Stall | Bottle |
| 16 | Bottle in a tin | Bottle + Cocktail Shaker |

Notes:

- Catalog name for level 16 is `'Bottle in a tin'` (existing identity).
- Medium Bottle and Cocktail Shaker are separate `PracticeVariant`s, not new movement identities.
- `Movement.enabled` remains product/catalog availability, never user progression.

Canonical helpers (names follow repo style):

- `requiredLevel(variant)`
- `isLevelUnlocked(variant, level)`
- `nextUnlock(level)`
- `xpRemainingToNextUnlock(totalXp)` using `GamificationRules`
- `allPersonallyLevelUnlockedVariants(level)`

## Access equations

### Personal practice / Playground / personal calendar / personal Start Practice

```text
valid official PracticeVariant
AND currentLevel >= requiredLevel(variant)
AND hasCompletedLesson(variant)
====================================
personalReady
```

Level unlock alone yields `personalLearn` (tutorial available; practice blocked).

### Assignment tutorial / practice

```text
valid official PracticeVariant
AND assignment exists and remains accessible
AND authenticated trainee is authorized recipient
AND assignment.official movement == variant.movementName
AND resolvedAllowedProp(assignment) == variant.trainingProp
AND (for practice) hasCompletedLesson(variant)
====================================
assignmentLearn or assignmentReady
```

No personal level check.

Assignment tutorial completion persists globally for that exact variant. It does **not**:

- change `requiredLevel`
- grant early `personalReady`
- unlock Playground
- unlock personal recommendations or personal training-plan selection

When the trainee later reaches the required personal level, prior exact tutorial completion is honored for personal practice without replaying the lesson.

## Tutorial progress migration

`TutorialProgressService` remains local account-scoped JSON (not Firestore).

- New completion keys encode exact `PracticeVariant`.
- Effective API: `hasCompletedLesson(movement, prop)` / `markLessonCompleted(movement, prop)` (or equivalent).
- Legacy movement-only entries migrate deterministically and idempotently to the movement’s **first/default** supported prop only:
  - single-prop movements → that prop
  - Medium dual-prop → Bottle only (Shaker remains incomplete)
  - Bottle in a tin → `bottle_and_shaker`
- Migration must be safe across repeated launches; do not duplicate progress.
- New writes use exact-variant format only.

## Official assignment prop pinning

### New official assignments

Teachers always choose an exact prop for Medium dual-prop movements. Single-prop movements auto-set their sole supported prop.

Persist `allowed_prop` on create. Coordinated updates required in:

- `TeacherAssignmentCreationService` / composer UI
- `officialAssignmentPayload` and repository create path
- Cloud Function official create path
- `firestore.rules` `validOfficialAssignmentCreate` (stop forbidding `allowed_prop`; require a prop that is valid for that official movement’s supported props)
- repository / rules / function tests

Teacher official movement picker must **not** be filtered by trainee personal level. Optional non-blocking UI note about below-level recipients is allowed; it must never block publish.

### Updates to official assignments

If official assignments can be edited/updated, the same movement/prop validation applies to **updates**, not only creation.

Invariant for any assignment created or rewritten under the new schema (`official movement + allowed_prop`):

- `allowed_prop` must remain present
- `allowed_prop` must remain a supported prop for that official movement
- updates must not create a movement/prop mismatch
- updates must not strip `allowed_prop` from a new-format official assignment

Cover:

- Flutter repository update path, if one exists
- Firestore create **and** update rules
- Cloud Function mutation paths
- tests for rejected invalid updates

### Legacy official assignments missing `allowed_prop`

Deterministic fallback (locked decision):

- Resolve to the movement’s first/default supported prop only.
- Medium stalls → Bottle.
- Bottle in a tin → combined Bottle + Cocktail Shaker.
- No trainee prop picker.
- No implicit access to both Medium variants.
- Assignment bypass applies only to that resolved exact variant.

Legacy documents without `allowed_prop` remain readable through this fallback. Once rewritten under the new schema, the create/update invariants above apply.

### Cross-language catalog parity

Flutter owns the canonical `movementCatalog`, but Firestore Rules and Cloud Functions cannot import that Dart catalog. Any duplicated official movement/prop allowlist required by Rules or Functions must stay aligned with Flutter’s catalog-supported pairs (the full official supported set, including all sixteen progression milestones and every catalog-supported combination).

Requirement:

- Parity tests must fail if Flutter, Functions, and Rules disagree on any official supported movement + prop pair.
- Test **all** official supported combinations, not only the four Medium dual-prop movements.
- A future catalog change that updates only one runtime must break CI until the others match.

## Router and loading behavior

- Router consumes already-resolved access results from the progression/access layer.
- Router must not fetch assignment authorization or XP itself.
- Direct personal lesson/practice routes cannot bypass progression via query params.
- Unknown/unsupported movement + prop → fail safely (`invalid`).
- Personal route gates use personal evaluation only (`personalLoading` / `personalLocked` / `personalLearn` / `personalReady`).
- Assignment route gates use assignment evaluation only (`assignmentLoading` / `assignmentLearn` / `assignmentReady` / `invalid`).
- Preserve auth, verification, teacher-role, join-code, and assignment routing; avoid redirect loops.
- Never add client bypass flags (`bypass=true`, `teacher=true`, `assignmentAccess=true`, `ignoreLevel=true`).
- Bare assignment ID is never sufficient; use real authenticated assignment authorization already enforced by Firestore rules and existing client membership/recipient checks.

## Surface behavior

### Learning / Movements

- Keep future content visible; do not hide locked variants.
- Medium movements: one movement card with independent prop rows/chips.
- Show lock, required level, Learn/New, Ready, Practiced, and correct CTAs.
- Locked variants: subdued, lock icon, no misleading press/hover activation; meaningful semantics.
- Assignment surfaces: compact Assignment Access copy (“Normally unlocks at Level X”) without implying permanent unlock.

### Playground

- Selectable pool = `personalReady` exact variants only.
- Persist `PracticeVariant` list; migrate legacy movement-name entries to first/default prop only.
- Discard unknown/invalid combinations; dedupe preserving order; preserve unrelated music/pace/interval settings.
- Runtime always revalidates against current personal progression before start.
- Level 1: single-variant Quick Run / repeated routine is allowed.
- Progression HUD: Level, XP into level, Next Unlock (or all-content unlocked message at 16+).
- Preserve existing session lifecycle; miss continues; no fake accuracy tiers; no combo XP.

### Recommendations

- `personalReady` → may Start Practice.
- `personalLearn` → may Learn Next.
- `personalLocked` → must not expose Start Practice.
- Assignment access does not alter personal recommendation eligibility.

### Personal calendar / training plans

- Only `personalReady` exact variants selectable for personal practice plans.
- Prop must be explicit for dual-prop movements.
- Teacher classroom assignments remain independently visible even when above personal level.

### Level-up presentation

- Exactly one content milestone per level 1–16; `nextUnlock` is canonical.
- At 16+: next unlock = none.
- Optional restrained unlock celebration only if a clean existing level-transition signal exists; otherwise prefer persistent New / Next Unlock UI.

## Accessibility

- Locked: e.g. “Elbow Stall, Cocktail Shaker, locked, unlocks at Level 12.”
- Assignment above-level: e.g. “Elbow Stall, Cocktail Shaker, available for this assignment, normally unlocks at Level 12.”
- Keyboard must not activate locked states; do not rely on color alone; respect reduced motion; keep focus visible; preserve Fluent dark/pink Windows layout behavior.

## Security invariants

- Do not weaken Firestore recipient/membership authorization.
- Assignment bypass requires authentic assignment document + recipient authorization + movement/prop match + accessible state.
- Client-supplied difficulty/query flags are not authority.
- Capstone leaderboard XP remains client-written; do not claim server-authoritative unlocks against a hostile client.

## Verification (definition of done summary)

Targeted tests for progression mapping, prop identity, tutorial migration, personal lesson/practice access, teacher assign-any-variant, assignment access isolation, assignment security negatives, official `allowed_prop` create/update validation, cross-language catalog/prop parity (Flutter ↔ Functions ↔ Rules for all official supported pairs), Learning/Playground/recs/calendar gating, context-specific loading, and XP formula regression.

Then:

1. Targeted tests by subsystem
2. `flutter analyze`
3. Full `flutter test` once
4. Separate pre-existing failures from regressions
5. Do not deploy rules/functions unless explicitly requested
6. Do not broadly run backend Python unless backend CV files change

## Likely touch surfaces

**New (illustrative):** `lib/core/progression/` — `practice_variant.dart`, `progression_catalog.dart`, `progression_access_policy.dart` (+ tests)

**Core / services:** `tutorial_progress_service.dart`, `app_redirect.dart`, `app_router.dart`, `settings_service.dart` (Playground persistence)

**Teacher / assignment:** `teacher_assignment_composer.dart`, `classroom_assignment_repository.dart` / firebase + in-memory, `assigned_practice_screen.dart`, `firestore.rules`, `functions/index.js`, related tests

**Surfaces:** learning/movements widgets, Playground setlist/live practice wiring, `training_recommendation.dart`, `training_plan_editor.dart`, assignment detail presentation

Do not invent teacher composer paths; use existing `lib/features/teacher/movements/teacher_assignment_composer.dart`.
