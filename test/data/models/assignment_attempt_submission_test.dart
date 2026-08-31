import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _identity({
  String origin = 'teacher_created',
  String assessmentMode = 'teacher_reviewed',
}) {
  return {
    'trainee_id': 'trainee-1',
    'teacher_id': 'teacher-1',
    'group_id': 'g1',
    'assignment_id': 'asg1',
    'movement_id': 'tm1',
    'revision_id': 'rev1',
    'origin': origin,
    'assessment_mode': assessmentMode,
    'awards_global_xp': false,
  };
}

Map<String, dynamic> _draft({
  Object? awardsGlobalXp = false,
  String? sourceSessionId,
  String status = 'draft',
  Map<String, dynamic>? extra,
}) {
  return {
    ..._identity(),
    'attempt_kind': AssignmentAttemptKind.teacherReviewSubmission.wireValue,
    'status': status,
    'awards_global_xp': awardsGlobalXp,
    'source_session_id': ?sourceSessionId,
    ...?extra,
  };
}

Map<String, dynamic> _submitted({
  String status = 'submitted',
  String? path =
      'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_a.mp4',
  String contentType = 'video/mp4',
  int sizeBytes = 2048,
  int durationMs = 4000,
  Object? submittedAt,
  Object? expiresAt,
  Object? deletedAt,
  bool deletionFailed = false,
  String? verdict,
  String? feedback,
  Object? reviewedAt,
  Map<String, dynamic>? extra,
}) {
  final map = <String, dynamic>{
    ..._identity(),
    'attempt_kind': AssignmentAttemptKind.teacherReviewSubmission.wireValue,
    'status': status,
    'video_content_type': contentType,
    'video_size_bytes': sizeBytes,
    'video_duration_ms': durationMs,
    'submitted_at': submittedAt ?? DateTime.utc(2026, 8, 20),
    'video_expires_at': expiresAt ?? DateTime.utc(2026, 9, 19),
    'deletion_failed': deletionFailed,
  };
  if (path != null) map['video_storage_path'] = path;
  if (deletedAt != null) map['video_deleted_at'] = deletedAt;
  if (verdict != null) map['review_verdict'] = verdict;
  if (feedback != null) map['review_feedback'] = feedback;
  if (reviewedAt != null) map['reviewed_at'] = reviewedAt;
  map.addAll(extra ?? const {});
  return map;
}

