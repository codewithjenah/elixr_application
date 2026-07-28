import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/data/models/camera_device.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;
  late SettingsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_settings_');
    settingsFile = File('${tempDir.path}/settings.json');
    service = SettingsService(settingsFile: settingsFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'older settings file without camera selection resolves to Auto-select',
    () async {
      await settingsFile.writeAsString(
        jsonEncode({'camera_mirrored': false, 'dark_mode': false}),
      );

      await service.initialize();

      expect(service.selectedCameraDeviceId, isNull);
      expect(service.selectedCameraDisplayName, isNull);
      expect(service.hasPendingLegacyCameraMigration, isFalse);
      expect(service.cameraMirrored, isFalse);
      expect(service.darkMode, isFalse);
    },
  );

  test('persists null Auto-select and explicit device id', () async {
    await service.initialize();
    expect(service.selectedCameraDeviceId, isNull);

    await service.setSelectedCameraDevice(
      'dev-b',
      displayName: 'HIKVISION USB Camera',
    );
    expect(service.selectedCameraDeviceId, 'dev-b');
    expect(service.selectedCameraDisplayName, 'HIKVISION USB Camera');

    final reloaded = SettingsService(settingsFile: settingsFile);
    await reloaded.initialize();
    expect(reloaded.selectedCameraDeviceId, 'dev-b');
    expect(reloaded.selectedCameraDisplayName, 'HIKVISION USB Camera');

    await reloaded.clearCameraSelectionForAutoSelect();
    expect(reloaded.selectedCameraDeviceId, isNull);

    final again = SettingsService(settingsFile: settingsFile);
    await again.initialize();
    expect(again.selectedCameraDeviceId, isNull);
  });

  test('migrates legacy camera_index once to device id', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': 1,
      }),
    );
    await service.initialize();
    expect(service.selectedCameraDeviceId, isNull);
    expect(service.hasPendingLegacyCameraMigration, isTrue);
    expect(service.pendingLegacyCameraIndex, 1);

    final discovered = [
      const CameraDevice(
        deviceId: 'dev-a',
        displayName: 'Integrated Camera',
        runtimeIndex: 0,
        identityStable: true,
      ),
      const CameraDevice(
        deviceId: 'dev-b',
        displayName: 'HIKVISION',
        runtimeIndex: 1,
        identityStable: true,
      ),
    ];

    final migrated = await service.migrateLegacyCameraIndex(discovered);
    expect(migrated, isTrue);
    expect(service.selectedCameraDeviceId, 'dev-b');
    expect(service.selectedCameraDisplayName, 'HIKVISION');
    expect(service.hasPendingLegacyCameraMigration, isFalse);

    final saved =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    expect(saved['camera_device_id'], 'dev-b');
    expect(saved['camera_display_name'], 'HIKVISION');
    expect(saved['camera_index'], isNull);

    // Second migration is a no-op once device id is persisted.
    final again = await service.migrateLegacyCameraIndex(discovered);
    expect(again, isFalse);
  });

  test('legacy migration does not silently pick another device', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': 3,
      }),
    );
    await service.initialize();

    final migrated = await service.migrateLegacyCameraIndex([
      const CameraDevice(
        deviceId: 'dev-a',
        displayName: 'Integrated Camera',
        runtimeIndex: 0,
        identityStable: true,
      ),
    ]);
    expect(migrated, isFalse);
    expect(service.selectedCameraDeviceId, isNull);
    expect(service.hasPendingLegacyCameraMigration, isTrue);
    expect(service.pendingLegacyCameraIndex, 3);
  });

  test('negative or invalid camera_index values fall back to null', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': -1,
      }),
    );
    await service.initialize();
    expect(service.selectedCameraDeviceId, isNull);
    expect(service.hasPendingLegacyCameraMigration, isFalse);

    final bad = SettingsService(settingsFile: settingsFile);
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': 'usb',
      }),
    );
    await bad.initialize();
    expect(bad.selectedCameraDeviceId, isNull);
  });

  test(
    'preserves camera_mirrored and dark_mode across camera migration',
    () async {
      await settingsFile.writeAsString(
        jsonEncode({
          'camera_mirrored': false,
          'dark_mode': false,
          'camera_index': 0,
        }),
      );
      await service.initialize();
      await service.migrateLegacyCameraIndex([
        const CameraDevice(
          deviceId: 'dev-a',
          displayName: 'Integrated Camera',
          runtimeIndex: 0,
          identityStable: true,
        ),
      ]);
      expect(service.cameraMirrored, isFalse);
      expect(service.darkMode, isFalse);
    },
  );
}
