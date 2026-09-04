import 'dart:io';

import 'package:elixr_application/data/models/activity_learning_material.dart';
import 'package:elixr_application/data/repositories/activity_learning_material_repository.dart';
import 'package:elixr_application/features/activity_learning_materials/activity_learning_materials_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _MaterialsRepository implements ActivityLearningMaterialRepository {
  _MaterialsRepository(this.materials);

  final List<ActivityLearningMaterial> materials;

  @override
  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
  }) => throw UnimplementedError();

  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) => throw UnimplementedError();

  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) => throw UnimplementedError();

  @override
  Future<List<ActivityLearningMaterial>> list({
    required String assignmentId,
  }) async => materials;

  @override
  Future<File> openFile(ActivityLearningMaterial material) =>
      throw UnimplementedError();

  @override
  Future<void> remove({
    required String assignmentId,
    required String materialId,
  }) => throw UnimplementedError();

  @override
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  }) => throw UnimplementedError();
}

void main() {
  const material = ActivityLearningMaterial(
    id: 'material-1',
    assignmentId: 'assignment-1',
    type: ActivityLearningMaterialType.pdf,
    displayName: 'Safety Guidelines.pdf',
    sizeBytes: 1468006,
    storagePath: 'server-only-path',
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(FluentApp(home: ScaffoldPage(content: child)));
    await tester.pump();
  }

  testWidgets('teacher manager shows its section and add action', (
    tester,
  ) async {
    await pump(
      tester,
      ActivityLearningMaterialsPanel(
        assignmentId: 'assignment-1',
        repository: _MaterialsRepository(const [material]),
      ),
    );

    expect(find.text('Learning materials'), findsOneWidget);
    expect(find.text('Add material'), findsOneWidget);
    expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
    expect(find.text('PDF · 1.4 MB'), findsOneWidget);
  });

  testWidgets('trainee section stays hidden when no material is accessible', (
    tester,
  ) async {
    await pump(
      tester,
      ActivityLearningMaterialsTraineeSection(
        assignmentId: 'assignment-1',
        repository: _MaterialsRepository(const []),
      ),
    );

    expect(find.text('Learning materials'), findsNothing);
  });

  testWidgets(
    'trainee section presents an accessible material without an attempt action',
    (tester) async {
      await pump(
        tester,
        ActivityLearningMaterialsTraineeSection(
          assignmentId: 'assignment-1',
          repository: _MaterialsRepository(const [material]),
        ),
      );

      expect(find.text('Safety Guidelines.pdf'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.textContaining('Start'), findsNothing);
    },
  );
}
