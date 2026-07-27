# Practice UI redesign (scored + Free Practice)

Date: 2026-07-27  
Status: approved (clarifications applied; implementation plan written)

## Goal

Redesign and refactor the scored Practice screen and Free Practice screen into one consistent Training Session visual system that is cleaner, more compact, responsive, and easier to understand during a live flair-training session.

The camera remains the dominant surface. The session panel shows only information and controls useful during the current session. All existing camera, WebSocket, scoring, timer, countdown, audio, bottle detection, hold confirmation, combo, session saving, summary, error handling, and navigation behavior is preserved.

## Decisions (locked)

| Topic | Choice |
| --- | --- |
| Architecture | Shared Training Session shell under `lib/features/practice/widgets/`; screens keep orchestration |
| Panel composition | Slot-based shell (`metrics`, `statusContent`, `actionArea`, etc.) — not a broad scored/free mode dump |
| Live corrections | Camera HUD only; session panel shows bottle/posture status chips without repeating the feedback sentence |
| Active camera chrome | Subtle active border only; remove `PulsingGlow` and heavy shadows from these screens |
| Disconnected camera | Neutral “Camera disconnected” state; no idle preview hint; Connection Error stays the red Retry state |
| Action area | `TrainingActionArea` is the presentation widget for the panel’s pinned `actionArea` slot; panel owns pin/position, action widget owns button chrome |
| Connection badge | Header only (connection state); session Ready/In Progress stays in the panel |
| Free Practice notice | “No score or session history will be saved.” |
| Free Practice pill | `NO SCORING` (not UNASSESSED) |
| Finish label | Rename Stop → Finish Session; preserve exact stop/summary/reset behavior |
| Pause | Do not add Pause/Resume; protocol is Start/Stop only |
| Performance bar | New/generalized practice performance component; do not fake-rename `XpBar` internals |
| Score unavailable | Em dash (`—`), not `0` |
| Performance bands | 85–100 Excellent; 70–84 Developing; below 70 Needs Practice — centralized for scored-session presentation only |
| Themes | `context.elix*` for surfaces/text/borders; camera viewport may stay dark neutral |
| Tiny helpers | Keep in nearest feature widget file; no microscopic one-off files |
| Core widgets | Do not move practice-specific widgets into `lib/core/widgets/` |
| `freeMode` / picker | Remove only after repo-wide search confirms no call sites, deep links, or tests |

## Constraints

1. Do not change WebSocket protocol, scoring math, hold/combo logic, countdown, audio, mirroring, session save, summary sheet, routes, or backend files.
2. Do not add Pause by stopping the session or resetting the timer.
3. Do not add a new Flutter package unless absolutely necessary.
4. Reuse Fluent UI, `AppColors`, `AppSpacing`, `AppTheme`, `ElixCard`, `ElixPrimaryButton`, and existing game overlays.
5. Do not hardcode dark-only card, text, or border colors when theme extensions exist.
6. Do not invent a Free Practice completion summary.

## Architecture

### Approach

Shared Training Session presentation shell. `PracticeScreen` and `LivePracticeScreen` remain responsible for session orchestration and state. Duplicated camera, connection badge, status, and action chrome move into feature widgets. Scored vs Free content is supplied through panel slots so the shell does not accumulate mode conditionals.

### File layout

```
lib/features/practice/
├── practice_screen.dart              # scored orchestration (unchanged behavior)
├── live_practice_screen.dart         # Free Practice orchestration
├── practice_game_widgets.dart        # countdown, combo, score popup, victory, GameActionButton
└── widgets/
    ├── training_session_header.dart
    ├── training_camera_workspace.dart
    ├── training_session_panel.dart   # shell only (slots)
    ├── training_connection_badge.dart
    ├── training_status_row.dart
    └── training_action_area.dart
```

