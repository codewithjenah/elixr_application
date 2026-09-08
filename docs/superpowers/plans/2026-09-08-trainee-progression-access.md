# Trainee Progression Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one canonical Level 1–16 personal progression/access policy for exact `PracticeVariant`s, with secure teacher assignment-scoped override that never leaks into Playground or personal surfaces.

**Architecture:** Pure `ProgressionAccessPolicy` evaluates already-resolved inputs into context-specific results (`personal*` vs `assignment*`). `PracticeVariant` is the persistence identity; resolve against `movementCatalog` to `PracticeCatalogStep`. Tutorial keys, Playground setlists, and official `allowed_prop` all use exact variants. Firestore Rules + Cloud Functions gain prop allowlists kept honest by parity tests.

**Tech Stack:** Flutter/Dart (Windows desktop), Provider/`ChangeNotifier`, go_router, Firestore rules, Cloud Functions (`functions/index.js`), existing `GamificationRules` / leaderboard XP.

**Spec:** `docs/superpowers/specs/2026-09-08-trainee-progression-access-design.md`

## Global Constraints

- Work directly on `main` only — do not create, switch, or suggest another branch.
- Do not create git commits unless the user explicitly requests them (skip Commit steps otherwise).
- Do not deploy Firestore rules or Cloud Functions unless the user explicitly requests deploy.
- Do not change XP formulas (`xpPerSession=25`, `xpPerLevel=250`), Daily Quest XP, or leaderboard award semantics.
- Do not change official movement identities or invent duplicate movements.
- Do not use `Movement.enabled` as a user progression flag.
- Do not weaken Firestore recipient/membership authorization.
- Never add client bypass query flags (`bypass`, `teacher`, `assignmentAccess`, `ignoreLevel`).
- Router must consume resolved access results; must not fetch XP or assignment auth itself.
- Personal surfaces must never wait on assignment authorization (`personalLoading` ≠ assignment loading).
- Preserve CV assessment, reduced motion, keyboard/semantics, Fluent dark/pink Windows layout.
- No temporary diagnostics; no unrelated refactors.

## File structure (create / modify)

### Create

| File | Responsibility |
|---|---|
| `lib/core/progression/practice_variant.dart` | Stable identity: movementName + TrainingProp; persistence key helpers |
| `lib/core/progression/progression_catalog.dart` | Exact 16 milestones + requiredLevel / nextUnlock helpers |
| `lib/core/progression/progression_access.dart` | Access result enum + AssignmentGrant + pure policy |
| `lib/core/progression/official_supported_props.dart` | Flutter-side derived allowlist from `movementCatalog` (parity source) |
| `lib/core/progression/assignment_prop_resolution.dart` | Resolve assignment `allowed_prop` with legacy fallback A |
| `test/core/progression/practice_variant_test.dart` | Variant identity / persistence keys |
| `test/core/progression/progression_catalog_test.dart` | 16 milestones + catalog drift guards |
| `test/core/progression/progression_access_policy_test.dart` | Personal vs assignment evaluation + loading |
| `test/core/progression/tutorial_progress_migration_test.dart` | Legacy → exact-variant migration |
| `test/core/progression/official_movement_prop_parity_test.dart` | Flutter ↔ Functions ↔ Rules allowlist parity |
| `test/core/progression/assignment_prop_resolution_test.dart` | Legacy fallback A |

### Modify (primary)

