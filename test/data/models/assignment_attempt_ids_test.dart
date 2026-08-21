import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official pointer id is derived only from sessionId', () {
    expect(
      assignmentAttemptIdForOfficialSession('sessA'),
      'official_ptr_sessA',
    );
  });

  test('teacher-created first attempt id is assignment+trainee', () {
    expect(
      assignmentAttemptIdForTeacherCreatedDraft(
        assignmentId: 'asg1',
        traineeId: 'trainee-1',
      ),
      'tc_draft_asg1_trainee-1',
    );
  });

  test('review submission ids use review_sub_ and alphanumeric entropy', () {
    expect(
      assignmentAttemptIdForTeacherReviewSubmission('abc123'),
      'review_sub_abc123',
    );
    expect(
      () => assignmentAttemptIdForTeacherReviewSubmission('ada@x.com'),
      throwsArgumentError,
    );
    final generated = newTeacherReviewSubmissionAttemptId(
      entropy: () => 'Token42',
    );
    expect(generated, 'review_sub_Token42');
  });
}
