import 'package:elixr_core/models/rubric_assessment.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'assessment_mode.dart';
import 'assignment_submission_limits.dart';
import 'movement_origin.dart';
import 'training_prop.dart';

enum AssignmentAttemptKind {
  practicePointer('practice_pointer'),
  teacherReviewDraft('teacher_review_draft'),
  teacherReviewSubmission('teacher_review_submission'),
  templateScore('template_score');

  const AssignmentAttemptKind(this.wireValue);

  final String wireValue;

  static AssignmentAttemptKind? tryParse(String? value) {
    if (value == null) return null;
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

enum AssignmentAttemptStatus {
  draft('draft'),
  inProgress('in_progress'),
  submitted('submitted'),
  approved('approved'),
  needsRetry('needs_retry');

  const AssignmentAttemptStatus(this.wireValue);

  final String wireValue;

  static AssignmentAttemptStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

enum AssignmentReviewVerdict {
  approved('approved'),
  needsRetry('needs_retry');

  const AssignmentReviewVerdict(this.wireValue);

  final String wireValue;

  static AssignmentReviewVerdict? tryParse(String? value) {
    if (value == null) return null;
    for (final verdict in values) {
      if (verdict.wireValue == value) return verdict;
    }
    return null;
  }
}

/// Classroom attempt at `assignment_attempts/{attemptId}`.
///
/// `awards_global_xp` is always false. Official pointers copy sanitized
/// Assessment V2 fields from the source session so the assigning Teacher can
/// see results without Progress Access or a public profile.
class AssignmentAttempt {
  const AssignmentAttempt({
    required this.id,
    required this.traineeId,
    required this.teacherId,
    required this.groupId,
    required this.assignmentId,
    required this.movementId,
    required this.revisionId,
    required this.origin,
    required this.assessmentMode,
    required this.attemptKind,
    required this.status,
    this.awardsGlobalXp = false,
    this.sourceSessionId,
    this.rubric,
    this.durationSeconds,
    this.propType,
    this.completedAt,
    this.createdAt,
    this.videoStoragePath,
    this.videoContentType,
    this.videoSizeBytes,
    this.videoDurationMs,
    this.submittedAt,
    this.videoExpiresAt,
    this.videoDeletedAt,
    this.deletionFailed = false,
    this.deletionFailedAt,
    this.reviewVerdict,
    this.reviewFeedback,
    this.reviewedAt,
    this.supersedesAttemptId,
    this.abandonedAt,
  });

  final String id;
  final String traineeId;
  final String teacherId;
  final String groupId;
  final String assignmentId;
  final String movementId;
  final String revisionId;
  final MovementOrigin origin;
  final AssessmentMode assessmentMode;
  final AssignmentAttemptKind attemptKind;
  final AssignmentAttemptStatus status;
  final bool awardsGlobalXp;
  final String? sourceSessionId;
  final RubricAssessment? rubric;
  final int? durationSeconds;
  final TrainingProp? propType;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final String? videoStoragePath;
  final String? videoContentType;
  final int? videoSizeBytes;
  final int? videoDurationMs;
  final DateTime? submittedAt;
  final DateTime? videoExpiresAt;
  final DateTime? videoDeletedAt;
  final bool deletionFailed;
  final DateTime? deletionFailedAt;
  final AssignmentReviewVerdict? reviewVerdict;
  final String? reviewFeedback;
  final DateTime? reviewedAt;
  final String? supersedesAttemptId;
  final DateTime? abandonedAt;

  int? get rubricTotal => rubric?.total;
  PerformanceLevel? get performanceLevel => rubric?.performanceLevel;

  bool get isTeacherReviewSubmission =>
      attemptKind == AssignmentAttemptKind.teacherReviewSubmission;

  bool get isAbandonedTeacherReviewDraft {
    if (!isTeacherReviewSubmission) return false;
    return status == AssignmentAttemptStatus.draft && abandonedAt != null;
  }

  bool get isReviewFacingSubmission {
    if (!isTeacherReviewSubmission) return false;
    if (isAbandonedTeacherReviewDraft) return false;
    return status == AssignmentAttemptStatus.submitted ||
        status == AssignmentAttemptStatus.approved ||
        status == AssignmentAttemptStatus.needsRetry;
  }

  bool get hasPlayableVideo =>
      videoStoragePath != null &&
      videoStoragePath!.isNotEmpty &&
      videoDeletedAt == null;

  bool get videoExpired {
    final expires = videoExpiresAt;
    if (expires == null || !hasPlayableVideo) return videoDeletedAt != null;
    return !DateTime.now().toUtc().isBefore(expires.toUtc());
  }

  Map<String, dynamic> toCreateMap({required Object createdAt}) {
    final map = <String, dynamic>{
      'trainee_id': traineeId,
      'teacher_id': teacherId,
      'group_id': groupId,
      'assignment_id': assignmentId,
      'movement_id': movementId,
      'revision_id': revisionId,
      'origin': origin.wireValue,
      'assessment_mode': assessmentMode.wireValue,
      'attempt_kind': attemptKind.wireValue,
      'status': status.wireValue,
      'awards_global_xp': false,
      'created_at': createdAt,
    };
    if (sourceSessionId != null) {
      map['source_session_id'] = sourceSessionId;
    }
    if (rubric != null) {
      map.addAll(rubric!.toFirestoreFields());
    }
    if (durationSeconds != null) {
      map['duration_seconds'] = durationSeconds;
    }
    if (propType != null) {
      map['prop_type'] = propType!.protocolValue;
    }
    if (completedAt != null) {
      map['completed_at'] = completedAt;
    }
    if (supersedesAttemptId != null) {
      map['supersedes_attempt_id'] = supersedesAttemptId;
    }
    return map;
  }

  AssignmentAttempt copyWith({
    AssignmentAttemptStatus? status,
    String? videoStoragePath,
    String? videoContentType,
    int? videoSizeBytes,
    int? videoDurationMs,
    DateTime? submittedAt,
    DateTime? videoExpiresAt,
    DateTime? videoDeletedAt,
    bool? deletionFailed,
    DateTime? deletionFailedAt,
    AssignmentReviewVerdict? reviewVerdict,
    String? reviewFeedback,
    DateTime? reviewedAt,
    String? supersedesAttemptId,
    DateTime? abandonedAt,
    bool clearVideoStoragePath = false,
    bool clearReviewFeedback = false,
    bool clearDeletionFailedAt = false,
  }) {
    return AssignmentAttempt(
      id: id,
      traineeId: traineeId,
      teacherId: teacherId,
      groupId: groupId,
      assignmentId: assignmentId,
      movementId: movementId,
      revisionId: revisionId,
      origin: origin,
      assessmentMode: assessmentMode,
      attemptKind: attemptKind,
      status: status ?? this.status,
      awardsGlobalXp: awardsGlobalXp,
      sourceSessionId: sourceSessionId,
      rubric: rubric,
      durationSeconds: durationSeconds,
      propType: propType,
      completedAt: completedAt,
      createdAt: createdAt,
      videoStoragePath: clearVideoStoragePath
          ? null
          : (videoStoragePath ?? this.videoStoragePath),
      videoContentType: videoContentType ?? this.videoContentType,
      videoSizeBytes: videoSizeBytes ?? this.videoSizeBytes,
      videoDurationMs: videoDurationMs ?? this.videoDurationMs,
      submittedAt: submittedAt ?? this.submittedAt,
      videoExpiresAt: videoExpiresAt ?? this.videoExpiresAt,
      videoDeletedAt: videoDeletedAt ?? this.videoDeletedAt,
      deletionFailed: deletionFailed ?? this.deletionFailed,
      deletionFailedAt: clearDeletionFailedAt
          ? null
          : (deletionFailedAt ?? this.deletionFailedAt),
      reviewVerdict: reviewVerdict ?? this.reviewVerdict,
      reviewFeedback: clearReviewFeedback
          ? null
          : (reviewFeedback ?? this.reviewFeedback),
      reviewedAt: reviewedAt ?? this.reviewedAt,
      supersedesAttemptId: supersedesAttemptId ?? this.supersedesAttemptId,
      abandonedAt: abandonedAt ?? this.abandonedAt,
    );
  }

  static AssignmentAttempt? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final traineeId = _readId(map['trainee_id']);
    final teacherId = _readId(map['teacher_id']);
    final groupId = _readId(map['group_id']);
    final assignmentId = _readId(map['assignment_id']);
    final movementId = _readId(map['movement_id']);
    final revisionId = _readId(map['revision_id']);
    final origin = MovementOrigin.tryParse(
      map['origin'] is String ? map['origin'] as String : null,
    );
    final assessmentMode = AssessmentMode.tryParse(
      map['assessment_mode'] is String
          ? map['assessment_mode'] as String
          : null,
    );
    final attemptKind = AssignmentAttemptKind.tryParse(
      map['attempt_kind'] is String ? map['attempt_kind'] as String : null,
    );
    final status = AssignmentAttemptStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    if (traineeId == null ||
        teacherId == null ||
        groupId == null ||
        assignmentId == null ||
        movementId == null ||
        revisionId == null ||
        origin == null ||
        assessmentMode == null ||
        attemptKind == null ||
        status == null) {
      return null;
    }
    if (map['awards_global_xp'] != false) return null;

    final sourceSessionId = _readId(map['source_session_id']);
    final reviewVerdict = AssignmentReviewVerdict.tryParse(
      map['review_verdict'] is String ? map['review_verdict'] as String : null,
    );
    final reviewFeedback = _readBounded(
      map['review_feedback'],
      maxLength: 1000,
    );
    if (map.containsKey('review_feedback') &&
        map['review_feedback'] != null &&
        reviewFeedback == null) {
      return null;
    }
    final videoStoragePath = _readBounded(
      map['video_storage_path'],
      maxLength: 512,
    );
    final videoContentType = _readBounded(
      map['video_content_type'],
      maxLength: 64,
    );
    final supersedesAttemptId = _readId(map['supersedes_attempt_id']);
    final submittedAt = TeacherRosterInvite.readDateTime(map['submitted_at']);
    final videoExpiresAt = TeacherRosterInvite.readDateTime(
      map['video_expires_at'],
    );
    final videoDeletedAt = TeacherRosterInvite.readDateTime(
      map['video_deleted_at'],
    );
    final reviewedAt = TeacherRosterInvite.readDateTime(map['reviewed_at']);
    final deletionFailedAt = TeacherRosterInvite.readDateTime(
      map['deletion_failed_at'],
    );
    final abandonedAt = TeacherRosterInvite.readDateTime(map['abandoned_at']);
    final deletionFailed = map['deletion_failed'] == true;
    final videoSizeBytes = _readInt(map['video_size_bytes']);
    final videoDurationMs = _readInt(map['video_duration_ms']);

    if (attemptKind == AssignmentAttemptKind.practicePointer) {
      if (sourceSessionId == null) return null;
      if (origin != MovementOrigin.officialElixr) return null;
      if (status != AssignmentAttemptStatus.submitted) return null;
      if (videoStoragePath != null ||
          videoContentType != null ||
          videoSizeBytes != null ||
          videoDurationMs != null ||
          submittedAt != null ||
          videoExpiresAt != null ||
          videoDeletedAt != null ||
          reviewVerdict != null ||
          reviewFeedback != null ||
          reviewedAt != null ||
          supersedesAttemptId != null ||
          abandonedAt != null) {
        return null;
      }
    } else if (attemptKind == AssignmentAttemptKind.teacherReviewDraft) {
      if (sourceSessionId != null) return null;
      if (status != AssignmentAttemptStatus.draft &&
          status != AssignmentAttemptStatus.inProgress) {
        return null;
      }
      if (videoStoragePath != null ||
          videoContentType != null ||
          videoSizeBytes != null ||
          videoDurationMs != null ||
          submittedAt != null ||
          videoExpiresAt != null ||
          videoDeletedAt != null ||
          reviewVerdict != null ||
          reviewFeedback != null ||
          reviewedAt != null ||
          supersedesAttemptId != null ||
          abandonedAt != null ||
          deletionFailed) {
        return null;
      }
    } else if (attemptKind == AssignmentAttemptKind.teacherReviewSubmission) {
      if (sourceSessionId != null) return null;
      if (origin != MovementOrigin.teacherCreated) return null;
      if (assessmentMode != AssessmentMode.teacherReviewed) return null;
      if (!_validTeacherReviewSubmission(
        status: status,
        reviewVerdict: reviewVerdict,
        reviewFeedback: reviewFeedback,
        reviewedAt: reviewedAt,
        videoStoragePath: videoStoragePath,
        videoContentType: videoContentType,
        videoSizeBytes: videoSizeBytes,
        videoDurationMs: videoDurationMs,
        submittedAt: submittedAt,
        videoExpiresAt: videoExpiresAt,
        videoDeletedAt: videoDeletedAt,
        deletionFailed: deletionFailed,
        abandonedAt: abandonedAt,
      )) {
        return null;
      }
    } else if (attemptKind == AssignmentAttemptKind.templateScore) {
      if (sourceSessionId != null) return null;
      if (origin != MovementOrigin.teacherCreated) return null;
      if (assessmentMode != AssessmentMode.templateScored) return null;
      if (status != AssignmentAttemptStatus.submitted) return null;
      if (videoStoragePath != null ||
          videoContentType != null ||
          videoSizeBytes != null ||
          videoDurationMs != null ||
          submittedAt != null ||
          videoExpiresAt != null ||
          videoDeletedAt != null ||
          reviewVerdict != null ||
          reviewFeedback != null ||
          reviewedAt != null ||
          supersedesAttemptId != null ||
          abandonedAt != null ||
          deletionFailed) {
        return null;
      }
      if (RubricAssessment.tryFromFirestore(map) == null) return null;
      if (TeacherRosterInvite.readDateTime(map['completed_at']) == null) {
        return null;
      }
      if (TrainingProp.tryParseStrict(map['prop_type']) !=
          TrainingProp.bottle) {
        return null;
      }
    } else {
      return null;
    }

    return AssignmentAttempt(
      id: id,
      traineeId: traineeId,
      teacherId: teacherId,
      groupId: groupId,
      assignmentId: assignmentId,
      movementId: movementId,
      revisionId: revisionId,
      origin: origin,
      assessmentMode: assessmentMode,
      attemptKind: attemptKind,
      status: status,
      awardsGlobalXp: false,
      sourceSessionId: sourceSessionId,
      rubric: RubricAssessment.tryFromFirestore(map),
      durationSeconds: _readInt(map['duration_seconds']),
      propType: map.containsKey('prop_type')
          ? TrainingProp.tryParseStrict(map['prop_type'])
          : null,
      completedAt: TeacherRosterInvite.readDateTime(map['completed_at']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
      videoDeletedAt: videoDeletedAt,
      deletionFailed: deletionFailed,
      deletionFailedAt: deletionFailedAt,
      reviewVerdict: reviewVerdict,
      reviewFeedback: reviewFeedback,
      reviewedAt: reviewedAt,
      supersedesAttemptId: supersedesAttemptId,
      abandonedAt: abandonedAt,
    );
  }

  static bool _validTeacherReviewSubmission({
    required AssignmentAttemptStatus status,
    required AssignmentReviewVerdict? reviewVerdict,
    required String? reviewFeedback,
    required DateTime? reviewedAt,
    required String? videoStoragePath,
    required String? videoContentType,
    required int? videoSizeBytes,
    required int? videoDurationMs,
    required DateTime? submittedAt,
    required DateTime? videoExpiresAt,
    required DateTime? videoDeletedAt,
    required bool deletionFailed,
    required DateTime? abandonedAt,
  }) {
    switch (status) {
      case AssignmentAttemptStatus.draft:
      case AssignmentAttemptStatus.inProgress:
        if (abandonedAt != null) {
          if (status != AssignmentAttemptStatus.draft) return false;
          return reviewVerdict == null &&
              reviewFeedback == null &&
              reviewedAt == null &&
              videoStoragePath == null &&
              videoContentType == null &&
              videoSizeBytes == null &&
              videoDurationMs == null &&
              submittedAt == null &&
              videoExpiresAt == null;
        }
        return reviewVerdict == null &&
            reviewFeedback == null &&
            reviewedAt == null &&
            videoStoragePath == null &&
            videoContentType == null &&
            videoSizeBytes == null &&
            videoDurationMs == null &&
            submittedAt == null &&
            videoExpiresAt == null &&
            videoDeletedAt == null &&
            !deletionFailed;
      case AssignmentAttemptStatus.submitted:
        return abandonedAt == null &&
            reviewVerdict == null &&
            reviewFeedback == null &&
            reviewedAt == null &&
            _validSubmittedVideoMetadata(
              videoStoragePath: videoStoragePath,
              videoContentType: videoContentType,
              videoSizeBytes: videoSizeBytes,
              videoDurationMs: videoDurationMs,
              submittedAt: submittedAt,
              videoExpiresAt: videoExpiresAt,
              videoDeletedAt: videoDeletedAt,
              deletionFailed: deletionFailed,
            );
      case AssignmentAttemptStatus.approved:
        return abandonedAt == null &&
            reviewVerdict == AssignmentReviewVerdict.approved &&
            reviewedAt != null &&
            _validSubmittedVideoMetadata(
              videoStoragePath: videoStoragePath,
              videoContentType: videoContentType,
              videoSizeBytes: videoSizeBytes,
              videoDurationMs: videoDurationMs,
              submittedAt: submittedAt,
              videoExpiresAt: videoExpiresAt,
              videoDeletedAt: videoDeletedAt,
              deletionFailed: deletionFailed,
            );
      case AssignmentAttemptStatus.needsRetry:
        return abandonedAt == null &&
            reviewVerdict == AssignmentReviewVerdict.needsRetry &&
            reviewedAt != null &&
            _validSubmittedVideoMetadata(
              videoStoragePath: videoStoragePath,
              videoContentType: videoContentType,
              videoSizeBytes: videoSizeBytes,
              videoDurationMs: videoDurationMs,
              submittedAt: submittedAt,
              videoExpiresAt: videoExpiresAt,
              videoDeletedAt: videoDeletedAt,
              deletionFailed: deletionFailed,
            );
    }
  }

  static bool _validSubmittedVideoMetadata({
    required String? videoStoragePath,
    required String? videoContentType,
    required int? videoSizeBytes,
    required int? videoDurationMs,
    required DateTime? submittedAt,
    required DateTime? videoExpiresAt,
    required DateTime? videoDeletedAt,
    required bool deletionFailed,
  }) {
    if (videoContentType != AssignmentSubmissionLimits.contentType) {
      return false;
    }
    if (videoSizeBytes == null ||
        videoSizeBytes <= 0 ||
        videoSizeBytes > AssignmentSubmissionLimits.maxSizeBytes) {
      return false;
    }
    if (videoDurationMs == null ||
        videoDurationMs <= 0 ||
        videoDurationMs > AssignmentSubmissionLimits.maxDurationMs) {
      return false;
    }
    if (submittedAt == null || videoExpiresAt == null) return false;

    final hasPath = videoStoragePath != null && videoStoragePath.isNotEmpty;
    final deleted = videoDeletedAt != null;
    if (deletionFailed) {
      return hasPath && !deleted;
    }
    if (deleted) {
      return !hasPath;
    }
    return hasPath;
  }

  static String? _readId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  static String? _readBounded(Object? value, {required int maxLength}) {
    if (value == null) return null;
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }
}
