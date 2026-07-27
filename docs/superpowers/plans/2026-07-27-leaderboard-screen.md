# Leaderboard Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show live Top 3 on the Dashboard, add a shell `/leaderboard` screen with paginated full rankings, and share podium/rank-row widgets without changing XP awarding or Firestore schema.

**Architecture:** Dashboard keeps `watchTopPlayers(limit: 3)`. Full screen uses one-shot `fetchPlayersPage` (page size 50, opaque cursor) with Load More + Refresh. A testable `LeaderboardListController` owns generation tokens, append/dedupe, empty-page end, and one-shot post-sync refresh. Shared podium widgets live under `lib/features/leaderboard/widgets/`; dashboard keeps its own compact section header.

**Tech Stack:** Flutter Windows desktop, Fluent UI, `go_router`, Cloud Firestore, existing `AppColors` / `AppSpacing` / `AppTheme` / `context.elix*`.

**Spec:** `docs/superpowers/specs/2026-07-27-leaderboard-screen-design.md`

## Global Constraints

- Do not change XP awarding, session processing, leaderboard document schema, Firestore rules, or indexes.
- Do not expose email or local profile-picture paths.
- Do not add an unbounded real-time listener for the full leaderboard.
- Dashboard: live Top 3 only — no ranks 4+, no standing row, no `watchPlayer` subscription.
- Full screen: single paginated list drives podium (`take(3)`) and rows (`skip(3)`); `rank = index + 1`.
- Opaque `LeaderboardPageCursor`; UI never sees `DocumentSnapshot`.
- `hasMore` may be true only when a next cursor exists; page fullness uses returned Firestore document count, not parsed entry count.
- YOU badge only via `entry.userId == currentUserId` on loaded entries.
- Sync is non-fatal, at most once per mounted user ID per surface; post-sync auto-refresh at most once and must not re-trigger sync.
- No universal shared header — `leaderboard_header.dart` is full-screen only.
- Full-screen list must be virtualized (`CustomScrollView` / `ListView.builder`), not a giant `Column` in `SingleChildScrollView`.
- Keep the project buildable after every task (do not delete old dashboard presentation until Task 6 migrates callers).
- No commits unless the user asks.
- Smallest coherent change; no unrelated refactors.
- Format only changed paths; final check: `dart format --output=none --set-exit-if-changed lib test`.

## File map

| File | Responsibility |
| --- | --- |
| `lib/data/repositories/leaderboard_repository.dart` | Add `LeaderboardPage`, opaque cursor, `fetchPlayersPage`, `buildPage` |
| `lib/features/leaderboard/leaderboard_presentation.dart` | Pure helpers: podium, ranked rows, initials, ranked display order |
| `lib/features/leaderboard/leaderboard_list_controller.dart` | Paginated load state, generation token, sync refresh |
| `lib/features/leaderboard/leaderboard_screen.dart` | ScaffoldPage; injectable controller; virtualized list |
| `lib/features/leaderboard/widgets/leaderboard_header.dart` | Full-screen header + Refresh |
| `lib/features/leaderboard/widgets/leaderboard_identity.dart` | `LeaderboardInitialsAvatar`, `LeaderboardYouBadge` |
| `lib/features/leaderboard/widgets/leaderboard_podium.dart` | Responsive `#2 \| #1 \| #3` layout using ranked display slots |
| `lib/features/leaderboard/widgets/leaderboard_podium_card.dart` | Gold/silver/bronze card (uses explicit `rank`) |
| `lib/features/leaderboard/widgets/leaderboard_rank_row.dart` | Rank 4+ row |
| `lib/features/dashboard/widgets/dashboard_leaderboard.dart` | Top 3 stream + compact header + View Full |
| `lib/features/dashboard/leaderboard_presentation.dart` | Temporary until Task 6 deletes it |
| `lib/core/router/app_router.dart` | `/leaderboard` shell route |
| `lib/core/widgets/elix_sidebar.dart` | Sidebar item after Dashboard (`startsWith` active check) |
| `test/features/leaderboard/leaderboard_presentation_test.dart` | Presentation helpers |
| `test/features/leaderboard/leaderboard_list_controller_test.dart` | Append/dedupe/generation/sync refresh |
| `test/data/repositories/leaderboard_page_test.dart` | `hasMore` / page factory semantics |

