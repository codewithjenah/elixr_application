import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/session_assignment_context.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

const _rubric = RubricAssessment(
  technique: 3,
  stability: 2,
  completion: 3,
  propPositioning: 2,
);

void main() {
  test('old records without prop_type default to Bottle', () {
    final session = Session.fromMap({
      'id': 'session-old',
      'user_id': 'user-1',
      'movement_name': 'Hand Stall',
      'difficulty': 'Medium',
      'score': 80,
      'duration_seconds': 30,
      'created_at': null,
    });

    expect(session.propType, TrainingProp.bottle);
    expect(session.toMap()['prop_type'], 'bottle');
  });

  test('legacy records expose legacyScore and no rubric', () {
    final session = Session.fromMap({
      'id': 'session-legacy',
      'user_id': 'user-1',
      'movement_name': 'Hand Stall',
      'difficulty': 'Medium',
      'score': 80,
      'duration_seconds': 30,
      'created_at': null,
    });

    expect(session.assessmentVersion, 1);
    expect(session.isRubricAssessed, isFalse);
    expect(session.legacyScore, 80);
    expect(session.rubricTotal, isNull);
    expect(session.performanceLevel, isNull);
  });

  test('rubric sessions expose total and performance level', () {
    const session = Session(
      id: 'session-rubric',
      userId: 'user-1',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      rubric: _rubric,
      assessmentVersion: 2,
      durationSeconds: 45,
    );

    expect(session.isRubricAssessed, isTrue);
    expect(session.rubricTotal, 10);
    expect(session.performanceLevel, PerformanceLevel.proficient);
    expect(session.legacyScore, isNull);

    final round = Session.fromMap(session.toMap());
    expect(round.isRubricAssessed, isTrue);
    expect(round.rubricTotal, 10);
    expect(round.assessmentVersion, 2);
  });

  test('shaker sessions serialize and deserialize prop_type', () {
    const session = Session(
      id: 'session-shaker',
      userId: 'user-1',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      rubric: _rubric,
      assessmentVersion: 2,
      durationSeconds: 45,
      propType: TrainingProp.shaker,
    );

    expect(session.toMap()['prop_type'], 'shaker');
    expect(Session.fromMap(session.toMap()).propType, TrainingProp.shaker);
  });

  test('custom movement identity round-trips with shared history sessions', () {
    const session = Session(
      id: 'custom-session-1',
      userId: 'user-1',
      movementName: 'My custom movement',
      difficulty: 'Easy',
      legacyScore: 84,
      assessmentVersion: 1,
      durationSeconds: 28,
      customMovementId: 'movement-1',
      customMovementRevisionId: 'revision-1',
      referenceImageStoragePath:
          'users/user-1/custom_movement_references/movement-1_revision-1.jpg',
    );

    final roundTrip = Session.fromMap(session.toMap());
    expect(roundTrip.legacyScore, 84);
    expect(roundTrip.customMovementId, 'movement-1');
    expect(roundTrip.customMovementRevisionId, 'revision-1');
    expect(
      roundTrip.referenceImageStoragePath,
      'users/user-1/custom_movement_references/movement-1_revision-1.jpg',
    );
  });

  test(
    'assignment_context round-trips and stays absent for ordinary practice',
    () {
      const context = SessionAssignmentContext(
        assignmentId: 'asg1',
        groupId: 'g1',
        teacherId: 't1',
        movementId: 'official_hand_stall',
        revisionId: 'official_hand_stall_v1',
      );
      const assigned = Session(
        id: 'session-assigned',
        userId: 'user-1',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        assessmentVersion: 2,
        durationSeconds: 45,
        assignmentContext: context,
      );
      final round = Session.fromMap(assigned.toMap());
      expect(round.assignmentContext, context);

      const ordinary = Session(
        id: 'session-ordinary',
        userId: 'user-1',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        assessmentVersion: 2,
        durationSeconds: 45,
      );
      expect(ordinary.toMap().containsKey('assignment_context'), isFalse);
      expect(Session.fromMap(ordinary.toMap()).assignmentContext, isNull);
    },
  );
}
