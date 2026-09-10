import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/settings/sections/privacy_section.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  User? _user;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
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
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
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
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {}
}

class _FakePublicProfileRepository extends PublicProfileRepository {
  _FakePublicProfileRepository({required this.root});

  PublicProfile? root;
  ProfileVisibility? lastUpdatedVisibility;
  int updateVisibilityCalls = 0;
  int ensureRootCalls = 0;
  Future<void>? nextUpdate;
  Future<PublicProfile?>? nextServerRead;
  Object? updateError;
  Object? serverReadError;

  @override
  Future<PublicProfile?> getProfileRoot(
    String userId, {
    bool forceServer = false,
  }) async {
    if (forceServer && serverReadError != null) throw serverReadError!;
    if (forceServer && nextServerRead != null) return nextServerRead!;
    return root;
  }

  @override
  Future<void> ensurePrivacyProfileRoot({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) async {
    ensureRootCalls++;
    root ??= PublicProfile(
      userId: userId,
      displayName: displayName,
      visibility: ProfileVisibility.private,
      role: role,
    );
  }

  @override
  Future<void> updateVisibility({
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    updateVisibilityCalls++;
    lastUpdatedVisibility = visibility;
    final pending = nextUpdate;
    if (pending != null) await pending;
    if (updateError != null) throw updateError!;
    root = PublicProfile(
      userId: userId,
      displayName: root?.displayName ?? 'Ada',
      visibility: visibility,
      profilePictureUrl: root?.profilePictureUrl,
      role: root?.role,
    );
  }
}

class _FakeSessionService extends SessionService {
  _FakeSessionService({required this.enabled});

  bool? enabled;
  int revokeCalls = 0;
  Future<void>? nextRevoke;
  Object? revokeError;

  @override
  Future<bool?> sessionEvidenceEnabled(String userId) async => enabled;

  @override
  Future<void> setSessionEvidenceEnabled({
    required String userId,
    required bool enabled,
  }) async {
    this.enabled = enabled;
  }

  @override
  Future<void> revokeSessionEvidence(String userId) async {
    revokeCalls++;
    final pending = nextRevoke;
    if (pending != null) await pending;
    if (revokeError != null) throw revokeError!;
    enabled = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPrivacy({
    required WidgetTester tester,
    required _FakePublicProfileRepository repository,
    required AuthService auth,
    _FakeSessionService? sessionService,
    Duration saveDeadline = const Duration(seconds: 12),
    Duration reconciliationDeadline = const Duration(seconds: 6),
  }) async {
    final resolvedSessionService =
        sessionService ??
        _FakeSessionService(enabled: auth.currentUser?.sessionEvidenceEnabled);
    Widget buildSection({required bool isActive}) {
      return FluentApp(
        theme: AppTheme.dark,
        home: MultiProvider(
          providers: [ChangeNotifierProvider<AuthService>.value(value: auth)],
          child: ScaffoldPage(
            content: PrivacySection(
              isActive: isActive,
              publicProfileRepository: repository,
              sessionService: resolvedSessionService,
              saveDeadline: saveDeadline,
              reconciliationDeadline: reconciliationDeadline,
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
    expect(
      find.textContaining('other signed-in Trainees and Teachers'),
      findsOneWidget,
    );

    final toggle = tester.widget<ToggleSwitch>(
      find.byKey(const Key('privacy_profile_lock_toggle')),
    );
    expect(toggle.checked, isFalse);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pumpAndSettle();

    expect(repository.updateVisibilityCalls, 1);
    expect(repository.lastUpdatedVisibility, ProfileVisibility.private);

    final locked = tester.widget<ToggleSwitch>(
      find.byKey(const Key('privacy_profile_lock_toggle')),
    );
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

    final toggle = tester.widget<ToggleSwitch>(
      find.byKey(const Key('privacy_profile_lock_toggle')),
    );
    expect(toggle.checked, isTrue);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pumpAndSettle();

    expect(repository.updateVisibilityCalls, 1);
    expect(repository.lastUpdatedVisibility, ProfileVisibility.public);
  });

  testWidgets('explicit failure exits Saving and restores the prior state', (
    tester,
  ) async {
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..updateError = StateError('denied');
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Saving...'), findsNothing);
    expect(
      find.textContaining('Could not save privacy setting'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isFalse,
    );
  });

  testWidgets(
    'pending write leaves Saving and recovers to authoritative state',
    (tester) async {
      final pending = Completer<void>();
      final auth = await _auth();
      final repository = _repository(ProfileVisibility.public)
        ..nextUpdate = pending.future;
      await pumpPrivacy(
        tester: tester,
        repository: repository,
        auth: auth,
        saveDeadline: const Duration(milliseconds: 1),
        reconciliationDeadline: const Duration(milliseconds: 1),
      );

      await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Saving...'), findsNothing);
      expect(find.textContaining('Could not confirm'), findsOneWidget);
      expect(
        tester
            .widget<ToggleSwitch>(
              find.byKey(const Key('privacy_profile_lock_toggle')),
            )
            .onChanged,
        isNotNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('delayed success keeps the requested visibility', (tester) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..nextUpdate = pending.future;
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saving...'), findsNothing);
    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isTrue,
    );
  });

  testWidgets('pending unlock reconciles to authoritative private visibility', (
    tester,
  ) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.private)
      ..nextUpdate = pending.future;
    await pumpPrivacy(
      tester: tester,
      repository: repository,
      auth: auth,
      saveDeadline: const Duration(milliseconds: 1),
      reconciliationDeadline: const Duration(milliseconds: 1),
    );

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isTrue,
    );
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('unavailable reconciliation restores prior visibility', (
    tester,
  ) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..nextUpdate = pending.future
      ..serverReadError = StateError('network unavailable');
    await pumpPrivacy(
      tester: tester,
      repository: repository,
      auth: auth,
      saveDeadline: const Duration(milliseconds: 1),
      reconciliationDeadline: const Duration(milliseconds: 1),
    );

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isFalse,
    );
    expect(find.textContaining('Could not confirm'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('delayed failure restores the requested visibility', (
    tester,
  ) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.private)
      ..nextUpdate = pending.future;
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isTrue,
    );
    expect(
      find.textContaining('Could not save privacy setting'),
      findsOneWidget,
    );
  });

  testWidgets('duplicate taps do not issue concurrent writes', (tester) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..nextUpdate = pending.future;
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();

    expect(repository.updateVisibilityCalls, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a late stale completion cannot overwrite a newer result', (
    tester,
  ) async {
    final first = Completer<void>();
    final second = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..nextUpdate = first.future;
    await pumpPrivacy(
      tester: tester,
      repository: repository,
      auth: auth,
      saveDeadline: const Duration(milliseconds: 1),
      reconciliationDeadline: const Duration(milliseconds: 1),
    );

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    repository.nextUpdate = second.future;
    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();
    second.completeError(StateError('second write failed'));
    await tester.pumpAndSettle();
    first.complete();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_profile_lock_toggle')),
          )
          .checked,
      isFalse,
    );
  });

  testWidgets('missing current user fails safely without a write', (
    tester,
  ) async {
    final auth = AuthService(
      repository: _StubAuthRepository(null),
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();
    final repository = _repository(ProfileVisibility.public);
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);

    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.updateVisibilityCalls, 0);
    expect(find.textContaining('Sign in'), findsOneWidget);
  });

  testWidgets('disposing during a pending operation does not set state', (
    tester,
  ) async {
    final pending = Completer<void>();
    final auth = await _auth();
    final repository = _repository(ProfileVisibility.public)
      ..nextUpdate = pending.future;
    await pumpPrivacy(tester: tester, repository: repository, auth: auth);
    await tester.tap(find.byKey(const Key('privacy_profile_lock_toggle')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved-image copy separates classroom progress and confirms deletion',
    (tester) async {
      final auth = await _auth(sessionEvidenceEnabled: true);
      final repository = _repository(ProfileVisibility.private);
      final sessions = _FakeSessionService(enabled: true);
      await pumpPrivacy(
        tester: tester,
        repository: repository,
        auth: auth,
        sessionService: sessions,
      );

      expect(
        find.textContaining('separately from classroom learning progress'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Teachers with approved classroom membership'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('available saved practice images'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('privacy_evidence_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Delete saved movement images?'), findsOneWidget);
      expect(
        find.textContaining('stops Teachers from viewing'),
        findsOneWidget,
      );
      expect(
        find.textContaining('permanently deletes retained confirmed-movement'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Classroom learning progress sharing is unchanged'),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep images'));
      await tester.pumpAndSettle();
      expect(sessions.revokeCalls, 0);
      expect(
        find.textContaining('On - Teachers with approved classroom membership'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'successful evidence revocation updates status after completion',
    (tester) async {
      final pending = Completer<void>();
      final auth = await _auth(sessionEvidenceEnabled: true);
      final repository = _repository(ProfileVisibility.private);
      final sessions = _FakeSessionService(enabled: true)
        ..nextRevoke = pending.future;
      await pumpPrivacy(
        tester: tester,
        repository: repository,
        auth: auth,
        sessionService: sessions,
      );

      await tester.tap(find.byKey(const Key('privacy_evidence_toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete and turn off'),
      );
      await tester.pump();

      expect(sessions.revokeCalls, 1);
      expect(find.text('Updating private session images...'), findsOneWidget);
      expect(
        find.textContaining('On - Teachers with approved classroom membership'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ToggleSwitch>(
              find.byKey(const Key('privacy_evidence_toggle')),
            )
            .checked,
        isTrue,
      );

      pending.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('Off - Teachers cannot view saved practice images.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ToggleSwitch>(
              find.byKey(const Key('privacy_evidence_toggle')),
            )
            .checked,
        isFalse,
      );

      // AuthService still holds the original cached `true`; reopening must read
      // the authoritative setting from SessionService instead.
      await pumpPrivacy(
        tester: tester,
        repository: repository,
        auth: auth,
        sessionService: sessions,
      );
      expect(
        find.text('Off - Teachers cannot view saved practice images.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ToggleSwitch>(
              find.byKey(const Key('privacy_evidence_toggle')),
            )
            .checked,
        isFalse,
      );
    },
  );

  testWidgets('failed evidence revocation keeps the enabled access status', (
    tester,
  ) async {
    final auth = await _auth(sessionEvidenceEnabled: true);
    final repository = _repository(ProfileVisibility.private);
    final sessions = _FakeSessionService(enabled: true)
      ..revokeError = StateError('offline');
    await pumpPrivacy(
      tester: tester,
      repository: repository,
      auth: auth,
      sessionService: sessions,
    );

    await tester.tap(find.byKey(const Key('privacy_evidence_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete and turn off'));
    await tester.pumpAndSettle();

    expect(sessions.revokeCalls, 1);
    expect(
      find.textContaining('Could not update session image privacy'),
      findsOneWidget,
    );
    expect(
      find.textContaining('On - Teachers with approved classroom membership'),
      findsOneWidget,
    );
    expect(
      find.text('Off - Teachers cannot view saved practice images.'),
      findsNothing,
    );
    expect(
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('privacy_evidence_toggle')),
          )
          .checked,
      isTrue,
    );
  });
}

Future<AuthService> _auth({bool? sessionEvidenceEnabled}) async {
  final auth = AuthService(
    repository: _StubAuthRepository(
      User(
        id: 'u1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        sessionEvidenceEnabled: sessionEvidenceEnabled,
      ),
    ),
    awaitInitialAuthState: () async {},
  );
  await auth.initialize();
  return auth;
}

_FakePublicProfileRepository _repository(ProfileVisibility visibility) {
  return _FakePublicProfileRepository(
    root: PublicProfile(
      userId: 'u1',
      displayName: 'Ada Lovelace',
      visibility: visibility,
    ),
  );
}
