# Practice sound effects design

Date: 2026-07-27  
Status: approved for planning (pending user review of this written spec)

## Goal

Add one-shot practice SFX so that:

1. After the user presses **Start**, the 3 → 2 → 1 → GO! overlay plays `assets/music/countdown.mp3` once for the whole countdown.
2. When the user successfully holds a movement and the **Movement Complete** victory dialog appears, play `assets/music/congrats.mp3` once.

Background loop music (`practice.mp3`) stays as it is today.

## Decisions (locked)

| Topic | Choice |
| --- | --- |
| Congrats trigger | Victory dialog only (not session summary sheet) |
| Countdown playback | Once when overlay starts (full clip) |
| Screens for countdown | Scored Practice **and** Live Practice |
| Screens for congrats | Scored Practice only (Live has no victory dialog) |
| Architecture | Dedicated `PracticeSfxService` (separate player from BGM) |

## Architecture

### `PracticeSfxService`

New file: `lib/services/practice_sfx_service.dart`

Mirror `PracticeMusicService` patterns:

- Own `AudioPlayer` with `ReleaseMode.release` (one-shot, not loop).
- Asset sources: `music/countdown.mp3`, `music/congrats.mp3` (same `AssetSource` style as BGM).
- Public API:
  - `Future<void> playCountdown()`
  - `Future<void> playCongrats()`
  - `Future<void> stop()`
  - `Future<void> dispose()`
- On play: stop any currently playing SFX first, then play the requested clip (avoids overlap if Start is hammered or victory follows quickly).
- Errors: catch, `debugPrint`, never throw into UI/session flow.
- Windows teardown: always `stop` before `dispose`; screens must await stop/dispose before navigation the same way they already do for music.

### Ownership

- `PracticeScreen` and `LivePracticeScreen` each construct a `PracticeSfxService` alongside `_music`.
- Dispose SFX in the same dispose/leave paths that already dispose music.
- Stop SFX when leaving mid-countdown or mid-victory audio.

## Trigger wiring

### Countdown

1. Screen `initState` calls `PracticeSfxService.preload()` to warm the countdown source.
2. User presses Start → `await playCountdown()` (seeks past ~520 ms lead-in silence, then resumes).
3. Only then set `_countdownActive = true` so the overlay mounts in sync with the first audible beat.
4. Overlay step duration is **1000 ms** to match `countdown.mp3` beat spacing (~0.55 / 1.60 / 2.55 / 3.50 s).
5. If overlay is disposed early (navigate away / leave), stop SFX.

### Congrats

1. Hold completes → `_onMovementConfirmed`.
2. Session detection paused; BGM stopped (existing behavior).
3. Immediately before or as `showVictoryDialog` opens, call `playCongrats()`.
4. Do **not** play on `SessionSummarySheet` (save/discard after Quit).

Preferred wiring: call `playCongrats()` from `_onMovementConfirmed` / `_showMovementConfirmedDialog` in `practice_screen.dart`, or pass a callback into `showVictoryDialog`. Screen-level call is enough and keeps the dialog free of service ownership.

### BGM interaction

- Unchanged: BGM starts in `_beginSessionAfterCountdown` after GO completes.
- Unchanged: BGM stops before victory dialog.
- SFX uses a separate player so countdown/congrats do not require changing BGM APIs.
- No ducking/volume mixing in this scope.

## Assets / pubspec

Existing files:

- `assets/music/countdown.mp3`
- `assets/music/congrats.mp3`

`pubspec.yaml` already includes `assets/` and explicitly lists `assets/music/practice.mp3`. Add explicit entries for the two new mp3s next to practice for discoverability (redundant with `assets/` but consistent with current style).

`.wav` copies under `assets/music/` (if present) are unused by this design; do not wire them.

## Out of scope

- Session summary sheet audio
- Per-beat countdown retrigger
- Muting or ducking BGM under SFX
- Settings toggle for SFX volume / mute (unless already covered by a global mute — not required here)
- Backend / WebSocket / Firestore changes

## Acceptance criteria

1. Practice + Live Practice: Start → hear countdown once while 3-2-1-GO overlay runs.
2. Practice: successful hold → victory dialog appears and congrats plays once.
3. Quit → session summary sheet does **not** play congrats.
4. Leaving / disposing screens does not leave orphan players or crash Windows audio teardown.
5. Missing/corrupt audio fails soft (session continues; debug log only).

## Verification

- `dart format --output=none --set-exit-if-changed lib`
- `flutter analyze`
- `flutter test`
- Manual on Windows: Start countdown on both screens; complete a hold on Practice and confirm congrats with victory dialog; leave mid-countdown and confirm no crash.

## Test notes

Unit-testing `audioplayers` on Windows desktop is limited. Prefer a thin service that can be faked if tests already inject services; otherwise rely on analyze + manual check. Do not add tests that require real device audio hardware.
