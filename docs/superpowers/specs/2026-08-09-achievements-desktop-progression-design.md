# Achievements Desktop Progression & Profile Frames Redesign

**Date:** 2026-08-09  
**Status:** Approved (design sections 1–5 + refinements)  
**Branch constraint:** Work on current `main` only; no branch creation or switching.

## Problem

The Achievements screen feels compressed (web/mobile grid): max content width ~1120, cards ~168px tall with max cross extent ~380, duplicated status badges, and catalog order instead of intentional easy→hard progression. Settings Profile Frames iterates `profileBorderCatalog` directly, mixing locked and unlocked cosmetics so owned frames are hard to find.

## Goals

1. Desktop-first Achievements layout that uses horizontal workspace well.
2. Explicit easiest-to-hardest achievement progression (presentation only).
3. Profile Frames in Settings follow the same progression and show unlocked before locked.
4. Preserve all evaluation, claiming, Firestore, XP, leaderboard, and border persistence behavior.

## Non-goals

- Changing achievement IDs, border IDs, targets, evaluators, claim flow, Firestore schema, repository APIs (unless required for presentation helpers), XP, leaderboard, session tracking, border painters, or animation mechanics.
- Per-achievement Easy/Medium/Hard difficulty badges.
- Large new cosmetics architecture.
- Equating achievement progression with movement session Easy/Medium/Hard.

## Files in scope

| File | Role |
| --- | --- |
| `lib/data/models/achievement.dart` | Progression metadata + minimal sort comparator |
| `lib/data/models/profile_border.dart` | Small pure presentation-order helper for frames |
| `lib/features/achievements/achievements_screen.dart` | Responsive grid, progression cue, sorted filtered views |
| `lib/features/achievements/widgets/achievement_card.dart` | Card hierarchy / single status / calmer states |
| `lib/features/settings/widgets/profile_frame_selector.dart` | Grouped Unlocked/Locked UI using domain helper |

Tests: add/update under `test/data/models/`, `test/features/achievements/`, `test/features/settings/` as needed.

---

## 1. Progression domain (source of truth)

### Metadata

Add `progressionOrder` (`int`) to `AchievementDefinition`. Every current achievement gets a unique deterministic value.

### Agreed order

| Order | Achievement |
| ---: | --- |
| 1 | First Steps (`first_steps`) |
| 2 | Getting Started (`getting_started`) |
| 3 | Movement Explorer (`movement_explorer`) |
| 4 | Sharp Pour (`sharp_pour`) |
| 5 | Week Warrior (`week_warrior`) |
| 6 | Flair Regular (`flair_regular`) |
| 7 | Versatility Master (`versatility_master`) |
| 8 | Bottle in a Tin Specialist (`bottle_in_tin_specialist`) |
| 9 | Perfect Serve (`perfect_serve`) |
| 10 | Century Club (`century_club`) |

### Minimal API

Keep the public/domain API small:

1. Field: `AchievementDefinition.progressionOrder`
2. One central comparator/helper for sorting `AchievementDefinition` / `AchievementViewData` by `progressionOrder` (and stable tie-break by `id` if needed)
3. Only the additional border presentation-order helper Settings needs (owned by profile-border / achievement domain, not the widget)

Do **not** add overlapping helpers (`achievementProgressionOrder`, `achievementsInProgressionOrder`, etc.) unless each has a concrete caller.

### Filtered achievements

1. Apply existing filter semantics (All / Claimable / In Progress / Claimed / Locked).
2. Sort the resulting subset by `progressionOrder`.

Catalog list order must **not** be treated as visual progression. Evaluation and `buildAllAchievementViewData` semantics stay the same aside from optional sorting at the presentation boundary (or sorting inside filtered getters).

---

## 2. Desktop Achievements layout

### Content width

- Max content width ≈ **1400** logical px (1360–1440 band).
- Preserve outer gutters via existing page padding + sidebar shell.

### Responsive grid (prefer card-width-driven)

Derive column count from available `LayoutBuilder` width:

- Desired minimum readable card width ≈ **420**
- Grid spacing ≈ **16**
- Max columns **3**, min **1**
- Never force 3 columns when cards would become cramped

Conceptual algorithm:

```
columns = floor((availableWidth + gap) / (minCardWidth + gap)).clamp(1, 3)
```

Use `SliverGridDelegateWithFixedCrossAxisCount` (or equivalent) with that column count and `mainAxisExtent` ≈ **200**. Explicit breakpoints are acceptable only if they yield clearer Flutter code **and** still enforce the no-cramped-3-columns invariant.

