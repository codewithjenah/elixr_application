import 'package:elixr_application/data/models/custom_movement_save_diagnostics.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Firebase diagnostics retain plugin and code, not the error message',
    () {
      final line = formatCustomMovementSaveDiagnostic(
        stage: CustomMovementSaveStage.referenceImageUpload,
        error: FirebaseException(
          plugin: 'firebase_storage',
          code: 'permission-denied',
          message: 'Bearer secret-token user@example.com',
        ),
      );

      expect(line, contains('stage=reference_image_upload'));
      expect(line, contains('plugin=firebase_storage'));
      expect(line, contains('code=permission-denied'));
      expect(line, isNot(contains('secret-token')));
      expect(line, isNot(contains('user@example.com')));
    },
  );

  test('stack diagnostics redact credentials and local file paths', () {
    const stack =
        'at save (C:\\Users\\Jiro\\private.dart:42) '
        'Bearer abc123 token=secret-token apiKey=secret-key '
        '/Users/Jiro/private.dart user@example.com';

    final sanitized = sanitizeCustomMovementDiagnosticText(stack);

    expect(sanitized, contains('[redacted-path]'));
    expect(sanitized, contains('Bearer [redacted]'));
    expect(sanitized, contains('token=[redacted]'));
    expect(sanitized, contains('apiKey=[redacted]'));
    expect(sanitized, contains('[redacted-email]'));
    expect(sanitized, isNot(contains('C:\\Users\\Jiro')));
    expect(sanitized, isNot(contains('/Users/Jiro')));
    expect(sanitized, isNot(contains('secret-token')));
    expect(sanitized, isNot(contains('secret-key')));
  });
}
