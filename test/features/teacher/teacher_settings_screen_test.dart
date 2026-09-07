import 'dart:io';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/features/settings/sections/account_profile_section.dart';
import 'package:elixr_application/features/settings/settings_section.dart';
import 'package:elixr_application/features/settings/widgets/profile_frame_selector.dart';
import 'package:elixr_application/features/teacher/teacher_settings_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/settings_service.dart';
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
    String? role,
  }) async {
    seedCalls++;
    root ??= PublicProfile(
      userId: userId,
      displayName: displayName,
      visibility: ProfileVisibility.public,
      profilePictureUrl: profilePictureUrl,
      role: role,
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
      role: existing?.role,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService auth;
  late _RecordingPublicProfileRepository profiles;
  late Directory tempDir;
  late SettingsService settingsService;

  setUp(() async {
    auth = phase3TeacherAuth();
    profiles = _RecordingPublicProfileRepository();
    tempDir = await Directory.systemTemp.createTemp('elixr_teacher_settings_');
    settingsService = SettingsService(
      settingsFile: File('${tempDir.path}/settings.json'),
    );
    await settingsService.initialize();
  });

  tearDown(() async {
    auth.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<GoRouter> pumpSettings(
    WidgetTester tester, {
    SettingsSection? initialSection,
    AccountProfileUpdateTeacherBorder? updateTeacherBorder,
    VoidCallback? onWatchPlayer,
    VoidCallback? onWatchUserCosmetics,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherSettings,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherSettings,
          builder: (context, state) => TeacherSettingsScreen(
            initialSection: initialSection,
            publicProfileRepository: profiles,
            watchPlayer: (_) {
              onWatchPlayer?.call();
              return Stream<LeaderboardEntry?>.value(null);
            },
            watchUserCosmetics: (_) {
              onWatchUserCosmetics?.call();
              return Stream<UserCosmetics?>.value(null);
            },
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
            updateTeacherBorder: updateTeacherBorder,
          ),
        ),
        GoRoute(
          path: AppRoutePaths.teacherDashboard,
          builder: (context, state) => const Text('teacher-dashboard'),
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
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          Provider<PublicProfileRepository>.value(value: profiles),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return router;
  }

  testWidgets('Account & Profile is editable and Legal stays on the page', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('Account & Profile'), findsWidgets);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Manage your Elixr experience'), findsOneWidget);
    expect(find.text('Practice'), findsNothing);
    expect(find.text('Teacher Access'), findsNothing);
    expect(find.byType(ProfileFrameSelector), findsOneWidget);
    expect(find.text('Avatar Frame'), findsOneWidget);
    expect(find.text('Frames'), findsOneWidget);
    expect(find.text('No Frame · Default'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Unlocked'), findsNothing);
    expect(
      find.text('Frames are unlocked by claiming achievements.'),
      findsNothing,
    );
    expect(find.textContaining('practice session'), findsNothing);
    expect(find.byIcon(FluentIcons.cancel), findsOneWidget);
  });

  testWidgets('Teacher can select and clear any available profile frame', (
    tester,
  ) async {
    String? savedBorder;
    var saveCount = 0;
    var playerWatchCalls = 0;
    var cosmeticsWatchCalls = 0;
    await pumpSettings(
      tester,
      updateTeacherBorder: ({required userId, required borderId}) async {
        saveCount++;
        savedBorder = borderId;
      },
      onWatchPlayer: () => playerWatchCalls++,
      onWatchUserCosmetics: () => cosmeticsWatchCalls++,
    );

    expect(playerWatchCalls, 0);
    expect(cosmeticsWatchCalls, 0);

    for (final border in profileBorderCatalog) {
      expect(find.byKey(Key('frame_tile_${border.id}')), findsOneWidget);
    }

    final lockedTraineeWords = [
      find.text('Locked'),
      find.text('Unlocked'),
      find.textContaining('achievement'),
      find.textContaining('XP'),
      find.textContaining('leaderboard'),
    ];
    for (final finder in lockedTraineeWords) {
      expect(finder, findsNothing);
    }

    final frame = find.byKey(const Key('frame_tile_tin_specialist'));
    await tester.ensureVisible(frame);
    await tester.tap(frame);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedBorder, 'tin_specialist');
    expect(saveCount, 1);
    final avatarFinder = find.descendant(
      of: find.byKey(const Key('account_profile_avatar_tap')),
      matching: find.byType(ProfileAvatarWidget),
    );
    var avatar = tester.widget<ProfileAvatarWidget>(avatarFinder);
    expect(avatar.equippedBorderId, 'tin_specialist');

    final none = find.byKey(const Key('frame_tile_none'));
    await tester.ensureVisible(none);
    await tester.tap(none);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedBorder, isNull);
    expect(saveCount, 2);
    avatar = tester.widget<ProfileAvatarWidget>(
      find.descendant(
        of: find.byKey(const Key('account_profile_avatar_tap')),
        matching: find.byType(ProfileAvatarWidget),
      ),
    );
    expect(avatar.equippedBorderId, isNull);
  });

  testWidgets('Teacher frame failures keep the previous selection', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      updateTeacherBorder: ({required userId, required borderId}) async {
        throw StateError('offline');
      },
    );

    final frame = find.byKey(const Key('frame_tile_starter_glow'));
    await tester.ensureVisible(frame);
    await tester.tap(frame);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not update avatar frame.'), findsOneWidget);
    final avatar = tester.widget<ProfileAvatarWidget>(
      find.descendant(
        of: find.byKey(const Key('account_profile_avatar_tap')),
        matching: find.byType(ProfileAvatarWidget),
      ),
    );
    expect(avatar.equippedBorderId, isNull);
  });

  testWidgets(
    'Privacy section seeds a missing root as public and can lock it',
    (tester) async {
      await pumpSettings(tester, initialSection: SettingsSection.privacy);

      expect(find.text('Privacy'), findsWidgets);
      expect(find.text('Lock profile'), findsOneWidget);
      expect(
        find.textContaining('other students and teachers'),
        findsOneWidget,
      );
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
    await pumpSettings(tester, initialSection: SettingsSection.privacy);

    expect(profiles.seedCalls, 1);
    expect(profiles.root?.visibility, ProfileVisibility.private);

    final toggle = tester.widget<ToggleSwitch>(
      find.byKey(const Key('teacher_privacy_profile_lock_toggle')),
    );
    expect(toggle.checked, isTrue);
  });

  testWidgets('close returns to the Teacher dashboard', (tester) async {
    final router = await pumpSettings(tester);

    await tester.tap(find.byIcon(FluentIcons.cancel));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutePaths.teacherDashboard);
    expect(find.text('teacher-dashboard'), findsOneWidget);
  });

  testWidgets('View my public profile opens the teacher-shell profile page', (
    tester,
  ) async {
    await pumpSettings(tester, initialSection: SettingsSection.privacy);

    await tester.tap(find.byKey(const Key('teacher_view_my_public_profile')));
    await tester.pumpAndSettle();

    expect(find.text('profile:teacher'), findsOneWidget);
  });
}
