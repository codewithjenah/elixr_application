import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/teacher/teacher_settings_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'teacher_phase3_test_support.dart';

class _RecordingPublicProfileRepository extends PublicProfileRepository {
  PublicProfile? root;
  int seedCalls = 0;
  int updateVisibilityCalls = 0;
  ProfileVisibility? lastUpdatedVisibility;
  ProfileVisibility? seededVisibility;

  @override
  Future<PublicProfile?> getProfileRoot(
    String userId, {
    bool forceServer = false,
  }) async {
    return root;
  }

  @override
  Future<void> seedNewAccountPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    seedCalls++;
    root ??= PublicProfile(
      userId: userId,
      displayName: displayName,
      visibility: ProfileVisibility.public,
      profilePictureUrl: profilePictureUrl,
    );
    seededVisibility = root!.visibility;
  }

  @override
  Future<void> updateVisibility({
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    updateVisibilityCalls++;
    lastUpdatedVisibility = visibility;
    final existing = root;
    root = PublicProfile(
      userId: userId,
      displayName: existing?.displayName ?? 'Teacher',
      visibility: visibility,
      profilePictureUrl: existing?.profilePictureUrl,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService auth;
  late _RecordingPublicProfileRepository profiles;

  setUp(() {
    auth = phase3TeacherAuth();
    profiles = _RecordingPublicProfileRepository();
  });

  tearDown(() {
    auth.dispose();
  });

  Future<GoRouter> pumpSettings(WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherSettings,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherSettings,
          builder: (context, state) => const TeacherSettingsScreen(),
        ),
        GoRoute(
          path: '/teacher/profile/:userId',
          builder: (context, state) =>
              Text('profile:${state.pathParameters['userId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<PublicProfileRepository>.value(value: profiles),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return router;
  }

  testWidgets(
    'Privacy section seeds a missing root as public and can lock it',
    (tester) async {
      await pumpSettings(tester);

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Lock profile'), findsOneWidget);
      expect(find.textContaining('including other faculty'), findsOneWidget);
      expect(find.text('Save confirmed movement images'), findsNothing);
      expect(profiles.seedCalls, 1);
      expect(profiles.seededVisibility, ProfileVisibility.public);

      final toggle = tester.widget<ToggleSwitch>(
        find.byKey(const Key('teacher_privacy_profile_lock_toggle')),
      );
      expect(toggle.checked, isFalse);

      await tester.tap(
        find.byKey(const Key('teacher_privacy_profile_lock_toggle')),
      );
      await tester.pumpAndSettle();

      expect(profiles.updateVisibilityCalls, 1);
      expect(profiles.lastUpdatedVisibility, ProfileVisibility.private);
    },
  );

  testWidgets('existing private root is not rewritten to public', (
    tester,
  ) async {
    profiles.root = const PublicProfile(
      userId: 'teacher',
      displayName: 'Grace Hopper',
      visibility: ProfileVisibility.private,
    );
    await pumpSettings(tester);

    expect(profiles.seedCalls, 1);
    expect(profiles.root?.visibility, ProfileVisibility.private);

    final toggle = tester.widget<ToggleSwitch>(
      find.byKey(const Key('teacher_privacy_profile_lock_toggle')),
    );
    expect(toggle.checked, isTrue);
  });

  testWidgets('View my public profile opens the teacher-shell profile page', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('teacher_view_my_public_profile')));
    await tester.pumpAndSettle();

    expect(find.text('profile:teacher'), findsOneWidget);
  });
}
