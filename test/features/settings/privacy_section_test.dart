import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/settings/sections/privacy_section.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  User? _user;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

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
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User?> refreshAuthenticatedUser() async => _user;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount({required String password}) async {}
}

class _FakePublicProfileRepository extends PublicProfileRepository {
  _FakePublicProfileRepository({required this.root});

  PublicProfile? root;
  ProfileVisibility? lastUpdatedVisibility;
  int updateVisibilityCalls = 0;

  @override
  Future<PublicProfile?> getProfileRoot(String userId) async => root;

  @override
  Future<void> updateVisibility({
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    updateVisibilityCalls++;
    lastUpdatedVisibility = visibility;
    root = PublicProfile(
      userId: userId,
      displayName: root?.displayName ?? 'Ada',
      visibility: visibility,
      profilePictureUrl: root?.profilePictureUrl,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPrivacy({
    required WidgetTester tester,
    required _FakePublicProfileRepository repository,
    required AuthService auth,
  }) async {
    Widget buildSection({required bool isActive}) {
      return FluentApp(
        theme: AppTheme.dark,
        home: MultiProvider(
          providers: [ChangeNotifierProvider<AuthService>.value(value: auth)],
          child: ScaffoldPage(
            content: PrivacySection(
              isActive: isActive,
              publicProfileRepository: repository,
            ),
          ),
        ),
      );
    }

    // Mirror Settings: mount inactive, then activate so didUpdateWidget loads.
    await tester.pumpWidget(buildSection(isActive: false));
    await tester.pump();
    await tester.pumpWidget(buildSection(isActive: true));
    await tester.pumpAndSettle();
  }

  testWidgets('public profile shows Lock profile toggle OFF', (tester) async {
    final auth = AuthService(
      repository: _StubAuthRepository(
        const User(
          id: 'u1',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
        ),
      ),
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    final repository = _FakePublicProfileRepository(
      root: const PublicProfile(
        userId: 'u1',
        displayName: 'Ada Lovelace',
        visibility: ProfileVisibility.public,
      ),
    );

    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    expect(find.text('Lock profile'), findsOneWidget);
    expect(find.text('Public profile'), findsNothing);

    final toggle = tester.widget<ToggleSwitch>(find.byType(ToggleSwitch));
    expect(toggle.checked, isFalse);

    await tester.tap(find.byType(ToggleSwitch));
    await tester.pumpAndSettle();

    expect(repository.updateVisibilityCalls, 1);
    expect(repository.lastUpdatedVisibility, ProfileVisibility.private);

    final locked = tester.widget<ToggleSwitch>(find.byType(ToggleSwitch));
    expect(locked.checked, isTrue);
  });

  testWidgets('locked profile shows Lock profile toggle ON', (tester) async {
    final auth = AuthService(
      repository: _StubAuthRepository(
        const User(
          id: 'u1',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
        ),
      ),
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    final repository = _FakePublicProfileRepository(
      root: const PublicProfile(
        userId: 'u1',
        displayName: 'Ada Lovelace',
        visibility: ProfileVisibility.private,
      ),
    );

    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    final toggle = tester.widget<ToggleSwitch>(find.byType(ToggleSwitch));
    expect(toggle.checked, isTrue);

    await tester.tap(find.byType(ToggleSwitch));
    await tester.pumpAndSettle();

    expect(repository.updateVisibilityCalls, 1);
    expect(repository.lastUpdatedVisibility, ProfileVisibility.public);
  });
}