Optional scored-only presentation helper (only if `practice_screen.dart` remains unwieldy), e.g. `training_scored_panel_content.dart` or private builders in the screen file. Keep Free Practice content construction near `LivePracticeScreen`.

Centralize the performance thresholds for scored-session presentation (helper or small file under `widgets/`). Reuse elsewhere only after confirming the same score semantics apply. Do not leave `XpBar` labeled as Performance while retaining XP assumptions; generalize or replace with a practice-specific performance bar.

Tiny helpers (difficulty pill, metric cell, status chip mapping) stay inside the nearest larger widget file.

### Ownership

**`practice_screen.dart`**

- WebSocket connect/start/stop, feedback stream, score pulse, hold confirm, combo, countdown, music/SFX
- Session summary/save and back-navigation behavior
- Build scored panel slot children and pass them into the shared shell

**`live_practice_screen.dart`**

- WebSocket connect/start/stop, bottle detection, countdown, music/SFX
- Finish → local reset (no save); Back → `_leave` teardown to dashboard
- Build Free Practice panel slot children

**`training_session_panel.dart`**

- Structural shell: panel header chrome + scrollable body region + pinned action slot
- Slots such as `metrics`, `statusContent`, `supportingContent` (optional), `actionArea`
- Owns positioning of the pinned action slot (Column + Expanded scroll body + fixed action below)
- A small enum is fine for light styling variants; do not encode scored/free business content inside the shell

**`training_action_area.dart`**

- Reusable presentation widget supplied to the panel’s pinned `actionArea` slot
- Owns button appearance and Start / Get Ready… / Finish Session state presentation
- Does not own pinning, panel spacing, or session orchestration logic

**`training_camera_workspace.dart`**

- Disconnected / idle / connecting / waiting / error / running rendering
- Overlay slots for scored effects (hold, combo, score popup) rather than many scored-only nullables when the two screens diverge
- Optional bottom status strip driven by injected status items (max 2–3 chips)
- Generic `onRetry` callback

**`practice_game_widgets.dart`**

- Keep game overlays and victory dialog here
- Screens stop wrapping the camera in `PulsingGlow`

### Cleanup search (required before delete/rename)

Repo-wide search before removing or renaming:

- `freeMode`
- `_MovementPicker`
- `PulsingGlow`
- `XpBar`
- `_CameraPanel`
- `_ConnectionStatusBadge`
- `_BottleStatusIndicator`

Also check tests and any deep-link / constructor call sites. Prefer wiring the new shell first, then delete dead presentation after call sites are gone.

## Layout and responsive behavior

**Breakpoint:** initial content-area width `1100` logical px via `LayoutBuilder` around the **page content** (usable area after shell/navigation), not the whole OS window. Treat `1100` as a tunable starting value.

**Wide (≥ breakpoint)**

- Side-by-side: camera flexes; panel width clamped ~370 (within 360–390)
- Gap: `AppSpacing.lg` (24)
- Outer padding from existing `AppSpacing` tokens
- Connection badge in header (right)
- Panel: `Column` with `Expanded(scrollable body)` + fixed action area below (no overlays/absolute pin)

**Narrow (< breakpoint)**

- Stack: header → camera → session panel
- Prefer: constrained camera height/aspect + min usable camera height; panel body scrolls internally; action pinned within the panel via the same `Column` structure
- Do not crush the panel into a skinny side column
- Realistic short-height guarantee: action stays pinned **within the session panel** when the panel is visible; the **overall page may scroll** on very short windows
- Avoid one giant scroll that collapses the camera into a letterbox with no min height

**Overflow**

- Long titles: ellipsis
- Instructions: max 2 lines with ellipsis
- Errors wrap
- No `Spacer` inside scrollables in a way that causes unbounded constraints

## Header

**Left (title row)**

- Back button vertically aligned with the title row (not centered against title + instruction)
- Title: movement name, or `Free Practice`
- Pill: difficulty text+color (scored), or `NO SCORING` (free)
- Instruction under title (2-line max):
  - Scored: catalog description for current movement name, with safe fallback to route value or a neutral instruction if lookup fails
  - Free: `Practice freely with live bottle detection. Results are not scored or saved.`

