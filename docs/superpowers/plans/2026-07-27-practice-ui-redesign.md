# Practice UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign scored Practice and Free Practice into one Training Session visual system with a shared presentation shell, while preserving all session orchestration behavior.

**Architecture:** Keep orchestration in `PracticeScreen` and `LivePracticeScreen`. Extract shared presentation under `lib/features/practice/widgets/`. `TrainingSessionPanel` is a slot-based shell that owns action pinning; scored/free content is built by each screen and passed in. Camera corrections stay on the HUD; the panel shows status chips only.

**Tech Stack:** Flutter Windows desktop, Fluent UI, existing `AppColors` / `AppSpacing` / `AppTheme` / `ElixCard` / `GameActionButton`, `go_router`, `provider`.

**Spec:** `docs/superpowers/specs/2026-07-27-practice-ui-redesign-design.md`

## Global Constraints

- Do not change WebSocket protocol, scoring math, hold/combo, countdown, audio, mirroring, session save, summary sheet, routes, or backend files.
- Do not add Pause/Resume.
- Rename Stop → Finish Session but keep exact stop/summary/reset/`_leave` behavior.
- Panel composition is slot-based; do not fill `TrainingSessionPanel` with scored/free conditionals.
- `TrainingActionArea` owns button chrome/state presentation; `TrainingSessionPanel` owns pin/position.
- Active camera chrome: thin border only — no `PulsingGlow` on these screens.
- Connection badge: connection state only.
- Performance bands are for scored-session presentation only; do not change summary terminology.
- Use `context.elix*` for surfaces/text/borders; camera viewport may stay dark neutral.
- No practice widgets in `lib/core/widgets/`.
- No commits unless the user asks.
- Smallest coherent change; no unrelated refactors.

## File map

| File | Responsibility |
| --- | --- |
| `lib/features/practice/widgets/training_performance.dart` | Band helper + performance bar widget |
| `lib/features/practice/widgets/training_connection_badge.dart` | Header connection chip |
| `lib/features/practice/widgets/training_status_row.dart` | Detection/posture status chips |
| `lib/features/practice/widgets/training_action_area.dart` | Start / Get Ready… / Finish presentation |
| `lib/features/practice/widgets/training_session_header.dart` | Back, title, pill, instruction, badge |
| `lib/features/practice/widgets/training_camera_workspace.dart` | Shared camera surface + overlays |
| `lib/features/practice/widgets/training_session_panel.dart` | Slot shell + pinned action |
| `lib/features/practice/practice_screen.dart` | Wire scored UI; keep all behavior |
| `lib/features/practice/live_practice_screen.dart` | Wire Free Practice UI; keep all behavior |
| `lib/features/practice/practice_game_widgets.dart` | Keep overlays; leave or remove unused `XpBar`/`PulsingGlow` only after search |
| `test/features/practice/training_performance_test.dart` | Unit tests for band helper |

---

### Task 1: Performance band helper + bar

**Files:**
- Create: `lib/features/practice/widgets/training_performance.dart`
- Create: `test/features/practice/training_performance_test.dart`

**Interfaces:**
- Produces:
  - `String trainingPerformanceLabel(int score)` → Excellent / Developing / Needs Practice
  - `double trainingPerformanceFraction(int? score)` → clamped 0.0–1.0
  - `class TrainingPerformanceBar extends StatelessWidget` with `final int? score`

- [ ] **Step 1: Write the failing test**

Create `test/features/practice/training_performance_test.dart`:

```dart
import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trainingPerformanceLabel', () {
    test('Excellent at 85–100', () {
      expect(trainingPerformanceLabel(85), 'Excellent');
      expect(trainingPerformanceLabel(100), 'Excellent');
    });

    test('Developing at 70–84', () {
      expect(trainingPerformanceLabel(70), 'Developing');
      expect(trainingPerformanceLabel(84), 'Developing');
    });

    test('Needs Practice below 70', () {
      expect(trainingPerformanceLabel(69), 'Needs Practice');
      expect(trainingPerformanceLabel(0), 'Needs Practice');
    });
  });

  group('trainingPerformanceFraction', () {
    test('null is 0', () {
      expect(trainingPerformanceFraction(null), 0.0);
    });

    test('clamps below 0 and above 100', () {
      expect(trainingPerformanceFraction(-10), 0.0);
      expect(trainingPerformanceFraction(150), 1.0);
      expect(trainingPerformanceFraction(50), 0.5);
    });
  });
}
```

