import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_practice_screen.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

class _UnusedCustomMovements extends Fake implements CustomMovementRepository {}

class _RouteSettings extends SettingsService {
  @override
  bool get cameraMirrored => true;

  @override
  int? get pendingLegacyCameraIndex => null;

  @override
  Future<String?> loadSelectedCameraDeviceId() async => null;
}

class _RouteSocket extends WebSocketService {
  final stopGate = Completer<CommandAck>();
  int stopCalls = 0;

  CommandAck _ack(String action) => CommandAck(
    protocolVersion: 1,
    requestId: 'route-$action',
    action: action,
    accepted: true,
    sessionId: 'route-session',
    sessionState: action == 'stop' ? 'idle' : 'readying',
  );

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  String beginPracticeAttempt() => 'route-session';

  @override
  Future<CommandAck> sendPrepare({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    String? sessionId,
    bool allowSubmissionRecording = false,
    TeacherActivityReadinessSpec? readinessSpec,
    String? sessionMode,
    List<({String movement, TrainingProp prop})>? allowedMovements,
    Map<String, dynamic>? customMovementTemplate,
  }) async => _ack('prepare');

  @override
  Future<CommandAck> sendBeginReadiness({String? sessionId}) async =>
      _ack('begin_readiness');

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    stopCalls++;
    return stopGate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'assigned Custom Movement Back returns to its exact detail route',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final settings = _RouteSettings();
      final socket = _RouteSocket();
      final assignment = GroupAssignment(
        id: 'assigned-reference-1',
        teacherId: 'teacher-1',
        groupId: 'group-1',
        movementId: 'movement-1',
        revisionId: 'revision-1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.referenceMatched,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Assigned Cascade',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        allowedProp: TrainingProp.bottle,
        attemptPolicy: const AssignmentAttemptPolicy.finite(2),
        movementTemplate: MovementTemplate.tryFrom({
          'schema_version': 1,
          'capture_version': 1,
          'duration_ms': 900,
          'reference_count': 3,
          'required_modalities': ['hands', 'prop_translation'],
          'normalization_metadata': {
            'anchor': 'shoulder_midpoint',
            'scale': 'shoulder_width',
            'mirrored': false,
          },
          'feature_capabilities': {
            'pose': false,
            'hands': true,
            'prop_translation': true,
            'release_catch': false,
            'prop_rotation': false,
            'left_hand': true,
            'right_hand': false,
          },
          'canonical_sequence': [
            {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
            {'timestamp_ms': 900, 'pose': <String, dynamic>{}},
          ],
          'variability_metadata': {'duration_std_ms': 0.0},
          'prop_events': <Map<String, dynamic>>[],
        })!,
      );
      assignments.assignments[assignment.id] = assignment;
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(
            groupId: assignment.groupId,
            traineeId: 'trainee-1',
          ),
          groupId: assignment.groupId,
          teacherId: assignment.teacherId,
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );
      final detailPath = AppRoutePaths.assignmentDetail(assignment.id);
      final router = GoRouter(
        initialLocation: AppRoutePaths.assignedPractice(assignment.id),
        routes: [
          GoRoute(
            path: '${AppRoutePaths.assignedPracticePrefix}/:assignmentId',
            builder: (_, state) => AssignedPracticeScreen(
              assignmentId: state.pathParameters['assignmentId']!,
              customMovementWebSocket: socket,
            ),
          ),
          GoRoute(
            path: '${AppRoutePaths.assignedMovements}/:assignmentId',
            builder: (_, state) => Text(
              'assignment detail:${state.pathParameters['assignmentId']}',
            ),
          ),
        ],
      );
      addTearDown(() {
        router.dispose();
        socket.dispose();
        settings.dispose();
        auth.dispose();
        assignments.dispose();
        groups.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            Provider<GroupRepository>.value(value: groups),
            Provider<CustomMovementRepository>.value(
              value: _UnusedCustomMovements(),
            ),
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<CameraDeviceService>(
              create: (_) =>
                  CameraDeviceService(httpGet: (_) async => '{"cameras":[]}'),
            ),
          ],
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CustomMovementPracticeScreen), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.assignedPractice(assignment.id),
      );

      final back = find.byKey(const ValueKey('training-header-back'));
      await tester.tap(back);
      await tester.pump();
      await tester.tap(back);
      expect(socket.stopCalls, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, detailPath);
      expect(find.text('assignment detail:${assignment.id}'), findsOneWidget);
      expect(socket.stopCalls, 1);
    },
  );

  testWidgets(
    'historical template assignment stays read-only and never opens the camera',
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

      assignments.assignments['retired-assignment'] = const GroupAssignment(
        id: 'retired-assignment',
        teacherId: 'teacher-1',
        groupId: 'group-1',
        movementId: 'movement-1',
        revisionId: 'revision-1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.templateScored,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Historical Wrist Stall',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        allowedProp: TrainingProp.bottle,
        assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.either),
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
              child: AssignedPracticeScreen(assignmentId: 'retired-assignment'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Automatic template assessment has been retired'),
        findsOneWidget,
      );
      expect(find.byType(LivePracticeScreen), findsNothing);
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
        await assignments.markTeacherReviewSubmitted(
          traineeId: 'trainee-1',
          attempt: reserved,
          videoStoragePath:
              'assignment_submissions/teacher-1/g1/activity-1/trainee-1/${reserved.id}.mp4',
          videoContentType: 'video/mp4',
          videoSizeBytes: 1024,
          videoDurationMs: 1000,
          submittedAt: DateTime.utc(2026, 9, 8, 12),
          videoExpiresAt: DateTime.utc(2026, 9, 15, 12),
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
