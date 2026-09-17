import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/music_tracks.dart';
import '../data/models/music_track.dart';
import 'app_background_music_service.dart';
import 'audio_player_handle.dart';
import 'settings_service.dart';

/// Owns one Practice-music channel for the lifetime of a Practice screen.
class PracticeMusicService {
  PracticeMusicService({
    required SettingsService settings,
    AppBackgroundMusicService? appBackgroundMusic,
    AudioPlayerHandle? player,
    Random? random,
    bool Function(String path)? fileExists,
  }) : _settings = settings,
       _appBackgroundMusic = appBackgroundMusic,
       _player = player ?? AudioplayersHandle(),
       _random = random ?? Random(),
       _fileExists = fileExists {
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      unawaited(_playNextShuffleTrack());
    });
    _lastSoundEnabled = _settings.soundEnabled;
    _lastMusicVolume = _settings.musicVolume;
    _settings.addListener(_onSettingsChanged);
  }

  final SettingsService _settings;
  final AppBackgroundMusicService? _appBackgroundMusic;
  final AudioPlayerHandle _player;
  final Random _random;
  final bool Function(String path)? _fileExists;
  late final StreamSubscription<void> _completeSubscription;

  List<MusicTrack> _tracks = const <MusicTrack>[];
  String? _selectedTrackId;
  String? _currentTrackId;
  Future<void> _operation = Future<void>.value();
  bool _sessionActive = false;
  bool _disposed = false;
  late bool _lastSoundEnabled;
  late double _lastMusicVolume;
  bool _settingsUpdatePending = false;
  bool _settingsUpdateQueued = false;

  @visibleForTesting
  String? get currentTrackId => _currentTrackId;

  @visibleForTesting
  Future<void> get settled => _operation;

  Future<void> start({
    required String? selectedTrackId,
    required Iterable<MusicTrack> customTracks,
  }) {
    if (_disposed) return Future<void>.value();
    _selectedTrackId = selectedTrackId;
    _tracks = availablePracticeTracks(customTracks, fileExists: _fileExists);
    _sessionActive = true;
    return _queue(() async {
      await _appBackgroundMusic?.suspendForPractice(this);
      await _startCurrentMode();
    });
  }

  void _onSettingsChanged() {
    if (_disposed || !_sessionActive) return;
    final soundEnabled = _settings.soundEnabled;
    final musicVolume = _settings.musicVolume;
    if (_lastSoundEnabled == soundEnabled && _lastMusicVolume == musicVolume) {
      return;
    }
    _lastSoundEnabled = soundEnabled;
    _lastMusicVolume = musicVolume;
    _settingsUpdatePending = true;
    if (_settingsUpdateQueued) return;
    _settingsUpdateQueued = true;
    unawaited(_queue(_drainSettingsUpdates));
  }

  Future<void> _drainSettingsUpdates() async {
    try {
      while (_settingsUpdatePending && !_disposed) {
        _settingsUpdatePending = false;
        if (!_sessionActive) return;
        if (!_settings.soundEnabled) {
          await _player.stop();
          _currentTrackId = null;
          continue;
        }
        await _player.setVolume(_settings.musicVolume);
        if (_currentTrackId == null) await _startCurrentMode();
      }
    } finally {
      _settingsUpdateQueued = false;
    }
  }

  Future<void> _startCurrentMode() async {
    if (!_sessionActive || _disposed) return;
    await _player.stop();
    _currentTrackId = null;
    if (!_settings.soundEnabled || _tracks.isEmpty) return;
    await _player.setVolume(_settings.musicVolume);

    final selected = _tracks.where((track) => track.id == _selectedTrackId);
    if (_selectedTrackId != null && selected.isNotEmpty) {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _playTrack(selected.first);
      return;
    }

    // A moved/deleted custom selection degrades to real Shuffle for the whole
    // session, not to one randomly selected song that then stops.
    _selectedTrackId = null;
    await _player.setReleaseMode(ReleaseMode.release);
    await _playNextShuffleTrackNow();
  }

  Future<void> _playNextShuffleTrack() {
    if (_selectedTrackId != null || !_sessionActive || _disposed) {
      return Future<void>.value();
    }
    return _queue(_playNextShuffleTrackNow);
  }

  Future<void> _playNextShuffleTrackNow() async {
    if (!_sessionActive || _disposed || !_settings.soundEnabled) return;
    final track = nextShuffleTrack(
      _tracks,
      previousTrackId: _currentTrackId,
      random: _random,
    );
    await _playTrack(track);
  }

  Future<void> _playTrack(MusicTrack track) async {
    try {
      switch (track.source) {
        case MusicTrackSource.asset:
          await _player.playAsset(track.assetPath!);
        case MusicTrackSource.localFile:
          await _player.playFile(track.filePath!);
      }
      _currentTrackId = track.id;
    } catch (error, stack) {
      debugPrint(
        'Practice music failed to start (${track.id}): $error\n$stack',
      );
      final fallback = musicTrackCatalog.first;
      if (track.id == fallback.id) return;
      try {
        await _player.playAsset(fallback.assetPath!);
        _currentTrackId = fallback.id;
      } catch (fallbackError, fallbackStack) {
        debugPrint(
          'Practice music fallback failed (${fallback.id}): '
          '$fallbackError\n$fallbackStack',
        );
      }
    }
  }

  Future<void> stop() {
    if (_disposed || !_sessionActive) return Future<void>.value();
    _sessionActive = false;
    _currentTrackId = null;
    return _queue(() async {
      try {
        await _player.stop();
      } finally {
        await _appBackgroundMusic?.resumeAfterPractice(this);
      }
    });
  }

  Future<void> _queue(Future<void> Function() action) {
    _operation = _operation.then((_) => action()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Practice music operation failed: $error\n$stack');
    });
    return _operation;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _sessionActive = false;
    _currentTrackId = null;
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    await _completeSubscription.cancel();
    await _operation;
    try {
      await _player.stop();
    } catch (error, stack) {
      debugPrint(
        'Practice music failed to stop during disposal: $error\n$stack',
      );
    }
    try {
      await _appBackgroundMusic?.resumeAfterPractice(this);
    } catch (error, stack) {
      debugPrint(
        'Practice background music failed to resume during disposal: '
        '$error\n$stack',
      );
    }
    try {
      await _player.dispose();
    } catch (error, stack) {
      debugPrint('Practice music failed to dispose: $error\n$stack');
    }
  }
}