---

### Task 1: Create new presentation helpers + tests (keep old file)

**Files:**
- Create: `lib/features/leaderboard/leaderboard_presentation.dart`
- Create: `test/features/leaderboard/leaderboard_presentation_test.dart`
- Keep: `lib/features/dashboard/leaderboard_presentation.dart` (still used by dashboard until Task 6)
- Keep: `test/features/dashboard/leaderboard_presentation_test.dart` until Task 6

**Buildability:** After this task the project must still compile. Do **not** delete or break the old dashboard presentation file.

**Interfaces:**
- Produces:
  - `LeaderboardPresentation.podiumOf(List<LeaderboardEntry>)` → first ≤3 entries (rank order 1st, 2nd, 3rd)
  - `LeaderboardPresentation.rankedRowsOf(List<LeaderboardEntry>)` → `List<({int rank, LeaderboardEntry entry})>` from index 3; `rank = index + 1`
  - `LeaderboardPresentation.initialsFor(String)`
  - `LeaderboardPresentation.podiumDisplayOrder(List<LeaderboardEntry> podium)` → `List<({int rank, LeaderboardEntry entry})>`  
    For length 3: `(rank: 2, second), (rank: 1, first), (rank: 3, third)`.  
    Otherwise: each entry paired with `rank = index + 1` in podium order.  
    **Widgets must style from `rank`, never from display-list index.**

- [ ] **Step 1: Write the failing tests**

Create `test/features/leaderboard/leaderboard_presentation_test.dart`:

```dart
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry entry({
  required String id,
  required String name,
  required int xp,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: 0,
  );
}

void main() {
  group('LeaderboardPresentation', () {
    final top = [
      entry(id: '1', name: 'A', xp: 300),
      entry(id: '2', name: 'B', xp: 275),
      entry(id: '3', name: 'C', xp: 250),
      entry(id: '4', name: 'D', xp: 200),
      entry(id: 'me', name: 'Me', xp: 150),
    ];

    test('podium takes first three in rank order', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      expect(podium.map((e) => e.userId), ['1', '2', '3']);
    });

    test('podium handles 0–3 entries', () {
      expect(LeaderboardPresentation.podiumOf(const []), isEmpty);
      expect(LeaderboardPresentation.podiumOf(top.take(1).toList()).length, 1);
      expect(LeaderboardPresentation.podiumOf(top.take(2).toList()).length, 2);
      expect(LeaderboardPresentation.podiumOf(top.take(3).toList()).length, 3);
    });

    test('display order is 2nd, 1st, 3rd with ranks retained', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      final display = LeaderboardPresentation.podiumDisplayOrder(podium);
      expect(display.map((s) => s.entry.userId), ['2', '1', '3']);
      expect(display.map((s) => s.rank), [2, 1, 3]);
    });

    test('ranked rows start at rank 4 from same list', () {
      final rows = LeaderboardPresentation.rankedRowsOf(top);
      expect(rows.map((r) => r.rank), [4, 5]);
      expect(rows.map((r) => r.entry.userId), ['4', 'me']);
    });

    test('podium and rows partition the same list', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      final rows = LeaderboardPresentation.rankedRowsOf(top);
      expect([
        ...podium.map((e) => e.userId),
        ...rows.map((r) => r.entry.userId),
      ], top.map((e) => e.userId).toList());
    });

    test('YOU matching is identity equality on loaded entries only', () {
      const currentUserId = 'me';
      expect(top.any((e) => e.userId == currentUserId), isTrue);
      expect(
        LeaderboardPresentation.podiumOf(top)
            .any((e) => e.userId == currentUserId),
        isFalse,
      );
      expect(
        LeaderboardPresentation.rankedRowsOf(top)
            .any((r) => r.entry.userId == currentUserId),
        isTrue,
      );
      // Off-page user: not in loaded list → no standing helper exists.
      expect(top.any((e) => e.userId == 'missing'), isFalse);
    });

    test('initials helper', () {
      expect(LeaderboardPresentation.initialsFor('Ada Lovelace'), 'AL');
      expect(LeaderboardPresentation.initialsFor('Grace'), 'GR');
      expect(LeaderboardPresentation.initialsFor('  '), '?');
    });
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/features/leaderboard/leaderboard_presentation_test.dart`
Expected: FAIL (library missing).

