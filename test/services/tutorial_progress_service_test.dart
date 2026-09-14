import 'dart:io';

import 'package:elixr_application/core/progression/matrix_test_access.dart';
import 'package:elixr_application/core/progression/official_supported_props.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'matrix account completes only official variants without persisting',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'elixr_matrix_tutorial_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}progress.json',
      );
      final service = TutorialProgressService(
        file: file,
        matrixTestAccessPolicy: const MatrixTestAccessPolicy(
          configuredUid: 'matrix-uid',
        ),
      );

      await service.setUser('matrix-uid');

      for (final variant in officialSupportedPracticeVariants()) {
        expect(
          service.hasCompletedLesson(
            variant.movementName,
            variant.trainingProp,
          ),
          isTrue,
          reason: variant.persistenceKey,
        );
      }
      expect(
        service.hasCompletedLesson('Unknown Movement', TrainingProp.bottle),
        isFalse,
      );
      expect(
        service.hasCompletedLesson('Normal Grip', TrainingProp.shaker),
        isFalse,
      );
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'ordinary accounts retain persisted tutorial completion behavior',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'elixr_matrix_tutorial_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}progress.json',
      );
      final service = TutorialProgressService(
        file: file,
        matrixTestAccessPolicy: const MatrixTestAccessPolicy(
          configuredUid: 'matrix-uid',
        ),
      );

      await service.setUser('ordinary-uid');
      expect(
        service.hasCompletedLesson('Normal Grip', TrainingProp.bottle),
        isFalse,
      );
      await service.completeLesson('Normal Grip', TrainingProp.bottle);
      expect(
        service.hasCompletedLesson('Normal Grip', TrainingProp.bottle),
        isTrue,
      );
    },
  );
}