If the package import path differs, match `name:` in `pubspec.yaml`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/practice/training_performance_test.dart`

Expected: FAIL (library/file not found).

- [ ] **Step 3: Implement helper + bar**

Create `lib/features/practice/widgets/training_performance.dart`:

```dart
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

String trainingPerformanceLabel(int score) {
  final clamped = score.clamp(0, 100);
  if (clamped >= 85) return 'Excellent';
  if (clamped >= 70) return 'Developing';
  return 'Needs Practice';
}

double trainingPerformanceFraction(int? score) {
  if (score == null) return 0.0;
  return (score / 100).clamp(0.0, 1.0);
}

/// Practice-session performance bar (not XP). Scored presentation only.
class TrainingPerformanceBar extends StatelessWidget {
  const TrainingPerformanceBar({super.key, required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final value = trainingPerformanceFraction(score);
    final label = score == null
        ? '—'
        : trainingPerformanceLabel(score!);
    final display = score == null ? '— / 100' : '${score!.clamp(0, 100)} / 100';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Performance',
              style: AppTheme.caption.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.elixTextSecondary,
              ),
            ),
            Text(
              display,
              style: AppTheme.caption.copyWith(
                color: AppColors.primarySoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: ColoredBox(
            color: context.elixBorder.withValues(alpha: 0.35),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: value),
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v == 0 ? 0.001 : v,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primarySoft],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          score == null ? '—' : label,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
      ],
    );
  }
}
```

Do **not** modify `XpBar` in place. Leave it until cleanup search; scored UI will use `TrainingPerformanceBar`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/practice/training_performance_test.dart`

Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/practice/widgets/training_performance.dart`

Expected: no issues.

---

### Task 2: Connection badge + status row

**Files:**
- Create: `lib/features/practice/widgets/training_connection_badge.dart`
- Create: `lib/features/practice/widgets/training_status_row.dart`

**Interfaces:**
- Produces:
  - `TrainingConnectionBadge({required WebSocketConnectionState state, bool connecting = false})`
  - Labels: Camera Connected / Connecting / Disconnected / Connection Error
  - `enum TrainingDetectionStatus { inactive, searching, detected }`
  - `TrainingDetectionStatus resolveDetectionStatus({required bool sessionActive, bool? bottleDetected})`
  - `String? postureDisplayLabel(String? postureStatus)` — maps useful values only (e.g. `stable` → `Posture stable`); unknown/raw → null
  - `TrainingStatusRow({required TrainingDetectionStatus detection, String? postureLabel})`

- [ ] **Step 1: Implement connection badge**

```dart
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/websocket_service.dart';

class TrainingConnectionBadge extends StatelessWidget {
  const TrainingConnectionBadge({
    super.key,
    required this.state,
    this.connecting = false,
  });

