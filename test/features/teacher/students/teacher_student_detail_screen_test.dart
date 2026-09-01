import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_detail_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late FakeTeacherLinksRepository links;
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late AuthService auth;
  late InMemoryClassroomAssignmentRepository assignments;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    links = FakeTeacherLinksRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    auth = phase3TeacherAuth();
    assignments = InMemoryClassroomAssignmentRepository();
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
    assignments.dispose();
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    String? preferredGroupId,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherStudentDetail(
        'trainee',
        groupId: preferredGroupId,
      ),
      routes: [
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (context, state) => TeacherStudentDetailScreen(
            traineeId: state.pathParameters['traineeId'] ?? '',
            preferredGroupId: state.uri.queryParameters['groupId'],
          ),
        ),
        GoRoute(
          path: '/teacher/profile/:userId',
          builder: (context, state) =>
              Text('profile:${state.pathParameters['userId']}'),
        ),
        GoRoute(
          path: AppRoutePaths.teacherStudents,
          builder: (context, state) => const Text('students home'),
        ),
        GoRoute(
          path: AppRoutePaths.teacherMessages,
          builder: (context, state) => const Text('messages'),
        ),
        GoRoute(
          path: '${AppRoutePaths.teacherGroups}/:groupId',
          builder: (context, state) =>
              Text('classroom:${state.pathParameters['groupId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<TeacherRelationshipRepository>.value(value: links),
          Provider<TeacherProgressRepository>.value(value: progress),
          Provider<PublicProfileRepository>.value(value: profiles),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'approved classroom membership loads progress without legacy consent',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      await pumpDetail(tester);
      await tester.pump();

      expect(find.text('No history yet'), findsOneWidget);
      expect(
        find.textContaining('Classroom membership is required'),
        findsNothing,
      );
      expect(find.text('Not authorized'), findsNothing);
      expect(find.textContaining('Profile locked'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
    },
  );

  testWidgets(
    'private profile badge stays visible while consented progress remains available',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
          traineeName: 'Ada Lovelace',
        ),
      );
      progress.inner.setSummary('trainee', sampleSummary());
      progress.inner.sessions['trainee'] = [sampleSession()];
      await pumpDetail(tester);
      profiles.emitProfile(
        'trainee',
        const PublicProfile(
          userId: 'trainee',
          displayName: 'Ada Lovelace',
          visibility: ProfileVisibility.private,
        ),
      );
      await tester.pump();

      expect(find.text('Ada Lovelace'), findsWidgets);
      expect(find.text('Profile locked'), findsOneWidget);
      expect(find.text('Recent History'), findsOneWidget);
      expect(find.text('Hand Stall'), findsWidgets);
      expect(find.text('Achievements'), findsNothing);
      expect(find.text('Completed Movements'), findsNothing);
      expect(find.text('Not authorized'), findsNothing);
    },
  );

  testWidgets('student identity displays the trainee profile picture', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
        traineeName: 'Ada Lovelace',
      ),
    );
    await pumpDetail(tester);

    profiles.emitProfile(
      'trainee',
      const PublicProfile(
        userId: 'trainee',
        displayName: 'Ada Lovelace',
        visibility: ProfileVisibility.public,
        profilePictureUrl: 'https://example.test/ada.png',
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_student_detail_avatar')),
    );
    expect(avatar.networkImageUrl, 'https://example.test/ada.png');
    expect(find.text('Student details'), findsOneWidget);
  });

  testWidgets(
    'public profile reuses highlights while classroom History stays local',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      progress.inner.setSummary('trainee', sampleSummary());
      await pumpDetail(tester);
      profiles.emitProfile(
        'trainee',
        const PublicProfile(
          userId: 'trainee',
          displayName: 'Ada Lovelace',
          visibility: ProfileVisibility.public,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Profile highlights'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Completed Movements'), findsOneWidget);
      expect(find.text('Recent History'), findsOneWidget);
    },
  );

  testWidgets(
    'unauthorized guessed uid hides progress, coaching, and protected profile details',
    (tester) async {
      await pumpDetail(tester);

      expect(find.text('Not authorized'), findsOneWidget);
      expect(find.textContaining('not in any of your groups'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      expect(find.text('Add note'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.textContaining('Profile locked'), findsNothing);
    },
  );

  testWidgets('progress ready and classroom data remain available', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await pumpDetail(tester);
    await tester.pump();
    expect(find.text('Hand Stall'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MovementImage && widget.movementName == 'Hand Stall',
      ),
      findsWidgets,
    );
  });

  testWidgets('empty progress history shows empty copy', (tester) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    progress.inner.setSummary('trainee', null);
    await pumpDetail(tester);
    await tester.pump();

    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('Hand Stall'), findsNothing);
  });

  testWidgets(
    'approved details keeps messaging but removes public-profile detour',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
          traineeName: 'Ada Lovelace',
        ),
      );
      await pumpDetail(tester);
      await tester.pump();

      expect(find.text('View public profile'), findsNothing);
      expect(find.text('Message student'), findsOneWidget);
    },
  );

  testWidgets('back returns to the teacher students list', (tester) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    await pumpDetail(tester);
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(const Key('teacher_student_back'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ElixEditorialPageHeader)).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('teacher_student_back')));
    await tester.pumpAndSettle();

    expect(find.text('students home'), findsOneWidget);
  });

  testWidgets(
    'class-scoped detail offers lazy classwork instead of embedding it',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      assignments.seedAssignment(
        const GroupAssignment(
          id: 'classwork-1',
          teacherId: 'teacher',
          groupId: 'group-1',
          movementId: 'movement-1',
          revisionId: 'revision-1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          status: GroupAssignmentStatus.active,
          displayTitle: 'Tin Balance',
          teacherDisplayName: 'Grace Hopper',
          groupName: 'BSHM 4A',
          maxScore: 100,
        ),
      );
      assignments.seedAssignment(
        const GroupAssignment(
          id: 'other-classwork',
          teacherId: 'teacher',
          groupId: 'group-2',
          movementId: 'movement-2',
          revisionId: 'revision-2',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          status: GroupAssignmentStatus.active,
          displayTitle: 'Other Classroom Work',
          teacherDisplayName: 'Grace Hopper',
          groupName: 'Other class',
          maxScore: 100,
        ),
      );

      await pumpDetail(tester, preferredGroupId: 'group-1');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('teacher_student_classwork_entry')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('teacher_student_classwork')), findsNothing);
      expect(find.text('Tin Balance'), findsNothing);
      expect(find.text('Other Classroom Work'), findsNothing);
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('teacher_student_classwork_entry')),
            )
            .dy,
        lessThan(tester.getTopLeft(find.text('No history yet')).dy),
      );
    },
  );

  testWidgets('class-scoped back returns to the source classroom', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    await pumpDetail(tester, preferredGroupId: 'group-1');
    await tester.pump();

    await tester.tap(find.byKey(const Key('teacher_student_back')));
    await tester.pumpAndSettle();

    expect(find.text('classroom:group-1'), findsOneWidget);
  });

  testWidgets('invalid preferred class does not fall back to another class', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    await pumpDetail(tester, preferredGroupId: 'group-2');
    await tester.pump();

    expect(find.text('Not authorized'), findsOneWidget);
    expect(find.byKey(const Key('teacher_student_classwork')), findsNothing);
    expect(find.text('History'), findsNothing);
  });
}
