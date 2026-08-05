import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;
  late SettingsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_just_dance_');
    settingsFile = File('${tempDir.path}/settings.json');
    service = SettingsService(settingsFile: settingsFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'defaults to the full movement catalog and a 25s interval when absent',
    () async {
      await service.initialize();
      expect(
        service.justDanceMovementNames,
        movementCatalog.map((m) => m.name).toList(),
      );
      expect(service.justDanceIntervalSeconds, 25);
      expect(service.selectedMusicTrackId, isNull);
    },
  );

  test('persists a custom setlist, interval, and music selection', () async {
    await service.initialize();
    final custom = [movementCatalog[2].name, movementCatalog[0].name];

    await service.setJustDanceSetlist(custom);
    await service.setJustDanceIntervalSeconds(40);
    await service.setSelectedMusicTrackId('practice_classic');

    expect(service.justDanceMovementNames, custom);
    expect(service.justDanceIntervalSeconds, 40);
    expect(service.selectedMusicTrackId, 'practice_classic');

    final reloaded = SettingsService(settingsFile: settingsFile);
    await reloaded.initialize();
    expect(reloaded.justDanceMovementNames, custom);
    expect(reloaded.justDanceIntervalSeconds, 40);
    expect(reloaded.selectedMusicTrackId, 'practice_classic');
  });

  test('setSelectedMusicTrackId(null) restores shuffle', () async {
    await service.initialize();
    await service.setSelectedMusicTrackId('practice_classic');
    expect(service.selectedMusicTrackId, 'practice_classic');

    await service.setSelectedMusicTrackId(null);
    expect(service.selectedMusicTrackId, isNull);
  });

  test('setJustDanceSetlist throws when the list is empty', () async {
    await service.initialize();

    expect(() => service.setJustDanceSetlist(const []), throwsArgumentError);
  });

  test(
    'drops persisted movement names no longer in the catalog on load',
    () async {
      await settingsFile.writeAsString(
        jsonEncode({
          'camera_mirrored': true,
          'dark_mode': true,
          'just_dance_movement_names': [
            movementCatalog.first.name,
            'Retired Legacy Movement',
          ],
          'just_dance_interval_seconds': 15,
        }),
      );

      await service.initialize();

      expect(service.justDanceMovementNames, [movementCatalog.first.name]);
      expect(service.justDanceIntervalSeconds, 15);
    },
  );

  test('falls back to the full catalog when nothing valid remains', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'camera_mirrored': true,
        'dark_mode': true,
        'just_dance_movement_names': ['Retired Legacy Movement'],
      }),
    );

    await service.initialize();

    expect(
      service.justDanceMovementNames,
      movementCatalog.map((m) => m.name).toList(),
    );
  });
}
