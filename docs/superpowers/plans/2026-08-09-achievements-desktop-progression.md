# Achievements Desktop Progression & Profile Frames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (preferred for this session on `main`) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Achievements for Windows desktop with explicit easy→hard progression, cleaner cards, and Settings Profile Frames grouped Unlocked-before-Locked using the same achievement progression.

**Architecture:** Add `progressionOrder` on `AchievementDefinition` plus one sort comparator in `achievement.dart`. Add one small pure presentation-order helper in `profile_border.dart` that Settings consumes. Achievements screen derives responsive column count from available width and min card width. Cards drop duplicate status badges. No evaluation/claim/Firestore changes.

**Tech Stack:** Flutter Windows desktop, Fluent UI, existing achievement/profile-border models, `flutter_test`.

## Global Constraints

- Work on current `main` only — do not create, suggest, or switch branches.
- Do not commit unless the user explicitly asks.
- Do not change achievement IDs, border IDs, targets, evaluators, claim/Firestore/XP/leaderboard, border painters, or animation mechanics.
- Keep domain API minimal: `progressionOrder` + one achievement sort helper + one frame presentation-order helper.
- Do not hard-code progression sequences in widgets.
- Rarity is not difficulty/progression.

## File map

| File | Responsibility |
| --- | --- |
| `lib/data/models/achievement.dart` | `progressionOrder` field; assign 1–10; `compareAchievementsByProgression` (or equivalent single helper) |
| `lib/data/models/profile_border.dart` | Pure `buildProfileFramePresentationOrder(...)` returning unlocked/locked lists |
| `lib/features/achievements/achievements_screen.dart` | max width ~1400; card-width-driven columns; sort filtered views; progression cue |
| `lib/features/achievements/widgets/achievement_card.dart` | Single status pill; hierarchy; calmer claimed/in-progress; no lift on non-interactive |
| `lib/features/settings/widgets/profile_frame_selector.dart` | No Frame outside groups; Unlocked/Locked labels; consume domain helper |
| `test/data/models/achievement_test.dart` | Progression uniqueness + filter+sort order |
| `test/data/models/profile_border_test.dart` (or new sibling) | Frame presentation order + bidirectional resolve |
| `test/features/achievements/achievements_screen_test.dart` | Update if layout/copy assertions break |
| `test/features/settings/profile_frame_settings_test.dart` | Update for grouping/order if needed |

---

### Task 1: Achievement progression metadata + comparator

**Files:**
- Modify: `lib/data/models/achievement.dart`
- Test: `test/data/models/achievement_test.dart`

**Interfaces:**
- Produces:
  - `AchievementDefinition.progressionOrder` (`int`, required)
  - `int compareAchievementsByProgression(AchievementDefinition a, AchievementDefinition b)`  
    (or accept `AchievementViewData` via `.definition` — one helper is enough)
- Consumes: existing catalog entries only

- [ ] **Step 1: Write failing progression invariant tests**

Add to `test/data/models/achievement_test.dart`:

```dart
group('achievement progression', () {
  test('every achievement has a unique positive progressionOrder', () {
    final orders = achievementCatalog.map((a) => a.progressionOrder).toList();
    expect(orders.every((o) => o > 0), isTrue);
    expect(orders.toSet(), hasLength(achievementCatalog.length));
  });

  test('progressionOrder matches agreed easy-to-hard sequence', () {
    final byOrder = [...achievementCatalog]
      ..sort(compareAchievementsByProgression);
    expect(
      byOrder.map((a) => a.id).toList(),
      [
        'first_steps',
        'getting_started',
        'movement_explorer',
        'sharp_pour',
        'week_warrior',
        'flair_regular',
        'versatility_master',
        'bottle_in_tin_specialist',
        'perfect_serve',
        'century_club',
      ],
    );
  });

  test('filtered subsets preserve progression order', () {
    final views = buildAllAchievementViewData(
      sessions: const [],
      leaderboardEntry: null,
      claimedAchievementIds: {'first_steps', 'century_club'},
    );
    final claimed = views
        .where((v) => v.state == AchievementState.claimed)
        .toList()
      ..sort((a, b) => compareAchievementsByProgression(a.definition, b.definition));
    expect(
      claimed.map((v) => v.definition.id).toList(),
      ['first_steps', 'century_club'],
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
flutter test test/data/models/achievement_test.dart
```