  final WebSocketConnectionState state;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      WebSocketConnectionState.connected => (
        'Camera Connected',
        AppColors.success,
      ),
      WebSocketConnectionState.connecting => (
        'Connecting',
        AppColors.warning,
      ),
      WebSocketConnectionState.error => (
        'Connection Error',
        AppColors.error,
      ),
      WebSocketConnectionState.disconnected => (
        'Disconnected',
        context.elixTextSecondary,
      ),
    };

    final showSpinner =
        connecting || state == WebSocketConnectionState.connecting;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: showSpinner
                ? const ProgressRing(strokeWidth: 2)
                : Center(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTheme.body.copyWith(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
```

Badge width must stay stable when the spinner appears (fixed 14×14 leading slot).

- [ ] **Step 2: Implement status row + helpers**

```dart
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

enum TrainingDetectionStatus { inactive, searching, detected }

TrainingDetectionStatus resolveDetectionStatus({
  required bool sessionActive,
  bool? bottleDetected,
}) {
  if (!sessionActive) return TrainingDetectionStatus.inactive;
  if (bottleDetected == true) return TrainingDetectionStatus.detected;
  // Active but not detected, or feedback temporarily unavailable → searching
  return TrainingDetectionStatus.searching;
}

String? postureDisplayLabel(String? postureStatus) {
  switch (postureStatus) {
    case 'stable':
      return 'Posture stable';
    case 'unstable':
      return 'Posture unstable';
    default:
      return null;
  }
}

class TrainingStatusRow extends StatelessWidget {
  const TrainingStatusRow({
    super.key,
    required this.detection,
    this.postureLabel,
  });

  final TrainingDetectionStatus detection;
  final String? postureLabel;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (detection) {
      TrainingDetectionStatus.detected => (
        'Bottle detected',
        AppColors.success,
        FluentIcons.status_circle_checkmark,
      ),
      TrainingDetectionStatus.searching => (
        'Searching for bottle',
        AppColors.warning,
        FluentIcons.search,
      ),
      TrainingDetectionStatus.inactive => (
        'Detection inactive',
        context.elixTextSecondary,
        FluentIcons.circle_ring,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusLine(icon: icon, label: label, color: color),
        if (postureLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _StatusLine(
            icon: FluentIcons.contact,
            label: postureLabel!,
            color: context.elixTextSecondary,
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTheme.body.copyWith(color: color, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Analyze new files**

Run: `flutter analyze lib/features/practice/widgets/training_connection_badge.dart lib/features/practice/widgets/training_status_row.dart`

Expected: no issues.

---

### Task 3: Action area + session panel shell

**Files:**
- Create: `lib/features/practice/widgets/training_action_area.dart`
- Create: `lib/features/practice/widgets/training_session_panel.dart`

**Interfaces:**
- Produces:
  - `enum TrainingActionKind { start, getReady, finish }`
  - `TrainingActionArea({required TrainingActionKind kind, required String startLabel, VoidCallback? onPressed, bool isLoading = false})`
  - `enum TrainingSessionPhase { ready, inProgress, completed }`
  - `TrainingSessionPanel({required TrainingSessionPhase phase, Widget? rankBadge, required Widget metrics, required Widget statusContent, Widget? supportingContent, Widget? notice, Widget? compactStatusNote, required Widget actionArea})`

- [ ] **Step 1: Implement `TrainingActionArea`**

Owns button appearance only. Uses existing `GameActionButton`.

```dart
import 'package:fluent_ui/fluent_ui.dart';

import '../practice_game_widgets.dart';

enum TrainingActionKind { start, getReady, finish }

class TrainingActionArea extends StatelessWidget {
  const TrainingActionArea({
    super.key,
    required this.kind,
    required this.startLabel,
    this.onPressed,
    this.isLoading = false,
  });

  final TrainingActionKind kind;
  /// e.g. "Start Session" or "Start Free Practice"
  final String startLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      TrainingActionKind.finish => GameActionButton(
        label: 'Finish Session',
        icon: FluentIcons.stop_solid,
        danger: true,
        onPressed: onPressed,
      ),
      TrainingActionKind.getReady => GameActionButton(
        label: 'Get Ready…',
        icon: FluentIcons.play_solid,
        onPressed: null,
        isLoading: false,
      ),
      TrainingActionKind.start => GameActionButton(
        label: startLabel,
        icon: FluentIcons.play_solid,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    };
  }
}
```

- [ ] **Step 2: Implement `TrainingSessionPanel` shell**

Panel owns pin structure. Do not put scored/free branches here.

```dart
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_card.dart';

enum TrainingSessionPhase { ready, inProgress, completed }

class TrainingSessionPanel extends StatelessWidget {
  const TrainingSessionPanel({
    super.key,
    required this.phase,
    required this.metrics,
    required this.statusContent,
    required this.actionArea,
    this.rankBadge,
    this.supportingContent,
    this.notice,
    this.compactStatusNote,
  });

  final TrainingSessionPhase phase;
  final Widget metrics;
  final Widget statusContent;
  final Widget actionArea;
  final Widget? rankBadge;
  final Widget? supportingContent;
  final Widget? notice;
  final Widget? compactStatusNote;

  String get _phaseLabel => switch (phase) {
    TrainingSessionPhase.ready => 'Ready',
    TrainingSessionPhase.inProgress => 'In Progress',
    TrainingSessionPhase.completed => 'Completed',
  };

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Session', style: AppTheme.headingMedium),
                      const SizedBox(width: AppSpacing.sm),
                      _PhaseChip(label: _phaseLabel),
                      const Spacer(),
                      if (rankBadge != null) rankBadge!,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  metrics,
                  const SizedBox(height: AppSpacing.md),
                  statusContent,
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    notice!,
                  ],
                  if (supportingContent != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Divider(
                      style: DividerThemeData(
                        decoration: BoxDecoration(
                          color: context.elixBorder.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    supportingContent!,
                  ],
                  if (compactStatusNote != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    compactStatusNote!,
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: actionArea,
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.elixBorder.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: context.elixTextSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

Adjust `Divider` usage to match Fluent API already used in the project if the snippet’s `DividerThemeData` differs — prefer a 1px `Container` divider matching existing practice screens if simpler.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/practice/widgets/training_action_area.dart lib/features/practice/widgets/training_session_panel.dart`

Expected: no issues.

---

### Task 4: Header + camera workspace

**Files:**
- Create: `lib/features/practice/widgets/training_session_header.dart`
- Create: `lib/features/practice/widgets/training_camera_workspace.dart`

**Interfaces:**
- Produces:
  - `TrainingSessionHeader({required VoidCallback onBack, required String title, required String statusPill, required String instruction, required WebSocketConnectionState connectionState, bool connecting = false, bool wideLayout = true})`
  - Back aligned to title row; instruction max 2 lines; badge right (wide) or below (narrow)
  - `class TrainingCameraStatusItem { final String label; final Color? color; }`
  - `TrainingCameraWorkspace({required Uint8List? frameBytes, required bool mirrored, required WebSocketConnectionState connectionState, required bool connecting, required bool isSessionActive, required VoidCallback onRetry, String? errorMessage, String? sessionError, bool countdownActive = false, required VoidCallback onCountdownComplete, Widget? overlays, List<TrainingCameraStatusItem> statusItems = const []})`
  - State precedence: fatal → connection error → connecting → disconnected → running/waiting → idle

- [ ] **Step 1: Implement header**

Include a difficulty/status pill that shows **text + color**. For scored difficulty strings (`Easy`/`Medium`/`Hard`), map colors with light-theme-readable contrast; for Free Practice pass `NO SCORING` with primary-soft styling.

Lookup instruction in the **screen**, not the header:

```dart
String scoredInstructionFor(String movement) {
  for (final m in movementCatalog) {
    if (m.name == movement) return m.description;
  }
  return 'Follow the on-screen guidance for this movement.';
}
```

Header API sketch:

```dart
class TrainingSessionHeader extends StatelessWidget {
  const TrainingSessionHeader({
    super.key,
    required this.onBack,
    required this.title,
    required this.statusPill,
    required this.instruction,
    required this.connectionState,
    this.connecting = false,
    this.wideLayout = true,
    this.statusPillColor,
  });
  // build: Row title-row with back + title + pill; instruction under title (maxLines: 2);
  // wide: badge on trailing; narrow: badge below title block
}
```

- [ ] **Step 2: Implement camera workspace**

Extract common rendering from both screens’ `_CameraPanel`. Pass scored overlays as a single `overlays` slot (`Stack` children from the screen: hold, combo, score popup). Free Practice passes `null`/empty overlays besides countdown (countdown is built into workspace).

Disconnected branch (must not fall through to idle):

```dart
if (connectionState == WebSocketConnectionState.disconnected &&
    !connecting &&
    sessionError == null) {
  // Neutral "Camera disconnected" centered state — no idle hint
}
```

Active border only when `isSessionActive` — thin `AppColors.primary` border, no glow/shadow/`PulsingGlow`.

Overlay order inside the stack:

1. Feed or placeholder  
2. `overlays` (hold/combo/score)  
3. Optional bottom status strip from `statusItems` (max 3)  
4. Countdown if active  
5. Fatal/error surface last  

Correction HUD for scored sessions: keep a compact top HUD inside the workspace or as part of `overlays` supplied by PracticeScreen — one prioritized message, max ~2 lines / ~80 chars (preserve existing shorten behavior).

Idle only when `connectionState == connected && !isSessionActive && frameBytes == null && sessionError == null`.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/practice/widgets/training_session_header.dart lib/features/practice/widgets/training_camera_workspace.dart`

Expected: no issues.

---

### Task 5: Wire `PracticeScreen` (scored)

**Files:**
- Modify: `lib/features/practice/practice_screen.dart`

**Interfaces:**
- Consumes: all widgets from Tasks 1–4
- Preserves: `_connect`, `_startSession`, `_beginSessionAfterCountdown`, `_stopSession`, hold/combo/score pulse, summary, back behavior

- [ ] **Step 1: Replace `build` layout with responsive shell**

Use `LayoutBuilder` on the **content** (inside padding), not the whole window:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final wide = constraints.maxWidth >= 1100;
    final header = TrainingSessionHeader(
      onBack: () { /* existing back logic */ },
      title: _movement,
      statusPill: _difficulty.toUpperCase(),
      instruction: scoredInstructionFor(_movement),
      connectionState: _ws.connectionState,
      connecting: _connecting,
      wideLayout: wide,
    );
    final camera = TrainingCameraWorkspace(
      // map existing fields; overlays: hold + combo + score popup
      // statusItems: optional compact chips
    );
    final panel = TrainingSessionPanel(
      phase: isSessionActive
          ? TrainingSessionPhase.inProgress
          : TrainingSessionPhase.ready,
      rankBadge: _latestFeedback?.score != null
          ? RankBadge(score: _latestFeedback!.score)
          : null,
      metrics: /* timer + pulsing score (— if null) + TrainingPerformanceBar */,
      statusContent: TrainingStatusRow(
        detection: resolveDetectionStatus(
          sessionActive: isSessionActive,
          bottleDetected: _latestFeedback?.bottleDetected,
        ),
        postureLabel: postureDisplayLabel(_latestFeedback?.postureStatus),
      ),
      supportingContent: /* movement, difficulty, best combo if > 1 */,
      compactStatusNote: /* short note only; no second Retry if camera shows Retry */,
      actionArea: TrainingActionArea(
        kind: isSessionActive
            ? TrainingActionKind.finish
            : (_countdownActive
                ? TrainingActionKind.getReady
                : TrainingActionKind.start),
        startLabel: 'Start Session',
        onPressed: /* existing start/connect/stop wiring */,
        isLoading: _connecting,
      ),
    );

    if (wide) {
      return Column(
        children: [
          header,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: camera),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: 370, child: panel),
              ],
            ),
          ),
        ],
      );
    }

    // Narrow: SingleChildScrollView OK for short height; camera has min height;
    // panel still uses Expanded-style pin when given a bounded height — if page
    // scrolls, give panel a sensible min height (e.g. 320) so action stays at
    // panel bottom.
    return SingleChildScrollView(
      child: Column(
        children: [
          header,
          SizedBox(
            height: math.max(280.0, constraints.maxHeight * 0.42),
            child: camera,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(height: 360, child: panel),
        ],
      ),
    );
  },
);
```

Tune constants after resize testing; breakpoint remains content-based.

- [ ] **Step 2: Metrics presentation details**

- Timer + score in a two-column row without heavy bordered tiles
- Score uses existing `_scorePulse` on the **number only**
- Missing score shows `—`
- Below metrics: `TrainingPerformanceBar(score: _latestFeedback?.score)`

- [ ] **Step 3: Remove local duplicated presentation**

Delete private `_CameraPanel`, `_ConnectionStatusBadge`, `_BottleStatusIndicator`, `_StatTile` usage from the layout after the shared widgets are wired. Keep hold/HUD helpers only if still needed as overlay builders; otherwise move HUD into camera workspace.

Do **not** remove `freeMode` / `_MovementPicker` in this task — that is Task 7 after search.

- [ ] **Step 4: Analyze practice screen**

Run: `flutter analyze lib/features/practice/practice_screen.dart`

Expected: no issues. Behavior methods unchanged.

---

### Task 6: Wire `LivePracticeScreen` (Free Practice)

**Files:**
- Modify: `lib/features/practice/live_practice_screen.dart`

**Interfaces:**
- Consumes: same shell widgets
- Preserves: `_connect`, `_startSession`, `_beginSessionAfterCountdown`, `_stopSession` reset, `_leave`

- [ ] **Step 1: Replace layout with same responsive shell**

Header:

- title: `Free Practice`
- statusPill: `NO SCORING`
- instruction: `Practice freely with live bottle detection. Results are not scored or saved.`
- onBack: `_leave`

Panel slots:

- metrics: large elapsed timer only
- statusContent: `TrainingStatusRow` via `resolveDetectionStatus`
- notice: quiet text `No score or session history will be saved.`
- omit supporting/rank/performance
- omit redundant camera status row (header badge owns connection)
- actionArea: `startLabel: 'Start Free Practice'`; Finish → `_stopSession`

After finish: timer `00:00`, phase Ready, detection inactive.

- [ ] **Step 2: Camera without scored overlays**

Pass empty overlays; still include countdown. Disconnected/error/idle rules identical to scored.

- [ ] **Step 3: Delete local duplicates**

Remove `_CameraPanel`, `_ConnectionStatusBadge`, `_BottleStatusIndicator` from this file once shared widgets are used.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/features/practice/live_practice_screen.dart`

Expected: no issues.

---

### Task 7: Cleanup after repo-wide search

**Files:**
- Possibly modify: `practice_screen.dart`, `practice_game_widgets.dart`, both screens
- Search only first — delete only when unused

**Search before any delete/rename:**

```powershell
rg -n "freeMode|_MovementPicker|PulsingGlow|XpBar|_CameraPanel|_ConnectionStatusBadge|_BottleStatusIndicator" lib test
```

- [ ] **Step 1: Run the search and record hits**

- [ ] **Step 2: Conditionally remove `freeMode` / `_MovementPicker`**

Only if zero constructor/deep-link/test references outside dead local code.

- [ ] **Step 3: Remove `PulsingGlow` call sites** on practice/live screens (already done in Tasks 5–6). Delete `PulsingGlow` class only if search shows no remaining references.

- [ ] **Step 4: `XpBar`**

If only unused after scored UI switched to `TrainingPerformanceBar`, delete `XpBar`. If still referenced (e.g. summary), leave it alone — do not relabel as Performance.

- [ ] **Step 5: Confirm private camera/badge/bottle widgets are gone** from both screens.

- [ ] **Step 6: Analyze practice feature**

Run: `flutter analyze lib/features/practice`

Expected: no issues.

---

### Task 8: Format, analyze, test, manual checklist

**Files:** all modified Dart files from Tasks 1–7

- [ ] **Step 1: Format**

Run:

```powershell
dart format lib/features/practice lib/features/practice/widgets test/features/practice
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`

Expected: no issues introduced by this change.

- [ ] **Step 3: Test**

Run: `flutter test`

Expected: `training_performance_test` passes; no regressions.

- [ ] **Step 4: Manual checklist (do not claim done without running)**

- Normal Grip: title, difficulty, instruction
- Another movement name/difficulty
- Free Practice loads
- Camera connect; Disconnected shows “Camera disconnected” (not idle hint)
- Connection Error + Retry
- Start Session → countdown → session; Start Free Practice same
- Frames + mirror; hold; combo; score popup
- Score + Performance label; Detection inactive → Searching → Detected
- Finish Session → existing scored summary
- Free Finish → Ready + 00:00, no save/summary
- Back navigation both screens
- Wide ≥1100 content width
- Narrow width stacked layout
- Short-height window: camera min height, panel body scroll, action at panel bottom, page may scroll
- Dark + light readable (amber, Easy pill)

---

## Spec coverage checklist

| Spec item | Task |
| --- | --- |
| Performance helper + bar (not XpBar rename) | 1 |
| Connection badge + detection status mapping | 2 |
| Action area vs panel pin ownership | 3 |
| Header + camera states including disconnected | 4 |
| Scored panel slots + PracticeScreen wiring | 5 |
| Free Practice panel + LivePracticeScreen wiring | 6 |
| Cleanup search list | 7 |
| Format / analyze / test / short-height manual | 8 |
| No protocol/scoring/audio/route/backend changes | Global + all tasks |
| Corrections on HUD only | 4–5 |
| Border-only active camera | 4–6 |

## Plan self-review notes

- No TBD placeholders.
- Interfaces named consistently (`TrainingActionKind`, `TrainingSessionPhase`, `resolveDetectionStatus`).
- Commits omitted per repo preference unless the user asks.
- Flutter has no existing practice widget tests; Task 1 adds a focused unit test for the only pure logic introduced.
