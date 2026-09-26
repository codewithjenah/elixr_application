import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

import '../repositories/custom_movement_repository.dart';

/// Safe `(code, message)` details of a backend error, or null for others.
(String code, String? message)? _backendErrorDetails(Object error) {
  return switch (error) {
    PostgrestException(:final code, :final message) => (
      code ?? 'database',
      message,
    ),
    StorageException(:final statusCode, :final message) => (
      statusCode ?? 'storage',
      message,
    ),
    AuthException(:final code, :final statusCode, :final message) => (
      code ?? statusCode ?? 'auth',
      message,
    ),
    _ => null,
  };
}

void _writeDiagnosticDetails(StringBuffer buffer, Object error) {
  final details = _backendErrorDetails(error);
  if (details == null) return;
  buffer.write(' code=${_safeDiagnosticIdentifier(details.$1)}');
  final safeMessage = sanitizeCustomMovementDiagnosticText(
    details.$2 ?? '',
  ).replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  if (safeMessage.isNotEmpty) {
    buffer.write(' message="${safeMessage.replaceAll('"', "'")}"');
  }
}

String formatCustomMovementSaveDiagnostic({
  required CustomMovementSaveStage stage,
  required Object error,
}) {
  final buffer = StringBuffer()
    ..write('[CustomMovementSave] stage=${stage.wireValue}')
    ..write(' error_type=${error.runtimeType}');
  _writeDiagnosticDetails(buffer, error);
  return buffer.toString();
}

String customMovementSaveFailureMessage({
  required CustomMovementSaveStage stage,
  required Object cause,
}) {
  if (isBackendUnavailableError(cause)) {
    return 'The ELIXR server is temporarily unavailable. Check your connection and try again.';
  }
  if (cause is AuthException) {
    return 'Your sign-in has expired. Sign in again, then retry.';
  }
  if (isPermissionDeniedError(cause)) {
    return stage == CustomMovementSaveStage.referenceImageUpload
        ? 'Storage denied the reference image upload. Check your account access and retry.'
        : 'The server denied this change. Your account access may have changed.';
  }
  return stage.userMessage;
}

String customMovementDeleteFailureMessage(Object error) {
  final cause = error is CustomMovementDeleteException ? error.cause : error;
  if (isBackendUnavailableError(cause)) {
    return 'The ELIXR server is temporarily unavailable. Check your connection and try again.';
  }
  if (cause is AuthException) {
    return 'Your sign-in has expired. Sign in again, then retry.';
  }
  if (isPermissionDeniedError(cause)) {
    return 'The server denied this change. Your account access may have changed.';
  }
  return 'Could not delete this movement. Try again.';
}

String formatCustomMovementDeleteDiagnostic({required Object error}) {
  final stage = error is CustomMovementDeleteException
      ? error.stage
      : CustomMovementDeleteStage.unknown;
  final cause = error is CustomMovementDeleteException ? error.cause : error;
  final buffer = StringBuffer()
    ..write('[CustomMovementDelete] stage=${stage.wireValue}')
    ..write(' error_type=${cause.runtimeType}');
  _writeDiagnosticDetails(buffer, cause);
  return buffer.toString();
}

void emitCustomMovementDeleteDiagnostic({
  required Object error,
  required StackTrace stackTrace,
  void Function(String line)? log,
}) {
  final emit = log ?? debugPrint;
  emit(formatCustomMovementDeleteDiagnostic(error: error));
  final detailStack = error is CustomMovementDeleteException
      ? error.stackTrace
      : stackTrace;
  final safeStack = sanitizeCustomMovementDiagnosticText(
    detailStack.toString(),
  );
  for (final line in safeStack.split('\n')) {
    if (line.isNotEmpty) emit('[CustomMovementDelete] stack=$line');
  }
}

String sanitizeCustomMovementDiagnosticText(String raw) {
  var text = raw;
  text = text.replaceAll(
    RegExp(r'https?://[^\s]+', caseSensitive: false),
    '[redacted-url]',
  );
  text = text.replaceAll(
    RegExp(r'gs://[^\s]+', caseSensitive: false),
    '[redacted-url]',
  );
  text = text.replaceAll(
    RegExp(r'Bearer\s+[^\s]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'\b((?:access|refresh|id)?_?token|api[_-]?key|client[_-]?secret|password|secret)[=:][^\s&]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  text = text.replaceAll(RegExp(r'[A-Za-z]:\\[^\r\n\t ]+'), '[redacted-path]');
  text = text.replaceAll(
    RegExp(r'file://[^\r\n\t ]+', caseSensitive: false),
    '[redacted-path]',
  );
  text = text.replaceAll(
    RegExp(r'/(?:Users|home|root|mnt|tmp|private|Volumes)/[^\r\n\t ]+'),
    '[redacted-path]',
  );
  text = text.replaceAllMapped(
    RegExp(r'(/users/)[^/\s]+(?=/)', caseSensitive: false),
    (match) => '${match.group(1)}[redacted]',
  );
  text = text.replaceAll(
    RegExp(r'\b[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b'),
    '[redacted-token]',
  );
  text = text.replaceAll(
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
    '[redacted-email]',
  );
  return text;
}

void emitCustomMovementSaveDiagnostic({
  required CustomMovementSaveStage stage,
  required Object error,
  required StackTrace stackTrace,
  void Function(String line)? log,
}) {
  final emit = log ?? debugPrint;
  emit(formatCustomMovementSaveDiagnostic(stage: stage, error: error));
  final safeStack = sanitizeCustomMovementDiagnosticText(stackTrace.toString());
  for (final line in safeStack.split('\n')) {
    if (line.isNotEmpty) emit('[CustomMovementSave] stack=$line');
  }
}

String _safeDiagnosticIdentifier(String value) {
  if (RegExp(r'^[A-Za-z0-9._:/-]{1,80}$').hasMatch(value)) return value;
  return '[redacted]';
}
