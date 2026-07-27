# Leaderboard screen design

Date: 2026-07-27  
Status: approved for implementation (plan corrections locked)

## Goal

Enhance the leaderboard feature so that:

1. The Dashboard shows only the live Top 3 podium.
2. A dedicated Leaderboard screen shows the full ranked list via paginated one-shot loads.
3. Shared podium / rank-row widgets prevent visual duplication.
4. Existing XP awarding, session processing, Firestore schema, security rules, and ordering remain untouched.

Visual inspiration comes from the attached podium mockup, but the implementation must preserve ELIXR dark/light themes, Fluent UI, spacing constants, and neon pink/purple language. Gold / silver / bronze accents apply only to podium ranks 1–3. The dashboard composition stays compact and responsive.

## Decisions (locked)

| Topic | Choice |
| --- | --- |
| Full-list loading | Approach 1: one-shot paginated fetches + Load More + Refresh |
| Dashboard data | Real-time `watchTopPlayers(limit: 3)` only |
| Full-screen data | Single paginated list drives both podium and ranked rows |
| Off-page standing | None — YOU badge only when the user appears in loaded results |
| Approximate rank | Never shown |
| Pagination cursor | Opaque `LeaderboardPageCursor`; UI never sees `DocumentSnapshot` |
| Page size | 50 |
| `hasMore` | `returnedDocumentCount == limit`; requires non-null cursor when true |
| Page fullness | Based on Firestore document count, not parsed entry count |
| Podium display order | Returns `(rank, entry)` slots so widgets never derive rank from display index |
| Shared identity widgets | `leaderboard_identity.dart` (`LeaderboardInitialsAvatar`, `LeaderboardYouBadge`) |
| Full-screen list | Virtualized (`CustomScrollView` / lazy slivers); injectable controller for tests |
| Sync start API | `startBackgroundSync({required userId, required syncUser})` on the list controller |
| Sync ownership | Call guarded `syncCurrentUserLeaderboard()` from both dashboard and full screen |
| Sync failure | Non-fatal; never replaces leaderboard with a sync error |
| Sync + first page | Parallel with first-page fetch; if sync awards sessions and only page 1 is loaded, refresh page 1 once |
| Shared widgets | Podium / podium card / rank row under `lib/features/leaderboard/widgets/` |
| Headers | Full-screen header widget only; dashboard keeps its compact section header locally |
| Standing helpers | Remove `standingOutsideTop`, `compactRowsOf`, and all off-list standing UI/`watchPlayer` subscriptions |
| YOU highlight | `entry.userId == currentUserId` — no `containsUser` helper unless genuinely reused |
| Empty next page | Ends pagination quietly (not an error); keep existing entries |
| Stale requests | Request-generation token; ignore completed requests from older generations |
| Sync start | At most once per mounted user ID per surface (`_syncStartedForUserId`) |
| Route | `/leaderboard` inside existing `ShellRoute` |
| Sidebar | Leaderboard item directly after Dashboard |

## Constraints

1. Do not change XP awarding, session processing, Firestore writes, leaderboard document schema, security rules, or indexes.
2. Do not expose email addresses or local profile-picture paths.
3. Do not add a permanently unbounded real-time listener for every user.
4. Do not modify unrelated dashboard sections, practice behavior, scoring logic, or authentication.
5. Reuse `AppColors`, `AppSpacing`, `AppTheme` / `context.elix*`, and Fluent UI patterns.
6. Prefer the smallest coherent cross-layer change; delete stale Top-10 / standing code rather than leaving dead paths.

## Architecture

### File layout

```
lib/features/leaderboard/
  leaderboard_screen.dart
  leaderboard_presentation.dart
  widgets/
    leaderboard_header.dart      # full-screen page header only
    leaderboard_identity.dart    # InitialsAvatar + YouBadge
    leaderboard_podium.dart
    leaderboard_podium_card.dart
    leaderboard_rank_row.dart
  leaderboard_list_controller.dart

lib/features/dashboard/widgets/
  dashboard_leaderboard.dart     # includes compact dashboard section header

lib/data/repositories/
  leaderboard_repository.dart   # + LeaderboardPage, LeaderboardPageCursor
```

Move presentation helpers from `lib/features/dashboard/leaderboard_presentation.dart` into `lib/features/leaderboard/leaderboard_presentation.dart`. Delete the old dashboard presentation file after imports/tests are updated. Do not leave duplicate private podium / card / row implementations in the dashboard widget.

Do **not** force a heavily parameterized universal header. The shared podium is reusable; the two headers are not the same composition:

- Dashboard: compact section title, All Time chip, View Full Leaderboard.
- Full screen: page title, supporting text, All Time chip, Refresh.

`leaderboard_header.dart` is the full-screen header. The dashboard section header stays inside `dashboard_leaderboard.dart` unless a clean shared API naturally emerges later.

`LeaderboardPage` and `LeaderboardPageCursor` live next to `LeaderboardRepository` because they describe repository pagination results, not domain entities.

### Ownership

**`DashboardLeaderboard`**

- Subscribe to `watchTopPlayers(limit: 3)`.
- Render shared podium only (plus header chrome and “View Full Leaderboard”).
- Start non-blocking `syncCurrentUserLeaderboard()` for the signed-in user (existing single-flight guard).
- Pass `currentUserId` only for YOU badge matching on loaded Top 3 entries.
- Keep loading / empty / error states.

**`LeaderboardScreen`**

- Own paginated load state, Refresh, and Load More.
- Derive podium and rows from the same loaded list.
- Start the same guarded background sync.
- Use shared header / podium / rank-row widgets.
- Work inside `AppShell` via `ScaffoldPage`.

**`LeaderboardRepository`**

- Keep existing `watchTopPlayers`, `watchPlayer` (if still used elsewhere), award, and sync APIs unchanged in behavior.
- Add `fetchPlayersPage({int limit = 50, LeaderboardPageCursor? startAfter})`.
- Preserve ordering: `total_xp` descending, then `best_score` descending.
- Use `startAfterDocument(...)` internally via the opaque cursor.

### Presentation helpers

Keep pure helpers that remain useful, for example:

- `podiumOf(entries)` → first up to 3 entries (rank order 1st, 2nd, 3rd).
- `rankedRowsOf(entries)` → entries from index 3 onward with `rank = index + 1`.
- `initialsFor(displayName)`.
- Desktop visual order helper: `podiumDisplayOrder` returns `List<({int rank, LeaderboardEntry entry})>` so cards style from explicit rank (never display-list index).

Do **not** keep:

- `compactRowsOf` (Top 10 rows).
- `standingOutsideTop`.
- `containsUser` solely for old tests.

YOU highlighting stays inline: `entry.userId == currentUserId`.

## Pagination API

```dart
Future<LeaderboardPage> fetchPlayersPage({
  int limit = 50,
  LeaderboardPageCursor? startAfter,
});

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
```

- Default page size: **50**.
- `LeaderboardPageCursor` is an opaque abstract type; Firestore `DocumentSnapshot` stays inside a private implementation.
- Screens/tests store the cursor and pass it back; they never import or handle `DocumentSnapshot`.
- `hasMore == true` when `returnedDocumentCount == limit`; otherwise `false`.
- When `hasMore` is true, `nextCursor` **must** be non-null; when `hasMore` is false, `nextCursor` is null.
- Page fullness uses Firestore **document** count, not successfully parsed entry count.
- Internal query continues to use `startAfterDocument` because the composite order has two fields; passing XP/score values alone is insufficient.
- Internal query continues to use `startAfterDocument` because the composite order has two fields; passing XP/score values alone is insufficient.

### Exact-multiple page-size case

With `hasMore = entries.length == limit`, a leaderboard of exactly 50, 100, or 150 users will show Load More one extra time. The following request returns an empty page.

That is the intentional tradeoff for avoiding a separate count query or fetching `limit + 1`. Treat the empty (or otherwise short) follow-up page as **normal pagination end**, not an error:

- Keep all existing entries.
- Set `hasMore` to `false`.
- Set `nextCursor` to `null`.
- Do not show an error.
- Do not append anything.

## Data loading by surface

### Dashboard

```
DashboardLeaderboard
└── Real-time watchTopPlayers(limit: 3)
    └── Shared LeaderboardPodium
```

- No ranks 4–10.
- No “Your standing” row.
- Static “All Time” chip (not a dropdown).
- “View Full Leaderboard” navigates to `/leaderboard`.
- YOU badge only if the signed-in user is among the Top 3 stream results.

### Full Leaderboard screen

```
LeaderboardScreen
└── One-shot paginated list (page size 50)
    ├── Entries 1–3 → shared LeaderboardPodium
    └── Entries 4+  → LeaderboardRankRow list
```

Do **not** open a separate Top 3 stream on this screen. Podium and rows must come from the same loaded list so they cannot disagree.

Displayed rank is always derived from the full loaded-list index:

```text
rank = index + 1
```

### Full-screen load state