- [ ] **Step 3: Implement helpers**

```dart
import '../../data/models/leaderboard_entry.dart';

abstract final class LeaderboardPresentation {
  static List<LeaderboardEntry> podiumOf(List<LeaderboardEntry> entries) {
    if (entries.isEmpty) return const [];
    return entries.take(3).toList(growable: false);
  }

  static List<({int rank, LeaderboardEntry entry})> podiumDisplayOrder(
    List<LeaderboardEntry> podium,
  ) {
    if (podium.length != 3) {
      return [
        for (var i = 0; i < podium.length; i++)
          (rank: i + 1, entry: podium[i]),
      ];
    }
    return [
      (rank: 2, entry: podium[1]),
      (rank: 1, entry: podium[0]),
      (rank: 3, entry: podium[2]),
    ];
  }

  static List<({int rank, LeaderboardEntry entry})> rankedRowsOf(
    List<LeaderboardEntry> entries,
  ) {
    if (entries.length < 4) return const [];
    return [
      for (var i = 3; i < entries.length; i++)
        (rank: i + 1, entry: entries[i]),
    ];
  }

  static String initialsFor(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
  }
}
```

- [ ] **Step 4: Leave old dashboard presentation in place**

Do not delete `lib/features/dashboard/leaderboard_presentation.dart` or its test. Task 6 migrates and deletes them.

- [ ] **Step 5: Run tests — expect PASS**

Run: `flutter test test/features/leaderboard/leaderboard_presentation_test.dart`
Expected: PASS.

Also run: `flutter analyze lib/features/leaderboard lib/features/dashboard`
Expected: no issues (project still builds with both presentation files present).

---

### Task 2: Pagination types + `fetchPlayersPage` + page semantics tests

**Files:**
- Modify: `lib/data/repositories/leaderboard_repository.dart`
- Create: `test/data/repositories/leaderboard_page_test.dart`

**Interfaces:**
- Produces:
  - Abstract opaque `LeaderboardPageCursor` (UI/tests never see `DocumentSnapshot`)
  - Private Firestore-backed implementation in the repository library (e.g. `_FirestoreLeaderboardPageCursor`)
  - `@visibleForTesting class FakeLeaderboardPageCursor implements LeaderboardPageCursor` for controller tests (or a public test-only fake constructor on an abstract interface)
  - `class LeaderboardPage { entries, nextCursor, hasMore }`
  - `Future<LeaderboardPage> fetchPlayersPage({int limit = 50, LeaderboardPageCursor? startAfter})`
  - `@visibleForTesting static LeaderboardPage buildPage({required List<LeaderboardEntry> entries, required int returnedDocumentCount, required int limit, required LeaderboardPageCursor? cursorFromLastDoc})`

**Invariants:**
- `hasMore = returnedDocumentCount == limit`.
- If `hasMore` is true, `nextCursor` **must** be non-null (`cursorFromLastDoc`); otherwise throw `ArgumentError` or assert in `buildPage`.
- If `hasMore` is false, `nextCursor` is null (ignore any supplied cursor).
- Page fullness uses **Firestore document count**, not parsed `entries.length` (malformed docs filtered by `tryFromMap` must not stop pagination early).