| File | Why |
|---|---|
| `lib/services/tutorial_progress_service.dart` | Exact-variant lesson keys + migration |
| `lib/core/router/app_redirect.dart` | Consume personal access results (no fetches) |
| `lib/core/router/app_router.dart` | Pass resolved personal access inputs into redirect state |
| `lib/data/repositories/classroom_assignment_repository.dart` | Official create payload requires `allowed_prop` |
| `lib/data/repositories/firebase_classroom_assignment_repository.dart` | Pass `allowed_prop` through Function create |
| `lib/data/repositories/in_memory_classroom_assignment_repository.dart` | Mirror official prop create |
| `lib/features/teacher/movements/teacher_assignment_composer.dart` | Exact prop picker for official Medium variants |
| `lib/features/assigned_movements/assigned_practice_screen.dart` | No prop picker; use resolved assignment variant |
| `lib/features/learning/movement_lesson.dart` | Exact prop completion + personal/assignment access |
| `lib/features/learning/learning_center_screen.dart` | Prop-aware lesson links / states |
| `lib/features/movements/widgets/movement_card.dart` | Independent prop rows + lock/learn/ready CTAs |
| `lib/features/movements/movements_presentation.dart` | Wire policy presentation if needed |
| `lib/services/settings_service.dart` | Persist Playground as variants; migrate legacy names |
| `lib/features/settings/widgets/practice_preferences_controller.dart` | Variant setlist editing |
| `lib/features/practice/just_dance/movement_setlist_dialog.dart` | Build Your Set = exact variants |
| `lib/features/practice/live_practice_screen.dart` | Resolve variants + personalReady gate + HUD |
| `lib/features/progress/training_recommendation.dart` | Respect personal access |
| `lib/features/calendar/widgets/training_plan_editor.dart` | Only personalReady selectable |
| `lib/features/dashboard/dashboard_screen.dart` / hero | Practice CTAs respect personal access |
| `firestore.rules` | Official create/update require valid `allowed_prop` |
| `functions/index.js` | Official create persists/validates `allowed_prop` |
| Matching existing tests under `test/` and `firestore-tests/` | Update contracts |

### Rollout / migration order (do not reorder)

1. Domain: variant + catalog + pure policy (tests first)
2. Tutorial migration (local only; safe)
3. Assignment prop resolution helper (client read path)
4. Official create/update contracts: Flutter → Functions → Rules + parity tests
5. Teacher composer prop UI
6. Trainee assignment flow (no picker; assignment access)
7. Router personal gates
8. Learning / Movements UI
9. Playground persistence + runtime gate
10. Recommendations + calendar
11. Targeted tests → `flutter analyze` → full `flutter test` once
12. Deploy rules/functions **only** on explicit user request

---

### Task 1: PracticeVariant identity

**Files:**
- Create: `lib/core/progression/practice_variant.dart`
- Test: `test/core/progression/practice_variant_test.dart`

**Interfaces:**
- Produces: `PracticeVariant`, `PracticeVariant.persistenceKey`, `PracticeVariant.tryParsePersistenceKey`, equality/hashCode

- [ ] **Step 1: Write the failing test**

```dart
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hand Stall Bottle and Shaker are distinct', () {
    const bottle = PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.bottle,
    );
    const shaker = PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.shaker,
    );
    expect(bottle, isNot(equals(shaker)));
    expect(bottle.persistenceKey, 'Hand Stall|bottle');
    expect(shaker.persistenceKey, 'Hand Stall|shaker');
  });

  test('round-trips persistence key', () {
    const v = PracticeVariant(
      movementName: 'Bottle in a tin',
      trainingProp: TrainingProp.bottleAndShaker,
    );
    expect(PracticeVariant.tryParsePersistenceKey(v.persistenceKey), v);
  });

  test('rejects malformed keys', () {
    expect(PracticeVariant.tryParsePersistenceKey('Hand Stall'), isNull);
    expect(PracticeVariant.tryParsePersistenceKey('Hand Stall|nope'), isNull);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (library missing)**

```powershell
flutter test test/core/progression/practice_variant_test.dart
```

- [ ] **Step 3: Implement**

```dart
import '../../data/models/training_prop.dart';

/// Stable domain/persistence identity for an exact practice variant.
class PracticeVariant {
  const PracticeVariant({
    required this.movementName,
    required this.trainingProp,
  });

  final String movementName;
  final TrainingProp trainingProp;

  /// Deterministic persistence token. Never store display labels.
  String get persistenceKey => '$movementName|${trainingProp.protocolValue}';