### Spacing

- Grid gap ≈ 16px
- Card height ≈ 190–210 (target ~200)
- Internal card padding ≈ 16–18px
- Comfortable vertical rhythm between header, toolbar, and grid

### Common Windows widths

Validate layout mentally/code-wise for content areas typical at shell widths **1280 / 1366 / 1440 / 1600 / 1920** (after sidebar). Avoid large empty gutters from an undersized max-width **and** avoid overflow on narrower windows.

### Progression cue

Near the Achievements section heading, subtle caption:

`Progression · Easy → Advanced`

UX cue only — not the movement difficulty system.

---

## 3. Achievement card hierarchy

```
Top:    [frame preview] [title + category] [single status pill]
Middle: description (readable, max ~2 lines, no overflow)
Bottom: progress label + current/target
        progress bar
        reward name + Claim button when claimable
```

### Rules

- Exactly **one** status pill (Locked / In Progress / Claimable / Claimed).
- Remove duplicated footer state badges.
- Reward name remains discoverable.
- Claimable: strongest interaction affordance (Claim button + existing hover/focus/keyboard activate).
- Do **not** lift/animate non-interactive cards as clickable.
- In Progress: use warning color carefully; calm, not error-like.
- Claimed: completed without heavy green outline.
- Locked: subdued but readable.
- Frame preview remains the strongest decorative element.
- Preserve Semantics / mouse / keyboard.

Do not leave large dead space inside ~200px cards by over-thinning content.

---

## 4. Settings Profile Frames

### Visual structure

```
[No Frame]          ← utility control, outside Unlocked

Unlocked            ← compact subtle label
  [equipped]        ← first when present
  [other unlocked…] ← by achievement progressionOrder

Locked              ← compact subtle label
  [locked…]         ← by achievement progressionOrder
```

- Keep labels subtle/compact; small gaps so it remains one cosmetics selector.
- Do **not** put No Frame under Unlocked.
- Do **not** hard-code the progression sequence in `profile_frame_selector.dart`.

### Sort keys

| Group | Order |
| --- | --- |
| Unlocked | equipped first (if present), then others by achievement `progressionOrder` |
| Locked | by achievement `progressionOrder` |

Do **not** sort by rarity, catalog position (except defensive unmapped fallback), display name, color, or ID as primary keys.

### Edge cases

**Equipped but not in `unlockedBorderIds`:**  
Present first under Unlocked as equipped/selected. Do **not** mutate unlocked sets, persist unlocks, or change Firestore/repos. Presentation-only tolerance. Unknown/invalid equipped IDs: keep current defensive behavior (no manufactured frame).

**Border without achievement mapping:**  
After all progression-backed borders within its unlock group; deterministic fallback (e.g. original catalog index). Must not mask 1:1 catalog contract failures — tests fail if an achievement references a missing border.

---

## 5. Testability

Extract a **small pure** presentation-order function (likely on `profile_border.dart` or beside it) returning ordered border IDs / definitions for Unlocked and Locked so unit tests cover:

- No Frame remains outside Unlocked (widget or structure assertion)
- Equipped first among unlocked
- Unlocked before locked
- Progression ordering in both subsets
- Defensive equipped-not-unlocked and unmapped-border fallback

Achievement filter + progression: test at domain/helper level (sort after filter).

Contract invariants:

- Unique `progressionOrder` for every achievement
- Every achievement has valid `progressionOrder`
- Every `rewardBorderId` resolves to a known border
- Every achievement-backed border can resolve back to its achievement progression

Existing evaluation / claim / catalog contract tests must continue passing.

---

## 6. Verification

```powershell
flutter analyze
flutter test test/data/models/achievement_test.dart
flutter test test/data/models/profile_border_test.dart
flutter test test/data/models/achievement_catalog_contract_test.dart
flutter test test/features/achievements/
flutter test test/features/settings/profile_frame_settings_test.dart
```

Plus any new progression/order test files created by the plan.

---

## 7. Acceptance

At wide desktop: better horizontal use, substantial cards, intentional spacing, clear easy→advanced progression, no duplicated status badges.  
At smaller Windows sizes: 3→2→1 columns gracefully; no overflow/clipping.  
Settings: No Frame → Unlocked (equipped first) → Locked; no mixed hunting.  
Ordering deterministic after relaunch. No underlying achievement logic changes.