- [ ] **Step 1: Write page-semantics tests**

```dart
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry e(String id, int xp) => LeaderboardEntry(
  userId: id,
  displayName: id,
  totalXp: xp,
  sessionsCompleted: 1,
  scoreSum: 0,
  averageScore: 0,
  bestScore: xp,
);

void main() {
  test('full document page sets hasMore and requires cursor', () {
    final entries = [for (var i = 0; i < 49; i++) e('u$i', 100 - i)];
    final cursor = FakeLeaderboardPageCursor('page1');
    final page = LeaderboardRepository.buildPage(
      entries: entries, // one malformed doc dropped → 49 entries
      returnedDocumentCount: 50,
      limit: 50,
      cursorFromLastDoc: cursor,
    );
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, same(cursor));
    expect(page.entries.length, 49);
  });

  test('hasMore true without cursor throws', () {
    expect(
      () => LeaderboardRepository.buildPage(
        entries: [for (var i = 0; i < 50; i++) e('u$i', 100 - i)],
        returnedDocumentCount: 50,
        limit: 50,
        cursorFromLastDoc: null,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('short document page sets hasMore false and null cursor', () {
    final page = LeaderboardRepository.buildPage(
      entries: [e('a', 10), e('b', 5)],
      returnedDocumentCount: 2,
      limit: 50,
      cursorFromLastDoc: FakeLeaderboardPageCursor('ignored'),
    );
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('empty page sets hasMore false', () {
    final page = LeaderboardRepository.buildPage(
      entries: const [],
      returnedDocumentCount: 0,
      limit: 50,
      cursorFromLastDoc: null,
    );
    expect(page.entries, isEmpty);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `flutter test test/data/repositories/leaderboard_page_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add types + `fetchPlayersPage` in repository file**

```dart
/// Opaque pagination cursor. UI stores and returns it; never unwraps it.
abstract class LeaderboardPageCursor {}

@visibleForTesting
class FakeLeaderboardPageCursor implements LeaderboardPageCursor {
  FakeLeaderboardPageCursor(this.id);
  final String id;
}

class _FirestoreLeaderboardPageCursor implements LeaderboardPageCursor {
  _FirestoreLeaderboardPageCursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
}

class LeaderboardPage {
  const LeaderboardPage({
    required this.entries,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardPageCursor? nextCursor;
  final bool hasMore;
}

@visibleForTesting
static LeaderboardPage buildPage({
  required List<LeaderboardEntry> entries,
  required int returnedDocumentCount,
  required int limit,
  required LeaderboardPageCursor? cursorFromLastDoc,
}) {
  final hasMore = returnedDocumentCount == limit;
  if (hasMore && cursorFromLastDoc == null) {
    throw ArgumentError(
      'hasMore requires cursorFromLastDoc when returnedDocumentCount == limit',
    );
  }
  return LeaderboardPage(
    entries: List<LeaderboardEntry>.unmodifiable(entries),
    hasMore: hasMore,
    nextCursor: hasMore ? cursorFromLastDoc : null,
  );
}

Future<LeaderboardPage> fetchPlayersPage({
  int limit = 50,
  LeaderboardPageCursor? startAfter,
}) async {
  Query<Map<String, dynamic>> query = _firestore
      .collection(FirestoreCollections.leaderboard)
      .orderBy('total_xp', descending: true)
      .orderBy('best_score', descending: true)
      .limit(limit);

  if (startAfter is _FirestoreLeaderboardPageCursor) {
    query = query.startAfterDocument(startAfter.document);
  } else if (startAfter != null) {
    throw ArgumentError(
      'startAfter must be a Firestore-backed LeaderboardPageCursor',
    );
  }

  final snapshot = await query.get();
  final docs = snapshot.docs;
  final entries = docs
      .map((doc) => LeaderboardEntry.tryFromMap(doc.data(), id: doc.id))
      .whereType<LeaderboardEntry>()
      .toList(growable: false);

  final cursor = docs.isEmpty
      ? null
      : _FirestoreLeaderboardPageCursor(docs.last);

  return buildPage(
    entries: entries,
    returnedDocumentCount: docs.length,
    limit: limit,
    cursorFromLastDoc: cursor,
  );
}
```