**Right (wide) / below title block (narrow)**

- `TrainingConnectionBadge`: Camera Connected / Connecting / Disconnected / Connection Error
- Connection state only — never session Ready/Running

**Difficulty**

- Color + text for Easy / Medium / Hard
- Readable contrast in light and dark themes

## Camera workspace

### State precedence (explicit)

1. Session-fatal error  
2. Connection error  
3. Connecting  
4. Disconnected (no error)  
5. Running / waiting for frames  
6. Idle  

Idle hint (“Camera preview will appear here.” + positioning instruction) only when **connected and inactive**. Disconnected must not look ready.

### Disconnected

- Neutral “Camera disconnected” state
- Do not show the idle preview hint
- Connection Error remains the red recoverable error state (with Retry)

### Idle copy

- “Camera preview will appear here.”
- “Keep your upper body, hands, and bottle visible.”

### Connecting / waiting / error

- Connecting: progress + “Connecting to camera…”
- Running, no frame: “Waiting for camera frames…”
- Error: clear title, message, Retry via generic `onRetry`
- Prefer camera as the primary error surface; panel may show a short status note without a second Retry when the camera already owns Retry

### Running with frames

- Preserve feed, mirroring, detection overlays
- Live correction HUD: one prioritized message, 1–2 lines max (existing ~80 char shorten is acceptable baseline)
- Preserve hold indicator, combo badge, score popup, countdown
- Active chrome: thin primary border only

### Overlay order

1. Camera feed  
2. Detection overlay  
3. Correction HUD / optional status strip  
4. Hold / combo / score effects  
5. Countdown  
6. Fatal / error surface  

Countdown and error surfaces block or visually supersede ordinary overlays.

### Status strip

- Optional; driven by injected items; max 2–3 chips
- Avoid redundant pairs like both “Camera ready” and “Session running” when they add no distinct value

## Scored session panel

Built as slot children for the shared shell.

1. **Header:** “Session”; Ready / In Progress / Completed; `RankBadge` only when score available. Completed may exist only briefly before summary/navigation — do not force a visible completed dwell if the flow opens the summary immediately.
2. **Metrics:** elapsed + current score (score stronger emphasis; subtle pulse on the number only — no metrics-row jump/reflow). Missing score → `—`.
3. **Performance:** `N / 100`, one bar labeled Performance, band label from centralized helper; clamp 0–100.
4. **Status:** Detection inactive | Searching for bottle | Bottle detected; posture chip only when mappable to useful user-facing text (e.g. `stable` → “Posture stable”). No feedback sentence. If the session is active but detection feedback is temporarily unavailable, map to Searching for bottle rather than introducing another visible state.
5. **Supporting:** Movement, Difficulty; Best combo only when `> 1`. Subtle dividers/surface contrast, not nested cards.
6. **Action:** Start Session | Get Ready… | Finish Session → existing `_stopSession` / summary.

## Free Practice session panel

Same shell; simpler slots.

- Header: Session + Ready / In Progress
- Large elapsed timer only (no score/performance/rank/empty score space)
- Detection status: Detection inactive (before start); Searching for bottle (active + not detected, or detection feedback temporarily unavailable); Bottle detected
- Connection/error state takes priority over “Searching for bottle” if the camera disconnects mid-session
- Omit redundant panel camera-status row when the header badge already covers connection
- Quiet notice near status: “No score or session history will be saved.” (not warning-styled)
- Actions: Start Free Practice | Get Ready… | Finish Session → existing reset; no summary
- After Finish: timer may show `00:00` and status returns to **Ready** so the reset does not look like data loss
- Back continues to use `_leave`

## Visual styling and component states

### Color hierarchy

