import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'audio_player_handle.dart';
import 'settings_service.dart';

abstract interface class NotificationSoundPlayer {
  void playNotification();
}

class NotificationAudioScope extends InheritedWidget {
  const NotificationAudioScope({
    super.key,
    required this.player,
    required super.child,
  });

  final NotificationSoundPlayer player;

  static NotificationSoundPlayer? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NotificationAudioScope>()?.player;

  @override
  bool updateShouldNotify(NotificationAudioScope oldWidget) =>
      !identical(player, oldWidget.player);
}

/// Reuses one player for all one-shot toast and incoming-event sounds.
class NotificationAudioService implements NotificationSoundPlayer {
  NotificationAudioService({
    required SettingsService settings,
    AudioPlayerHandle? player,
  }) : _settings = settings,
       _player = player ?? AudioplayersHandle() {
    _lastSoundEnabled = _settings.soundEnabled;
    _lastNotificationVolume = _settings.notificationVolume;
    _settings.addListener(_onSettingsChanged);
  }

  static const _assetPath = 'music/notification.mp3';

  final SettingsService _settings;
  final AudioPlayerHandle _player;
  Future<void> _operation = Future<void>.value();
  bool _disposed = false;
  late bool _lastSoundEnabled;
  late double _lastNotificationVolume;
  bool _settingsUpdatePending = false;
  bool _settingsUpdateQueued = false;

  @visibleForTesting
  Future<void> get settled => _operation;

  @override
  void playNotification() {
    if (_disposed || !_settings.soundEnabled) return;
    _enqueue(() async {
      if (_disposed || !_settings.soundEnabled) return;
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(_settings.notificationVolume);
      await _player.playAsset(_assetPath);
    });
  }

  void _onSettingsChanged() {
    final soundEnabled = _settings.soundEnabled;
    final notificationVolume = _settings.notificationVolume;
    if (_lastSoundEnabled == soundEnabled &&
        _lastNotificationVolume == notificationVolume) {
      return;
    }
    _lastSoundEnabled = soundEnabled;
    _lastNotificationVolume = notificationVolume;
    _settingsUpdatePending = true;
    if (_settingsUpdateQueued) return;
    _settingsUpdateQueued = true;
    _enqueue(_drainSettingsUpdates);
  }

  Future<void> _drainSettingsUpdates() async {
    try {
      while (_settingsUpdatePending && !_disposed) {
        _settingsUpdatePending = false;
        if (!_settings.soundEnabled) {
          await _player.stop();
        } else {
          await _player.setVolume(_settings.notificationVolume);
        }
      }
    } finally {
      _settingsUpdateQueued = false;
    }
  }

  void _enqueue(Future<void> Function() action) {
    if (_disposed) return;
    _operation = _operation.then((_) => action()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Notification audio failed: $error\n$stack');
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    await _operation;
    try {
      await _player.stop();
      await _player.dispose();
    } catch (error, stack) {
      debugPrint('Notification audio disposal failed: $error\n$stack');
    }
  }
}