Keep `watchTopPlayers` unchanged. Leave `watchPlayer` on the repository for now.

- [ ] **Step 4: Run page tests — expect PASS**

Run: `flutter test test/data/repositories/leaderboard_page_test.dart`
Expected: PASS.

**Not verified in unit tests:** live Firestore ordering / `startAfterDocument` against production data (manual or emulator later).

---

### Task 3: `LeaderboardListController` (generation, append, sync refresh)

**Files:**
- Create: `lib/features/leaderboard/leaderboard_list_controller.dart`
- Create: `test/features/leaderboard/leaderboard_list_controller_test.dart`

**Interfaces:**
- Consumes: `Future<LeaderboardPage> Function({LeaderboardPageCursor? startAfter}) fetchPage`
- Produces: `LeaderboardListController` with:
  - `List<LeaderboardEntry> entries`
  - `bool isInitialLoading`, `isLoadingMore`, `hasMore`
  - `Object? initialError`, `loadMoreError`
  - `Future<void> loadInitial()`
  - `Future<void> loadMore()`
  - `Future<void> refresh()`
  - `Future<void> startBackgroundSync({required String userId, required Future<LeaderboardSyncResult> Function() syncUser})`
  - `void dispose()`
  - extends `ChangeNotifier`

**Locked sync API:** only `startBackgroundSync({required userId, required syncUser})`. Do not inject `syncUser` via the constructor. The controller tracks `_syncStartedForUserId`; the screen captures display name inside the `syncUser` closure.

Behavior locked by spec:

1. Generation token increments on `refresh()` (and starts at 1 for initial).
2. Each request captures generation; ignore results when mismatched; also check disposed.
3. Load More: append with `userId` dedupe; concurrent calls no-op while `isLoadingMore`.
4. Empty/short page: keep entries, `hasMore=false`, `nextCursor=null`, no error, append nothing.
5. Load More error → set `loadMoreError` only; keep entries.
6. Sync: at most once per `userId` passed to `startBackgroundSync`; non-fatal.
7. If `newlyProcessed > 0` and still initial-loading → set `_pendingPostSyncRefresh`.
8. After successful initial load, if pending → refresh page 1 once without calling sync again; clear pending; never loop (`_didAutoRefreshAfterSync` flag).
9. If `newlyProcessed > 0` after initial load and only one page loaded (`!_hasLoadedAdditionalPage`) → one auto refresh.
10. If user already loaded more pages → no auto refresh.
11. `refresh()` resets: `entries`, `_nextCursor`, `hasMore`, `loadMoreError`, `initialError`, `_hasLoadedAdditionalPage`.  
    `refresh()` does **not** reset: `_syncStartedForUserId`, `_didAutoRefreshAfterSync`, or re-run sync.

- [ ] **Step 1: Write controller tests**

Use a fake page source:

```dart
class FakePages {
  FakePages(this.pages);
  final List<LeaderboardPage> pages;
  int calls = 0;
  int? failOnCall;
  final inFlight = <Completer<LeaderboardPage>>[];

  Future<LeaderboardPage> fetch({LeaderboardPageCursor? startAfter}) async {
    final call = calls++;
    if (failOnCall == call) throw Exception('network');
    if (call >= pages.length) {
      return const LeaderboardPage(
        entries: [],
        nextCursor: null,
        hasMore: false,
      );
    }
    return pages[call];
  }
}

LeaderboardEntry e(String id, int xp) => /* same as Task 1 */;
```

Tests to include:

