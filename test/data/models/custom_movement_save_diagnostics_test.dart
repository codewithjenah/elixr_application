import 'dart:io';
import 'package:elixr_application/data/models/custom_movement_save_diagnostics.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Backend diagnostics retain safe context and redact credentials', () {
    final line = formatCustomMovementSaveDiagnostic(
      stage: CustomMovementSaveStage.referenceImageUpload,
      error: const StorageException(
        'Reference upload rejected. Bearer secret-token user@example.com',
        statusCode: '403',
      ),
    );

    expect(line, contains('stage=reference_image_upload'));
    expect(line, contains('code=403'));
    expect(line, contains('Reference upload rejected.'));
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('user@example.com')));
  });

  test('save backend categories map to safe actionable copy', () {
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.databaseCommit,
        cause: const PostgrestException(
          message: 'forbidden',
          code: '42501',
          details: 'permission-denied',
        ),
      ),
      'The server denied this change. Your account access may have changed.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.databaseCommit,
        cause: const SocketException('unavailable'),
      ),
      'The ELIXR server is temporarily unavailable. Check your connection and try again.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.databaseCommit,
        cause: const AuthException('unauthenticated', statusCode: '401'),
      ),
      'Your sign-in has expired. Sign in again, then retry.',
    );
    expect(
      customMovementSaveFailureMessage(
        stage: CustomMovementSaveStage.referenceImageUpload,
        cause: const StorageException('unauthorized', statusCode: '403'),
      ),
      'Storage denied the reference image upload. Check your account access and retry.',
    );
  });

  test('delete failures preserve stage and backend code in safe diagnostics', () {
    final error = CustomMovementDeleteException(
      stage: CustomMovementDeleteStage.archive,
      cause: const PostgrestException(
        message: 'Archive write denied. Bearer secret-token user@example.com',
        code: '42501',
      ),
      stackTrace: StackTrace.current,
    );

    expect(
      customMovementDeleteFailureMessage(error),
      'The server denied this change. Your account access may have changed.',
    );
    final line = formatCustomMovementDeleteDiagnostic(error: error);
    expect(line, contains('stage=archive'));
    expect(line, contains('code=42501'));
    expect(line, contains('Archive write denied.'));
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('user@example.com')));
    expect(
      customMovementDeleteFailureMessage(const SocketException('unavailable')),
      'The ELIXR server is temporarily unavailable. Check your connection and try again.',
    );
    expect(
      customMovementDeleteFailureMessage(
        const AuthException('unauthenticated', statusCode: '401'),
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