void main() {
  test('teacher_review_submission draft parses without video or XP', () {
    final attempt = AssignmentAttempt.tryFromMap(_draft(), id: 'review_sub_a');
    expect(attempt, isNotNull);
    expect(attempt!.awardsGlobalXp, isFalse);
    expect(attempt.sourceSessionId, isNull);
    expect(attempt.isReviewFacingSubmission, isFalse);
    expect(attempt.isAbandonedTeacherReviewDraft, isFalse);
  });

  test(
    'abandoned teacher_review_submission draft remains an authorization anchor',
    () {
      final attempt = AssignmentAttempt.tryFromMap(
        _draft(extra: {'abandoned_at': DateTime.utc(2026, 8, 21)}),
        id: 'review_sub_a',
      );
      expect(attempt, isNotNull);
      expect(attempt!.isAbandonedTeacherReviewDraft, isTrue);
      expect(attempt.isReviewFacingSubmission, isFalse);
      expect(attempt.status, AssignmentAttemptStatus.draft);
      expect(attempt.awardsGlobalXp, isFalse);
      expect(attempt.sourceSessionId, isNull);

      expect(
        AssignmentAttempt.tryFromMap(
          _draft(
            extra: {
              'abandoned_at': DateTime.utc(2026, 8, 21),
              'submitted_at': DateTime.utc(2026, 8, 21),
            },
          ),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _draft(
            extra: {
              'abandoned_at': DateTime.utc(2026, 8, 21),
              'review_verdict': 'approved',
            },
          ),
          id: 'review_sub_a',
        ),
        isNull,
      );
    },
  );

  test('malformed review submissions fail closed', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _draft(awardsGlobalXp: true),
        id: 'review_sub_a',
      ),
      isNull,
    );
    expect(
      AssignmentAttempt.tryFromMap(
        _draft(sourceSessionId: 'sess-1'),
        id: 'review_sub_a',
      ),
      isNull,
    );
    expect(
      AssignmentAttempt.tryFromMap(
        _draft(status: 'approved'),
        id: 'review_sub_a',
      ),
      isNull,
    );
  });

  test(
    'draft or in_progress review submissions reject video and review fields',
    () {
      expect(
        AssignmentAttempt.tryFromMap(
          _draft(extra: {'video_storage_path': 'assignment_submissions/x.mp4'}),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _draft(extra: {'submitted_at': DateTime.utc(2026, 8, 20)}),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _draft(
            status: 'in_progress',
            extra: {'video_expires_at': DateTime.utc(2026, 9, 19)},
          ),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _draft(extra: {'review_verdict': 'approved'}),
          id: 'review_sub_a',
        ),
        isNull,
      );
    },
  );

  test('canonical in-progress work can hold one private attached clip', () {
    final attempt = AssignmentAttempt.tryFromMap(
      _draft(
        status: 'in_progress',
        extra: {
          'video_storage_path':
              'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_asg1_trainee-1.mp4',
          'video_content_type': 'video/mp4',
          'video_size_bytes': 2048,
          'video_duration_ms': 4000,
          'draft_saved_at': DateTime.utc(2026, 8, 31),
        },
      ),
      id: 'review_sub_asg1_trainee-1',
    );
    expect(attempt, isNotNull);
    expect(attempt!.hasAttachedDraftClip, isTrue);
    expect(AssignmentAttemptSemantics.isTurnedIn(attempt), isFalse);
  });

  test(
    'submitted review requires bounded mp4 metadata and no review fields',
    () {
      final attempt = AssignmentAttempt.tryFromMap(
        _submitted(),
        id: 'review_sub_a',
      );
      expect(attempt, isNotNull);
      expect(attempt!.isReviewFacingSubmission, isTrue);
      expect(attempt.hasPlayableVideo, isTrue);

      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(contentType: 'video/webm'),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(sizeBytes: 0),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(durationMs: 20001),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(submittedAt: null)..remove('submitted_at'),
          id: 'review_sub_a',
        ),
        isNull,
      );
      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(
            verdict: 'approved',
            reviewedAt: DateTime.utc(2026, 8, 21),
          ),
          id: 'review_sub_a',
        ),
        isNull,
      );
    },
  );

  test('approved and needs_retry require matching verdict and reviewed_at', () {
    final approved = AssignmentAttempt.tryFromMap(
      _submitted(
        status: 'approved',
        verdict: 'approved',
        reviewedAt: DateTime.utc(2026, 8, 21),
        feedback: 'Nice tin balance.',
      ),
      id: 'review_sub_a',
    );
    expect(approved, isNotNull);
    expect(approved!.reviewVerdict, AssignmentReviewVerdict.approved);

    final retry = AssignmentAttempt.tryFromMap(
      _submitted(
        status: 'needs_retry',
        verdict: 'needs_retry',
        reviewedAt: DateTime.utc(2026, 8, 21),
      ),
      id: 'review_sub_a',
    );
    expect(retry, isNotNull);

    expect(
      AssignmentAttempt.tryFromMap(
        _submitted(
          status: 'approved',
          verdict: 'needs_retry',
          reviewedAt: DateTime.utc(2026, 8, 21),
        ),
        id: 'review_sub_a',
      ),
      isNull,
    );
    expect(
      AssignmentAttempt.tryFromMap(
        _submitted(status: 'approved', verdict: 'approved'),
        id: 'review_sub_a',
      ),
      isNull,
    );
  });

  test('deletion metadata is consistent for playable vs cleaned clips', () {
    final cleaned = AssignmentAttempt.tryFromMap(
      _submitted(path: null, deletedAt: DateTime.utc(2026, 9, 1)),
      id: 'review_sub_a',
    );
    expect(cleaned, isNotNull);
    expect(cleaned!.hasPlayableVideo, isFalse);

    final failedDelete = AssignmentAttempt.tryFromMap(
      _submitted(deletionFailed: true),
      id: 'review_sub_a',
    );
    expect(failedDelete, isNotNull);
    expect(failedDelete!.hasPlayableVideo, isTrue);

    expect(
      AssignmentAttempt.tryFromMap(
        _submitted(path: null, deletionFailed: true),
        id: 'review_sub_a',
      ),
      isNull,
    );
    expect(
      AssignmentAttempt.tryFromMap(
        _submitted(deletedAt: DateTime.utc(2026, 9, 1)),
        id: 'review_sub_a',
      ),
      isNull,
    );
  });

  test('checked review parses bounded grade and revision result metadata', () {
    final checked = AssignmentAttempt.tryFromMap(
      _submitted(
        status: 'checked',
        path: null,
        deletedAt: DateTime.utc(2026, 9, 1),
        extra: {
          'grade_score': 75,
          'grade_max_score': 80,
          'checked_at': DateTime.utc(2026, 8, 21),
          'review_updated_at': DateTime.utc(2026, 8, 22),
          'review_revision': 2,
          'result_sent_revision': 2,
          'result_sent_at': DateTime.utc(2026, 8, 22, 1),
          'result_message_id': 'message-2',
          'review_feedback': 'Good control.',
        },
      ),
      id: 'review_sub_a',
    );

    expect(checked, isNotNull);
    expect(checked!.isChecked, isTrue);
    expect(checked.hasNewReview, isTrue);
    expect(checked.gradeScore, 75);
    expect(checked.gradeMaxScore, 80);
    expect(checked.reviewRevision, 2);
    expect(checked.resultSentForCurrentRevision, isTrue);
    expect(checked.hasPlayableVideo, isFalse);

    for (final entry in [
      {'grade_score': 81, 'grade_max_score': 80},
      {'grade_score': 75, 'grade_max_score': 0},
      {'grade_score': 75, 'grade_max_score': 80, 'review_revision': 0},
      {
        'grade_score': 75,
        'grade_max_score': 80,
        'review_revision': 2,
        'result_sent_revision': 1,
      },
    ]) {
      expect(
        AssignmentAttempt.tryFromMap(
          _submitted(
            status: 'checked',
            extra: {
              ...entry,
              'checked_at': DateTime.utc(2026, 8, 21),
              'review_updated_at': DateTime.utc(2026, 8, 22),
            },
          ),
          id: 'review_sub_a',
        ),
        isNull,
      );
    }
  });

  test('practice_pointer and teacher_review_draft still parse', () {
    final pointer = AssignmentAttempt.tryFromMap({
      ..._identity(
        origin: MovementOrigin.officialElixr.wireValue,
        assessmentMode: AssessmentMode.officialGuided.wireValue,
      ),
      'attempt_kind': AssignmentAttemptKind.practicePointer.wireValue,
      'status': 'submitted',
      'source_session_id': 'sess-1',
    }, id: 'official_ptr_sess-1');
    expect(pointer, isNotNull);
    expect(pointer!.attemptKind, AssignmentAttemptKind.practicePointer);

    final draft = AssignmentAttempt.tryFromMap({
      ..._identity(),
      'attempt_kind': AssignmentAttemptKind.teacherReviewDraft.wireValue,
      'status': 'in_progress',
    }, id: 'tc_draft_asg1_trainee-1');
    expect(draft, isNotNull);
    expect(draft!.attemptKind, AssignmentAttemptKind.teacherReviewDraft);
  });
}