Track separately:

| State | Purpose |
| --- | --- |
| `isInitialLoading` | First page in flight |
| `isLoadingMore` | Subsequent page in flight |
| `hasMore` | Whether Load More is available |
| `initialError` | Fatal for first paint |
| `loadMoreError` | Non-fatal; existing rows remain visible |
| `entries` | Accumulated loaded list |
| `nextCursor` | Opaque cursor for the next page |

Rules:

1. Start first-page fetch immediately on mount.
2. Append Load More results; do not replace the list.
3. Deduplicate appended entries by `userId` (skip duplicates).
4. Prevent concurrent Load More requests (`isLoadingMore` guard).
5. Hide or disable Load More when `hasMore == false` or while loading more.
6. A Load More failure must not replace the visible leaderboard with a full-screen error.
7. An empty or short Load More page ends pagination quietly (see Exact-multiple page-size case).
8. Refresh clears `entries`, cursor, `hasMore`, and errors, then fetches page 1 again.
9. Deduplication and the concurrent-load guard also apply after refresh / subsequent loads.
10. Protect against stale async completions with a **request-generation token**:
    - Increment the generation when Refresh begins (and for the initial load generation).
    - Capture the current generation for every page request.
    - Ignore a completed request when its generation no longer matches.
    - Also check `mounted` before updating state.
    - This is required so an in-flight Load More cannot append after Refresh has already replaced the list.

## Sync sequencing

Leaderboard synchronization repairs missing session awards for the signed-in user. It is **non-fatal** relative to ranking UI.

On both dashboard and full leaderboard compositions:

1. Start the ranking data path immediately (stream or first-page fetch).
2. Run `syncCurrentUserLeaderboard()` in parallel (fire-and-forget / unawaited from the UI’s critical path).
3. A sync failure must never replace the leaderboard with an error state; debug-log only.
4. The repository single-flight guard already prevents duplicate concurrent syncs for the same `userId`, so calling sync from both screens is safe.
5. Each surface starts sync **at most once per mounted user ID**, matching the dashboard’s existing `_syncStartedForUserId` approach. Do not re-trigger sync on every Refresh.

### Full-screen post-sync refresh

After a successful sync with `newlyProcessed > 0`:

- If **only the first page** is currently loaded (initial load finished, user has not accumulated further pages), refresh that first page once so the current user’s repaired XP can appear without waiting for a manual Refresh.
- If the user has already loaded multiple pages, do **not** automatically erase those pages; leave Refresh as the explicit recovery action.

### Sync-versus-first-fetch race

Sync may finish while the initial page is still loading. At that moment “only the first page is loaded” is not yet true.

Handle it as follows:

1. If sync finishes with `newlyProcessed > 0` while the initial page is still loading, record a **pending one-time refresh** flag.
2. After the first-page request finishes successfully, if that flag is set, refresh page 1 once and clear the flag.
3. The automatic refresh must **not** trigger another sync.
4. The automatic refresh must occur **at most once** (no refresh loop). Use the same request-generation token so a superseded fetch cannot overwrite newer state.

## Pagination consistency limitation

The full leaderboard is a **best-effort paginated snapshot**, not a transactional frozen ranking.

If players gain XP between page requests, Firestore ordering may shift. Deduplication prevents the same `userId` from appearing twice, but cannot guarantee that every user appears exactly once in global rank order across pages, nor that ranks are a perfect global snapshot.

That limitation is acceptable for this capstone and is preferred over maintaining a large permanent live listener.

## UI requirements

### Shared podium

Desktop visual order for three entries: **`#2 | #1 | #3`**.

Responsive:

- Wide: second, first, third in one row; first taller / larger.
- Medium: first on top; second and third below.
- Narrow: all cards stacked vertically.

Rank accents:

- 1st: gold border, subtle glow, crown icon, larger card.
- 2nd: silver accents.
- 3rd: bronze accents.

Each card shows initials, display name (ellipsis), level, and total XP. YOU badge when `entry.userId == currentUserId`.

Prevent overflow with long names and short-height windows.

### Full-screen header

Owned by `leaderboard_header.dart`:

- Trophy icon.
- “Leaderboard” title.
- Brief supporting text.
- Static “All Time” chip.
- Refresh action in the header or adjacent chrome.

The dashboard compact section header (title, All Time chip, View Full Leaderboard) remains in `dashboard_leaderboard.dart`.

### Ranked rows (rank 4+)

Show rank, initials avatar, display name (ellipsis), level, sessions completed, average score, and XP. Pink accent + YOU badge for the signed-in user when present in loaded results. Clear separation and hover feedback.