- Initial load populates entries and clears `isInitialLoading`.
- Load More appends.
- Duplicate `userId` skipped on append.
- Second `loadMore` while first in flight does not double-call (use Completer gate).
- Empty next page ends pagination without error.
- Load More error preserves rows and sets `loadMoreError`.
- Refresh clears and restarts; stale prior Load More result ignored (start loadMore, then refresh before it completes).
- Ranks via presentation helpers remain `index + 1` after two pages.
- Sync completing before initial load schedules one post-sync refresh; `fetch` call count increases by one after initial; sync function called once.
- Auto refresh at most once even if sync reports awards again (guard flag).
- Sync failure does not set `initialError`.

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/features/leaderboard/leaderboard_list_controller_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement controller**

Sketch (implement fully in code; keep public API as above):

```dart
class LeaderboardListController extends ChangeNotifier {
  LeaderboardListController({
    required Future<LeaderboardPage> Function({
      LeaderboardPageCursor? startAfter,
    }) fetchPage,
  }) : _fetchPage = fetchPage;

  final Future<LeaderboardPage> Function({LeaderboardPageCursor? startAfter})
  _fetchPage;

  // … state fields …

  Future<void> startBackgroundSync({
    required String userId,
    required Future<LeaderboardSyncResult> Function() syncUser,
  }) async { /* once per userId; non-fatal; pending refresh flags */ }
}
```

Append helper:

```dart
List<LeaderboardEntry> _appendDeduped(
  List<LeaderboardEntry> current,
  List<LeaderboardEntry> incoming,
) {
  final seen = current.map((e) => e.userId).toSet();
  final out = [...current];
  for (final entry in incoming) {
    if (seen.add(entry.userId)) out.add(entry);
  }
  return List.unmodifiable(out);
}
```

Empty/short page handling inside loadMore success path:

```dart
if (page.entries.isEmpty || !page.hasMore && page.entries.isEmpty) {
  hasMore = false;
  _nextCursor = null;
  // keep entries; no error
} else {
  entries = _appendDeduped(entries, page.entries);
  hasMore = page.hasMore;
  _nextCursor = page.nextCursor;
  if (page.entries.isNotEmpty) _hasLoadedAdditionalPage = true;
}
```

Also treat short non-empty final page normally: append, `hasMore=false`.

- [ ] **Step 4: Run controller tests — expect PASS**

Run: `flutter test test/features/leaderboard/leaderboard_list_controller_test.dart`
Expected: PASS.

---

### Task 4: Shared identity + podium + rank row widgets

**Files:**
- Create: `lib/features/leaderboard/widgets/leaderboard_identity.dart`
- Create: `lib/features/leaderboard/widgets/leaderboard_podium_card.dart`
- Create: `lib/features/leaderboard/widgets/leaderboard_podium.dart`
- Create: `lib/features/leaderboard/widgets/leaderboard_rank_row.dart`

**Interfaces:**
- Produces:
  - `LeaderboardInitialsAvatar({required String initials, required Color accent, required double size})`
  - `LeaderboardYouBadge()`
  - `LeaderboardPodiumCard({required int rank, required LeaderboardEntry entry, required bool isCurrentUser})` — styles from **`rank`**, never from parent index
  - `LeaderboardPodium({required List<LeaderboardEntry> podium, required String? currentUserId})` — uses `podiumDisplayOrder` slots; each card gets `slot.rank`
  - `LeaderboardRankRow({required int rank, required LeaderboardEntry entry, required bool isCurrentUser})`

Do **not** declare private `_YouBadge` / `_InitialsAvatar` in one widget file and try to reuse from another. Put shared chrome in `leaderboard_identity.dart`.

Visual rules from spec:

- Accents: gold `#1`, silver `#2`, bronze `#3`.
- First place taller, glow, crown.
- Responsive breakpoints matching current dashboard: ≥720 wide row; ≥480 medium; else stack.
- Use `context.elixTextPrimary` / `elixCardSurface` / `AppColors.panelSurface`.

