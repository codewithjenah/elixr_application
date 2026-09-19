import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_player_handle.dart';
import 'settings_service.dart';

/// One-shot practice sound effects (countdown, victory congrats).
class PracticeSfxService {
  PracticeSfxService({AudioPlayerHandle? player})
    : _player = player ?? AudioplayersHandle();

  static final _countdown = AssetSource('music/countdown.mp3');
  static final _congrats = AssetSource('music/congrats.mp3');

  /// Leading silence before the first audible "3" beat in countdown.mp3.
  static const countdownLeadIn = Duration(milliseconds: 520);

  final AudioPlayerHandle _player;
  SettingsService? _settings;
  Future<void> _operation = Future<void>.value();
  Future<void>? _disposeFuture;
  bool _closing = false;
  bool _preloaded = false;
  bool? _lastSoundEnabled;
  double? _lastMusicVolume;

  /// Binds the long-lived settings instance after the Practice screen gains
  /// access to inherited dependencies. Repeated binding is idempotent.
  void bindSettings(SettingsService settings) {
    if (_closing || identical(_settings, settings)) return;
    _settings?.removeListener(_onSettingsChanged);
    _settings = settings;
    _settings!.addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  void _onSettingsChanged() {
    final settings = _settings;
    if (_closing || settings == null) return;
    if (_lastSoundEnabled == settings.soundEnabled &&
        _lastMusicVolume == settings.musicVolume) {
      return;
    }
    _lastSoundEnabled = settings.soundEnabled;
    _lastMusicVolume = settings.musicVolume;
    unawaited(setVolume(settings.soundEnabled ? settings.musicVolume : 0.0));
  }

  @visibleForTesting
  Future<void> get settled => _operation;

  /// Serializes every command issued to the native player. The Windows
  /// backend can load sources and emit callbacks asynchronously, so allowing
  /// stop, source changes, and volume updates to overlap is unsafe.
  Future<void> _queue(String operation, Future<void> Function() action) {
    if (_closing) return _operation;
    _operation = _operation.then((_) => action()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Practice SFX $operation failed: $error\n$stack');
    });
    return _operation;
  }

  Future<void> setVolume(double volume) =>
      _queue('set volume', () => _player.setVolume(volume));

  /// Warm the countdown source so Start → first beat is not delayed by decode.
  Future<void> preload() {
    if (_preloaded || _closing) return _operation;
    return _queue('preload', () async {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setSourceAsset(_countdown.path);
      _preloaded = true;
    });
  }

  Future<void> playCountdown({
    double? volume,
  }) => _queue('play countdown', () async {
    if (volume != null) await _player.setVolume(volume);
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.release);
    // Use play() (not setSource+resume) so switching from congrats is reliable
    // on Windows after Try Again.
    await _player.playAssetAtPosition(
      _countdown.path,
      position: countdownLeadIn,
    );
    _preloaded = true;
  });

  /// Queues the volume and all playback commands together. This keeps a
  /// settings update or navigation stop from splitting a completion playback.
  Future<void> playCongrats({required double volume}) =>
      _queue('play congratulations', () async {
        await _player.setVolume(volume);
        await _player.stop();
        await _player.setReleaseMode(ReleaseMode.release);
        await _player.playAsset(_congrats.path);
        _preloaded = false;
      });

  Future<void> stop() => _queue('stop', _player.stop);

  Future<void> dispose() async {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _closing = true;
    _settings?.removeListener(_onSettingsChanged);
    _settings = null;
    _disposeFuture = _operation.then((_) async {
      try {
        await _player.stop();
      } catch (e, st) {
        debugPrint('Practice SFX failed to stop during disposal: $e\n$st');
      }
      try {
        await _player.dispose();
      } catch (e, st) {
        debugPrint('Practice SFX failed to dispose: $e\n$st');
      }
    });
    return _disposeFuture!;
  }
}
