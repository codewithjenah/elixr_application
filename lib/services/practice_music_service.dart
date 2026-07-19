import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Loops practice background music while a session is active.
/// Track: assets/music/practice.mp3
class PracticeMusicService {
  PracticeMusicService() : _player = AudioPlayer();

  static final _track = AssetSource('music/practice.mp3');

  final AudioPlayer _player;
  bool _playing = false;

  Future<void> start() async {
    if (_playing) return;
    try {
      _playing = true;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(_track);
    } catch (e, st) {
      _playing = false;
      debugPrint('Practice music failed to start: $e\n$st');
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _player.stop();
    } catch (e, st) {
      debugPrint('Practice music failed to stop: $e\n$st');
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (e, st) {
      debugPrint('Practice music failed to dispose: $e\n$st');
    }
  }
}