- [ ] **Step 1: Implement identity widgets, then port podium/card/row from dashboard privates**

- [ ] **Step 2: Analyze widgets**

Run: `flutter analyze lib/features/leaderboard/widgets`
Expected: no issues.

**Not verified:** visual pixel match to the mockup (manual).

---

### Task 5: Full Leaderboard screen + header

**Files:**
- Create: `lib/features/leaderboard/widgets/leaderboard_header.dart`
- Create: `lib/features/leaderboard/leaderboard_screen.dart`

**Interfaces:**
- Produces:
  - `LeaderboardHeader({required VoidCallback onRefresh, bool refreshEnabled})`
  - `LeaderboardScreen({Key? key, LeaderboardRepository? repository, LeaderboardListController? controller})` — injectable controller/repo so widget tests need no Firestore
  - Body uses `CustomScrollView` (or equivalent) with header/podium as leading slivers and lazily built rank rows — **not** a giant `Column` inside `SingleChildScrollView`

- [ ] **Step 1: Implement header**

Full-screen only: trophy icon, “Leaderboard”, one short supporting sentence (“All-time rankings by total XP.”), static All Time chip, Refresh button calling `onRefresh`.

- [ ] **Step 2: Implement screen**

Prefer:

```dart
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    this.repository,
    this.controller,
  });

  final LeaderboardRepository? repository;
  final LeaderboardListController? controller;
}
```

If `controller` is null, create one with `fetchPlayersPage` from `repository ?? LeaderboardRepository()`.

In `initState` / first frame:

1. `loadInitial()`.
2. `startBackgroundSync(userId: …, syncUser: () => repo.syncCurrentUserLeaderboard(...))`.

`build` uses `ListenableBuilder` / `AnimatedBuilder` on the controller:

- Virtualized scroll: `CustomScrollView` with `SliverToBoxAdapter` for header + podium, `SliverList` / `SliverChildBuilderDelegate` for ranked rows, then a Load More footer sliver.
- States: initial loading, initial error + retry, empty, load-more inline error, Load More button when `hasMore`.

Dispose the owned controller only if this screen created it.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/leaderboard`
Expected: no issues.

---

### Task 6: Slim DashboardLeaderboard + delete old presentation

**Files:**
- Modify: `lib/features/dashboard/widgets/dashboard_leaderboard.dart`
- Delete: `lib/features/dashboard/leaderboard_presentation.dart`
- Delete: `test/features/dashboard/leaderboard_presentation_test.dart`

**Interfaces:**
- Consumes: shared `LeaderboardPodium`, `LeaderboardPresentation` from `lib/features/leaderboard/`
- Removes: `_playerSub`, `_currentUserEntry`, `standingOutsideTop`, compact rows, `_YourStandingRow`, private podium duplicates
- Keeps: `watchTopPlayers(limit: 3)`, `_syncStartedForUserId` background sync, loading/empty/error, compact local header, All Time chip, View Full Leaderboard → `context.go('/leaderboard')`

- [ ] **Step 1: Migrate dashboard imports to the new presentation + shared podium**

- [ ] **Step 2: Rewrite dashboard composition**

Key changes:

```dart
_topSub = _repository.watchTopPlayers(limit: 3).listen(/* … */);
// no _listenPlayer / watchPlayer
```

Content when loaded:

```dart
Column(
  children: [
    // local header row + All Time chip
    LeaderboardPodium(
      podium: LeaderboardPresentation.podiumOf(_topPlayers),
      currentUserId: widget.currentUserId,
    ),
    const SizedBox(height: AppSpacing.sm),
    // View Full Leaderboard → context.go('/leaderboard')
  ],
)
```

- [ ] **Step 3: Delete old dashboard presentation file and its test**

Only after dashboard compiles against the new helpers.

- [ ] **Step 4: Search stale strings**

Search repo for:

- `Top 10`
- `compactRowsOf`
- `standingOutsideTop`
- `Not currently in the Top 10`
- `_YourStandingRow`
- `dashboard/leaderboard_presentation`

Expected: only docs/plan mentions, or none in `lib/` / `test/`.

- [ ] **Step 5: Analyze dashboard widget**

Run: `flutter analyze lib/features/dashboard lib/features/leaderboard`
Expected: no issues.

---

### Task 7: Router + sidebar

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/core/widgets/elix_sidebar.dart`

