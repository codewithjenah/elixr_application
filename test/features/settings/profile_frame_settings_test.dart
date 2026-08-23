import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/features/settings/sections/account_profile_section.dart';
import 'package:elixr_application/features/settings/widgets/profile_frame_selector.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  User? _user;

  @override
  Future<void> clearCurrentUser() async => _user = null;

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User?> refreshAuthenticatedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<void> requestDeleteAccountEmailVerification() async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async => _user!;

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async => _user!;
}

class _StubProfileImageRepository implements ProfileImageRepositoryBase {
  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {}
}

LeaderboardEntry _entry({String? border}) {
  return LeaderboardEntry(
    userId: 'u1',
    displayName: 'Test User',
    totalXp: 25,
    sessionsCompleted: 1,
    scoreSum: 80,
    averageScore: 80,
    bestScore: 80,
    equippedBorderId: border,
  );
}

UserCosmetics _cosmetics(Set<String> unlocked) {
  return UserCosmetics(
    userId: 'u1',
    unlockedBorderIds: unlocked.toList(),
    lastAchievementClaimId: 'u1_first_steps',
  );
}

void main() {
  late AuthService authService;
  late StreamController<LeaderboardEntry?> leaderboardController;
  late StreamController<UserCosmetics?> cosmeticsController;
  final equipCalls = <String>[];
  Completer<EquipBorderResult>? pendingEquip;

  setUp(() {
    equipCalls.clear();
    pendingEquip = null;
    leaderboardController = StreamController<LeaderboardEntry?>.broadcast();
    cosmeticsController = StreamController<UserCosmetics?>.broadcast();
    final user = User(
      id: 'u1',
      firstName: 'Test',
      lastName: 'User',
      email: 'user@example.com',
    );
    authService = AuthService(
      repository: _StubAuthRepository(user),
      leaderboardRepository: null,
      profileImageRepository: _StubProfileImageRepository(),
    );
    authService.seedAuthenticatedUser(user);
  });

  tearDown(() async {
    authService.dispose();
    await leaderboardController.close();
    await cosmeticsController.close();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    LeaderboardEntry? initialEntry,
    UserCosmetics? initialCosmetics = const UserCosmetics(
      userId: 'u1',
      unlockedBorderIds: [],
      lastAchievementClaimId: '',
    ),
    bool emitNullCosmetics = false,
    EquipBorderResult Function(String borderId)? equipResult,
    ValueChanged<bool>? onDirtyChanged,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<SettingsService>(
            create: (_) => SettingsService(),
          ),
          Provider<CameraDeviceService>(create: (_) => CameraDeviceService()),
        ],
        child: FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: AccountProfileSection(
                watchPlayer: (_) => leaderboardController.stream,
                watchUserCosmetics: (_) => cosmeticsController.stream,
                onDirtyChanged: onDirtyChanged,
                equipBorder: ({required userId, required borderId}) async {
                  equipCalls.add(borderId);
                  final pending = pendingEquip;
                  if (pending != null) {
                    return pending.future;
                  }
                  return (equipResult ??
                      (_) => const EquipBorderResult.equipped())(borderId);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    leaderboardController.add(initialEntry);
    cosmeticsController.add(emitNullCosmetics ? null : initialCosmetics);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapFrameTile(WidgetTester tester, String borderId) async {
    final finder = find.byKey(Key('frame_tile_$borderId'));
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('Avatar Frame selector appears under the profile picture', (
    tester,
  ) async {
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    expect(
      find.byKey(const Key('account_avatar_customization')),
      findsOneWidget,
    );
    expect(find.text('Avatar Frame'), findsOneWidget);
    expect(find.byType(ProfileFrameSelector), findsOneWidget);
    expect(find.byType(ProfileAvatarWidget), findsOneWidget);
    expect(
      find.text('Frames are unlocked by claiming achievements.'),
      findsOneWidget,
    );
  });

  testWidgets('unlocked frames equip once; locked frames do not', (
    tester,
  ) async {
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    await tapFrameTile(tester, 'starter_glow');
    expect(equipCalls, ['starter_glow']);

    await tapFrameTile(tester, 'gold_mastery');
    expect(equipCalls, ['starter_glow']);
  });

  testWidgets('No Frame unequips exactly once', (tester) async {
    await pumpSection(
      tester,
      initialEntry: _entry(border: 'starter_glow'),
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    await tapFrameTile(tester, 'none');
    expect(equipCalls, ['']);
  });

  testWidgets('clicking already equipped frame performs no write', (
    tester,
  ) async {
    await pumpSection(
      tester,
      initialEntry: _entry(border: 'starter_glow'),
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    await tapFrameTile(tester, 'starter_glow');
    expect(equipCalls, isEmpty);
  });

  testWidgets('actions disabled while write in progress', (tester) async {
    pendingEquip = Completer<EquipBorderResult>();
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow', 'cyan_orbit'}),
    );

    await tapFrameTile(tester, 'starter_glow');
    expect(equipCalls, ['starter_glow']);

    await tapFrameTile(tester, 'cyan_orbit');
    expect(equipCalls, ['starter_glow']);

    pendingEquip!.complete(const EquipBorderResult.equipped());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('live leaderboard updates change the main avatar frame', (
    tester,
  ) async {
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    var avatar = tester.widget<ProfileAvatarWidget>(
      find.byType(ProfileAvatarWidget),
    );
    expect(avatar.equippedBorderId, isNull);

    leaderboardController.add(_entry(border: 'starter_glow'));
    await tester.pump();

    avatar = tester.widget<ProfileAvatarWidget>(
      find.byType(ProfileAvatarWidget),
    );
    expect(avatar.equippedBorderId, 'starter_glow');
    expect(avatar.animateBorder, isTrue);
  });

  testWidgets('missing cosmetics renders locked frames without crashing', (
    tester,
  ) async {
    await pumpSection(tester, initialEntry: _entry(), emitNullCosmetics: true);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(FluentIcons.lock), findsWidgets);
  });

  testWidgets('missing leaderboard shows intended error state', (tester) async {
    await pumpSection(
      tester,
      initialEntry: null,
      initialCosmetics: _cosmetics({'starter_glow'}),
    );

    expect(find.textContaining('Complete a practice session'), findsOneWidget);
  });

  testWidgets('equip failure restores interaction and shows feedback', (
    tester,
  ) async {
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow'}),
      equipResult: (_) => const EquipBorderResult.borderLocked(),
    );

    await tapFrameTile(tester, 'starter_glow');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Unlock this frame first'), findsOneWidget);
    expect(equipCalls, ['starter_glow']);

    await tapFrameTile(tester, 'starter_glow');
    expect(equipCalls, ['starter_glow', 'starter_glow']);
  });

  testWidgets('equipping a frame does not dirty profile form or save', (
    tester,
  ) async {
    var dirty = false;
    await pumpSection(
      tester,
      initialEntry: _entry(),
      initialCosmetics: _cosmetics({'starter_glow'}),
      onDirtyChanged: (value) => dirty = value,
    );

    final state = tester.state<AccountProfileSectionState>(
      find.byType(AccountProfileSection),
    );
    expect(state.isDirty, isFalse);

    await tapFrameTile(tester, 'starter_glow');
    await tester.pump();

    expect(state.isDirty, isFalse);
    expect(dirty, isFalse);
    expect(equipCalls, ['starter_glow']);

    final save = find.widgetWithText(FilledButton, 'Save changes');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });
}
