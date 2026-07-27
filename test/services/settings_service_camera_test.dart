import 'dart:convert';
import 'dart:io';

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
    'older settings file without camera_index resolves to Auto-select',
    () async {
      await settingsFile.writeAsString(
        jsonEncode({'camera_mirrored': false, 'dark_mode': false}),
      );

      await service.initialize();

      expect(service.selectedCameraIndex, isNull);
      expect(service.cameraMirrored, isFalse);
      expect(service.darkMode, isFalse);
    },
  );

  test('persists null Auto-select and explicit camera index', () async {
    await service.initialize();
    expect(service.selectedCameraIndex, isNull);

    await service.setSelectedCameraIndex(1);
    expect(service.selectedCameraIndex, 1);

    final reloaded = SettingsService(settingsFile: settingsFile);
    await reloaded.initialize();
    expect(reloaded.selectedCameraIndex, 1);

    await reloaded.setSelectedCameraIndex(null);
    expect(reloaded.selectedCameraIndex, isNull);

    final again = SettingsService(settingsFile: settingsFile);
    await again.initialize();
    expect(again.selectedCameraIndex, isNull);
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
    expect(service.selectedCameraIndex, isNull);

    final bad = SettingsService(settingsFile: settingsFile);
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'camera_index': 'usb',
      }),
    );
    await bad.initialize();
    expect(bad.selectedCameraIndex, isNull);
  });
}
