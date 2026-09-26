import 'package:elixr_application/data/models/custom_movement_save_diagnostics.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase diagnostics retain safe context and redact credentials', () {
    final line = formatCustomMovementSaveDiagnostic(
      stage: CustomMovementSaveStage.referenceImageUpload,
      error: FirebaseException(
        plugin: 'firebase_storage',
        code: 'permission-denied',
        message:
            'Reference upload rejected. Bearer secret-token user@example.com',
      ),
    );

    expect(line, contains('stage=reference_image_upload'));
    expect(line, contains('plugin=firebase_storage'));
    expect(line, contains('code=permission-denied'));
    expect(line, contains('Reference upload rejected.'));
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('user@example.com')));
  });

  test('save Firebase categories map to safe actionable copy', () {
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.firestoreCommit,
        cause: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      ),
      'Firestore denied this change. Your account access or deployed security rules may be out of date.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.firestoreCommit,
        cause: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
      ),
      'Firebase is temporarily unavailable. Check your connection and try again.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.firestoreCommit,
        cause: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unauthenticated',
        ),
      ),
      'Your sign-in has expired. Sign in again, then retry.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.referenceImageUpload,
        cause: FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
        ),
      ),
      'Storage denied the reference image upload. Check your account access and retry.',
    );
  });

  test('delete failures preserve stage and Firebase code in safe diagnostics', () {
    final error = CustomMovementDeleteException(
      stage: CustomMovementDeleteStage.archive,
      cause: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Archive write denied. Bearer secret-token user@example.com',
      ),
      stackTrace: StackTrace.current,
    );

    expect(
      customMovementDeleteFailureMessage(error),
      'Firestore denied this change. Your account access or deployed security rules may be out of date.',
    );
    final line = formatCustomMovementDeleteDiagnostic(error: error);
    expect(line, contains('stage=archive'));
    expect(line, contains('plugin=cloud_firestore'));
    expect(line, contains('code=permission-denied'));
    expect(line, contains('Archive write denied.'));
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('user@example.com')));
    expect(
      customMovementDeleteFailureMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      'Firebase is temporarily unavailable. Check your connection and try again.',
    );
    expect(
      customMovementDeleteFailureMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
      ),
      'Your sign-in has expired. Sign in again, then retry.',
    );
  });

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