- Pink (`primary`): primary interaction and live score emphasis
- Purple (`accent`): secondary emphasis only — do not use pink and purple interchangeably
- Green: connected, detected, success
- Amber: connecting, corrections/warnings
- Red: errors; Finish Session is strong/destructive **while a session is active**, but should not feel equivalent to deleting data
- Neutral surfaces: ordinary information

### Connection badge

- Connected: green  
- Connecting: amber + small progress/animated dot **without changing badge width**  
- Disconnected: muted/neutral (not amber unless actively retrying)  
- Connection Error: red  

### Animation budget

Allowed: subtle score pulse, performance bar interpolation, connection/loading indicator, existing game overlays. Ordinary cards and status chips do not constantly animate.

### Reduce

Nested cards, strong borders on every metric, decorative glows competing with the camera, large empty gaps, duplicate information across header/camera/panel.

## Behavior that must not change

- WebSocket connection flow; `sendStart` / `sendStop`
- Feedback stream processing; score calculations; bottle detection; hold duration and confirmation; combo
- Countdown; music/SFX; camera mirroring setting
- Session saving and scored summary sheet
- Existing routes (`/practice`, `/live-practice`)
- Back-navigation behavior
- Free Practice no-score / no-save behavior

## Implementation phases

### Phase A — Shared shell

1. Add feature widgets under `lib/features/practice/widgets/`.
2. Wire both screens to the shell with slots; keep state in screen classes.
3. Implement responsive content-area layout (clamped panel, narrow stack, min camera height, structural action pin).

### Phase B — Scored content

4. Build scored metrics, Performance bar/helper, status, and supporting rows as slot content.
5. Apply border-only active camera chrome; constrain correction HUD; inject optional status strip items.

### Phase C — Free Practice content

6. Fill Free Practice slots (timer, detection status, quiet notice, Start Free Practice / Finish Session).
7. Preserve `_stopSession` reset and `_leave` teardown exactly.

### Phase D — Cleanup

8. Repo-wide search for the symbols listed under Cleanup search; remove dead presentation only when safe.
9. Remove duplicated private camera/badge/bottle widgets from both screens after shared widgets are wired.
10. Remove `PulsingGlow` usage from these screens (and the widget itself only if unused elsewhere).

## Validation

### Automated

```powershell
dart format <modified dart files>
flutter analyze
flutter test
```

Fix all errors introduced by the change. Do not hide analyzer warnings with ignore comments unless absolutely necessary.

### Manual acceptance

- Normal Grip and other movements: title, difficulty, instruction correct
- Free Practice loads; Start Free Practice → countdown → session; Finish resets to Ready with `00:00`, no save/summary
- Camera connect / connection error / Retry
- Frames render; mirroring follows settings
- Score updates; Performance label updates; detection status updates
- Hold indicator, combo, score popup, countdown still work
- Finish Session opens existing scored summary/save flow
- Back navigation unchanged for both screens
- Wide layout: camera dominant, panel ~360–390, no overflow
- Narrow-width layout: stacked, panel readable, no overflow
- Short-height window: camera retains usable min height; panel body scrolls; action pinned within panel; page may scroll if needed
- Dark and light themes remain readable (including amber and Easy difficulty on light surfaces)

## Out of scope

- Backend / vision / assessment changes
- Firestore schema or rules
- WebSocket contract field changes
- Scoring algorithm changes
- New audio assets or SFX behavior changes
- Route path changes
- Pause/Resume
- Free Practice save or summary sheet
- Moving practice widgets into `lib/core/widgets/`

## Risks and assumptions

- `PracticeScreen.freeMode` and `_MovementPicker` appear unused by the current router; removal is conditional on the cleanup search.
- Content breakpoint `1100` may need slight tuning after manual resize testing.
- On very short windows, promising globally pinned actions for the whole page is unrealistic; the structural pin is within the session panel.
- Posture backend strings may need a small display map; unmapped values should be hidden rather than shown raw.
