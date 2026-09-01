import 'dart:typed_data';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/widgets/elix_status_panel.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_practice_history_screen.dart';
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
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late AuthService auth;
  late TrackingTeacherEvidenceRepository evidence;

  setUp(() {
    groups = InMemoryGroupRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    evidence = TrackingTeacherEvidenceRepository();
    auth = phase3TeacherAuth();
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherStudentPracticeHistory(
        'trainee',
        groupId: 'group-1',
      ),
      routes: [
        GoRoute(
          path: '/teacher/students/:traineeId/practice',
          builder: (context, state) => TeacherStudentPracticeHistoryScreen(
            traineeId: state.pathParameters['traineeId']!,
            groupId: state.uri.queryParameters['groupId'],
            evidenceRepository: evidence,
          ),
        ),
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (_, _) => const Text('student details'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<TeacherProgressRepository>.value(value: progress),
          Provider<PublicProfileRepository>.value(value: profiles),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'uses a bounded paginated history list at desktop and narrow widths',
    (tester) async {
      progress.inner.sessions['trainee'] = [
        for (var index = 0; index < 21; index++)
          sampleSession(id: 'session-$index'),
      ];
      await pumpScreen(tester, size: const Size(700, 720));

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Hand Stall'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Load more'),
        400,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Load more'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(progress.sessionFetches, ['trainee', 'trainee']);
    },
  );

  testWidgets(
    'shows empty and authorization-blocked states without a history list',
    (tester) async {
      await pumpScreen(tester);
      expect(find.text('No History yet.'), findsOneWidget);

      groups = InMemoryGroupRepository();
      groups.seedGroup(activeGroup());
      await pumpScreen(tester);
      expect(find.byType(ElixStatusPanel), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    },
  );

  testWidgets('saved images load only after the teacher requests them', (
    tester,
  ) async {
    final session = sampleSession(evidenceAvailable: true);
    progress.inner.sessions['trainee'] = [session];
    await pumpScreen(tester);

    expect(evidence.downloads, isEmpty);
    expect(find.textContaining('66.7%'), findsOneWidget);
    expect(find.text('Assessment V2'), findsNothing);
    await tester.tap(find.byKey(const Key('teacher_history_row_session-1')));
    await tester.pumpAndSettle();
    expect(evidence.downloads, ['trainee:session-1']);
    expect(find.textContaining('Assessment V2'), findsOneWidget);
    expect(find.text('Saved image is unavailable.'), findsOneWidget);

    evidence.responses[session.sessionId] = Uint8List.fromList(_tinyPng);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(evidence.downloads, ['trainee:session-1', 'trainee:session-1']);
    expect(
      find.byKey(const Key('teacher_history_evidence_preview_session-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('teacher_history_evidence_preview_session-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hand Stall · Saved image'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'rows without retained evidence never offer or request an image',
    (tester) async {
      progress.inner.sessions['trainee'] = [sampleSession()];
      await pumpScreen(tester, size: const Size(340, 720));

      expect(find.text('View saved image'), findsNothing);
      expect(evidence.downloads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

const _tinyPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  153,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  128,
  2,
  63,
  73,
  194,
  238,
  207,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
