import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/camera_device.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;
  late int writeCount;
  late int notifyCount;
  Future<void> Function(File file, String contents)? writeOverride;

  SettingsService buildService() {
    final service = SettingsService(
      settingsFile: settingsFile,
      writeSettings: (file, contents) async {
        writeCount++;
        final override = writeOverride;
        if (override != null) {
          await override(file, contents);
        } else {
          await file.writeAsString(contents);
        }
      },
    );
    service.addListener(() => notifyCount++);
    return service;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_persist_');
    settingsFile = File('${tempDir.path}/settings.json');
    writeCount = 0;
    notifyCount = 0;
    writeOverride = null;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('batch update performs one write and one notification', () async {
    final service = buildService();
    await service.initialize();
    writeCount = 0;
    notifyCount = 0;

    final custom = [movementCatalog[1].name, movementCatalog[0].name];
    final outcome = await service.updateLivePracticePreferences(
      movementNames: custom,
      intervalSeconds: 40,
      musicTrackId: 'practice_classic',
    );

    expect(outcome, SettingsWriteOutcome.saved);
    expect(writeCount, 1);
    expect(notifyCount, 1);
    expect(service.justDanceMovementNames, custom);
    expect(service.justDanceIntervalSeconds, 40);
    expect(service.selectedMusicTrackId, 'practice_classic');
  });

  test('unchanged values perform no write and no notification', () async {
    final service = buildService();
    await service.initialize();
    writeCount = 0;
    notifyCount = 0;

    final outcome = await service.updateLivePracticePreferences(
      movementNames: service.justDanceMovementNames,
      intervalSeconds: service.justDanceIntervalSeconds,
      musicTrackId: service.selectedMusicTrackId,
    );

    expect(outcome, SettingsWriteOutcome.unchanged);
    expect(writeCount, 0);
    expect(notifyCount, 0);
  });

  test(
    'forced write failure returns writeFailed and leaves memory unchanged',
    () async {
      final service = buildService();
      await service.initialize();
      final beforeNames = service.justDanceMovementNames;
      final beforeInterval = service.justDanceIntervalSeconds;
      final beforeTrack = service.selectedMusicTrackId;
      writeCount = 0;
      notifyCount = 0;

      writeOverride = (file, contents) async {
        throw const FileSystemException('simulated write failure');
      };

      final outcome = await service.updateLivePracticePreferences(
        movementNames: [movementCatalog.first.name],
        intervalSeconds: 15,
        musicTrackId: 'practice_classic',
      );

      expect(outcome, SettingsWriteOutcome.writeFailed);
      expect(writeCount, 1);
      expect(notifyCount, 0);
      expect(service.justDanceMovementNames, beforeNames);
      expect(service.justDanceIntervalSeconds, beforeInterval);
      expect(service.selectedMusicTrackId, beforeTrack);
    },
  );

  test('dark mode write failure leaves in-memory theme unchanged', () async {
    final service = buildService();
    await service.initialize();
    expect(service.darkMode, isTrue);
    writeOverride = (file, contents) async {
      throw const FileSystemException('simulated write failure');
    };
    notifyCount = 0;

    final outcome = await service.setDarkMode(false);

    expect(outcome, SettingsWriteOutcome.writeFailed);
    expect(service.darkMode, isTrue);
    expect(notifyCount, 0);
  });

  test('sound defaults are enabled with volume 0.7', () async {
    final service = buildService();
    await service.initialize();

    expect(service.soundEnabled, isTrue);
    expect(service.musicVolume, 0.7);
  });

  test('sound enabled and music volume persist across reload', () async {
    final service = buildService();
    await service.initialize();

    expect(await service.setSoundEnabled(false), SettingsWriteOutcome.saved);
    expect(await service.setMusicVolume(0.35), SettingsWriteOutcome.saved);
    expect(service.soundEnabled, isFalse);
    expect(service.musicVolume, 0.35);

    final reloaded = buildService();
    await reloaded.initialize();
    expect(reloaded.soundEnabled, isFalse);
    expect(reloaded.musicVolume, 0.35);

    final data =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    expect(data['sound_enabled'], isFalse);
    expect(data['music_volume'], 0.35);
  });

  test('setSoundEnabled unchanged values skip write', () async {
    final service = buildService();
    await service.initialize();
    writeCount = 0;
    notifyCount = 0;

    final outcome = await service.setSoundEnabled(true);

    expect(outcome, SettingsWriteOutcome.unchanged);
    expect(writeCount, 0);
    expect(notifyCount, 0);
  });

  test('setMusicVolume unchanged values skip write', () async {
    final service = buildService();
    await service.initialize();
    writeCount = 0;
    notifyCount = 0;

    final outcome = await service.setMusicVolume(0.7);

    expect(outcome, SettingsWriteOutcome.unchanged);
    expect(writeCount, 0);
    expect(notifyCount, 0);
  });

  test('setMusicVolume clamps to the 0.0–1.0 range', () async {
    final service = buildService();
    await service.initialize();

    expect(await service.setMusicVolume(-0.2), SettingsWriteOutcome.saved);
    expect(service.musicVolume, 0.0);
    expect(await service.setMusicVolume(1.5), SettingsWriteOutcome.saved);
    expect(service.musicVolume, 1.0);
  });

  test('sound write failure leaves in-memory values unchanged', () async {
    final service = buildService();
    await service.initialize();
    expect(service.soundEnabled, isTrue);
    expect(service.musicVolume, 0.7);
    writeOverride = (file, contents) async {
      throw const FileSystemException('simulated write failure');
    };
    notifyCount = 0;

    expect(
      await service.setSoundEnabled(false),
      SettingsWriteOutcome.writeFailed,
    );
    expect(await service.setMusicVolume(0.2), SettingsWriteOutcome.writeFailed);
    expect(service.soundEnabled, isTrue);
    expect(service.musicVolume, 0.7);
    expect(notifyCount, 0);
  });

  test(
    'accessibility defaults are default text scale and contrast off',
    () async {
      final service = buildService();
      await service.initialize();

      expect(service.textScale, 1.0);
      expect(service.highContrast, isFalse);
    },
  );

  test('text scale and high contrast persist across reload', () async {
    final service = buildService();
    await service.initialize();

    expect(await service.setTextScale(1.15), SettingsWriteOutcome.saved);
    expect(await service.setHighContrast(true), SettingsWriteOutcome.saved);
    expect(service.textScale, 1.15);
    expect(service.highContrast, isTrue);

    final reloaded = buildService();
    await reloaded.initialize();
    expect(reloaded.textScale, 1.15);
    expect(reloaded.highContrast, isTrue);

    final data =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    expect(data['text_scale'], 1.15);
    expect(data['high_contrast'], isTrue);
  });

  test('setTextScale unchanged values skip write', () async {
    final service = buildService();
    await service.initialize();
    writeCount = 0;
    notifyCount = 0;

    final outcome = await service.setTextScale(1.0);

    expect(outcome, SettingsWriteOutcome.unchanged);
    expect(writeCount, 0);
    expect(notifyCount, 0);
  });

  test('setTextScale rejects unsupported values', () {
    final service = buildService();
    expect(() => service.setTextScale(1.2), throwsArgumentError);
  });

  test(
    'high contrast write failure leaves in-memory value unchanged',
    () async {
      final service = buildService();
      await service.initialize();
      expect(service.highContrast, isFalse);
      writeOverride = (file, contents) async {
        throw const FileSystemException('simulated write failure');
      };
      notifyCount = 0;

      final outcome = await service.setHighContrast(true);

      expect(outcome, SettingsWriteOutcome.writeFailed);
      expect(service.highContrast, isFalse);
      expect(notifyCount, 0);
    },
  );

  test('extra large text scale persists and round-trips', () async {
    final service = buildService();
    await service.initialize();

    expect(await service.setTextScale(1.3), SettingsWriteOutcome.saved);
    expect(service.textScale, 1.3);

    final reloaded = buildService();
    await reloaded.initialize();
    expect(reloaded.textScale, 1.3);
  });

  test('legacy camera migration write failure retains legacy index', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': 1,
      }),
    );
    final service = buildService();
    await service.initialize();
    expect(service.hasPendingLegacyCameraMigration, isTrue);

    writeOverride = (file, contents) async {
      throw const FileSystemException('simulated write failure');
    };

    final migrated = await service.migrateLegacyCameraIndex(const [
      CameraDevice(
        deviceId: 'dev-a',
        displayName: 'Integrated Camera',
        runtimeIndex: 0,
        identityStable: true,
      ),
      CameraDevice(
        deviceId: 'dev-b',
        displayName: 'HIKVISION',
        runtimeIndex: 1,
        identityStable: true,
      ),
    ]);

    expect(migrated, isFalse);
    expect(service.selectedCameraDeviceId, isNull);
    expect(service.hasPendingLegacyCameraMigration, isTrue);
    expect(service.pendingLegacyCameraIndex, 1);
  });

  test('empty setlist after filtering throws ArgumentError', () {
    final service = buildService();
    expect(
      () => service.updateLivePracticePreferences(
        movementNames: const ['Retired Legacy Movement'],
        intervalSeconds: 25,
        musicTrackId: null,
      ),
      throwsArgumentError,
    );
  });

  test('non-positive interval throws ArgumentError', () {
    final service = buildService();
    expect(
      () => service.updateLivePracticePreferences(
        movementNames: [movementCatalog.first.name],
        intervalSeconds: 0,
        musicTrackId: null,
      ),
      throwsArgumentError,
    );
  });
}
