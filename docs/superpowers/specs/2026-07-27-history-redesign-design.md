# History screen redesign

Date: 2026-07-27  
Status: approved for planning (pending user review of this written spec)

## Goal

Redesign and refactor the History page into a clean, compact, responsive training log while preserving all existing session-loading, filtering, expansion, and navigation behavior.

Replace the oversized two-column card gallery with a full-width chronological list that is easier to scan, shows more sessions without excessive scrolling, and uses a clearer information hierarchy.

## Decisions (locked)

| Topic | Choice |
| --- | --- |
| Architecture | Screen orchestration + feature widgets under `lib/features/history/widgets/` |
| Score presentation | Score badge + label (Excellent / Developing / Needs Practice); no score ring; no duplicate progress bar |
| Search placement | Filter toolbar only (not duplicated in the header) |
| Shared movement visuals | `lib/core/constants/movement_visuals.dart`; update History, Movements, and Dashboard |
| Tiny helpers | Keep badges / small helpers in the nearest feature widget file; do not create microscopic one-off files |
| Core widgets | Do not add generic History primitives under `lib/core/widgets/` yet |
| Stats scope | Calculated from all loaded sessions, not the filtered subset |
| Feedback loading | Lazy on first expand; cache; no refetch on reopen |
| Themes | Use `context.elix*` surfaces/text/borders; both dark and light |
| Clear Filters | Resets Difficulty → All, Search → empty, Sort → Most Recent |

## Constraints

1. Do not modify scoring, session-saving, Firestore schema, or backend files.
2. Do not remove existing History functionality.
3. Do not add a new Flutter package unless absolutely necessary.
4. Reuse `AppColors`, `AppSpacing`, `AppTheme`, and existing theme extensions.
5. Do not hardcode dark-only surface, border, or text colors.

## Architecture

### File layout

```
lib/features/history/
├── history_screen.dart
└── widgets/
    ├── history_header.dart
    ├── history_summary_section.dart
    ├── history_filter_bar.dart
    ├── history_date_group.dart
    ├── history_session_row.dart
    ├── history_session_details.dart
    └── history_empty_state.dart

lib/core/constants/movement_visuals.dart
```

Tiny one-off widgets (difficulty badge, score badge helper, skeleton block) may live inside the closest feature widget file rather than as separate files.

### Ownership

**`history_screen.dart`**

- Load sessions for the authenticated user via `SessionRepository.getSessionsForUser`
- Refresh handling
- Listen to `SessionService` and reload when a session is saved
- Difficulty filter, search, and sort state
- Apply filters and sorting locally
- Group sessions by date
- Wire summary, filter bar, list, and empty/loading/no-match states

**`history_session_row.dart`**

- Hover state
- Expanded state
- Lazy feedback loading and cache
- Feedback loading / loaded / error presentation state
- Expand/collapse animation (~180–220 ms)

**`movement_visuals.dart`**

- Single movement-name → emoji map including legacy names used by historical sessions
- Small helper (e.g. `emojiForMovement(String name)`) with a sensible default
- Consumers: History, Movements, Dashboard (replace duplicated private maps)

### Unchanged contracts

- `Session` / `Feedback` models
- `SessionRepository.getSessionsForUser` / `getFeedbacksForSession`
- No new database queries for search or sort

## UI structure

### Header

- History icon, “History” title, subtitle: “Review and compare your previous training sessions”
- Refresh button with tooltip
- Pink accent used sparingly on the title; no heavy neon chrome
- No search field in the header

### Summary cards

Four separate cards:

- Total Sessions
- Average Score
- Best Score
- Total Training Time

Values come from **all** loaded sessions.

Duration formatting examples:

- `34s`
- `8m 12s`
- `1h 15m`

Responsive:

- Large (≥1200px): four cards in one row
- Medium (700–1199px): two cards per row
- Narrow (<700px): one or two cards per row

Use `LayoutBuilder` or `Wrap`; avoid fixed-width assumptions.

When difficulty/search filters are active, show a matching count such as “12 matching sessions”.

### Filter toolbar

- Difficulty: All, Easy, Medium, Hard
- Movement-name search (local, case-insensitive contains)
- Sort dropdown:
  - Most Recent (default)
  - Oldest
  - Highest Score
  - Lowest Score
  - Longest Session
- Clear Filters when any non-default filter/search/sort is active
- Clear Filters resets explicitly to:
  - Difficulty: All
  - Search: empty
  - Sort: Most Recent

### Date groups

- Keep grouping by Today / Yesterday / formatted date
- Header: date label, session count text (e.g. “4 sessions”), subtle divider
- No large permanent neon glows

### Session list

Full-width chronological list only. Do not restore a two-column card grid at any width.

Each row shows:

- Movement emoji
- Movement name
- Difficulty badge
- Session time
- Duration
- Score badge + label
- Expand/collapse chevron

Wide layout example:

`[Icon] Bartender's Grip | Easy | 6:23 PM | 14s | Score 100 Excellent | Chevron`

Narrow layout example:

```
[Icon] Bartender's Grip                         100
       Easy • 6:23 PM • 14s                  Chevron
```

Score labels:

- 80–100: Excellent
- 50–79: Developing
- Below 50: Needs Practice

Use score colors only on the score element.

### Expanded details

Nested panel with:

- Exact date and time
- Duration
- Score
- Difficulty
- Session Feedback as separate bullet items (not joined with “ · ”)

Do not display fields that do not exist on current models.

### States

- Loading: lightweight skeleton-style placeholders and/or `ProgressRing` where appropriate
- Empty: “No training sessions yet”, explain sessions appear after practice, Browse Movements button → `/movements`
- No results: “No sessions found”, suggest changing controls, Clear Filters button

## Data flow

```
_loadSessions → _sessions
                     ↓
            apply difficulty
                     ↓
            apply search
                     ↓
            apply sort
                     ↓
            _filtered → group by date → list UI

stats ← _sessions (unfiltered)
matching count ← _filtered when filters/search active
```

Feedback (per row, first expand only):

```
expand → if not cached → loading → getFeedbacksForSession → cache → show bullets
re-expand → use cache (no refetch)
fetch error → soft-fail message in details; list remains usable
```

## Interaction quality

- Tooltips for icon-only controls
- Visible hover states
- Keyboard focus where Fluent supports it
- Smooth expansion animation (~200 ms)
- Clear clickable row areas and mouse cursors
- No excessive glow animations

## Out of scope

- Backend / WebSocket / Firestore schema changes
- Scoring or session-save logic changes
- Session summary sheet audio or other practice SFX work
- Settings toggle for History filters
- Generic reusable History widgets in `lib/core/widgets/`

## Acceptance criteria

1. History is a chronological full-width list (no two-column grid).
2. Only one score visualization per session (badge + label).
3. Difficulty filtering, local search, and local sorting work.
4. Statistics represent all loaded sessions; matching count reflects active filters/search.
5. Feedback loads only on first expand and is not refetched on reopen.
6. Dark and light themes are readable via `context.elix*` tokens.
7. Layout does not overflow at narrow / medium / large widths.
8. Existing load, refresh, SessionService reload, empty → Movements navigation remain.
9. No backend or schema changes; no new packages unless unavoidable.
10. `flutter analyze` reports no new errors from these changes.

## Verification

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

Manual on Windows: both themes; widths <700, 700–1199, ≥1200; expand feedback once then again; filter/search/sort/clear; empty and no-match states.

## Test notes

Prefer analyze + manual UI checks. Do not add tests that require Firebase production data or device audio. Unit-test pure helpers (duration formatting, score labels, local sort/filter) only if extracted cleanly without over-abstracting.
