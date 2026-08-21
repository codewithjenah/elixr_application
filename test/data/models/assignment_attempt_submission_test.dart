import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _draft({
  Object? awardsGlobalXp = false,
  String? sourceSessionId,
  String status = 'draft',
}) {
  return {
    'trainee_id': 'trainee-1',
    'teacher_id': 'teacher-1',
    'group_id': 'g1',
    'assignment_id': 'asg1',
    'movement_id': 'tm1',
    'revision_id': 'rev1',
    'origin': MovementOrigin.teacherCreated.wireValue,
    'assessment_mode': AssessmentMode.teacherReviewed.wireValue,
    'attempt_kind': AssignmentAttemptKind.teacherReviewSubmission.wireValue,
    'status': status,
    'awards_global_xp': awardsGlobalXp,
    'source_session_id': ?sourceSessionId,
  };
}

void main() {
  test('teacher_review_submission draft parses without video or XP', () {
    final attempt = AssignmentAttempt.tryFromMap(_draft(), id: 'review_sub_a');
    expect(attempt, isNotNull);
    expect(attempt!.awardsGlobalXp, isFalse);
    expect(attempt.sourceSessionId, isNull);
  });

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
}
