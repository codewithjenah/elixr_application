import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'assignment_attempt.dart';
import 'assignment_submission_limits.dart';
import 'classroom_exceptions.dart';

/// Debug-only Phase 6 submission stages. User-facing errors stay generic.
enum Phase6SubmissionStage {
  createDraft,
  storageUpload,
  firestoreSubmit,
  supersededCleanup,
  localCleanup,
  abandonCompensation,
}

extension Phase6SubmissionStageWire on Phase6SubmissionStage {
  String get wireValue {
    switch (this) {
      case Phase6SubmissionStage.createDraft:
        return 'create_draft';
      case Phase6SubmissionStage.storageUpload:
        return 'storage_upload';
      case Phase6SubmissionStage.firestoreSubmit:
        return 'firestore_submit';
      case Phase6SubmissionStage.supersededCleanup:
        return 'superseded_cleanup';
      case Phase6SubmissionStage.localCleanup:
        return 'local_cleanup';
      case Phase6SubmissionStage.abandonCompensation:
        return 'abandon_compensation';
    }
  }
}

void phase6SubmissionDefaultLog(String line) {
  if (kDebugMode) {
    debugPrint(line);
  }
}

String sanitizePhase6DiagnosticText(String raw) {
  var text = raw;
  text = text.replaceAll(
    RegExp(r'https?://[^\s]+', caseSensitive: false),
    '[redacted-url]',
  );
  text = text.replaceAll(
    RegExp(r'Bearer\s+[^\s]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  text = text.replaceAll(
    RegExp(r'Authorization:\s*.+', caseSensitive: false),
    'Authorization:[redacted]',
  );
  text = text.replaceAllMapped(
    RegExp(r'(access_token|refresh_token|id_token|token)=[^\s&]+'),
    (match) => '${match[1]}=[redacted]',
  );
  text = text.replaceAll(RegExp(r'[A-Za-z]:\\[^\s]+'), '[redacted-path]');
  text = text.replaceAll(
    RegExp(r'/[^\s]*elixr_submissions[^\s]*'),
    '[redacted-path]',
  );
  text = text.replaceAll(
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
    '[redacted-email]',
  );
  return text;
}

String formatPhase6SubmissionDiagnostic({
  required Phase6SubmissionStage stage,
  required Object error,
}) {
  final buffer = StringBuffer()
    ..write('[Phase6Submission] stage=${stage.wireValue}')
    ..write(' error_type=${error.runtimeType}');
  if (error is FirebaseException) {
    buffer
      ..write(' plugin=${sanitizePhase6DiagnosticText(error.plugin)}')
      ..write(' code=${sanitizePhase6DiagnosticText(error.code)}');
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      buffer.write(' message=${sanitizePhase6DiagnosticText(message)}');
    }
  } else if (error is ClassroomException) {
    buffer.write(' classroom_code=${error.code.name}');
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      buffer.write(' message=${sanitizePhase6DiagnosticText(message)}');
    }
  } else if (error is AssignmentSubmissionException) {
    buffer.write(' message=${sanitizePhase6DiagnosticText(error.message)}');
  }
  return buffer.toString();
}

void emitPhase6SubmissionDiagnostic({
  required Phase6SubmissionStage stage,
  required Object error,
  void Function(String line)? log,
}) {
  (log ?? phase6SubmissionDefaultLog)(
    formatPhase6SubmissionDiagnostic(stage: stage, error: error),
  );
}

Future<int> runPhase6StorageUpload({
  required Future<int> Function() upload,
  void Function(String line)? log,
}) async {
  try {
    final bytes = await upload();
    (log ?? phase6SubmissionDefaultLog)(
      '[Phase6Submission] stage=storage_upload result=success bytes=$bytes',
    );
    return bytes;
  } on FirebaseException catch (error) {
    emitPhase6SubmissionDiagnostic(
      stage: Phase6SubmissionStage.storageUpload,
      error: error,
      log: log,
    );
    rethrow;
  }
}

String _phase6Flag(bool value) => value ? 'true' : 'false';

String _phase6Nullable(String? value) => value ?? 'null';

/// Debug-only Auth snapshot used immediately before Storage putFile.
class Phase6StorageAuthProbe {
  const Phase6StorageAuthProbe({required this.uid, this.forceRefreshIdToken});

  final String? uid;
  final Future<void> Function()? forceRefreshIdToken;
}

class Phase6StorageRequestSnapshot {
  const Phase6StorageRequestSnapshot({
    required this.authUid,
    required this.projectId,
    required this.bucket,
    required this.attemptId,
    required this.teacherId,
    required this.groupId,
    required this.assignmentId,
    required this.traineeId,
    required this.movementId,
    required this.revisionId,
    required this.storagePath,
    required this.fileSizeBytes,
    required this.contentType,
    required this.metadataKeys,
  });

  final String? authUid;
  final String? projectId;
  final String? bucket;
  final String attemptId;
  final String teacherId;
  final String groupId;
  final String assignmentId;
  final String traineeId;
  final String movementId;
  final String revisionId;
  final String storagePath;
  final int fileSizeBytes;
  final String contentType;
  final List<String> metadataKeys;

  bool get authUidMatchesTrainee => authUid != null && authUid == traineeId;

  bool get pathMatchesExpected {
    return storagePath ==
        assignmentSubmissionStoragePath(
          teacherId: teacherId,
          groupId: groupId,
          assignmentId: assignmentId,
          traineeId: traineeId,
          attemptId: attemptId,
        );
  }
}

