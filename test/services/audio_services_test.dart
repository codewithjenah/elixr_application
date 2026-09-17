import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:elixr_application/core/constants/music_tracks.dart';
import 'package:elixr_application/data/models/music_track.dart';
import 'package:elixr_application/services/app_background_music_service.dart';
import 'package:elixr_application/services/audio_player_handle.dart';
import 'package:elixr_application/services/practice_music_service.dart';
import 'package:elixr_application/services/notification_audio_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late SettingsService settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_audio_services_');
    settings = SettingsService(
      settingsFile: File('${tempDir.path}/settings.json'),
    );
    await settings.initialize();
  });

  tearDown(() async {
    settings.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'authenticated background music pauses for Practice and stops on logout',
    () async {
      final auth = ValueNotifier<String?>(null);
      final player = _FakeAudioPlayer();
      final service = AppBackgroundMusicService(
        authListenable: auth,
        authenticatedAccountId: () => auth.value,
        settings: settings,
        player: player,
      );
      service.setAuthenticatedAreaVisible(true);
      await service.settled;
      expect(player.playedAssets, isEmpty);

      auth.value = 'trainee-1';
      await service.settled;
      expect(player.playedAssets, ['music/hcc.mp3']);
      expect(player.releaseModes.last, ReleaseMode.loop);
      expect(player.volumes.last, settings.musicVolume);

      final firstOwner = Object();
      final secondOwner = Object();
      await service.suspendForPractice(firstOwner);
      await service.suspendForPractice(secondOwner);
      expect(player.pauseCount, 1);
      await service.resumeAfterPractice(firstOwner);
      expect(player.resumeCount, 0);
      await service.resumeAfterPractice(secondOwner);
      expect(player.resumeCount, 1);

      await settings.setSoundEnabled(false);
      await service.settled;
      expect(player.pauseCount, 2);
      await settings.setSoundEnabled(true);
      await service.settled;
      expect(player.resumeCount, 2);

      auth.value = 'teacher-2';
      await service.settled;
      expect(player.playedAssets, ['music/hcc.mp3', 'music/hcc.mp3']);
      auth.value = null;
      await service.settled;
      expect(service.isAudible, isFalse);
      expect(player.stopCount, greaterThanOrEqualTo(2));

      await service.dispose();
      auth.dispose();
    },
  );

  test(
    'notification sound uses its own volume and respects master mute',
    () async {
      final player = _FakeAudioPlayer();
      final service = NotificationAudioService(
        settings: settings,
        player: player,
      );

      await settings.setMusicVolume(0.2);
      await settings.setNotificationVolume(0.85);
      await service.settled;
      service.playNotification();
      await service.settled;
      expect(player.playedAssets, ['music/notification.mp3']);
      expect(player.volumes.last, 0.85);

      await settings.setMusicVolume(0.1);
      await service.settled;
      expect(player.volumes.last, 0.85);

      await settings.setNotificationVolume(0.55);
      await service.settled;
      expect(player.volumes.last, 0.55);

      await settings.setSoundEnabled(false);
      service.playNotification();
      await service.settled;
      expect(player.playedAssets, hasLength(1));
      expect(player.stopCount, 2);
      await service.dispose();
    },
  );

  test('fixed Practice selection loops only the selected track', () async {
    final player = _FakeAudioPlayer();
    final service = PracticeMusicService(settings: settings, player: player);

    await service.start(
      selectedTrackId: musicTrackCatalog[2].id,
      customTracks: const <MusicTrack>[],
    );
    player.complete();
    await Future<void>.delayed(Duration.zero);
    await service.settled;

    expect(player.releaseModes.last, ReleaseMode.loop);
    expect(player.playedAssets, [musicTrackCatalog[2].assetPath]);
    expect(player.volumes.last, settings.musicVolume);
    await service.dispose();
  });

  test('Shuffle advances without an immediate repeat', () async {
    final player = _FakeAudioPlayer();
    final service = PracticeMusicService(settings: settings, player: player);

    await service.start(
      selectedTrackId: null,
      customTracks: const <MusicTrack>[],
    );
    final first = service.currentTrackId;
    player.complete();
    await Future<void>.delayed(Duration.zero);
    await service.settled;

    expect(service.currentTrackId, isNot(first));
    expect(player.playedAssets, hasLength(2));
    expect(player.releaseModes.last, ReleaseMode.release);
    await service.dispose();
  });

  test('local Practice track uses a filesystem audio source', () async {
    final player = _FakeAudioPlayer();
    final track = MusicTrack.localFile(
      id: 'custom_test',
      displayName: 'Local.mp3',
      filePath: r'C:\Music\Local.mp3',
    );
    final service = PracticeMusicService(
      settings: settings,
      player: player,
      fileExists: (_) => true,
    );

    await service.start(selectedTrackId: track.id, customTracks: [track]);

    expect(player.playedFiles, [track.filePath]);
    expect(player.playedAssets, isEmpty);
    await service.dispose();
  });

  test('missing custom selection recovers to continuing Shuffle', () async {
    final player = _FakeAudioPlayer();
    final missing = MusicTrack.localFile(
      id: 'custom_missing',
      displayName: 'Missing.mp3',
      filePath: r'C:\Music\Missing.mp3',
    );
    final service = PracticeMusicService(
      settings: settings,
      player: player,
      fileExists: (_) => false,
    );

    await service.start(selectedTrackId: missing.id, customTracks: [missing]);
    final first = service.currentTrackId;
    player.complete();
    await Future<void>.delayed(Duration.zero);
    await service.settled;

    expect(service.currentTrackId, isNot(first));
    expect(player.playedAssets, hasLength(2));
    await service.dispose();
  });

  test(
    'Practice stop resumes app music even when its player stop fails',
    () async {
      final auth = ValueNotifier<String?>('trainee-1');
      final backgroundPlayer = _FakeAudioPlayer();
      final background = AppBackgroundMusicService(
        authListenable: auth,
        authenticatedAccountId: () => auth.value,
        settings: settings,
        player: backgroundPlayer,
      );
      background.setAuthenticatedAreaVisible(true);
      await background.settled;

      final practicePlayer = _FakeAudioPlayer();
      final service = PracticeMusicService(
        settings: settings,
        appBackgroundMusic: background,
        player: practicePlayer,
      );
      await service.start(
        selectedTrackId: musicTrackCatalog.first.id,
        customTracks: const <MusicTrack>[],
      );
      practicePlayer.throwOnStop = true;

      await service.stop();
      await background.settled;

      expect(background.practiceLeaseCount, 0);
      expect(backgroundPlayer.resumeCount, 1);
      practicePlayer.throwOnStop = false;
      await service.dispose();
      await background.dispose();
      auth.dispose();
    },
  );

  test('appearance changes do not enqueue audio work', () async {
    final auth = ValueNotifier<String?>('trainee-1');
    final backgroundPlayer = _FakeAudioPlayer();
    final background = AppBackgroundMusicService(
      authListenable: auth,
      authenticatedAccountId: () => auth.value,
      settings: settings,
      player: backgroundPlayer,
    );
    background.setAuthenticatedAreaVisible(true);
    await background.settled;

    final notificationPlayer = _FakeAudioPlayer();
    final notifications = NotificationAudioService(
      settings: settings,
      player: notificationPlayer,
    );
    final practicePlayer = _FakeAudioPlayer();
    final practice = PracticeMusicService(
      settings: settings,
      appBackgroundMusic: background,
      player: practicePlayer,
    );
    await practice.start(
      selectedTrackId: musicTrackCatalog.first.id,
      customTracks: const <MusicTrack>[],
    );
    await background.settled;

    final backgroundVolumes = backgroundPlayer.volumes.length;
    final backgroundStops = backgroundPlayer.stopCount;
    final backgroundPauses = backgroundPlayer.pauseCount;
    final backgroundResumes = backgroundPlayer.resumeCount;
    final notificationVolumes = notificationPlayer.volumes.length;
    final notificationStops = notificationPlayer.stopCount;
    final practiceVolumes = practicePlayer.volumes.length;
    final practiceStops = practicePlayer.stopCount;

    await settings.setDarkMode(false);
    await settings.setTextScale(1.15);
    await settings.setHighContrast(true);
    await background.settled;
    await notifications.settled;
    await practice.settled;

    expect(backgroundPlayer.volumes.length, backgroundVolumes);
    expect(backgroundPlayer.stopCount, backgroundStops);
    expect(backgroundPlayer.pauseCount, backgroundPauses);
    expect(backgroundPlayer.resumeCount, backgroundResumes);
    expect(notificationPlayer.volumes.length, notificationVolumes);
    expect(notificationPlayer.stopCount, notificationStops);
    expect(practicePlayer.volumes.length, practiceVolumes);
    expect(practicePlayer.stopCount, practiceStops);

    await settings.setMusicVolume(0.25);
    await background.settled;
    await notifications.settled;
    await practice.settled;
    // Background music is suspended while Practice owns the audio lease.
    expect(backgroundPlayer.volumes.length, backgroundVolumes);
    expect(practicePlayer.volumes.last, 0.25);
    expect(notificationPlayer.volumes.length, notificationVolumes);

    await settings.setNotificationVolume(0.85);
    await background.settled;
    await notifications.settled;
    await practice.settled;
    expect(notificationPlayer.volumes.last, 0.85);
    expect(backgroundPlayer.volumes.length, backgroundVolumes);
    expect(practicePlayer.volumes.last, 0.25);

    await practice.dispose();
    await notifications.dispose();
    await background.dispose();
    auth.dispose();
  });
}

class _FakeAudioPlayer implements AudioPlayerHandle {
  final _completions = StreamController<void>.broadcast();
  final playedAssets = <String>[];
  final playedFiles = <String>[];
  final releaseModes = <ReleaseMode>[];
  final volumes = <double>[];
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  bool throwOnStop = false;

  void complete() => _completions.add(null);

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> dispose() => _completions.close();

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> playAsset(String assetPath) async => playedAssets.add(assetPath);

  @override
  Future<void> playFile(String filePath) async => playedFiles.add(filePath);

  @override
  Future<void> resume() async => resumeCount++;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async => releaseModes.add(mode);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> stop() async {
    stopCount++;
    if (throwOnStop) throw StateError('stop failed');
  }
}
