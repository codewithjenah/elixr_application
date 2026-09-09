import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_core/models/rubric_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _canonical({
  String origin = 'teacher_created',
  String assessmentMode = 'template_scored',
  String status = 'submitted',
  Object awardsGlobalXp = false,
  Object? sourceSessionId,
  bool includeRubric = true,
  Object? completedAt,
  String propType = 'bottle',
  Map<String, dynamic>? extra,
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
    'attempt_kind': 'template_score',
    'status': status,
    'awards_global_xp': awardsGlobalXp,
    'source_session_id': ?sourceSessionId,
    if (includeRubric) ...{
      'assessment_version': 2,
      'rubric': {
        'technique': 3,
        'stability': 2,
        'completion': 3,
        'prop_positioning': 2,
      },
      'rubric_total': 10,
      'performance_level': 'proficient',
    },
    'duration_seconds': 12,
    'prop_type': propType,
    'completed_at': completedAt ?? DateTime.utc(2026, 8, 22),
    ...?extra,
  };
}

void main() {
  test('canonical template_score parses', () {
    final attempt = AssignmentAttempt.tryFromMap(
      _canonical(),
      id: 'template_score_abc',
    );
    expect(attempt, isNotNull);
    expect(attempt!.attemptKind, AssignmentAttemptKind.templateScore);
    expect(attempt.origin, MovementOrigin.teacherCreated);
    expect(attempt.assessmentMode, AssessmentMode.templateScored);
    expect(attempt.status, AssignmentAttemptStatus.submitted);
    expect(attempt.awardsGlobalXp, isFalse);
    expect(attempt.sourceSessionId, isNull);
    expect(attempt.rubric, isNotNull);
    expect(attempt.rubricTotal, 10);
    expect(attempt.performanceLevel, PerformanceLevel.proficient);
    expect(attempt.propType, TrainingProp.bottle);
    expect(attempt.completedAt, DateTime.utc(2026, 8, 22));
    expect(attempt.videoStoragePath, isNull);
    expect(attempt.reviewVerdict, isNull);
  });

  test('template_score requires rubric', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(includeRubric: false),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score requires submitted', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(status: 'draft'),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score requires template_scored', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(assessmentMode: 'teacher_reviewed'),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score requires teacher_created', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(origin: 'official_elixr'),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score awards true rejected', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(awardsGlobalXp: true),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score missing completedAt rejected', () {
    final map = _canonical();
    map.remove('completed_at');
    expect(AssignmentAttempt.tryFromMap(map, id: 'template_score_abc'), isNull);
  });

  test('template_score wrong prop rejected', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(propType: 'shaker'),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score video fields rejected', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(
          extra: {
            'video_storage_path': 'assignment_submissions/x.mp4',
            'video_content_type': 'video/mp4',
          },
        ),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score review fields rejected', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(
          extra: {'review_verdict': 'approved', 'review_feedback': 'Nice.'},
        ),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });

  test('template_score sourceSessionId rejected', () {
    expect(
      AssignmentAttempt.tryFromMap(
        _canonical(sourceSessionId: 'sess-1'),
        id: 'template_score_abc',
      ),
      isNull,
    );
  });
}