String formatPhase6StorageRequest(Phase6StorageRequestSnapshot request) {
  final keys = [...request.metadataKeys]..sort();
  return '[Phase6StorageRequest]\n'
      'auth_uid=${_phase6Nullable(request.authUid)}\n'
      'project_id=${_phase6Nullable(request.projectId)}\n'
      'bucket=${_phase6Nullable(request.bucket)}\n'
      'attempt_id=${request.attemptId}\n'
      'teacher_id=${request.teacherId}\n'
      'group_id=${request.groupId}\n'
      'assignment_id=${request.assignmentId}\n'
      'trainee_id=${request.traineeId}\n'
      'movement_id=${request.movementId}\n'
      'revision_id=${request.revisionId}\n'
      'storage_path=${request.storagePath}\n'
      'file_size_bytes=${request.fileSizeBytes}\n'
      'content_type=${request.contentType}\n'
      'metadata_keys=${keys.join(',')}\n'
      'auth_uid_matches_trainee=${_phase6Flag(request.authUidMatchesTrainee)}\n'
      'path_matches_expected=${_phase6Flag(request.pathMatchesExpected)}';
}

void emitPhase6StorageRequest(
  Phase6StorageRequestSnapshot request, {
  void Function(String line)? log,
}) {
  if (!kDebugMode) return;
  (log ?? phase6SubmissionDefaultLog)(formatPhase6StorageRequest(request));
}

String formatPhase6StorageAnchor({
  required AssignmentAttempt draft,
  required AssignmentAttempt? durable,
}) {
  return '[Phase6StorageAnchor]\n'
      'attempt_exists=${_phase6Flag(durable != null)}\n'
      'status=${durable?.status.wireValue ?? 'null'}\n'
      'abandoned=${_phase6Flag(durable?.abandonedAt != null)}\n'
      'awards_global_xp=${durable == null ? 'null' : _phase6Flag(durable.awardsGlobalXp)}\n'
      'teacher_match=${_phase6Flag(durable?.teacherId == draft.teacherId)}\n'
      'group_match=${_phase6Flag(durable?.groupId == draft.groupId)}\n'
      'assignment_match=${_phase6Flag(durable?.assignmentId == draft.assignmentId)}\n'
      'trainee_match=${_phase6Flag(durable?.traineeId == draft.traineeId)}\n'
      'movement_match=${_phase6Flag(durable?.movementId == draft.movementId)}\n'
      'revision_match=${_phase6Flag(durable?.revisionId == draft.revisionId)}\n'
      'origin_match=${_phase6Flag(durable?.origin == draft.origin)}\n'
      'assessment_mode_match=${_phase6Flag(durable?.assessmentMode == draft.assessmentMode)}';
}

String formatPhase6StorageAnchorReadFailure(Object error) {
  final buffer = StringBuffer()
    ..write('[Phase6StorageAnchor] read_failed')
    ..write(' error_type=${error.runtimeType}');
  if (error is FirebaseException) {
    buffer
      ..write(' plugin=${sanitizePhase6DiagnosticText(error.plugin)}')
      ..write(' code=${sanitizePhase6DiagnosticText(error.code)}');
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      buffer.write(' message=${sanitizePhase6DiagnosticText(message)}');
    }
  }
  return buffer.toString();
}

/// Reads the durable `review_sub_*` draft. Failures are logged and ignored.
Future<void> emitPhase6DurableDraftAnchor({
  required AssignmentAttempt draft,
  required Future<AssignmentAttempt?> Function({required String attemptId})
  readAttempt,
  void Function(String line)? diagnosticLog,
}) async {
  if (!kDebugMode) return;
  try {
    final durable = await readAttempt(attemptId: draft.id);
    (diagnosticLog ?? phase6SubmissionDefaultLog)(
      formatPhase6StorageAnchor(draft: draft, durable: durable),
    );
  } catch (error) {
    (diagnosticLog ?? phase6SubmissionDefaultLog)(
      formatPhase6StorageAnchorReadFailure(error),
    );
  }
}

String formatPhase6StorageAuthUid(String? uid) {
  return '[Phase6StorageAuth] uid=${_phase6Nullable(uid)}';
}

String formatPhase6StorageAuthTokenRefreshFailure(Object error) {
  final buffer = StringBuffer()
    ..write('[Phase6StorageAuth] token_refresh_failed')
    ..write(' error_type=${error.runtimeType}');
  if (error is FirebaseException) {
    buffer
      ..write(' plugin=${sanitizePhase6DiagnosticText(error.plugin)}')
      ..write(' code=${sanitizePhase6DiagnosticText(error.code)}');
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      buffer.write(' message=${sanitizePhase6DiagnosticText(message)}');
    }
  }
  return buffer.toString();
}

/// Logs Auth uid and force-refreshes the ID token once. Does not print tokens.
Future<void> runPhase6DebugPreUploadProbes({
  required Phase6StorageRequestSnapshot request,
  required Phase6StorageAuthProbe auth,
  void Function(String line)? log,
}) async {
  if (!kDebugMode) return;
  final emit = log ?? phase6SubmissionDefaultLog;
  emitPhase6StorageRequest(request, log: emit);
  emit(formatPhase6StorageAuthUid(auth.uid));
  final refresh = auth.forceRefreshIdToken;
  if (refresh == null) {
    emit('[Phase6StorageAuth] token_refresh=skipped');
    return;
  }
  try {
    await refresh();
    emit('[Phase6StorageAuth] token_refresh=forced');
  } catch (error) {
    emit(formatPhase6StorageAuthTokenRefreshFailure(error));
  }
}