### States to handle

- Loading (initial).
- Empty leaderboard.
- Firestore initial error with retry.
- Fewer than three users (partial podium).
- Signed-in user present or absent from loaded results (no standing card when absent).
- Loading more / load-more error / no more pages.

## Navigation

### `app_router.dart`

- Import `LeaderboardScreen`.
- Add `/leaderboard` inside the existing `ShellRoute`.
- Use `fadeTransitionPage` consistently with other shell pages.

### `elix_sidebar.dart`

- Add a Leaderboard sidebar item directly after Dashboard.
- Icon: `FluentIcons.trophy2_solid` (or closest existing trophy icon).
- Route: `/leaderboard`.
- Preserve active-route highlighting in expanded and collapsed states.

## Cleanup

Search for and remove stale references to:

- Dashboard Top 10 / `limit: 10` for the dashboard leaderboard.
- `compactRowsOf`.
- “Not currently in the Top 10”.
- `standingOutsideTop`.
- `_YourStandingRow`.
- `_playerSub` / `_currentUserEntry` / `watchPlayer` usage that existed only for off-list standing.
- Duplicated private podium / card widgets in `dashboard_leaderboard.dart`.

Keep `watchPlayer` on the repository only if another caller still needs it; otherwise leave the method (harmless) or remove only if unused after a repo-wide search.

## Testing

Separate tests by responsibility.

### Presentation tests

Update / move `test/features/dashboard/leaderboard_presentation_test.dart` to the leaderboard feature path.

Cover:

- Correct Top 3 selection.
- Correct podium ordering (data order 1st/2nd/3rd; display order helper if present).
- Zero, one, two, and three-entry podiums.
- Rank numbering beginning at 4 for rows from the same list.
- Initials generation.
- YOU badge detection only when the current-user entry is in the loaded results.
- Off-page current user produces no separate standing card / no standing helper output.
- Full-screen podium comes from the same paginated result as the ranked list (`take(3)` / `skip(3)`).

Ellipsis / overflow for long names belong in **widget tests**, not pure presentation-helper tests.

### Repository tests

Cover:

- Ordering by `total_xp` desc, then `best_score` desc (where practical with fakes).
- Page size of 50.
- Cursor forwarding to the next page.
- `hasMore` true when a full page returns; false when a short page returns.
- Next-page fetching continues after the opaque cursor.

### Screen / controller / widget tests

Cover:

- Initial page load populates entries.
- Load More appends rather than replacing.
- Duplicate `userId` values are not appended twice.
- Concurrent Load More calls cannot run simultaneously.
- `hasMore == false` disables or hides Load More.
- An empty next page ends pagination without an error (exact-multiple case).
- A Load More error preserves existing rows.
- Refresh clears previous pages and restarts from rank 1.
- Stale Load More completion is ignored after Refresh (request-generation token).
- Ranks remain correct after multiple pages (`index + 1`).
- Current user receives YOU only after their entry is loaded; loading more then highlights them.
- Pending post-sync refresh when sync completes before the initial fetch.
- Automatic sync refresh occurring at most once (no loop; does not re-trigger sync).
- Sync failure does not surface as the leaderboard error state (where practical).
- Long-name ellipsis / overflow behavior on podium cards and rank rows.

## Out of scope

- Changing XP formulas, award transactions, or processed-session markers.
- Firestore rules / index changes.
- Email or profile-image exposure on the leaderboard.
- Live updates on the full leaderboard screen.
- Computing or displaying global rank for users outside the loaded pages.
- Moving sync to an app-wide shell coordinator (acceptable later; not required now).

## Acceptance criteria

1. Dashboard shows only Top 3 from a live `limit: 3` stream, with View Full Leaderboard navigation.
2. `/leaderboard` exists in the shell; sidebar item appears directly after Dashboard.
3. Full screen uses one paginated list for podium + rows; page size 50; opaque cursor; Load More + Refresh.
4. Shared widgets are reused; no duplicate podium implementations remain.
5. YOU appears only for loaded matching entries; no off-page standing UI.
6. Sync runs from both surfaces at most once per mounted user ID, is non-fatal, may refresh first page only when awards were applied and only page 1 is loaded (including pending refresh if sync wins the race), and never loops.
7. Awarding, schema, rules, and XP logic are unchanged.
8. Tests listed above are added or updated; stale Top-10 / standing tests are removed or rewritten.
9. `dart format .`, `flutter analyze`, and `flutter test` pass for the change set.
