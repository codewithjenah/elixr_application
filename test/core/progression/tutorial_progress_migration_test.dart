import 'dart:io';

import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_tutorial_');
    file = File('${tempDir.path}${Platform.pathSeparator}tutorial_progress.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<TutorialProgressService> loadWithLegacy(
    List<String> completedLessons,
  ) async {
    await file.writeAsString(
      '{"user-a":{"onboarding_version":2,"completed_lessons":${_jsonList(completedLessons)},'
      '"first_camera_setup_complete":false,"first_session_guidance_complete":false,'
      '"dismissed_tips":[]}}',
    );
    final service = TutorialProgressService(file: file);
    await service.setUser('user-a');
    return service;
  }

  test('legacy Normal Grip maps to Bottle only', () async {
    final service = await loadWithLegacy(['Normal Grip']);
    expect(service.hasCompletedLesson('Normal Grip', TrainingProp.bottle), isTrue);
    expect(
      service.hasCompletedLesson('Normal Grip', TrainingProp.shaker),
      isFalse,
    );
  });

  test('legacy Hand Stall maps to Bottle only, not Shaker', () async {
    final service = await loadWithLegacy(['Hand Stall']);
    expect(service.hasCompletedLesson('Hand Stall', TrainingProp.bottle), isTrue);
    expect(
      service.hasCompletedLesson('Hand Stall', TrainingProp.shaker),
      isFalse,
    );
  });

  test('legacy Medium stalls do not complete Shaker', () async {
    final service = await loadWithLegacy([
      'One Finger Stall',
      'Forearm Stall',
      'Elbow Stall',
    ]);
    for (final name in [
      'One Finger Stall',
      'Forearm Stall',
      'Elbow Stall',
    ]) {
      expect(service.hasCompletedLesson(name, TrainingProp.bottle), isTrue);
      expect(service.hasCompletedLesson(name, TrainingProp.shaker), isFalse);
    }
  });

  test('legacy Bottle in a tin maps to combined prop', () async {
    final service = await loadWithLegacy(['Bottle in a tin']);
    expect(
      service.hasCompletedLesson(
        'Bottle in a tin',
        TrainingProp.bottleAndShaker,
      ),
      isTrue,
    );
  });

  test('migration is idempotent across setUser', () async {
    final service = await loadWithLegacy(['Hand Stall']);
    await service.setUser('user-a');
    expect(service.hasCompletedLesson('Hand Stall', TrainingProp.bottle), isTrue);
    expect(
      service.hasCompletedLesson('Hand Stall', TrainingProp.shaker),
      isFalse,
    );
    final raw = await file.readAsString();
    expect('Hand Stall|bottle'.allMatches(raw).length, 1);
    expect(raw.contains('Hand Stall|shaker'), isFalse);
  });

  test('new completion writes exact variant key', () async {
    final service = TutorialProgressService(file: file);
    await service.setUser('user-a');
    await service.completeLesson('Hand Stall', TrainingProp.shaker);
    expect(
      service.hasCompletedLesson('Hand Stall', TrainingProp.shaker),
      isTrue,
    );
    expect(
      service.hasCompletedLesson('Hand Stall', TrainingProp.bottle),
      isFalse,
    );
    final raw = await file.readAsString();
    expect(raw.contains('Hand Stall|shaker'), isTrue);
    expect(raw.contains('"Hand Stall"'), isFalse);
  });
}

String _jsonList(List<String> values) =>
    '[${values.map((v) => '"$v"').join(',')}]';
