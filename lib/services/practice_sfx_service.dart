import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One-shot practice sound effects (countdown, victory congrats).
class PracticeSfxService {
  PracticeSfxService() : _player = AudioPlayer();

  static final _countdown = AssetSource('music/countdown.mp3');
  static final _congrats = AssetSource('music/congrats.mp3');

  /// Leading silence before the first audible "3" beat in countdown.mp3.
  static const countdownLeadIn = Duration(milliseconds: 520);

  final AudioPlayer _player;
  bool _disposed = false;
  bool _preloaded = false;

  /// Warm the countdown source so Start → first beat is not delayed by decode.
  Future<void> preload() async {
    if (_disposed || _preloaded) return;
    try {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setSource(_countdown);
      _preloaded = true;
    } catch (e, st) {
      debugPrint('Practice SFX failed to preload: $e\n$st');
    }
  }

  Future<void> playCountdown() async {
    if (_disposed) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      // Use play() (not setSource+resume) so switching from congrats is reliable
      // on Windows after Try Again.
      await _player.play(_countdown, position: countdownLeadIn);
      _preloaded = true;
    } catch (e, st) {
      debugPrint('Practice SFX failed to play countdown: $e\n$st');
    }
  }

  Future<void> playCongrats() async {
    if (_disposed) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.play(_congrats);
      _preloaded = false;
    } catch (e, st) {
      debugPrint('Practice SFX failed to play congrats: $e\n$st');
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
