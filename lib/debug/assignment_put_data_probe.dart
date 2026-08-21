import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/models/assessment_mode.dart';
import '../data/models/assignment_attempt.dart';
import '../data/models/assignment_submission_limits.dart';
import '../data/models/group_assignment.dart';
import '../data/models/movement_origin.dart';
import '../data/models/phase6_submission_diagnostics.dart';
import '../data/repositories/classroom_assignment_repository.dart';
import '../data/repositories/firebase_classroom_assignment_repository.dart';

/// Tiny non-empty payload for the debug assignment putData probe.
/// Not a decodable MP4; Storage rules evaluate declared type/size/metadata.
final Uint8List assignmentPutDataProbeBytes = Uint8List.fromList(
  List<int>.filled(128, 0x45),
);

const bool kAssignmentPutDataProbeDartDefine =
    bool.fromEnvironment('ELIXR_ASSIGNMENT_PUTDATA_PROBE') ||
    String.fromEnvironment('ELIXR_ASSIGNMENT_PUTDATA_PROBE') == '1';

/// Production assignment used by the one-shot diagnostic.
const AssignmentPutDataProbeTarget kLiveAssignmentPutDataProbeTarget =
    AssignmentPutDataProbeTarget(
      teacherId: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
      groupId: 'i0CaSM4nEA9sNuKSRagO',
      assignmentId: 'ENvAezoRemcyihux3wpP',
      traineeId: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
      movementId: 'CYdQM78YMPbLTCTblERB',
      revisionId: 'DNLnQUFnxmwUP0y5uIM9',
    );

class AssignmentPutDataProbeTarget {
  const AssignmentPutDataProbeTarget({
    required this.teacherId,
    required this.groupId,
    required this.assignmentId,
    required this.traineeId,
    required this.movementId,
    required this.revisionId,
  });

  final String teacherId;
  final String groupId;
  final String assignmentId;
  final String traineeId;
  final String movementId;
  final String revisionId;
}

enum AssignmentPutDataProbeRemoteCleanup { success, failure, notCreated }

enum AssignmentPutDataProbeAnchorCleanup { abandoned, failure, notCreated }

class AssignmentPutDataProbeResult {
  const AssignmentPutDataProbeResult({
    required this.invoked,
    required this.uploadSucceeded,
    required this.remoteCleanup,
    required this.anchorCleanup,
    this.uid,
    this.bucket,
    this.attemptId,
    this.storagePath,
    this.sizeBytes,
    this.anchorValidBeforeUpload = false,
    this.pathCorrect = false,
    this.metadataCorrect = false,
    this.errorType,
    this.plugin,
    this.code,
    this.safeMessage,
  });

  final bool invoked;
  final bool uploadSucceeded;
  final AssignmentPutDataProbeRemoteCleanup remoteCleanup;
  final AssignmentPutDataProbeAnchorCleanup anchorCleanup;
  final String? uid;
  final String? bucket;
  final String? attemptId;
  final String? storagePath;
  final int? sizeBytes;
  final bool anchorValidBeforeUpload;
  final bool pathCorrect;
  final bool metadataCorrect;
  final String? errorType;
  final String? plugin;
  final String? code;
  final String? safeMessage;
}

typedef AssignmentPutDataUpload =
    Future<void> Function({
      required Uint8List bytes,
      required String storagePath,
      required String contentType,
      required Map<String, String> customMetadata,
    });

typedef AssignmentPutDataDelete = Future<void> Function(String storagePath);

void assignmentPutDataProbeDefaultLog(String line) {
  if (kDebugMode) {
    debugPrint(line);
  }
}

bool assignmentMatchesPutDataProbeTarget({
  required GroupAssignment assignment,
  required AssignmentPutDataProbeTarget target,
}) {
  return assignment.id == target.assignmentId &&
      assignment.teacherId == target.teacherId &&
      assignment.groupId == target.groupId &&
      assignment.movementId == target.movementId &&
      assignment.revisionId == target.revisionId &&
      assignment.origin == MovementOrigin.teacherCreated &&
      assignment.assessmentMode == AssessmentMode.teacherReviewed &&
      assignment.isActive;
}

bool isValidAssignmentPutDataProbeAnchor({
  required AssignmentAttempt attempt,
  required AssignmentPutDataProbeTarget target,
  required String authenticatedUid,
}) {
  return authenticatedUid == target.traineeId &&
      attempt.attemptKind == AssignmentAttemptKind.teacherReviewSubmission &&
      attempt.status == AssignmentAttemptStatus.draft &&
      attempt.awardsGlobalXp == false &&
      attempt.abandonedAt == null &&
      attempt.teacherId == target.teacherId &&
      attempt.groupId == target.groupId &&
      attempt.assignmentId == target.assignmentId &&
      attempt.traineeId == target.traineeId &&
      attempt.movementId == target.movementId &&
      attempt.revisionId == target.revisionId &&
      attempt.origin == MovementOrigin.teacherCreated &&
      attempt.assessmentMode == AssessmentMode.teacherReviewed &&
      attempt.submittedAt == null &&
      attempt.videoStoragePath == null &&
      attempt.sourceSessionId == null;
}