  static PracticeVariant? tryParsePersistenceKey(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final sep = trimmed.lastIndexOf('|');
    if (sep <= 0 || sep >= trimmed.length - 1) return null;
    final name = trimmed.substring(0, sep).trim();
    final prop = TrainingProp.tryParseStrict(trimmed.substring(sep + 1));
    if (name.isEmpty || prop == null) return null;
    return PracticeVariant(movementName: name, trainingProp: prop);
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeVariant &&
      other.movementName == movementName &&
      other.trainingProp == trainingProp;

  @override
  int get hashCode => Object.hash(movementName, trainingProp);
}
```

- [ ] **Step 4: Re-run test — expect PASS**

```powershell
flutter test test/core/progression/practice_variant_test.dart
```

- [ ] **Step 5: Commit only if user requested**

---

### Task 2: Progression catalog (16 milestones)

**Files:**
- Create: `lib/core/progression/progression_catalog.dart`
- Create: `lib/core/progression/official_supported_props.dart`
- Test: `test/core/progression/progression_catalog_test.dart`

**Interfaces:**
- Consumes: `PracticeVariant`, `movementCatalog`, `GamificationRules`
- Produces:
  - `progressionMilestones` (exactly 16)
  - `int? requiredLevelFor(PracticeVariant)`
  - `bool isLevelUnlocked(PracticeVariant, int level)`
  - `PracticeVariant? nextUnlockAfterLevel(int level)`
  - `int xpRemainingToNextUnlock(int totalXp)`
  - `List<PracticeVariant> allPersonallyLevelUnlockedVariants(int level)`
  - `PracticeCatalogStep? resolvePracticeVariant(PracticeVariant)`
  - `Set<PracticeVariant> officialSupportedPracticeVariants()` from catalog

- [ ] **Step 1: Write failing catalog drift tests**

```dart
import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exactly 16 milestones and one new unlock per level 1-16', () {
    expect(progressionMilestones.length, 16);
    for (var level = 1; level <= 16; level++) {
      expect(
        progressionMilestones.where((m) => m.requiredLevel == level).length,
        1,
      );
    }
  });

  test('level 1 is Normal Grip / Bottle; level 16 is Bottle in a tin combined', () {
    expect(progressionMilestones.first.variant, const PracticeVariant(
      movementName: 'Normal Grip',
      trainingProp: TrainingProp.bottle,
    ));
    expect(progressionMilestones.last.variant, const PracticeVariant(
      movementName: 'Bottle in a tin',
      trainingProp: TrainingProp.bottleAndShaker,
    ));
  });

  test('every milestone is a real catalog movement + supported prop', () {
    for (final milestone in progressionMilestones) {
      final step = resolvePracticeVariant(milestone.variant);
      expect(step, isNotNull, reason: milestone.variant.persistenceKey);
      expect(step!.movement.enabled, isTrue);
    }
  });

  test('Hand Stall bottle unlocks at 5 and shaker at 6', () {
    expect(
      requiredLevelFor(const PracticeVariant(
        movementName: 'Hand Stall',
        trainingProp: TrainingProp.bottle,
      )),
      5,
    );
    expect(
      requiredLevelFor(const PracticeVariant(
        movementName: 'Hand Stall',
        trainingProp: TrainingProp.shaker,
      )),
      6,
    );
  });

  test('level 17 unlocks no new content; nextUnlock after 16 is null', () {
    expect(allPersonallyLevelUnlockedVariants(16).length, 16);
    expect(allPersonallyLevelUnlockedVariants(17).length, 16);
    expect(nextUnlockAfterLevel(16), isNull);
  });

  test('xpRemainingToNextUnlock uses GamificationRules', () {
    // Level 1 trainee with 80 XP into level → 170 to level 2 unlock
    expect(xpRemainingToNextUnlock(80), GamificationRules.xpPerLevel - 80);
    // Already at/above content ceiling (level 16+): 0 remaining content XP gate
    final level16Xp = GamificationRules.xpPerLevel * 15;
    expect(xpRemainingToNextUnlock(level16Xp), 0);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```powershell
flutter test test/core/progression/progression_catalog_test.dart
```

- [ ] **Step 3: Implement catalog + resolve helper**

Implement `ProgressionMilestone` (`requiredLevel`, `variant`) and ordered `progressionMilestones` matching the spec table exactly.

```dart
PracticeCatalogStep? resolvePracticeVariant(PracticeVariant variant) {
  final movement = movementCatalog.cast<Movement?>().firstWhere(
    (m) => m!.name == variant.movementName,
    orElse: () => null,
  );
  if (movement == null || !movement.supportedProps.contains(variant.trainingProp)) {
    return null;
  }
  return PracticeCatalogStep(movement: movement, prop: variant.trainingProp);
}
```

Prefer a clear loop over `firstWhere` if that reads better in-repo.

`official_supported_props.dart`:

```dart
Set<PracticeVariant> officialSupportedPracticeVariants() {
  return {
    for (final movement in movementCatalog)
      if (movement.enabled)
        for (final prop in movement.supportedProps)
          PracticeVariant(movementName: movement.name, trainingProp: prop),
  };
}
```

- [ ] **Step 4: Re-run — expect PASS**

```powershell
flutter test test/core/progression/progression_catalog_test.dart
```

---

### Task 3: Pure ProgressionAccessPolicy

**Files:**
- Create: `lib/core/progression/progression_access.dart`
- Test: `test/core/progression/progression_access_policy_test.dart`

**Interfaces:**
- Consumes: `PracticeVariant`, `resolvePracticeVariant`, `requiredLevelFor`
- Produces:
  - `enum ProgressionAccessResult { personalLoading, assignmentLoading, invalid, personalLocked, personalLearn, personalReady, assignmentLearn, assignmentReady }`
  - `class AssignmentGrant { final bool isAuthorized; }` (or richer immutable grant already validated by caller)
  - `ProgressionAccessResult evaluatePersonal({required PracticeVariant variant, required int? currentLevel, required bool? tutorialCompleted})`
  - `ProgressionAccessResult evaluateAssignment({required PracticeVariant variant, required AssignmentGrant? assignmentGrant, required bool? tutorialCompleted})`

- [ ] **Step 1: Write failing policy tests**

```dart
test('personal loading when level unknown does not require assignment', () {
  expect(
    evaluatePersonal(
      variant: normalGripBottle,
      currentLevel: null,
      tutorialCompleted: false,
    ),
    ProgressionAccessResult.personalLoading,
  );
});

test('personal locked below level', () {
  expect(
    evaluatePersonal(
      variant: elbowShaker, // required 12
      currentLevel: 3,
      tutorialCompleted: true,
    ),
    ProgressionAccessResult.personalLocked,
  );
});

test('personal learn then ready', () {
  expect(
    evaluatePersonal(variant: handStallShaker, currentLevel: 6, tutorialCompleted: false),
    ProgressionAccessResult.personalLearn,
  );
  expect(
    evaluatePersonal(variant: handStallShaker, currentLevel: 6, tutorialCompleted: true),
    ProgressionAccessResult.personalReady,
  );
});

test('assignment ready ignores personal level', () {
  expect(
    evaluateAssignment(
      variant: elbowShaker,
      assignmentGrant: const AssignmentGrant(isAuthorized: true),
      tutorialCompleted: true,
    ),
    ProgressionAccessResult.assignmentReady,
  );
});

test('unauthorized assignment is invalid even if tutorial done', () {
  expect(
    evaluateAssignment(
      variant: elbowShaker,
      assignmentGrant: const AssignmentGrant(isAuthorized: false),
      tutorialCompleted: true,
    ),
    ProgressionAccessResult.invalid,
  );
});

test('assignment loading when grant unknown', () {
  expect(
    evaluateAssignment(
      variant: elbowShaker,
      assignmentGrant: null,
      tutorialCompleted: true,
    ),
    ProgressionAccessResult.assignmentLoading,
  );
});

test('unsupported variant is invalid', () {
  expect(
    evaluatePersonal(
      variant: const PracticeVariant(
        movementName: 'Not A Real Move',
        trainingProp: TrainingProp.bottle,
      ),
      currentLevel: 99,
      tutorialCompleted: true,
    ),
    ProgressionAccessResult.invalid,
  );
});
```

- [ ] **Step 2: Run — expect FAIL**

```powershell
flutter test test/core/progression/progression_access_policy_test.dart
```

- [ ] **Step 3: Implement pure policy**

```dart
ProgressionAccessResult evaluatePersonal({
  required PracticeVariant variant,
  required int? currentLevel,
  required bool? tutorialCompleted,
}) {
  if (resolvePracticeVariant(variant) == null) {
    return ProgressionAccessResult.invalid;
  }
  if (currentLevel == null || tutorialCompleted == null) {
    return ProgressionAccessResult.personalLoading;
  }
  final required = requiredLevelFor(variant);
  if (required == null || currentLevel < required) {
    return ProgressionAccessResult.personalLocked;
  }
  return tutorialCompleted
      ? ProgressionAccessResult.personalReady
      : ProgressionAccessResult.personalLearn;
}

ProgressionAccessResult evaluateAssignment({
  required PracticeVariant variant,
  required AssignmentGrant? assignmentGrant,
  required bool? tutorialCompleted,
}) {
  if (resolvePracticeVariant(variant) == null) {
    return ProgressionAccessResult.invalid;
  }
  if (assignmentGrant == null || tutorialCompleted == null) {
    return ProgressionAccessResult.assignmentLoading;
  }
  if (!assignmentGrant.isAuthorized) {
    return ProgressionAccessResult.invalid;
  }
  return tutorialCompleted
      ? ProgressionAccessResult.assignmentReady
      : ProgressionAccessResult.assignmentLearn;
}
```

Important: callers must only set `AssignmentGrant(isAuthorized: true)` after authentic assignment + recipient + movement/prop match checks. Policy does not re-fetch Firestore.

- [ ] **Step 4: Re-run — expect PASS**

---

### Task 4: Tutorial progress exact-variant migration

**Files:**
- Modify: `lib/services/tutorial_progress_service.dart`
- Test: `test/core/progression/tutorial_progress_migration_test.dart`

**Interfaces:**
- Produces:
  - `bool hasCompletedLesson(String movement, TrainingProp prop)`
  - `Future<bool> completeLesson(String movement, TrainingProp prop)`
  - Keep temporary adapters only if compile breaks; migrate all call sites in later tasks

Migration rules on load:

1. Read `completed_lessons` list.
2. For each entry:
   - If `PracticeVariant.tryParsePersistenceKey(entry)` succeeds → keep.
   - Else treat as legacy movement name → map to `PracticeVariant(name, firstSupportedProp)` if movement exists; else discard.
3. Write back only when migration changed the set (idempotent).
4. New writes store `persistenceKey` only.

- [ ] **Step 1: Write failing migration tests using `TutorialProgressService(file: tempFile)`**

Cover at minimum:

- legacy `Normal Grip` → `Normal Grip|bottle`
- legacy `Hand Stall` → Bottle only; Shaker incomplete
- same for One Finger / Forearm / Elbow Stall
- legacy `Bottle in a tin` → `bottle_and_shaker`
- second `setUser` does not duplicate
- `completeLesson('Hand Stall', TrainingProp.shaker)` writes exact key

- [ ] **Step 2: Run — expect FAIL on old API**

```powershell
flutter test test/core/progression/tutorial_progress_migration_test.dart
```

- [ ] **Step 3: Implement migration + new API**

Update `_load` / `_update` to store variant keys. Prefer migrating once when account map is loaded and persist if dirty.

- [ ] **Step 4: Fix compile breaks at call sites with temporary shim only if needed**

If many call sites still use `hasCompletedLesson(name)`, either:

- update them in this task for compile green, or
- provide deprecated wrapper that maps to first supported prop **only for compile**, then remove in Tasks 7–10.

Preferred: update known call sites in the same PR wave as this task if they are few (`movement_card`, `app_router`, `movement_lesson`, `assigned_practice_screen`, `dashboard_screen`). Use exact prop from route/context where available; otherwise first supported prop for display-only paths until UI tasks land.

- [ ] **Step 5: Re-run migration tests — PASS**

---

### Task 5: Assignment prop resolution (legacy fallback A)

**Files:**
- Create: `lib/core/progression/assignment_prop_resolution.dart`
- Test: `test/core/progression/assignment_prop_resolution_test.dart`

**Interfaces:**
- Produces: `TrainingProp? resolvedAllowedPropForOfficialAssignment({required String officialMovementName, required TrainingProp? storedAllowedProp})`
- Also: `PracticeVariant? practiceVariantForOfficialAssignment(...)`

Rules:

- If `storedAllowedProp != null`: accept only if supported for that movement; else null (invalid).
- If missing: return `movement.supportedProps.first` (Bottle for Medium; combined for Bottle in a tin).

- [ ] **Step 1–4: TDD as above**

---

### Task 6: Official assignment create/update — Flutter repositories

**Files:**
- Modify: `lib/data/repositories/classroom_assignment_repository.dart` (`officialAssignmentPayload`, abstract create signatures)
- Modify: `lib/data/repositories/firebase_classroom_assignment_repository.dart`
- Modify: `lib/data/repositories/in_memory_classroom_assignment_repository.dart`
- Modify: `lib/features/teacher/movements/teacher_assignment_composer.dart` (`TeacherAssignmentCreationService.create`)
- Update: `test/data/repositories/classroom_assignment_repository_test.dart`
- Update: `test/data/repositories/firebase_classroom_assignment_repository_test.dart` (payload expectations)
- Update: `test/features/teacher/movements/teacher_assignment_composer_test.dart` as needed

**Interfaces:**
- `createOfficialAssignment(... { required TrainingProp allowedProp })`
- `officialAssignmentPayload(... { required TrainingProp allowedProp })` must include `'allowed_prop': allowedProp.protocolValue`
- Validate prop ∈ movement `supportedProps` before payload build; throw `ClassroomException` on mismatch

Update path notes:

- `updateAssignmentSettings` today does not mutate prop — ensure Rules still reject any update that strips/changes `allowed_prop` illegally (Task 7).
- `updateTeacherActivityAssignment` already pins teacher-created `requiredProp`; leave teacher-created semantics intact.
- If any official edit path can rewrite assignment docs, require same prop invariant.

- [ ] **Step 1: Extend repository tests so official create without prop fails / with valid prop persists**
- [ ] **Step 2: Implement payload + signatures + in-memory/firebase plumbing**
- [ ] **Step 3: Composer service passes selected official prop**
- [ ] **Step 4: Run repository/composer unit tests**

```powershell
flutter test test/data/repositories/classroom_assignment_repository_test.dart
flutter test test/features/teacher/movements/teacher_assignment_composer_test.dart
```

---

### Task 7: Cloud Function + Firestore Rules + parity tests

**Files:**
- Modify: `functions/index.js` (official create branch ~2311)
- Modify: `firestore.rules` (`validOfficialAssignmentCreate`, official update validators)
- Create/Update: `test/core/progression/official_movement_prop_parity_test.dart`
- Update: `firestore-tests/assignments_v1.test.mjs` (and related) for official `allowed_prop` requirement
- Update: `functions/test/helpers.test.js` if official create helpers exist

**Rules changes (conceptual):**

Replace:

```
&& !data.keys().hasAny(['allowed_prop'])
```

With:

```
&& data.keys().hasAny(['allowed_prop'])
&& isTrainingProp(data.allowed_prop)
&& officialMovementSupportsProp(data.official_movement_name, data.allowed_prop)
```

Add `officialMovementSupportsProp(name, prop)` enumerating **all** catalog-supported pairs (Easy bottle-only, Medium bottle+shaker, Hard bottle-only / bottle_and_shaker for Bottle in a tin).

For updates: if resource is official and `allowed_prop` exists on resource or request, require:

- request cannot delete `allowed_prop` when resource already has it
- request `allowed_prop` (if present) must remain valid for `official_movement_name`
- cannot change `official_movement_name` to a movement that does not support the retained prop

**Functions changes:**

```js
const OFFICIAL_MOVEMENT_PROPS = new Map([
  ['Normal Grip', ['bottle']],
  ["Bartender's Grip", ['bottle']],
  // ... all official supported pairs matching Flutter movementCatalog
  ['Hand Stall', ['bottle', 'shaker']],
  // ...
  ['Bottle in a tin', ['bottle_and_shaker']],
]);
```

On official create, require `body.allowed_prop` in that list and persist it on the assignment document.

**Parity test (Dart):**

1. Build expected set from `officialSupportedPracticeVariants()`.
2. Parse `functions/index.js` `OFFICIAL_MOVEMENT_PROPS` entries (regex/structured comment markers OK if needed).
3. Parse `firestore.rules` `officialMovementSupportsProp` pairs.
4. `expect(functionsSet, expected); expect(rulesSet, expected);`

Also assert the 16 progression milestones ⊆ official supported set.

- [ ] **Step 1: Write parity test that fails on missing Function/Rules allowlists**
- [ ] **Step 2: Implement Function + Rules allowlists**
- [ ] **Step 3: Update firestore-tests for official create requiring prop; reject unsupported prop; reject stripping on update**
- [ ] **Step 4: Run**

```powershell
flutter test test/core/progression/official_movement_prop_parity_test.dart
# If node firestore tests are part of local workflow:
# npm test --prefix firestore-tests  (use the repo's existing command)
```

Do **not** deploy.

---

### Task 8: Teacher composer UI — exact prop selection

**Files:**
- Modify: `lib/features/teacher/movements/teacher_assignment_composer.dart`
- Update composer tests

Behavior:

- When official movement selected, if `supportedProps.length == 1`, auto-select that prop.
- If multiple, show ComboBox/radio for Bottle vs Cocktail Shaker; require selection before publish.
- Do **not** filter official movements by trainee level.
- Optional non-blocking info: “Some selected trainees have not reached this movement's personal unlock level. Assignment access will still be granted.” Never blocks publish.

- [ ] Implement UI + wire into `TeacherAssignmentCreationService.create(... allowedProp:)`
- [ ] Test: teacher can create Hand Stall + shaker assignment regardless of fictional trainee levels in unit harness

---

### Task 9: Trainee assignment flow

**Files:**
- Modify: `lib/features/assigned_movements/assigned_practice_screen.dart`
- Modify: `lib/features/learning/movement_lesson.dart` (assignmentId path)
- Modify: assignment detail presentation as needed for Assignment Access copy
- Update: `test/features/learning/movement_lesson_assignment_test.dart`
- Update: `test/features/assigned_movements/*` as applicable

Behavior:

1. After authentic membership + `isAvailableToTrainee`, resolve variant via Task 5 helper.
2. Build `AssignmentGrant(isAuthorized: true)` only when movement name matches and resolved prop matches requested variant.
3. `evaluateAssignment` → if `assignmentLearn`, route to lesson with exact prop + assignmentId.
4. On lesson complete: `completeLesson(movement, prop)` (global exact tutorial persistence).
5. If `assignmentReady`, open practice with that exact prop — **remove** `AssignedPracticePropPicker` for official assignments.
6. UI copy for above-level: “Assignment Access / Normally unlocks at Level X” using `requiredLevelFor` for display only.
7. Fail closed on `assignmentLoading` / `invalid`.

Personal level must not be consulted for assignment practice authorization.

- [ ] TDD/update assignment lesson tests for above-level access + no personal unlock leakage assertions where unit-testable

---

### Task 10: Router personal gates

**Files:**
- Modify: `lib/core/router/app_redirect.dart`
- Modify: `lib/core/router/app_router.dart`
- Update: `test/core/router/app_redirect_test.dart`

**Interfaces change for `AppRedirectState`:**

Replace `bool Function(String movement) hasCompletedLesson` with already-resolved personal inputs, e.g.:

```dart
final ProgressionAccessResult? personalPracticeAccess;
```

Router builder computes:

```dart
final variant = PracticeVariant(movementName: practiceMovement, trainingProp: parsedProp);
final result = evaluatePersonal(
  variant: variant,
  currentLevel: knownLevel, // null if leaderboard XP not ready
  tutorialCompleted: tutorialInitialized ? tutorials.hasCompletedLesson(name, prop) : null,
);
```

Redirect rules for `/practice` (trainee):

| Result | Redirect |
|---|---|
| `personalLoading` | stay / block (fail closed; do not open practice) — prefer Learning with no optimistic unlock flash |
| `personalLocked` | Learning or Movements |
| `personalLearn` | exact movement lesson URL with prop |
| `personalReady` | allow |
| `invalid` | Learning/Movements |

Do **not** add assignment fetches here. Assignment practice routes remain outside this personal gate (handled in Task 9 screens).

Preserve existing auth/verify/teacher/join-code/assigned-movements→teacher-access behavior.

- [ ] Expand `app_redirect_test.dart` for locked / learn / ready / invalid / loading
- [ ] Run:

```powershell
flutter test test/core/router/app_redirect_test.dart
```

---

### Task 11: Learning Center + Movements UI

**Files:**
- Modify: `lib/features/learning/learning_center_screen.dart`
- Modify: `lib/features/learning/movement_lesson.dart` (personal path level gate)
- Modify: `lib/features/movements/widgets/movement_card.dart`
- Modify: `lib/features/movements/movements_presentation.dart` / screen as needed
- Add/update widget tests if present

Behavior:

- Resolve trainee `currentLevel` from leaderboard entry / existing sidebar XP source (same authoritative `totalXp`).
- For each enabled catalog movement, evaluate each supported prop independently.
- Medium: one card, independent prop rows (Locked / Learn / Ready / Practiced presentation).
- Locked: show required level + lock; no activation; semantics string includes lock + level.
- Learn: Learn / Learn first CTA → exact lesson.
- Ready: Start Practice / Practice Again based on existing personal session history (presentation only).
- Personal lesson route: if `personalLocked`/`invalid`, bounce to Learning with clear messaging; if `personalLearn`/`personalReady`, allow lesson.

Do not hide locked content.

---

### Task 12: Playground persistence + runtime gate

**Files:**
- Modify: `lib/services/settings_service.dart`
- Modify: `lib/features/settings/widgets/practice_preferences_controller.dart`
- Modify: `lib/features/practice/just_dance/movement_setlist_dialog.dart`
- Modify: `lib/features/practice/live_practice_screen.dart`
- Prefer **not** changing `playground_session_controller.dart` lifecycle unless setlist type forces a thin adapter
- Update: `test/services/settings_service_just_dance_test.dart`
- Update: `test/features/practice/playground_session_controller_test.dart` if API changes

Persistence migration:

- New key preferred: `just_dance_practice_variants` as `List<String>` of `PracticeVariant.persistenceKey`
- On load: if new key present, parse/dedupe/validate.
- Else migrate legacy `just_dance_movement_names`: each name → first supported prop only; discard unknown.
- Keep reading old key for one-way migration; write new format going forward.
- Preserve interval/music settings.

Runtime:

- Map setlist → variants → filter `evaluatePersonal(...) == personalReady`
- If empty after filter: useful empty state; do not start broken routine
- Level 1: single Normal Grip / Bottle Quick Run allowed
- HUD near Playground: Level, xpIntoLevel/xpPerLevel, nextUnlock label, or mastery message at 16+
- Assignment bypass must never add variants to the selectable pool

- [ ] Extend just_dance settings tests for legacy Hand Stall → Bottle only
- [ ] Run settings + playground tests

---

### Task 13: Recommendations + personal calendar

**Files:**
- Modify: `lib/features/progress/training_recommendation.dart`
- Modify: `lib/features/dashboard/dashboard_screen.dart` / `dashboard_hero.dart` as needed
- Modify: `lib/features/calendar/widgets/training_plan_editor.dart`
- Update: `test/features/progress/training_recommendation_test.dart`
- Update calendar tests if they assert selectable movements

Behavior:

- Recommendation builder accepts personal access (or level + tutorial maps) and never emits Start Practice for locked/learn-only variants.
- Learn-only may suggest Learn Next.
- Training plan editor filters selectable variants to `personalReady` only; prop ComboBox only lists props that are personally ready for the selected movement (or disable movement until a ready prop exists).
- Classroom assignment calendar items remain visible independently (do not filter by personal level).

---

### Task 14: Final verification wave

- [ ] Run targeted suite in order:

```powershell
flutter test test/core/progression
flutter test test/core/router/app_redirect_test.dart
flutter test test/services/settings_service_just_dance_test.dart
flutter test test/features/progress/training_recommendation_test.dart
flutter test test/features/teacher/movements/teacher_assignment_composer_test.dart
flutter test test/data/repositories/classroom_assignment_repository_test.dart
```

- [ ] Run firestore-tests / functions tests using the repo’s documented npm commands if those files changed.
- [ ] `flutter analyze`
- [ ] Full `flutter test` once
- [ ] Separate pre-existing failures from regressions; do not rerun passing targeted suites unless later edits could affect them
- [ ] Do not run backend Python unless backend CV files changed
- [ ] Do not deploy
- [ ] Manual checklist (Main): locked personal → unlock → tutorial → practice → Playground; teacher assigns above-level → trainee assignment tutorial/practice → still personally locked → later level honors tutorial

- [ ] Optional: dispatch Luna Reviewer on the final diff (read-only) after implementation exists; Main validates findings before any fix

---

## Spec coverage checklist (plan self-review)

| Spec requirement | Task |
|---|---|
| PracticeVariant identity | 1 |
| 16 milestones + helpers + catalog drift tests | 2 |
| Pure evaluatePersonal / evaluateAssignment + context loading | 3 |
| Tutorial exact keys + legacy migration | 4 |
| Legacy assignment fallback A | 5 |
| Official allowed_prop create (Flutter) | 6 |
| Rules/Functions create+update + parity all pairs | 7 |
| Teacher exact prop picker; no trainee-level filter | 8 |
| Assignment access isolation + no prop picker | 9 |
| Router personal gates without assignment fetch | 10 |
| Learning/Movements independent prop UI | 11 |
| Playground variant persistence + personalReady gate | 12 |
| Recs + calendar personalReady only | 13 |
| Analyze + full test + manual flows | 14 |
| No deploy unless requested | Global + 7 + 14 |
| No second XP system | Global |
| Assignment never leaks to Playground/recs/calendar | 9, 12, 13 |

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-08-trainee-progression-access.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — execute tasks in this session with checkpoints

Which approach?
