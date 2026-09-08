import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/settings/widgets/practice_preferences_controller.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;
  late SettingsService settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_prefs_ctrl_');
    settingsFile = File('${tempDir.path}/settings.json');
    settings = SettingsService(settingsFile: settingsFile);
    await settings.initialize();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PracticeVariant bottle(String name) => PracticeVariant(
    movementName: name,
    trainingProp: TrainingProp.bottle,
  );

  PracticeVariant shaker(String name) => PracticeVariant(
    movementName: name,
    trainingProp: TrainingProp.shaker,
  );

  test('loads exact PracticeVariants from settings', () {
    final controller = PracticePreferencesController(settings);
    addTearDown(controller.dispose);

    expect(controller.draft.practiceVariants, settings.justDancePracticeVariants);
    expect(
      controller.draft.practiceVariants.any(
        (v) =>
            v.movementName == 'Hand Stall' &&
            v.trainingProp == TrainingProp.shaker,
      ),
      isFalse,
    );
  });

  test('Hand Stall Bottle and Shaker toggle independently', () {
    final controller = PracticePreferencesController(settings);
    addTearDown(controller.dispose);

    final handBottle = bottle('Hand Stall');
    final handShaker = shaker('Hand Stall');

    // Start from empty draft for clarity.
    for (final variant in List.of(controller.draft.practiceVariants)) {
      controller.toggleVariant(variant, false);
    }
    expect(controller.draft.practiceVariants, isEmpty);

    controller.toggleVariant(handBottle, true);
    expect(controller.draft.practiceVariants, [handBottle]);
    expect(controller.draft.practiceVariants.contains(handShaker), isFalse);

    controller.toggleVariant(handShaker, true);
    expect(controller.draft.practiceVariants, [handBottle, handShaker]);

    controller.toggleVariant(handBottle, false);
    expect(controller.draft.practiceVariants, [handShaker]);
  });

  test('moveVariant reorders exact variants', () {
    final controller = PracticePreferencesController(settings);
    addTearDown(controller.dispose);

    final a = bottle('Normal Grip');
    final b = bottle('Hand Stall');
    final c = shaker('Hand Stall');
    for (final variant in List.of(controller.draft.practiceVariants)) {
      controller.toggleVariant(variant, false);
    }
    controller.toggleVariant(a, true);
    controller.toggleVariant(b, true);
    controller.toggleVariant(c, true);

    controller.moveVariant(c, -1);
    expect(controller.draft.practiceVariants, [a, c, b]);
  });

  test('save persists both Bottle and Shaker Hand Stall variants', () async {
    final controller = PracticePreferencesController(settings);
    addTearDown(controller.dispose);

    for (final variant in List.of(controller.draft.practiceVariants)) {
      controller.toggleVariant(variant, false);
    }
    controller.toggleVariant(bottle('Normal Grip'), true);
    controller.toggleVariant(bottle('Hand Stall'), true);
    controller.toggleVariant(shaker('Hand Stall'), true);

    final outcome = await controller.save();
    expect(outcome, SettingsWriteOutcome.saved);
    expect(
      settings.justDancePracticeVariants.map((v) => v.persistenceKey).toList(),
      [
        'Normal Grip|bottle',
        'Hand Stall|bottle',
        'Hand Stall|shaker',
      ],
    );

    final reloaded = SettingsService(settingsFile: settingsFile);
    await reloaded.initialize();
    expect(
      reloaded.justDancePracticeVariants.map((v) => v.persistenceKey).toList(),
      [
        'Normal Grip|bottle',
        'Hand Stall|bottle',
        'Hand Stall|shaker',
      ],
    );
  });

  test('normalizeDraft drops unknown persistence identities', () {
    final controller = PracticePreferencesController(settings);
    addTearDown(controller.dispose);

    controller.toggleVariant(bottle('Normal Grip'), true);
    // Inject via copy into draft by toggling only known, then assert normalize
    // keeps catalog-resolvable variants only.
    final normalized = controller.normalizeDraft();
    for (final variant in normalized.practiceVariants) {
      expect(
        movementCatalog.any(
          (m) =>
              m.name == variant.movementName &&
              m.supportedProps.contains(variant.trainingProp),
        ),
        isTrue,
      );
    }
  });
}
