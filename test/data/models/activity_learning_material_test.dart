import 'package:flutter_test/flutter_test.dart';

import 'package:elixr_application/data/models/activity_learning_material.dart';

void main() {
  test('parses only canonical server file material metadata', () {
    final material = ActivityLearningMaterial.tryFromMap({
      'material_id': 'material-1',
      'assignment_id': 'assignment-1',
      'type': 'pdf',
      'display_name': 'Safety notes',
      'detected_content_type': 'application/pdf',
      'size_bytes': 123,
      'storage_path': 'activity_learning_materials/assignment-1/material-1',
    });

    expect(material, isNotNull);
    expect(material!.storagePath, contains('activity_learning_materials/'));
    expect(material.externalUrl, isNull);
  });

  test('rejects incomplete file records and non-HTTP link records', () {
    expect(
      ActivityLearningMaterial.tryFromMap({
        'material_id': 'material-1',
        'assignment_id': 'assignment-1',
        'type': 'image',
        'display_name': 'Image',
      }),
      isNull,
    );
    expect(
      ActivityLearningMaterial.tryFromMap({
        'material_id': 'material-2',
        'assignment_id': 'assignment-1',
        'type': 'link',
        'display_name': 'Unsafe',
        'external_url': 'javascript:alert(1)',
      }),
      isNull,
    );
  });

  test('parses a short-lived server upload capability only when complete', () {
    expect(
      ActivityMaterialUpload.tryFromMap({
        'upload_id': 'upload-1',
        'material_id': 'material-1',
        'staging_path': 'activity_material_staging/teacher/assignment/upload-1',
        'declared_content_type': 'image/png',
        'expires_at': '2026-09-04T01:00:00.000Z',
      }),
      isNotNull,
    );
    expect(ActivityMaterialUpload.tryFromMap(const {}), isNull);
  });
}
