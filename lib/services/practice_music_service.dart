import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/music_tracks.dart';
import '../data/models/music_track.dart';

/// Loops a selected practice background track while a session is active.
class PracticeMusicService {
  PracticeMusicService() : _player = AudioPlayer();

  final AudioPlayer _player;
  bool _playing = false;

  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } catch (e, st) {
      debugPrint('Practice music failed to set volume: $e\n$st');
    }
  }

  Future<void> start(MusicTrack track) async {
    if (_playing) return;
    _playing = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(track.assetPath));
    } catch (e, st) {
      debugPrint('Practice music failed to start (${track.id}): $e\n$st');
      final fallback = musicTrackCatalog.first;
      if (fallback.id == track.id) {
        _playing = false;
        return;
      }
      try {
        await _player.play(AssetSource(fallback.assetPath));
      } catch (fallbackError, fallbackSt) {
        _playing = false;
        debugPrint(
          'Practice music fallback failed (${fallback.id}): '
          '$fallbackError\n$fallbackSt',
        );
      }
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
