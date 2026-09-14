import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_player_handle.dart';
import 'settings_service.dart';

/// Owns ELIXR's fixed authenticated background-music channel.
class AppBackgroundMusicService {
  AppBackgroundMusicService({
    required Listenable authListenable,
    required String? Function() authenticatedAccountId,
    required SettingsService settings,
    AudioPlayerHandle? player,
  }) : _authListenable = authListenable,
       _authenticatedAccountId = authenticatedAccountId,
       _settings = settings,
       _player = player ?? AudioplayersHandle() {
    _authListenable.addListener(_scheduleReconcile);
    _settings.addListener(_scheduleReconcile);
  }

  static const _assetPath = 'music/hcc.mp3';

  final Listenable _authListenable;
  final String? Function() _authenticatedAccountId;
  final SettingsService _settings;
  final AudioPlayerHandle _player;
  final Set<Object> _practiceOwners = <Object>{};

  Future<void> _operation = Future<void>.value();
  String? _loadedAccountId;
  bool _authenticatedAreaVisible = false;
  bool _sourceLoaded = false;
  bool _audible = false;
  bool _disposed = false;

  @visibleForTesting
  bool get isAudible => _audible;

  @visibleForTesting
  int get practiceLeaseCount => _practiceOwners.length;

  @visibleForTesting
  Future<void> get settled => _operation;

  void setAuthenticatedAreaVisible(bool visible) {
    if (_authenticatedAreaVisible == visible || _disposed) return;
    _authenticatedAreaVisible = visible;
    _enqueueReconcile();
  }

  Future<void> suspendForPractice(Object owner) {
    if (_disposed || !_practiceOwners.add(owner)) return _operation;
    return _enqueueReconcile();
  }

  Future<void> resumeAfterPractice(Object owner) {
    if (_disposed || !_practiceOwners.remove(owner)) return _operation;
    return _enqueueReconcile();
  }

  void _scheduleReconcile() {
    _enqueueReconcile();
  }

  Future<void> _enqueueReconcile() {
    if (_disposed) return _operation;
    _operation = _operation.then((_) => _reconcile()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('App background music operation failed: $error\n$stack');
    });
    return _operation;
  }

  Future<void> _reconcile() async {
    if (_disposed) return;
    final accountId = _authenticatedAreaVisible
        ? _authenticatedAccountId()
        : null;

    if (_loadedAccountId != accountId) {
      if (_sourceLoaded) await _player.stop();
      _loadedAccountId = accountId;
      _sourceLoaded = false;
      _audible = false;
    }

    final shouldPlay =
        accountId != null && _settings.soundEnabled && _practiceOwners.isEmpty;
    if (!shouldPlay) {
      if (_audible) {
        await _player.pause();
        _audible = false;
      }
      return;
    }

    await _player.setVolume(_settings.musicVolume);
    if (_sourceLoaded) {
      if (!_audible) await _player.resume();
    } else {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.playAsset(_assetPath);
      _sourceLoaded = true;
    }
    _audible = true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _authListenable.removeListener(_scheduleReconcile);
    _settings.removeListener(_scheduleReconcile);
    await _operation;
    try {
      await _player.stop();
      await _player.dispose();
    } catch (error, stack) {
      debugPrint('App background music disposal failed: $error\n$stack');
    }
  }
}