Future<AssignmentPutDataProbeResult?> maybeRunLiveAssignmentPutDataProbe({
  bool? debugMode,
  bool? dartDefineEnabled,
  Future<AssignmentPutDataProbeResult> Function()? runLive,
}) async {
  final enabledDebug = debugMode ?? kDebugMode;
  final enabledDefine = dartDefineEnabled ?? kAssignmentPutDataProbeDartDefine;
  if (!enabledDebug || !enabledDefine) {
    return null;
  }
  final runner = runLive ?? runLiveAssignmentPutDataProbe;
  return runner();
}

/// Live production-bucket probe. No-op in Release.
Future<AssignmentPutDataProbeResult> runLiveAssignmentPutDataProbe({
  bool debugMode = kDebugMode,
  String? Function()? readUid,
  String? Function()? readBucket,
  ClassroomAssignmentRepository? classroom,
  FirebaseStorage? storage,
  AssignmentPutDataProbeTarget target = kLiveAssignmentPutDataProbeTarget,
  Uint8List? payload,
  void Function(String line)? log,
}) {
  final resolvedStorage = storage ?? FirebaseStorage.instance;
  final resolvedClassroom =
      classroom ?? FirebaseClassroomAssignmentRepository();
  return runAssignmentPutDataProbe(
    debugMode: debugMode,
    uid: (readUid ?? () => FirebaseAuth.instance.currentUser?.uid)(),
    bucket: (readBucket ?? () => resolvedStorage.bucket)(),
    target: target,
    payload: payload ?? assignmentPutDataProbeBytes,
    classroom: resolvedClassroom,
    now: DateTime.now().toUtc(),
    log: log ?? assignmentPutDataProbeDefaultLog,
    putData:
        ({
          required bytes,
          required storagePath,
          required contentType,
          required customMetadata,
        }) async {
          await resolvedStorage
              .ref(storagePath)
              .putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  customMetadata: customMetadata,
                ),
              );
        },
    deleteRemote: (storagePath) => resolvedStorage.ref(storagePath).delete(),
  );
}

