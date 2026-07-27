# Practice SFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play `countdown.mp3` once when the 3-2-1-GO overlay starts (Practice + Live), and `congrats.mp3` once when the Movement Complete victory dialog opens (Practice only).

**Architecture:** Add `PracticeSfxService` with its own `AudioPlayer` (mirrors `PracticeMusicService`). Overlay calls `onStarted` for countdown; Practice screen calls `playCongrats()` before victory dialog. Dispose/stop with existing music teardown paths.

**Tech Stack:** Flutter Windows, `audioplayers` ^6.7.1, Fluent UI practice screens.

## Global Constraints

- Do not play congrats on `SessionSummarySheet`.
- Countdown plays once per overlay mount, not per beat.
- Soft-fail audio errors with `debugPrint`; never crash the session.
- Stop SFX before dispose / leave (Windows AudioPlayer teardown).
- No commits unless the user asks.
- Smallest coherent change; no unrelated refactors.

---

### Task 1: PracticeSfxService + pubspec assets

**Files:**
- Create: `lib/services/practice_sfx_service.dart`
- Modify: `pubspec.yaml` (assets list)

**Interfaces:**
- Produces: `PracticeSfxService` with `playCountdown()`, `playCongrats()`, `stop()`, `dispose()`

- [ ] **Step 1: Add service**

```dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One-shot practice sound effects (countdown, victory congrats).
class PracticeSfxService {
  PracticeSfxService() : _player = AudioPlayer();

  static final _countdown = AssetSource('music/countdown.mp3');
  static final _congrats = AssetSource('music/congrats.mp3');

  final AudioPlayer _player;
  bool _disposed = false;

  Future<void> playCountdown() => _play(_countdown);

  Future<void> playCongrats() => _play(_congrats);

  Future<void> _play(AssetSource source) async {
    if (_disposed) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.play(source);
    } catch (e, st) {
      debugPrint('Practice SFX failed to play: $e\n$st');
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _player.stop();
    } catch (e, st) {
      debugPrint('Practice SFX failed to stop: $e\n$st');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _player.stop();
      await _player.dispose();
    } catch (e, st) {
      debugPrint('Practice SFX failed to dispose: $e\n$st');
    }
  }
}
```

- [ ] **Step 2: List assets in pubspec**

Under `flutter: assets:`, add:

```yaml
    - assets/music/countdown.mp3
    - assets/music/congrats.mp3
```

beside the existing `practice.mp3` entry.

- [ ] **Step 3: Verify service analyzes**

Run: `flutter analyze lib/services/practice_sfx_service.dart`
Expected: no issues.

---

### Task 2: Wire countdown into GameCountdownOverlay + both screens

**Files:**
- Modify: `lib/features/practice/practice_game_widgets.dart` (`GameCountdownOverlay`)
- Modify: `lib/features/practice/practice_screen.dart`
- Modify: `lib/features/practice/live_practice_screen.dart`

**Interfaces:**
- Consumes: `PracticeSfxService.playCountdown()`, `stop()`, `dispose()`
- Produces: `GameCountdownOverlay({required onComplete, VoidCallback? onStarted})`

- [ ] **Step 1: Add `onStarted` to overlay**

In `GameCountdownOverlay`, add optional `VoidCallback? onStarted`. Call it once at the end of `initState` after starting the controller (fire-and-forget; do not await).

- [ ] **Step 2: Practice screen ownership**

- Import + `final _sfx = PracticeSfxService();`
- `_sfx.dispose()` in `dispose`
- `_sfx.stop()` wherever `_music.stop()` runs for session teardown / fatal / confirmed (best-effort; at minimum dispose + leave paths + when stopping session)
- Pass `onStarted: _sfx.playCountdown` into `GameCountdownOverlay`

- [ ] **Step 3: Live Practice ownership**

Same as Step 2 for countdown only (no congrats). Also `await _sfx.stop()` in `_leave` next to music stop.

- [ ] **Step 4: Analyze touched files**

Run: `flutter analyze lib/services/practice_sfx_service.dart lib/features/practice/practice_game_widgets.dart lib/features/practice/practice_screen.dart lib/features/practice/live_practice_screen.dart`

---

### Task 3: Congrats on victory dialog

**Files:**
- Modify: `lib/features/practice/practice_screen.dart` (`_onMovementConfirmed` / `_showMovementConfirmedDialog`)

**Interfaces:**
- Consumes: `PracticeSfxService.playCongrats()`

- [ ] **Step 1: Play congrats when victory opens**

After `await _music.stop()` in `_onMovementConfirmed`, call `unawaited(_sfx.playCongrats())` or `await _sfx.playCongrats()` before `showVictoryDialog`. Prefer await so audio starts before dialog paint when possible.

Do **not** call from `SessionSummarySheet` / `_stopSession` summary path.

- [ ] **Step 2: Verify**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```

Manual (Windows): Start on Practice + Live → hear countdown; hold movement → victory + congrats; Quit summary → no congrats.

---

## Spec coverage

| Spec requirement | Task |
| --- | --- |
| Countdown once on overlay | Task 2 |
| Congrats on victory only | Task 3 |
| Live + Practice countdown | Task 2 |
| Separate SFX service | Task 1 |
| Soft-fail + dispose | Task 1–2 |
| pubspec assets | Task 1 |
| No summary SFX | Task 3 (explicit non-wire) |
