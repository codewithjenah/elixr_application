import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
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

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    links = FakeTeacherLinksRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);

    final router = GoRouter(
      initialLocation: '/teacher/students/trainee',
      routes: [
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (context, state) => TeacherStudentDetailScreen(
            traineeId: state.pathParameters['traineeId'] ?? '',
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

      expect(find.text('No practice history yet'), findsOneWidget);
      expect(
        find.textContaining('Classroom membership is required'),
        findsNothing,
      );
      expect(find.text('Not authorized'), findsNothing);
      expect(find.textContaining('Private public profile'), findsNothing);
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
      expect(find.textContaining('Private public profile'), findsOneWidget);
      expect(find.text('Practice progress'), findsOneWidget);
      expect(find.text('Hand Stall'), findsWidgets);
      expect(find.text('Not authorized'), findsNothing);
    },
  );

  testWidgets(
    'unauthorized guessed uid hides progress, coaching, and protected profile details',
    (tester) async {
      await pumpDetail(tester);

      expect(find.text('Not authorized'), findsOneWidget);
      expect(find.textContaining('not in any of your groups'), findsOneWidget);
      expect(find.text('Practice progress'), findsNothing);
      expect(find.text('Add note'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.textContaining('Private public profile'), findsNothing);
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

    expect(find.text('No practice history yet'), findsOneWidget);
    expect(find.text('Hand Stall'), findsNothing);
  });

  testWidgets('View public profile opens the teacher-shell profile page', (
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
    await tester.pump();

    expect(find.text('View public profile'), findsOneWidget);
    await tester.tap(find.text('View public profile'));
    await tester.pumpAndSettle();

    expect(find.text('profile:trainee'), findsOneWidget);
  });
}
