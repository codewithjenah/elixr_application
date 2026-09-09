import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:elixr_application/features/assigned_movements/template_scored_practice_screen.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'template-scored assignment opens automatic practice, not Teacher Review recording',
    (tester) async {
      final auth =
          AuthService(
            repository: _UnusedAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            const User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      final assignments = InMemoryClassroomAssignmentRepository();
      final groups = InMemoryGroupRepository();
      addTearDown(() {
        auth.dispose();
        assignments.dispose();
        groups.dispose();
      });

      assignments.assignments['template-assignment'] = const GroupAssignment(
        id: 'template-assignment',
        teacherId: 'teacher-1',
        groupId: 'group-1',
        movementId: 'movement-1',
        revisionId: 'revision-1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.templateScored,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Classroom Wrist Stall',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        allowedProp: TrainingProp.bottle,
        assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.left),
      );
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(
            groupId: 'group-1',
            traineeId: 'trainee-1',
          ),
          groupId: 'group-1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            Provider<GroupRepository>.value(value: groups),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const SizedBox(
              width: 1200,
              height: 800,
              child: AssignedPracticeScreen(
                assignmentId: 'template-assignment',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(TemplateScoredPracticeScreen), findsOneWidget);
      expect(find.byType(LivePracticeScreen), findsNothing);
      expect(find.text('Automatic ELIXR Assessment'), findsOneWidget);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Left wrist'), findsOneWidget);
      expect(find.text('Start Activity'), findsOneWidget);
      expect(
        find.textContaining('Automatic template assessment has been retired'),
        findsNothing,
      );
    },
  );

  group('assignedPracticeReservationFailureMessage', () {
    test(
      'maps exhausted, graded, overdue, forbidden, and recovery failures',
      () {
        expect(
          assignedPracticeReservationFailureMessage(
            const ClassroomException.fromFunction(
              ClassroomError.attemptLimitConflict,
              httpStatus: 409,
              serverCode: 'attempts_exhausted',
            ),
          ),
          'This Teacher Activity has no remaining recordings.',
        );
        expect(
          assignedPracticeReservationFailureMessage(
            const ClassroomException.fromFunction(
              ClassroomError.invalidState,
              httpStatus: 409,
              serverCode: 'graded',
            ),
          ),
          'This Teacher Activity has already been graded.',
        );
        expect(
          assignedPracticeReservationFailureMessage(
            const ClassroomException.fromFunction(
              ClassroomError.deadlinePassed,
              httpStatus: 409,
              serverCode: 'deadline_passed',
            ),
          ),
          'This Teacher Activity is past its deadline.',
        );
        expect(
          assignedPracticeReservationFailureMessage(
            const ClassroomException.fromFunction(
              ClassroomError.forbidden,
              httpStatus: 403,
              serverCode: 'forbidden',
            ),
          ),
          contains('no longer have permission'),
        );
        expect(
          assignedPracticeReservationFailureMessage(
            const ClassroomException.fromFunction(
              ClassroomError.conflict,
              httpStatus: 409,
              serverCode: 'attempt_in_progress',
            ),
          ),
          contains('could not recover'),
        );
      },
    );

    test('does not disguise backend unavailability as an attempt limit', () {
      final message = assignedPracticeReservationFailureMessage(
        const ClassroomException.fromFunction(
          ClassroomError.invalidState,
          httpStatus: 503,
          serverCode: 'unavailable',
        ),
      );
      expect(message, contains('unavailable'));
      expect(message, isNot(contains('another recording')));
      expect(message, isNot(contains('no remaining recordings')));
    });

    test('network failures stay generic instead of attempt-limit wording', () {
      final message = assignedPracticeReservationFailureMessage(
        const ClassroomException(ClassroomError.invalidState),
      );
      expect(message, 'Could not open this Teacher Activity. Try again.');
      expect(message, isNot(contains('another recording')));
    });
  });

  testWidgets(
    'backend unavailability is not shown as another recording unavailable',
    (tester) async {
      final auth =
          AuthService(
            repository: _UnusedAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            const User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      final assignments = _UnavailableActivityClassroom();
      final groups = InMemoryGroupRepository();
      addTearDown(() {
        auth.dispose();
        assignments.dispose();
        groups.dispose();
      });
      assignments.assignments['activity-1'] = _activityAssignment();
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
          groupId: 'g1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            Provider<GroupRepository>.value(value: groups),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const SizedBox(
              width: 1200,
              height: 800,
              child: AssignedPracticeScreen(assignmentId: 'activity-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('classroom service is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('another recording'), findsNothing);
      expect(find.byType(LivePracticeScreen), findsNothing);
    },
  );

  testWidgets(
    'exhausted Teacher Activity reservations show remaining-recording copy',
    (tester) async {
      final auth =
          AuthService(
            repository: _UnusedAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            const User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      final assignments = InMemoryClassroomAssignmentRepository();
      final groups = InMemoryGroupRepository();
      addTearDown(() {
        auth.dispose();
        assignments.dispose();
        groups.dispose();
      });
      final assignment = _activityAssignment();
      assignments.assignments[assignment.id] = assignment;
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
          groupId: 'g1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );
      for (var index = 0; index < 2; index++) {
        final reserved = await assignments.reserveTeacherActivityAttempt(
          traineeId: 'trainee-1',
          assignment: assignment,
          requestId: 'activity-open-$index',
        );
        await assignments.consumeTeacherActivityAttempt(
          traineeId: 'trainee-1',
          attempt: reserved,
        );
        await assignments.abandonTeacherActivityAttempt(
          traineeId: 'trainee-1',
          attempt: reserved,
        );
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            Provider<GroupRepository>.value(value: groups),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const SizedBox(
              width: 1200,
              height: 800,
              child: AssignedPracticeScreen(assignmentId: 'activity-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('no remaining recordings'), findsOneWidget);
      expect(find.textContaining('another recording'), findsNothing);
      expect(find.byType(LivePracticeScreen), findsNothing);
    },
  );
}

const _activityAssessment = TeacherActivityAssessmentConfig(
  readiness: TeacherActivityReadinessSpec(
    hands: ActivityHandRequirement.twoHands,
    body: ActivityBodyRequirement.upperBody,
  ),
  rubric: TeacherActivityRubric(
    template: TeacherActivityRubricTemplate.beginnerFundamentals,
    maximumScore: 30,
    criteria: [
      TeacherActivityRubricCriterion(
        id: 'setup',
        label: 'Setup',
        description: 'Start prepared.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'control',
        label: 'Control',
        description: 'Keep the bottle controlled.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'finish',
        label: 'Finish',
        description: 'Finish safely.',
        maximumPoints: 10,
      ),
    ],
  ),
  recordingDurationSeconds: 45,
);

GroupAssignment _activityAssignment() {
  return const GroupAssignment(
    id: 'activity-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Bottle Control Activity',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    allowedProp: TrainingProp.bottle,
    maxScore: 30,
    activityAssessment: _activityAssessment,
    attemptPolicy: AssignmentAttemptPolicy.finite(2),
  );
}

class _UnavailableActivityClassroom
    extends InMemoryClassroomAssignmentRepository {
  @override
  Future<AssignmentAttempt> reserveTeacherActivityAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required String requestId,
  }) async {
    throw const ClassroomException.fromFunction(
      ClassroomError.invalidState,
      httpStatus: 503,
      serverCode: 'unavailable',
    );
  }
}