- [ ] **Step 1: Add shell route**

After `/dashboard` route (or adjacent), add:

```dart
GoRoute(
  path: '/leaderboard',
  pageBuilder: (context, state) => fadeTransitionPage(
    key: state.pageKey,
    child: const LeaderboardScreen(),
  ),
),
```

Import `LeaderboardScreen`.

- [ ] **Step 2: Insert sidebar item directly after Dashboard**

```dart
const _sidebarItems = [
  SidebarItem(
    label: 'Dashboard',
    icon: FluentIcons.view_dashboard,
    route: '/dashboard',
  ),
  SidebarItem(
    label: 'Leaderboard',
    icon: FluentIcons.trophy2_solid,
    route: '/leaderboard',
  ),
  // … remaining items unchanged
];
```

Confirm active-route highlighting already keys off `widget.currentRoute.startsWith(item.route!)` (not strict equality). Adding `/leaderboard` after `/dashboard` is safe because neither route is a prefix of the other.

- [ ] **Step 3: Analyze router + sidebar**

Run: `flutter analyze lib/core/router/app_router.dart lib/core/widgets/elix_sidebar.dart`
Expected: no issues.

---

### Task 8: Final verification + cleanup

**Files:** any stragglers from search

- [ ] **Step 1: Format changed paths only**

Run: `dart format` on every path this change set created or modified under `lib/` and `test/` (and docs if touched in the same work). Do **not** run `dart format .` on the whole repo.

Then: `dart format --output=none --set-exit-if-changed lib test`
Expected: exits 0.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Test**

Run: `flutter test`
Expected: all tests PASS, including new leaderboard presentation, page, and controller suites; old dashboard presentation suite gone.

- [ ] **Step 4: Manual checklist (Not verified until run on Windows)**

- Dashboard shows ≤3 podium cards; no rows 4–10; no standing card.
- YOU on dashboard only if current user in Top 3.
- Sidebar Leaderboard after Dashboard navigates to `/leaderboard`.
- Full screen podium matches first three of the list; ranks 4+ below.
- Load More / Refresh / empty next page / error preservation behave as specified.

- [ ] **Step 5: Docs commit (only when user asks)**

When requested, commit design spec + this plan together:

```text
docs: add leaderboard screen design and implementation plan
```

Do not commit implementation code in that docs-only commit.

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| Presentation created; old file kept until migrate | 1, 6 |
| Rank retained in podium display order | 1, 4 |
| Opaque cursor + doc-count hasMore + cursor required | 2 |
| Empty next page quiet end | 2, 3 |
| Generation token / stale Load More | 3 |
| Append dedupe / concurrent Load More | 3 |
| Locked `startBackgroundSync({userId, syncUser})` | 3, 5 |
| Sync once per user; pending post-sync refresh; at most once | 3, 5, 6 |
| Shared identity + podium/card/row; no universal header | 4, 5 |
| Virtualized full screen + injectable controller | 5 |
| Dashboard Top 3 + View Full; delete old presentation | 6 |
| `/leaderboard` + sidebar after Dashboard | 7 |
| Format changed paths / analyze / test | 8 |
| Awarding/schema/rules untouched | all (no edits) |

## Placeholder / consistency self-review

- No TBD left in tasks.
- `LeaderboardPage` / cursor / `buildPage` / controller APIs are named consistently across tasks.
- Headers: full-screen widget vs dashboard-local — explicit.
- Firestore live pagination not unit-tested — called out as Not verified.
