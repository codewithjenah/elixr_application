import 'package:elixr_core/models/rubric_assessment.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'assessment_mode.dart';
import 'assignment_attempt_ids.dart';
import 'assignment_submission_limits.dart';
import 'movement_origin.dart';
import 'training_prop.dart';
import 'teacher_activity_assessment.dart';

enum AssignmentAttemptKind {
  practicePointer('practice_pointer'),
  teacherReviewDraft('teacher_review_draft'),
  teacherReviewSubmission('teacher_review_submission'),
  // Historical Firestore value. New attempts must use a current kind.
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
  unsubmitting('unsubmitting'),
  checked('checked'),
  // Legacy review states. New writes must use checked.
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
/// `template_score` is retained only so historical Firestore records can be
/// displayed; [toCreateMap] rejects it. `awards_global_xp` is always false.
/// Official pointers copy sanitized
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
    this.draftSavedAt,
    this.draftCleanupStartedAt,
    this.submittedAt,
    this.videoExpiresAt,
    this.videoDeletedAt,
    this.deletionFailed = false,
    this.deletionFailedAt,
    this.reviewVerdict,
    this.reviewFeedback,
    this.reviewedAt,
    this.gradeScore,
    this.gradeMaxScore,
    this.checkedAt,
    this.reviewUpdatedAt,
    this.reviewRevision,
    this.resultSentRevision,
    this.resultSentAt,
    this.resultMessageId,
    this.supersedesAttemptId,
    this.abandonedAt,
    this.recordingStartedAt,
    this.assignmentConfigurationRevision,
    this.activityAssessmentSnapshot,
    this.criterionScores,
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

  /// Present only while a canonical in-progress submission has a private,
  /// uploaded recording waiting for the trainee to turn it in.
  final DateTime? draftSavedAt;
  final DateTime? draftCleanupStartedAt;
  final DateTime? submittedAt;
  final DateTime? videoExpiresAt;
  final DateTime? videoDeletedAt;
  final bool deletionFailed;
  final DateTime? deletionFailedAt;
  final AssignmentReviewVerdict? reviewVerdict;
  final String? reviewFeedback;
  final DateTime? reviewedAt;
  final int? gradeScore;
  final int? gradeMaxScore;
  final DateTime? checkedAt;
  final DateTime? reviewUpdatedAt;
  final int? reviewRevision;
  final int? resultSentRevision;
  final DateTime? resultSentAt;
  final String? resultMessageId;
  final String? supersedesAttemptId;
  final DateTime? abandonedAt;
  final DateTime? recordingStartedAt;
  final int? assignmentConfigurationRevision;
  final TeacherActivityAssessmentConfig? activityAssessmentSnapshot;
  final Map<String, int>? criterionScores;

  int? get rubricTotal => rubric?.total;
  PerformanceLevel? get performanceLevel => rubric?.performanceLevel;

  bool get isTeacherReviewSubmission =>
      attemptKind == AssignmentAttemptKind.teacherReviewSubmission;

  bool get isCanonicalTeacherReviewSubmission {
    if (!isTeacherReviewSubmission) return false;
    try {
      return id ==
          assignmentAttemptIdForCanonicalTeacherReviewSubmission(
            assignmentId: assignmentId,
            traineeId: traineeId,
          );
    } on ArgumentError {
      return false;
    }
  }

  bool get isChecked =>
      isTeacherReviewSubmission && status == AssignmentAttemptStatus.checked;

  bool get isUnsubmitting =>
      isTeacherReviewSubmission &&
      status == AssignmentAttemptStatus.unsubmitting;

  bool get hasNewReview => isChecked && gradeScore != null;

  bool get resultSentForCurrentRevision =>
      isChecked &&
      resultSentRevision != null &&
      resultSentRevision == reviewRevision &&
      resultSentAt != null &&
      resultMessageId != null &&
      resultMessageId!.isNotEmpty;

  bool get isHistoricalTemplateScore =>
      attemptKind == AssignmentAttemptKind.templateScore ||
      assessmentMode == AssessmentMode.templateScored;