Expected: FAIL — `progressionOrder` / `compareAchievementsByProgression` missing.

- [ ] **Step 3: Implement metadata + single comparator**

In `AchievementDefinition`, add:

```dart
required this.progressionOrder,
// ...
final int progressionOrder;
```

Assign unique orders on each catalog entry per the agreed sequence (First Steps=1 … Century Club=10). Do not reorder catalog list for evaluation semantics.

Add:

```dart
int compareAchievementsByProgression(
  AchievementDefinition a,
  AchievementDefinition b,
) {
  final byOrder = a.progressionOrder.compareTo(b.progressionOrder);
  if (byOrder != 0) return byOrder;
  return a.id.compareTo(b.id);
}
```

Do not add extra unused helpers.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
flutter test test/data/models/achievement_test.dart
```

Expected: PASS for new progression group; existing evaluation tests still pass.

---

### Task 2: Profile frame presentation-order helper

**Files:**
- Modify: `lib/data/models/profile_border.dart` (import achievement if needed; prefer keeping pure Dart — `achievement.dart` already imports `profile_border.dart`, so **avoid circular imports**)

**Circular-import strategy (required):**  
Because `achievement.dart` already imports `profile_border.dart`, put the frame presentation helper in `profile_border.dart` **only if** it can resolve achievement progression without importing `achievement.dart`. Prefer one of:

- **Option A (recommended):** Put `buildProfileFramePresentationOrder` in `achievement.dart` (achievement owns progression; borders are looked up via existing maps), **or**
- **Option B:** Put a tiny pure function in a new file `lib/data/models/profile_frame_presentation.dart` that imports both models.

Update the File map accordingly when implementing — pick A or B to avoid cycles. Do **not** put progression maps in the Settings widget.

**Interfaces:**
- Produces (exact names may match Option A/B):

```dart
class ProfileFramePresentationOrder {
  const ProfileFramePresentationOrder({
    required this.unlockedBorders,
    required this.lockedBorders,
  });

  final List<ProfileBorderDefinition> unlockedBorders;
  final List<ProfileBorderDefinition> lockedBorders;
}

ProfileFramePresentationOrder buildProfileFramePresentationOrder({
  required Set<String> unlockedBorderIds,
  required String? equippedBorderId,
});
```

Algorithm:

1. Normalize equipped: trim; treat empty as null; ignore unknown IDs (not in catalog).
2. Build unlocked set for **presentation**: `unlockedBorderIds` ∪ `{equipped}` when equipped is a known catalog border (do not mutate caller sets).
3. Partition catalog into unlocked vs locked using that presentation set.
4. Sort unlocked: equipped first (if present), then by rewarding achievement `progressionOrder`, then catalog index fallback for unmapped.
5. Sort locked: by progressionOrder, then catalog index fallback.
6. Resolve progression via reverse of `achievementRewardBorderIds` / catalog scan — not rarity.

- [ ] **Step 1: Write failing unit tests**

In `test/data/models/profile_border_test.dart` (or new `test/data/models/profile_frame_presentation_test.dart`):

```dart
test('presentation order: equipped first, unlocked before locked, progression preserved', () {
  final order = buildProfileFramePresentationOrder(
    unlockedBorderIds: {'bronze_ember', 'cyan_orbit', 'starter_glow'},
    equippedBorderId: 'cyan_orbit',
  );
  expect(
    order.unlockedBorders.map((b) => b.id).toList(),
    ['cyan_orbit', 'starter_glow', 'bronze_ember'],
  );
  // locked should be remaining borders sorted by achievement progression
  expect(order.lockedBorders, isNotEmpty);
  expect(
    order.unlockedBorders.any((b) => order.lockedBorders.contains(b)),
    isFalse,
  );
});

test('equipped-but-not-unlocked is shown under unlocked without mutating input', () {
  final unlocked = <String>{'starter_glow'};
  final order = buildProfileFramePresentationOrder(
    unlockedBorderIds: unlocked,
    equippedBorderId: 'gold_mastery',
  );
  expect(unlocked, {'starter_glow'}); // unchanged
  expect(order.unlockedBorders.first.id, 'gold_mastery');
  expect(order.unlockedBorders.map((b) => b.id), contains('starter_glow'));
});