Future<AssignmentPutDataProbeResult> runAssignmentPutDataProbe({
  required bool debugMode,
  required String? uid,
  required String? bucket,
  required AssignmentPutDataProbeTarget target,
  required Uint8List payload,
  required ClassroomAssignmentRepository classroom,
  required DateTime now,
  required void Function(String line) log,
  required AssignmentPutDataUpload putData,
  required AssignmentPutDataDelete deleteRemote,
}) async {
  if (!debugMode) {
    return const AssignmentPutDataProbeResult(
      invoked: false,
      uploadSucceeded: false,
      remoteCleanup: AssignmentPutDataProbeRemoteCleanup.notCreated,
      anchorCleanup: AssignmentPutDataProbeAnchorCleanup.notCreated,
    );
  }

  AssignmentAttempt? createdDraft;
  var uploaded = false;
  var uploadSucceeded = false;
  var remoteCleanup = AssignmentPutDataProbeRemoteCleanup.notCreated;
  var anchorCleanup = AssignmentPutDataProbeAnchorCleanup.notCreated;
  var anchorValidBeforeUpload = false;
  var pathCorrect = false;
  var metadataCorrect = false;
  String? attemptId;
  String? storagePath;
  String? errorType;
  String? plugin;
  String? code;
  String? safeMessage;
  final sizeBytes = payload.length;

  Future<void> abandonDraft({
    required AssignmentAttempt attempt,
    bool deletionFailed = false,
  }) async {
    try {
      await classroom.markTeacherReviewSubmissionAbandoned(
        traineeId: attempt.traineeId,
        attempt: attempt,
        deletionFailed: deletionFailed,
        deletionFailedAt: deletionFailed ? now : null,
      );
      anchorCleanup = AssignmentPutDataProbeAnchorCleanup.abandoned;
      log('[AssignmentPutDataProbe] anchor_cleanup=abandoned');
    } catch (_) {
      anchorCleanup = AssignmentPutDataProbeAnchorCleanup.failure;
      log('[AssignmentPutDataProbe] anchor_cleanup=failure');
    }
  }

  void logFirebaseFailure(FirebaseException error) {
    errorType = 'FirebaseException';
    plugin = sanitizePhase6DiagnosticText(error.plugin);
    code = sanitizePhase6DiagnosticText(error.code);
    final message = error.message;
    safeMessage = message == null || message.isEmpty
        ? null
        : sanitizePhase6DiagnosticText(message);
    log(
      '[AssignmentPutDataProbe]\n'
      'result=failure\n'
      'error_type=FirebaseException\n'
      'plugin=$plugin\n'
      'code=$code'
      '${safeMessage == null ? '' : '\nmessage=$safeMessage'}',
    );
  }

  void logGenericFailure(Object error) {
    errorType = error.runtimeType.toString();
    safeMessage = sanitizePhase6DiagnosticText(error.toString());
    log(
      '[AssignmentPutDataProbe]\n'
      'result=failure\n'
      'error_type=$errorType\n'
      'message=$safeMessage',
    );
  }

  if (uid == null || uid.isEmpty) {
    log(
      '[AssignmentPutDataProbe]\n'
      'result=failure\n'
      'error_type=Unauthenticated',
    );
    log('[AssignmentPutDataProbe] remote_cleanup=not_created');
    log('[AssignmentPutDataProbe] anchor_cleanup=not_created');
    return const AssignmentPutDataProbeResult(
      invoked: false,
      uploadSucceeded: false,
      remoteCleanup: AssignmentPutDataProbeRemoteCleanup.notCreated,
      anchorCleanup: AssignmentPutDataProbeAnchorCleanup.notCreated,
      errorType: 'Unauthenticated',
    );
  }

  if (uid != target.traineeId) {
    log(
      '[AssignmentPutDataProbe]\n'
      'result=failure\n'
      'error_type=TraineeMismatch',
    );
    log('[AssignmentPutDataProbe] remote_cleanup=not_created');
    log('[AssignmentPutDataProbe] anchor_cleanup=not_created');
    return AssignmentPutDataProbeResult(
      invoked: false,
      uploadSucceeded: false,
      remoteCleanup: AssignmentPutDataProbeRemoteCleanup.notCreated,
      anchorCleanup: AssignmentPutDataProbeAnchorCleanup.notCreated,
      uid: uid,
      bucket: bucket,
      errorType: 'TraineeMismatch',
    );
  }

  try {
    final assignment = await classroom.getAssignment(
      assignmentId: target.assignmentId,
    );
    if (assignment == null ||
        !assignmentMatchesPutDataProbeTarget(
          assignment: assignment,
          target: target,
        )) {
      log(
        '[AssignmentPutDataProbe]\n'
        'result=failure\n'
        'error_type=InvalidAssignment',
      );
      log('[AssignmentPutDataProbe] remote_cleanup=not_created');
      log('[AssignmentPutDataProbe] anchor_cleanup=not_created');
      return AssignmentPutDataProbeResult(
        invoked: false,
        uploadSucceeded: false,
        remoteCleanup: AssignmentPutDataProbeRemoteCleanup.notCreated,
        anchorCleanup: AssignmentPutDataProbeAnchorCleanup.notCreated,
        uid: uid,
        bucket: bucket,
        errorType: 'InvalidAssignment',
      );
    }

    createdDraft = await classroom.createTeacherReviewSubmissionDraft(
      traineeId: uid,
      assignment: assignment,
    );
    attemptId = createdDraft.id;

    AssignmentAttempt? durable;
    try {
      durable = await classroom.getAttempt(attemptId: createdDraft.id);
    } catch (error) {
      if (error is FirebaseException) {
        logFirebaseFailure(error);
      } else {
        logGenericFailure(error);
      }
      log('[AssignmentPutDataProbe] remote_cleanup=not_created');
      await abandonDraft(attempt: createdDraft);
      return AssignmentPutDataProbeResult(
        invoked: true,
        uploadSucceeded: false,
        remoteCleanup: remoteCleanup,
        anchorCleanup: anchorCleanup,
        uid: uid,
        bucket: bucket,
        attemptId: attemptId,
        sizeBytes: sizeBytes,
        errorType: errorType,
        plugin: plugin,
        code: code,
        safeMessage: safeMessage,
      );
    }

    if (durable == null ||
        !isValidAssignmentPutDataProbeAnchor(
          attempt: durable,
          target: target,
          authenticatedUid: uid,
        )) {
      log(
        '[AssignmentPutDataProbe]\n'
        'result=failure\n'
        'error_type=InvalidAnchor',
      );
      log('[AssignmentPutDataProbe] remote_cleanup=not_created');
      await abandonDraft(attempt: createdDraft);
      return AssignmentPutDataProbeResult(
        invoked: true,
        uploadSucceeded: false,
        remoteCleanup: AssignmentPutDataProbeRemoteCleanup.notCreated,
        anchorCleanup: anchorCleanup,
        uid: uid,
        bucket: bucket,
        attemptId: attemptId,
        sizeBytes: sizeBytes,
        errorType: 'InvalidAnchor',
      );
    }

    anchorValidBeforeUpload = true;
    storagePath = assignmentSubmissionStoragePath(
      teacherId: durable.teacherId,
      groupId: durable.groupId,
      assignmentId: durable.assignmentId,
      traineeId: durable.traineeId,
      attemptId: durable.id,
    );
    final expectedPath = assignmentSubmissionStoragePath(
      teacherId: target.teacherId,
      groupId: target.groupId,
      assignmentId: target.assignmentId,
      traineeId: target.traineeId,
      attemptId: durable.id,
    );
    pathCorrect = storagePath == expectedPath;

    final customMetadata = assignmentSubmissionCustomMetadata(
      teacherId: durable.teacherId,
      groupId: durable.groupId,
      assignmentId: durable.assignmentId,
      traineeId: durable.traineeId,
      attemptId: durable.id,
      movementId: durable.movementId,
      revisionId: durable.revisionId,
    );
    final expectedMetadata = assignmentSubmissionCustomMetadata(
      teacherId: target.teacherId,
      groupId: target.groupId,
      assignmentId: target.assignmentId,
      traineeId: target.traineeId,
      attemptId: durable.id,
      movementId: target.movementId,
      revisionId: target.revisionId,
    );
    metadataCorrect =
        mapEquals(customMetadata, expectedMetadata) &&
        customMetadata.length == 7;

    log(
      '[AssignmentPutDataProbe]\n'
      'uid=$uid\n'
      'bucket=$bucket\n'
      'attempt_id=${durable.id}\n'
      'storage_path=$storagePath\n'
      'content_type=${AssignmentSubmissionLimits.contentType}\n'
      'size_bytes=$sizeBytes\n'
      'metadata_keys=${(customMetadata.keys.toList()..sort()).join(',')}\n'
      'anchor_status=${durable.status.wireValue}\n'
      'anchor_abandoned=false\n'
      'anchor_identity_matches=true',
    );

    try {
      await putData(
        bytes: payload,
        storagePath: storagePath,
        contentType: AssignmentSubmissionLimits.contentType,
        customMetadata: customMetadata,
      );
      uploaded = true;
      uploadSucceeded = true;
      log('[AssignmentPutDataProbe] result=success bytes=$sizeBytes');
    } on FirebaseException catch (error) {
      logFirebaseFailure(error);
    } catch (error) {
      logGenericFailure(error);
    }

    if (uploaded) {
      try {
        await deleteRemote(storagePath);
        remoteCleanup = AssignmentPutDataProbeRemoteCleanup.success;
        log('[AssignmentPutDataProbe] remote_cleanup=success');
        await abandonDraft(attempt: durable);
      } catch (_) {
        remoteCleanup = AssignmentPutDataProbeRemoteCleanup.failure;
        log('[AssignmentPutDataProbe] remote_cleanup=failure');
        await abandonDraft(attempt: durable, deletionFailed: true);
      }
    } else {
      log('[AssignmentPutDataProbe] remote_cleanup=not_created');
      await abandonDraft(attempt: durable);
    }
  } on FirebaseException catch (error) {
    logFirebaseFailure(error);
    log('[AssignmentPutDataProbe] remote_cleanup=not_created');
    if (createdDraft != null) {
      await abandonDraft(attempt: createdDraft);
    } else {
      log('[AssignmentPutDataProbe] anchor_cleanup=not_created');
    }
  } catch (error) {
    logGenericFailure(error);
    log('[AssignmentPutDataProbe] remote_cleanup=not_created');
    if (createdDraft != null) {
      await abandonDraft(attempt: createdDraft);
    } else {
      log('[AssignmentPutDataProbe] anchor_cleanup=not_created');
    }
  }

  return AssignmentPutDataProbeResult(
    invoked: true,
    uploadSucceeded: uploadSucceeded,
    remoteCleanup: remoteCleanup,
    anchorCleanup: anchorCleanup,
    uid: uid,
    bucket: bucket,
    attemptId: attemptId,
    storagePath: storagePath,
    sizeBytes: sizeBytes,
    anchorValidBeforeUpload: anchorValidBeforeUpload,
    pathCorrect: pathCorrect,
    metadataCorrect: metadataCorrect,
    errorType: errorType,
    plugin: plugin,
    code: code,
    safeMessage: safeMessage,
  );
}