  bool get isAbandonedTeacherReviewDraft {
    if (!isTeacherReviewSubmission) return false;
    return status == AssignmentAttemptStatus.draft && abandonedAt != null;
  }

  bool get isReviewFacingSubmission {
    if (!isTeacherReviewSubmission) return false;
    if (isAbandonedTeacherReviewDraft) return false;
    return status == AssignmentAttemptStatus.submitted ||
        status == AssignmentAttemptStatus.unsubmitting ||
        status == AssignmentAttemptStatus.checked ||
        status == AssignmentAttemptStatus.approved ||
        status == AssignmentAttemptStatus.needsRetry;
  }

  bool get hasPlayableVideo =>
      videoStoragePath != null &&
      videoStoragePath!.isNotEmpty &&
      videoDeletedAt == null;

  bool get hasAttachedDraftClip =>
      isCanonicalTeacherReviewSubmission &&
      status == AssignmentAttemptStatus.inProgress &&
      draftSavedAt != null &&
      draftCleanupStartedAt == null &&
      hasPlayableVideo;

  bool get isDraftClipRemovalPending =>
      isCanonicalTeacherReviewSubmission &&
      status == AssignmentAttemptStatus.inProgress &&
      draftCleanupStartedAt != null;

  bool get videoExpired {
    final expires = videoExpiresAt;
    if (expires == null || !hasPlayableVideo) return videoDeletedAt != null;
    return !DateTime.now().toUtc().isBefore(expires.toUtc());
  }

  Map<String, dynamic> toCreateMap({required Object createdAt}) {
    if (isHistoricalTemplateScore) {
      throw StateError(
        'Template-scored attempts are read-only historical records.',
      );
    }
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
    if (assignmentConfigurationRevision != null &&
        activityAssessmentSnapshot != null) {
      map['assignment_configuration_revision'] =
          assignmentConfigurationRevision;
      map['activity_assessment_snapshot'] = activityAssessmentSnapshot!.toMap();
    }
    return map;
  }