test('every achievement-backed border resolves to achievement progression', () {
  for (final border in profileBorderCatalog) {
    final achievementId = achievementRewardBorderIds.entries
        .firstWhere((e) => e.value == border.id)
        .key;
    final achievement = achievementById(achievementId);
    expect(achievement, isNotNull);
    expect(achievement!.progressionOrder, greaterThan(0));
  }
});
```

Adjust expected unlocked ID order to match progression (First Steps=`starter_glow`, Getting Started=`bronze_ember`, Sharp Pour=`cyan_orbit`).

- [ ] **Step 2: Run tests — expect FAIL**

```powershell
flutter test test/data/models/profile_border_test.dart
```

- [ ] **Step 3: Implement helper (Option A or B)**

Implement deterministic sort key:

```dart
int _borderProgressionKey(String borderId, Map<String, int> catalogIndex) {
  // find achievement rewarding this border → progressionOrder
  // else return large sentinel + catalogIndex[borderId]
}
```

- [ ] **Step 4: Run tests — expect PASS**

Also re-run:

```powershell
flutter test test/data/models/achievement_catalog_contract_test.dart
flutter test test/data/models/profile_border_test.dart
```

---

### Task 3: Achievements screen — sort + layout + cue

**Files:**
- Modify: `lib/features/achievements/achievements_screen.dart`
- Test: `test/features/achievements/achievements_screen_test.dart` (update as needed)

**Interfaces:**
- Consumes: `compareAchievementsByProgression`
- Layout constants: `_kMaxContentWidth = 1400`, `_kMinCardWidth ≈ 420`, `_kGridGap = 16`, `_kCardExtent ≈ 200`

- [ ] **Step 1: Sort filtered views by progression**

Change `_filteredViews` to filter then sort:

```dart
List<AchievementViewData> get _filteredViews {
  final views = [..._views]; // or filter from _views
  final filtered = switch (_filter) { /* existing */ };
  filtered.sort(
    (a, b) => compareAchievementsByProgression(a.definition, b.definition),
  );
  return filtered;
}
```

Ensure `_views` / `buildAllAchievementViewData` evaluation path unchanged.

- [ ] **Step 2: Add progression cue**

In `_AchievementsToolbarTitleGroup`, under the existing subtitle (or replace the denser subtitle carefully), add:

```dart
Text(
  'Progression · Easy → Advanced',
  style: AppTheme.caption.copyWith(
    color: context.elixTextSecondary.withValues(alpha: 0.85),
    fontSize: 11,
  ),
);
```

Keep existing helpful subtitle about Settings if space allows; prefer stacking: title → progression cue → short helper line without bulk.

- [ ] **Step 3: Card-width-driven grid**

Replace fixed `SliverGridDelegateWithMaxCrossAxisExtent` with `LayoutBuilder`:

```dart
int _achievementColumnCount(double width) {
  const minCard = 420.0;
  const gap = 16.0;
  final columns = ((width + gap) / (minCard + gap)).floor();
  return columns.clamp(1, 3);
}
```

Use:

```dart
SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: columnCount,
  mainAxisExtent: 200,
  mainAxisSpacing: 16,
  crossAxisSpacing: 16,
)
```

Set `_kMaxContentWidth = 1400`.

Sanity-check column counts for content widths ≈ 900 / 1100 / 1360 / 1600.

- [ ] **Step 4: Run achievements tests**

```powershell
flutter test test/features/achievements/
```

Fix assertion churn (keys, copy) without weakening coverage.

---

### Task 4: Modernize `AchievementCard`

**Files:**
- Modify: `lib/features/achievements/widgets/achievement_card.dart`

- [ ] **Step 1: Restructure layout**

Implement approved hierarchy; padding 16–18; ensure ~200 height fills without large empty voids and without overflow.

- [ ] **Step 2: Remove duplicate footer state badges**

Footer for non-claimable: reward name only (and progress already above). Claimable: reward name + Claim button. Keep single top status pill.

- [ ] **Step 3: Tone adjustments**

- Claimed: soft success accent (left strip / pill), border uses normal card border opacity — not heavy green outline.
- In Progress: calm warning tint (lower alpha), not alarm.
- Locked: reduced opacity / muted secondary text; still readable.
- Interactive lift/hover **only** when `_interactive` (claimable && !claiming).

- [ ] **Step 4: Preserve a11y**

Keep Semantics label with state + progress + claim action; FocusableActionDetector only when interactive.

- [ ] **Step 5: Run related tests**

```powershell
flutter test test/features/achievements/
```

---

### Task 5: Settings `ProfileFrameSelector` grouping UI

**Files:**
- Modify: `lib/features/settings/widgets/profile_frame_selector.dart`
- Test: `test/features/settings/profile_frame_settings_test.dart`

- [ ] **Step 1: Consume presentation helper**

```dart
final order = buildProfileFramePresentationOrder(
  unlockedBorderIds: unlockedBorderIds,
  equippedBorderId: equippedBorderId,
);
```

Build children:

1. `_NoFrameTile`
2. Compact `_FrameGroupLabel('Unlocked')` (only if unlocked list non-empty, or always if any frames exist — prefer always show Unlocked when there is at least one unlocked presentation frame; show Locked when locked non-empty)
3. unlocked tiles in `order.unlockedBorders`
4. `_FrameGroupLabel('Locked')` when locked non-empty
5. locked tiles

Use `Column` + nested `Wrap` (or Wrap with full-width label widgets) so labels sit above their tiles without bulky card chrome.

- [ ] **Step 2: Subtle labels**

Caption style, low contrast, tight vertical padding (~4–6px). No section cards.

- [ ] **Step 3: Tile affordances**

Keep existing grayscale locked tiles, tooltips, focus, equipped animation (`animate: selected && unlocked` — for equipped-not-in-unlocked presentation, allow animate when selected since it is visually under Unlocked; do not change painter). Slightly strengthen selected border if needed without enlarging tiles into huge cards.

- [ ] **Step 4: Update settings tests**

Assert No Frame key first; if tests traverse `frame_tile_*` order, update expectations to progression/equipped-first. Add a focused unit test on the helper rather than fragile pixel tests where possible.

```powershell
flutter test test/features/settings/profile_frame_settings_test.dart
```

---

### Task 6: Full verification + adversarial review

- [ ] **Step 1: Analyze**

```powershell
flutter analyze
```

Expected: no issues in touched files.

- [ ] **Step 2: Run focused test set**

```powershell
flutter test test/data/models/achievement_test.dart
flutter test test/data/models/profile_border_test.dart
flutter test test/data/models/achievement_catalog_contract_test.dart
flutter test test/features/achievements/
flutter test test/features/settings/profile_frame_settings_test.dart
```

If a new presentation test file was added, include it.

- [ ] **Step 3: Diff review checklist**

- No evaluator/target/ID changes
- No Firestore/repo claim changes
- No painter/animation mechanic changes
- No progression maps in widgets
- No commit unless user requested

- [ ] **Step 4: Completion report**

Report files changed, layout strategy, final progression order, frame sorting strategy, analyze/test results, edge cases, `Not verified` (manual Windows UI at 1280–1920).

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| `progressionOrder` + unique sequence | Task 1 |
| Minimal comparator API | Task 1 |
| Filter then sort | Task 1 tests + Task 3 |
| Bidirectional border↔achievement progression tests | Task 2 |
| Pure presentation-order helper (testable) | Task 2 |
| Card-width-driven 1–3 columns, ~1400 max width, ~200 height, 16 gaps | Task 3 |
| Progression cue copy | Task 3 |
| Single status pill / hierarchy / calmer states | Task 4 |
| No Frame outside Unlocked; Unlocked/Locked labels | Task 5 |
| Equipped-not-unlocked presentation-only | Task 2 + 5 |
| Unmapped border deterministic fallback | Task 2 |
| analyze + relevant tests | Task 6 |

## Placeholder / consistency self-review

- Helper ownership explicitly handles circular import via Option A or B.
- Comparator name locked as `compareAchievementsByProgression`.
- Presentation type locked as `ProfileFramePresentationOrder` / `buildProfileFramePresentationOrder`.
- Commit steps omitted per user rule (commit only when asked).