  AssignmentAttempt copyWith({
    AssignmentAttemptStatus? status,
    String? videoStoragePath,
    String? videoContentType,
    int? videoSizeBytes,
    int? videoDurationMs,
    DateTime? draftSavedAt,
    DateTime? draftCleanupStartedAt,
    DateTime? submittedAt,
    DateTime? videoExpiresAt,
    DateTime? videoDeletedAt,
    bool? deletionFailed,
    DateTime? deletionFailedAt,
    AssignmentReviewVerdict? reviewVerdict,
    String? reviewFeedback,
    DateTime? reviewedAt,
    int? gradeScore,
    int? gradeMaxScore,
    DateTime? checkedAt,
    DateTime? reviewUpdatedAt,
    int? reviewRevision,
    int? resultSentRevision,
    DateTime? resultSentAt,
    String? resultMessageId,
    String? supersedesAttemptId,
    DateTime? abandonedAt,
    DateTime? recordingStartedAt,
    int? assignmentConfigurationRevision,
    TeacherActivityAssessmentConfig? activityAssessmentSnapshot,
    Map<String, int>? criterionScores,
    bool clearVideoStoragePath = false,
    bool clearVideoMetadata = false,
    bool clearDraftSavedAt = false,
    bool clearDraftCleanupStartedAt = false,
    bool clearVideoDeletedAt = false,
    bool clearReviewFeedback = false,
    bool clearReview = false,
    bool clearLegacyReview = false,
    bool clearGrade = false,
    bool clearResultSent = false,
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
      videoStoragePath: clearVideoStoragePath || clearVideoMetadata
          ? null
          : (videoStoragePath ?? this.videoStoragePath),
      videoContentType: clearVideoMetadata
          ? null
          : (videoContentType ?? this.videoContentType),
      videoSizeBytes: clearVideoMetadata
          ? null
          : (videoSizeBytes ?? this.videoSizeBytes),
      videoDurationMs: clearVideoMetadata
          ? null
          : (videoDurationMs ?? this.videoDurationMs),
      draftSavedAt: clearVideoMetadata || clearDraftSavedAt
          ? null
          : (draftSavedAt ?? this.draftSavedAt),
      draftCleanupStartedAt: clearVideoMetadata || clearDraftCleanupStartedAt
          ? null
          : (draftCleanupStartedAt ?? this.draftCleanupStartedAt),
      submittedAt: clearVideoMetadata
          ? null
          : (submittedAt ?? this.submittedAt),
      videoExpiresAt: clearVideoMetadata
          ? null
          : (videoExpiresAt ?? this.videoExpiresAt),
      videoDeletedAt: clearVideoDeletedAt
          ? null
          : (videoDeletedAt ?? this.videoDeletedAt),
      deletionFailed: deletionFailed ?? this.deletionFailed,
      deletionFailedAt: clearDeletionFailedAt
          ? null
          : (deletionFailedAt ?? this.deletionFailedAt),
      reviewVerdict: clearReview || clearLegacyReview
          ? null
          : (reviewVerdict ?? this.reviewVerdict),
      reviewFeedback: clearReview || clearReviewFeedback
          ? null
          : (reviewFeedback ?? this.reviewFeedback),
      reviewedAt: clearReview || clearLegacyReview
          ? null
          : (reviewedAt ?? this.reviewedAt),
      gradeScore: clearGrade ? null : (gradeScore ?? this.gradeScore),
      gradeMaxScore: clearGrade ? null : (gradeMaxScore ?? this.gradeMaxScore),
      checkedAt: clearGrade ? null : (checkedAt ?? this.checkedAt),
      reviewUpdatedAt: clearGrade
          ? null
          : (reviewUpdatedAt ?? this.reviewUpdatedAt),
      reviewRevision: clearGrade
          ? null
          : (reviewRevision ?? this.reviewRevision),
      resultSentRevision: clearResultSent
          ? null
          : (resultSentRevision ?? this.resultSentRevision),
      resultSentAt: clearResultSent
          ? null
          : (resultSentAt ?? this.resultSentAt),
      resultMessageId: clearResultSent
          ? null
          : (resultMessageId ?? this.resultMessageId),
      supersedesAttemptId: supersedesAttemptId ?? this.supersedesAttemptId,
      abandonedAt: abandonedAt ?? this.abandonedAt,
      recordingStartedAt: recordingStartedAt ?? this.recordingStartedAt,
      activityAssessmentSnapshot:
          activityAssessmentSnapshot ?? this.activityAssessmentSnapshot,
      assignmentConfigurationRevision:
          assignmentConfigurationRevision ??
          this.assignmentConfigurationRevision,
      criterionScores: criterionScores ?? this.criterionScores,
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
    final draftSavedAt = TeacherRosterInvite.readDateTime(
      map['draft_saved_at'],
    );
    final draftCleanupStartedAt = TeacherRosterInvite.readDateTime(
      map['draft_cleanup_started_at'],
    );
    final videoExpiresAt = TeacherRosterInvite.readDateTime(
      map['video_expires_at'],
    );
    final videoDeletedAt = TeacherRosterInvite.readDateTime(
      map['video_deleted_at'],
    );
    final reviewedAt = TeacherRosterInvite.readDateTime(map['reviewed_at']);
    final checkedAt = TeacherRosterInvite.readDateTime(map['checked_at']);
    final reviewUpdatedAt = TeacherRosterInvite.readDateTime(
      map['review_updated_at'],
    );
    final resultSentAt = TeacherRosterInvite.readDateTime(
      map['result_sent_at'],
    );
    final deletionFailedAt = TeacherRosterInvite.readDateTime(
      map['deletion_failed_at'],
    );
    final abandonedAt = TeacherRosterInvite.readDateTime(map['abandoned_at']);
    final recordingStartedAt = TeacherRosterInvite.readDateTime(
      map['recording_started_at'],
    );
    final deletionFailed = map['deletion_failed'] == true;
    final videoSizeBytes = _readInt(map['video_size_bytes']);
    final videoDurationMs = _readInt(map['video_duration_ms']);
    final assignmentConfigurationRevision = _readInt(
      map['assignment_configuration_revision'],
    );
    final activityAssessmentSnapshot = TeacherActivityAssessmentConfig.tryFrom(
      map['activity_assessment_snapshot'],
    );
    Map<String, int>? criterionScores;
    if (map.containsKey('criterion_scores')) {
      final rawScores = map['criterion_scores'];
      if (rawScores is! Map) return null;
      criterionScores = {};
      for (final entry in rawScores.entries) {
        if (entry.key is! String || entry.value is! int) return null;
        criterionScores[entry.key as String] = entry.value as int;
      }
    }
    if ((assignmentConfigurationRevision == null) !=
            (activityAssessmentSnapshot == null) ||
        (assignmentConfigurationRevision != null &&
            assignmentConfigurationRevision < 1)) {
      return null;
    }
    final gradeScore = _readInt(map['grade_score']);
    final gradeMaxScore = _readInt(map['grade_max_score']);
    if (activityAssessmentSnapshot != null && criterionScores != null) {
      final criteria = activityAssessmentSnapshot.rubric.criteria;
      final expectedIds = criteria.map((item) => item.id).toSet();
      if (criterionScores.length != expectedIds.length ||
          !criterionScores.keys.toSet().containsAll(expectedIds) ||
          gradeScore == null ||
          gradeMaxScore != activityAssessmentSnapshot.rubric.maximumScore) {
        return null;
      }
      var total = 0;
      for (final criterion in criteria) {
        final score = criterionScores[criterion.id];
        if (score == null || score < 0 || score > criterion.maximumPoints) {
          return null;
        }
        total += score;
      }
      if (total != gradeScore) return null;
    }
    final reviewRevision = _readInt(map['review_revision']);
    final resultSentRevision = _readInt(map['result_sent_revision']);
    final resultMessageId = _readBounded(
      map['result_message_id'],
      maxLength: 256,
    );
    if ((map.containsKey('source_session_id') &&
            map['source_session_id'] != null &&
            sourceSessionId == null) ||
        (map.containsKey('video_storage_path') &&
            map['video_storage_path'] != null &&
            videoStoragePath == null) ||
        (map.containsKey('video_content_type') &&
            map['video_content_type'] != null &&
            videoContentType == null) ||
        (map.containsKey('supersedes_attempt_id') &&
            map['supersedes_attempt_id'] != null &&
            supersedesAttemptId == null)) {
      return null;
    }
    if (map.containsKey('review_verdict') &&
        map['review_verdict'] != null &&
        reviewVerdict == null) {
      return null;
    }
    if ((map.containsKey('grade_score') &&
            map['grade_score'] != null &&
            (map['grade_score'] is! int || gradeScore == null)) ||
        (map.containsKey('grade_max_score') &&
            map['grade_max_score'] != null &&
            (map['grade_max_score'] is! int || gradeMaxScore == null)) ||
        (map.containsKey('review_revision') &&
            map['review_revision'] != null &&
            (map['review_revision'] is! int || reviewRevision == null)) ||
        (map.containsKey('result_sent_revision') &&
            map['result_sent_revision'] != null &&
            (map['result_sent_revision'] is! int ||
                resultSentRevision == null))) {
      return null;
    }
    for (final entry in <String, DateTime?>{
      'submitted_at': submittedAt,
      'draft_saved_at': draftSavedAt,
      'draft_cleanup_started_at': draftCleanupStartedAt,
      'video_expires_at': videoExpiresAt,
      'video_deleted_at': videoDeletedAt,
      'reviewed_at': reviewedAt,
      'checked_at': checkedAt,
      'review_updated_at': reviewUpdatedAt,
      'result_sent_at': resultSentAt,
      'deletion_failed_at': deletionFailedAt,
      'abandoned_at': abandonedAt,
      'recording_started_at': recordingStartedAt,
    }.entries) {
      if (map.containsKey(entry.key) &&
          map[entry.key] != null &&
          entry.value == null) {
        return null;
      }
    }
    if (map.containsKey('deletion_failed') && map['deletion_failed'] is! bool) {
      return null;
    }
    if (map.containsKey('result_message_id') &&
        map['result_message_id'] != null &&
        resultMessageId == null) {
      return null;
    }

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
        draftSavedAt: draftSavedAt,
        draftCleanupStartedAt: draftCleanupStartedAt,
        submittedAt: submittedAt,
        videoExpiresAt: videoExpiresAt,
        videoDeletedAt: videoDeletedAt,
        deletionFailed: deletionFailed,
        abandonedAt: abandonedAt,
        deletionFailedAt: deletionFailedAt,
        gradeScore: gradeScore,
        gradeMaxScore: gradeMaxScore,
        checkedAt: checkedAt,
        reviewUpdatedAt: reviewUpdatedAt,
        reviewRevision: reviewRevision,
        resultSentRevision: resultSentRevision,
        resultSentAt: resultSentAt,
        resultMessageId: resultMessageId,
      )) {
        return null;
      }
      if (isCanonicalTeacherReviewSubmissionId(
            id: id,
            assignmentId: assignmentId,
            traineeId: traineeId,
          ) &&
          supersedesAttemptId != null) {
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
      draftSavedAt: draftSavedAt,
      draftCleanupStartedAt: draftCleanupStartedAt,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
      videoDeletedAt: videoDeletedAt,
      deletionFailed: deletionFailed,
      deletionFailedAt: deletionFailedAt,
      reviewVerdict: reviewVerdict,
      reviewFeedback: reviewFeedback,
      reviewedAt: reviewedAt,
      gradeScore: gradeScore,
      gradeMaxScore: gradeMaxScore,
      checkedAt: checkedAt,
      reviewUpdatedAt: reviewUpdatedAt,
      reviewRevision: reviewRevision,
      resultSentRevision: resultSentRevision,
      resultSentAt: resultSentAt,
      resultMessageId: resultMessageId,
      supersedesAttemptId: supersedesAttemptId,
      abandonedAt: abandonedAt,
      recordingStartedAt: recordingStartedAt,
      assignmentConfigurationRevision: assignmentConfigurationRevision,
      activityAssessmentSnapshot: activityAssessmentSnapshot,
      criterionScores: criterionScores,
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
    required DateTime? draftSavedAt,
    required DateTime? draftCleanupStartedAt,
    required DateTime? submittedAt,
    required DateTime? videoExpiresAt,
    required DateTime? videoDeletedAt,
    required bool deletionFailed,
    required DateTime? abandonedAt,
    required DateTime? deletionFailedAt,
    required int? gradeScore,
    required int? gradeMaxScore,
    required DateTime? checkedAt,
    required DateTime? reviewUpdatedAt,
    required int? reviewRevision,
    required int? resultSentRevision,
    required DateTime? resultSentAt,
    required String? resultMessageId,
  }) {
    switch (status) {
      case AssignmentAttemptStatus.draft:
      case AssignmentAttemptStatus.inProgress:
        if (gradeScore != null ||
            gradeMaxScore != null ||
            checkedAt != null ||
            reviewUpdatedAt != null ||
            reviewRevision != null ||
            resultSentRevision != null ||
            resultSentAt != null ||
            resultMessageId != null) {
          return false;
        }
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
              videoExpiresAt == null &&
              videoDeletedAt == null &&
              !deletionFailed &&
              deletionFailedAt == null;
        }
        final hasDraftClip =
            videoStoragePath != null ||
            videoContentType != null ||
            videoSizeBytes != null ||
            videoDurationMs != null ||
            draftSavedAt != null;
        if (hasDraftClip) {
          return status == AssignmentAttemptStatus.inProgress &&
              draftSavedAt != null &&
              submittedAt == null &&
              videoExpiresAt == null &&
              videoDeletedAt == null &&
              !deletionFailed &&
              deletionFailedAt == null &&
              reviewVerdict == null &&
              reviewFeedback == null &&
              reviewedAt == null &&
              _validDraftVideoMetadata(
                videoStoragePath: videoStoragePath,
                videoContentType: videoContentType,
                videoSizeBytes: videoSizeBytes,
                videoDurationMs: videoDurationMs,
              );
        }
        return reviewVerdict == null &&
            reviewFeedback == null &&
            reviewedAt == null &&
            videoStoragePath == null &&
            videoContentType == null &&
            videoSizeBytes == null &&
            videoDurationMs == null &&
            draftSavedAt == null &&
            draftCleanupStartedAt == null &&
            submittedAt == null &&
            videoExpiresAt == null &&
            videoDeletedAt == null &&
            !deletionFailed &&
            deletionFailedAt == null;
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
            ) &&
            _noNewReviewFields(
              gradeScore: gradeScore,
              gradeMaxScore: gradeMaxScore,
              checkedAt: checkedAt,
              reviewUpdatedAt: reviewUpdatedAt,
              reviewRevision: reviewRevision,
              resultSentRevision: resultSentRevision,
              resultSentAt: resultSentAt,
              resultMessageId: resultMessageId,
              deletionFailedAt: deletionFailedAt,
            );
      case AssignmentAttemptStatus.unsubmitting:
        if (abandonedAt != null ||
            reviewVerdict != null ||
            reviewFeedback != null ||
            reviewedAt != null ||
            gradeScore != null ||
            gradeMaxScore != null ||
            checkedAt != null ||
            reviewUpdatedAt != null ||
            reviewRevision != null ||
            resultSentRevision != null ||
            resultSentAt != null ||
            resultMessageId != null) {
          return false;
        }
        if (!deletionFailed) {
          return deletionFailedAt == null &&
              _validSubmittedVideoMetadata(
                videoStoragePath: videoStoragePath,
                videoContentType: videoContentType,
                videoSizeBytes: videoSizeBytes,
                videoDurationMs: videoDurationMs,
                submittedAt: submittedAt,
                videoExpiresAt: videoExpiresAt,
                videoDeletedAt: videoDeletedAt,
                deletionFailed: false,
              );
        }
        return deletionFailedAt != null &&
            _validSubmittedVideoMetadata(
              videoStoragePath: videoStoragePath,
              videoContentType: videoContentType,
              videoSizeBytes: videoSizeBytes,
              videoDurationMs: videoDurationMs,
              submittedAt: submittedAt,
              videoExpiresAt: videoExpiresAt,
              videoDeletedAt: videoDeletedAt,
              deletionFailed: true,
            );
      case AssignmentAttemptStatus.checked:
        if (abandonedAt != null ||
            reviewVerdict != null ||
            gradeScore == null ||
            gradeMaxScore == null ||
            gradeMaxScore < 1 ||
            gradeMaxScore > 100 ||
            gradeScore < 0 ||
            gradeScore > gradeMaxScore ||
            checkedAt == null ||
            reviewUpdatedAt == null ||
            reviewRevision == null ||
            reviewRevision < 1 ||
            resultSentRevision != null &&
                resultSentRevision != reviewRevision ||
            resultSentRevision != null && resultSentAt == null ||
            resultSentRevision != null && resultMessageId == null ||
            resultSentRevision == null &&
                (resultSentAt != null || resultMessageId != null)) {
          return false;
        }
        return !deletionFailed &&
            _validSubmittedVideoMetadata(
              videoStoragePath: videoStoragePath,
              videoContentType: videoContentType,
              videoSizeBytes: videoSizeBytes,
              videoDurationMs: videoDurationMs,
              submittedAt: submittedAt,
              videoExpiresAt: videoExpiresAt,
              videoDeletedAt: videoDeletedAt,
              deletionFailed: deletionFailed,
            ) &&
            deletionFailedAt == null;
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
            ) &&
            _noNewReviewFields(
              gradeScore: gradeScore,
              gradeMaxScore: gradeMaxScore,
              checkedAt: checkedAt,
              reviewUpdatedAt: reviewUpdatedAt,
              reviewRevision: reviewRevision,
              resultSentRevision: resultSentRevision,
              resultSentAt: resultSentAt,
              resultMessageId: resultMessageId,
              deletionFailedAt: deletionFailedAt,
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
            ) &&
            _noNewReviewFields(
              gradeScore: gradeScore,
              gradeMaxScore: gradeMaxScore,
              checkedAt: checkedAt,
              reviewUpdatedAt: reviewUpdatedAt,
              reviewRevision: reviewRevision,
              resultSentRevision: resultSentRevision,
              resultSentAt: resultSentAt,
              resultMessageId: resultMessageId,
              deletionFailedAt: deletionFailedAt,
            );
    }
  }

  static bool _noNewReviewFields({
    required int? gradeScore,
    required int? gradeMaxScore,
    required DateTime? checkedAt,
    required DateTime? reviewUpdatedAt,
    required int? reviewRevision,
    required int? resultSentRevision,
    required DateTime? resultSentAt,
    required String? resultMessageId,
    required DateTime? deletionFailedAt,
  }) {
    return gradeScore == null &&
        gradeMaxScore == null &&
        checkedAt == null &&
        reviewUpdatedAt == null &&
        reviewRevision == null &&
        resultSentRevision == null &&
        resultSentAt == null &&
        resultMessageId == null &&
        deletionFailedAt == null;
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

  static bool _validDraftVideoMetadata({
    required String? videoStoragePath,
    required String? videoContentType,
    required int? videoSizeBytes,
    required int? videoDurationMs,
  }) {
    return videoStoragePath != null &&
        videoStoragePath.isNotEmpty &&
        videoContentType == AssignmentSubmissionLimits.contentType &&
        videoSizeBytes != null &&
        videoSizeBytes > 0 &&
        videoSizeBytes <= AssignmentSubmissionLimits.maxSizeBytes &&
        videoDurationMs != null &&
        videoDurationMs > 0 &&
        videoDurationMs <= AssignmentSubmissionLimits.maxDurationMs;
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

/// Shared classroom completion semantics.
///
/// Keep this classification in the data layer so teacher roster counts and
/// analytics use the same meaning of "turned in". Draft, in-progress,
/// abandoned, and withdrawal-in-progress attempts are never completed work.
abstract final class AssignmentAttemptSemantics {
  static bool isTurnedIn(AssignmentAttempt? attempt) {
    if (attempt == null || attempt.isAbandonedTeacherReviewDraft) return false;
    switch (attempt.status) {
      case AssignmentAttemptStatus.draft:
      case AssignmentAttemptStatus.inProgress:
      case AssignmentAttemptStatus.unsubmitting:
        return false;
      case AssignmentAttemptStatus.submitted:
      case AssignmentAttemptStatus.checked:
      case AssignmentAttemptStatus.approved:
      case AssignmentAttemptStatus.needsRetry:
        break;
    }

    switch (attempt.attemptKind) {
      case AssignmentAttemptKind.practicePointer:
      case AssignmentAttemptKind.templateScore:
        return true;
      case AssignmentAttemptKind.teacherReviewSubmission:
        return attempt.isReviewFacingSubmission;
      case AssignmentAttemptKind.teacherReviewDraft:
        return false;
    }
  }

  /// Selects the current attempt for one assignment/student pair using the
  /// same canonical-submission preference as the teacher Movements view.
  static AssignmentAttempt? latestVisible({
    required Iterable<AssignmentAttempt> attempts,
    required String assignmentId,
    required String traineeId,
  }) {
    AssignmentAttempt? canonical;
    AssignmentAttempt? latest;
    for (final attempt in attempts) {
      if (attempt.assignmentId != assignmentId ||
          attempt.traineeId != traineeId ||
          attempt.isAbandonedTeacherReviewDraft) {
        continue;
      }
      if (attempt.isCanonicalTeacherReviewSubmission) {
        if (canonical == null || _isLater(attempt, canonical)) {
          canonical = attempt;
        }
        continue;
      }
      if (latest == null || _isLater(attempt, latest)) {
        latest = attempt;
      }
    }
    return canonical ?? latest;
  }

  static bool _isLater(AssignmentAttempt candidate, AssignmentAttempt other) {
    final candidateAt =
        candidate.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final otherAt = other.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return candidateAt.isAfter(otherAt) ||
        (candidateAt.isAtSameMomentAs(otherAt) &&
            candidate.id.compareTo(other.id) > 0);
  }
}

/// Convenience function for callers that do not need the namespace.
bool isAssignmentAttemptTurnedIn(AssignmentAttempt? attempt) =>
    AssignmentAttemptSemantics.isTurnedIn(attempt);
