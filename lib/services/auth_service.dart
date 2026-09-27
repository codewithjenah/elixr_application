import 'dart:async';
import 'dart:io';

import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/auth/teacher_auth_messages.dart';
import '../core/constants/app_constants.dart';
import '../data/models/profile_border.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/profile_image_repository.dart';
import '../data/repositories/public_profile_repository.dart';
import '../features/auth/auth_validators.dart';
import 'auth_email_callback_server.dart';
import 'join_link_service.dart';
import 'trainee_profile_snapshot_store.dart';
import 'trainee_progression_snapshot_store.dart';
import 'windows_google_oauth_flow.dart';

/// Account-scoped phrase used as a deliberate-action safeguard in the UI.
///
/// This is not authentication; password reauthentication remains the
/// security boundary for account deletion.
String accountDeletionConfirmationPhraseFor(String email) {
  return 'delete ${email.trim().toLowerCase()}';
}

enum AuthInitializationState { loading, ready, failed }

enum AuthInitializationFailureKind {
  authentication,
  teacherAuthorization,
  unknown,
}

/// Presentation-safe details for a failed initial auth restoration attempt.
///
/// The underlying exception is intentionally not retained here. Startup
/// failures can contain backend, HTTP, or token details that must stay out of
/// the production UI.
class AuthInitializationFailure {
  const AuthInitializationFailure({required this.kind, required this.message});

  final AuthInitializationFailureKind kind;
  final String message;
}

class _PendingEmailChangeState {
  _PendingEmailChangeState({
    required this.originalUid,
    required this.originalEmail,
    required this.pendingEmail,
    required String password,
    required this.expiresAt,
  }) : _password = password;

  final String originalUid;
  final String originalEmail;
  final String pendingEmail;
  final DateTime expiresAt;
  String _password;

  String get password => _password;

  void clearPassword() {
    _password = '';
  }
}

class AuthService extends ChangeNotifier {
  AuthService({
    AuthRepositoryBase? repository,
    LeaderboardRepository? leaderboardRepository,
    PublicProfileRepository? publicProfileRepository,
    ProfileImageRepositoryBase? profileImageRepository,
    Duration? pendingEmailPollInterval,
    Duration? pendingEmailTimeout,
    AuthEmailCallbackServer? emailCallbackServer,
    Duration? emailVerificationPollInterval,
    Duration? verificationResendCooldown,
    JoinLinkService? joinLinkService,
    @visibleForTesting Future<void> Function()? awaitInitialAuthState,
    @visibleForTesting Stream<String?>? authUidChanges,
    @visibleForTesting String? Function()? currentAuthUid,
    Future<void> Function()? accountScopeTeardownBarrier,
    Future<void> Function(String userId)? purgePendingSessions,
    TraineeProfileSnapshotStore? traineeProfileSnapshotStore,
    TraineeProgressionSnapshotStore? traineeProgressionSnapshotStore,
    Duration? profileRestorationTimeout,
  }) : _leaderboardRepository = leaderboardRepository,
       _publicProfileRepository = publicProfileRepository,
       _explicitProfileImageRepository = profileImageRepository,
       _pendingEmailPollInterval =
           pendingEmailPollInterval ?? const Duration(seconds: 5),
       _pendingEmailTimeout = pendingEmailTimeout ?? const Duration(minutes: 2),
       _emailCallbackServer =
           emailCallbackServer ?? LoopbackAuthEmailCallbackServer(),
       _emailVerificationPollInterval =
           emailVerificationPollInterval ?? const Duration(seconds: 1),
       _verificationResendCooldown =
           verificationResendCooldown ?? const Duration(seconds: 60),
       _joinLinkService = joinLinkService,
       _awaitInitialAuthState = awaitInitialAuthState,
       _authUidChangesOverride = authUidChanges,
       _currentAuthUidOverride = currentAuthUid,
       _accountScopeTeardownBarrier = accountScopeTeardownBarrier,
       _purgePendingSessions = purgePendingSessions,
       _traineeProfileSnapshotStore =
           traineeProfileSnapshotStore ?? TraineeProfileSnapshotStore(),
       _traineeProgressionSnapshotStore =
           traineeProgressionSnapshotStore ?? TraineeProgressionSnapshotStore(),
       _profileRestorationTimeout =
           profileRestorationTimeout ?? const Duration(seconds: 8) {
    _repository =
        repository ??
        AuthRepository(
          createMissingProfile: false,
          googleOAuthFlow: WindowsGoogleOAuthFlow(),
          // Confirmation links return to the loopback callback, which hands
          // the PKCE code back to this app.
          emailRedirectUrl: _verificationRedirectUrl,
        );
    _emailCallbackServer.passwordResetHandler = _completePasswordResetFromLink;
    _joinLinkService?.authCallbackHandler = handleEmailActionCallback;
  }

  late final AuthRepositoryBase _repository;
  EmailLinkAuthRepositoryBase? get _emailLinkRepository =>
      _repository is EmailLinkAuthRepositoryBase
      ? _repository as EmailLinkAuthRepositoryBase
      : null;
  GoogleAuthRepositoryBase? get _googleRepository =>
      _repository is GoogleAuthRepositoryBase
      ? _repository as GoogleAuthRepositoryBase
      : null;
  TeacherGoogleAuthRepositoryBase? get _teacherGoogleRepository =>
      _repository is TeacherGoogleAuthRepositoryBase
      ? _repository as TeacherGoogleAuthRepositoryBase
      : null;
  TeacherAuthorizationRepositoryBase? get _teacherAuthorizationRepository =>
      _repository is TeacherAuthorizationRepositoryBase
      ? _repository as TeacherAuthorizationRepositoryBase
      : null;
  TeacherProfileBorderRepositoryBase? get _teacherProfileBorderRepository =>
      _repository is TeacherProfileBorderRepositoryBase
      ? _repository as TeacherProfileBorderRepositoryBase
      : null;
  final LeaderboardRepository? _leaderboardRepository;
  final PublicProfileRepository? _publicProfileRepository;
  final Duration _pendingEmailPollInterval;
  final Duration _pendingEmailTimeout;
  final AuthEmailCallbackServer _emailCallbackServer;
  final Duration _emailVerificationPollInterval;
  final Duration _verificationResendCooldown;
  final JoinLinkService? _joinLinkService;
  final Future<void> Function()? _awaitInitialAuthState;
  final Stream<String?>? _authUidChangesOverride;
  final String? Function()? _currentAuthUidOverride;
  final Future<void> Function()? _accountScopeTeardownBarrier;
  final Future<void> Function(String userId)? _purgePendingSessions;
  final TraineeProfileSnapshotStore _traineeProfileSnapshotStore;
  final TraineeProgressionSnapshotStore _traineeProgressionSnapshotStore;
  final Duration _profileRestorationTimeout;

  // Lazily constructed so tests that never touch profile-image upload do not
  // need Storage initialized.
  ProfileImageRepositoryBase? _explicitProfileImageRepository;
  ProfileImageRepositoryBase get _profileImageRepository =>
      _explicitProfileImageRepository ??= ProfileImageRepository();

  User? _currentUser;
  PendingGoogleProfile? _pendingGoogleProfile;
  Set<AuthProviderKind> _providerKinds = const {};
  bool _isLoading = true;
  AuthInitializationState _initializationState =
      AuthInitializationState.loading;
  AuthInitializationFailure? _initializationFailure;
  Future<void>? _initializationInFlight;
  bool? _emailVerified;
  bool _isOfflineRestoredTrainee = false;
  bool _disposed = false;
  bool _checkingPendingEmail = false;
  _PendingEmailChangeState? _pendingEmailChange;
  Timer? _pendingEmailPollTimer;
  String? _pendingEmailRecoveryError;
  String? _pendingEmailChangeSuccessMessage;
  String? _accountDeletedMessage;
  String? _teacherAuthInfoMessage;
  String? _teacherAuthErrorMessage;
  Future<void>? _pendingEmailCheckInFlight;
  StreamSubscription<Uri>? _emailCallbackSubscription;
  StreamSubscription<String?>? _authUidSubscription;
  Completer<void>? _firstAuthState;
  int _accountSessionGeneration = 0;
  Uri? _emailCallbackBaseUri;
  Timer? _emailVerificationPollTimer;
  bool _emailVerificationWatchActive = false;
  bool _awaitingPasswordResetCallback = false;
  bool _passwordResetConfirmed = false;
  DateTime? _verificationResendAvailableAt;
  Timer? _verificationCooldownTimer;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  PendingGoogleProfile? get pendingGoogleProfile => _pendingGoogleProfile;
  bool get hasPendingGoogleProfile => _pendingGoogleProfile != null;
  Set<AuthProviderKind> get providerKinds => Set.unmodifiable(_providerKinds);
  bool get hasPasswordProvider =>
      _providerKinds.contains(AuthProviderKind.password);
  bool get isGoogleOnly =>
      _providerKinds.contains(AuthProviderKind.google) && !hasPasswordProvider;
  bool get isLoading => _isLoading;
  bool get isOfflineRestoredTrainee => _isOfflineRestoredTrainee;
  AuthInitializationState get initializationState => _initializationState;
  AuthInitializationFailure? get initializationFailure =>
      _initializationFailure;
  int get accountSessionGeneration => _accountSessionGeneration;
  bool get isAuthenticatedSessionReady =>
      !_disposed &&
      _initializationState == AuthInitializationState.ready &&
      !_isLoading &&
      _currentUser != null;
  bool get needsEmailVerification =>
      _currentUser != null &&
      _hasSupportedProductRole(_currentUser!) &&
      _emailVerified == false;
  String? get teacherAuthInfoMessage => _teacherAuthInfoMessage;
  String? get teacherAuthErrorMessage => _teacherAuthErrorMessage;
  String? get pendingEmail => _pendingEmailChange?.pendingEmail;
  bool get hasPendingEmailChange =>
      _pendingEmailChange != null && !_isPendingEmailExpired;
  bool get isCheckingPendingEmailChange => _checkingPendingEmail;
  String? get pendingEmailRecoveryError => _pendingEmailRecoveryError;

  String? takePendingEmailChangeSuccessMessage() {
    final message = _pendingEmailChangeSuccessMessage;
    _pendingEmailChangeSuccessMessage = null;
    return message;
  }

  bool get hasConfirmedPasswordResetLink => _passwordResetConfirmed;
  int get verificationResendSecondsRemaining {
    final availableAt = _verificationResendAvailableAt;
    if (availableAt == null) return 0;
    final remainingMilliseconds = availableAt
        .difference(DateTime.now())
        .inMilliseconds;
    if (remainingMilliseconds <= 0) return 0;
    return (remainingMilliseconds + 999) ~/ 1000;
  }

  bool get canResendVerification => verificationResendSecondsRemaining == 0;

  String? takeAccountDeletedMessage() {
    final message = _accountDeletedMessage;
    _accountDeletedMessage = null;
    return message;
  }

  bool get _isPendingEmailExpired {
    final pending = _pendingEmailChange;
    if (pending == null) return true;
    return DateTime.now().isAfter(pending.expiresAt);
  }

  @visibleForTesting
  Future<void> waitForPendingEmailCheckIdle() async {
    while (_pendingEmailCheckInFlight != null || _checkingPendingEmail) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @visibleForTesting
  void seedAuthenticatedUser(User user) {
    _currentUser = user;
    _accountSessionGeneration++;
    _providerKinds = const {AuthProviderKind.password};
    _isLoading = false;
    _initializationState = AuthInitializationState.ready;
    _initializationFailure = null;
    notifyListeners();
  }

  /// Restores the persisted auth session and always reaches a terminal state.
  ///
  /// The in-flight future is installed before the first notification so a
  /// listener-triggered retry cannot start a second restoration attempt.
  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    final inFlight = _initializationInFlight;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _initializationInFlight = completer.future;
    unawaited(_runInitialization(completer));
    return completer.future;
  }

  Future<void> _runInitialization(Completer<void> completer) async {
    try {
      _beginInitialization();
      final awaitInitialAuthState = _awaitInitialAuthState;
      if (awaitInitialAuthState != null) {
        await awaitInitialAuthState();
      } else {
        await _waitForInitialAuthState();
      }

      final authUid = _readCurrentAuthUid();
      if (authUid == null || authUid.isEmpty) {
        final restoredGoogle = await _googleRepository?.restoreGoogleSignIn();
        if (restoredGoogle is PendingGoogleSignIn) {
          // The access code is deliberately not durable. A restored incomplete
          // flow must make the user choose a role again and re-enter the code
          // for Teacher completion.
          _completeInitialization(
            currentUser: null,
            pendingGoogleProfile: restoredGoogle.profile.copyWith(
              intent: GoogleOnboardingIntent.unspecified,
              clearTeacherAccessCode: true,
            ),
            providerKinds: const {AuthProviderKind.google},
            emailVerified: null,
          );
          return;
        }
        if (restoredGoogle is ExistingGoogleProfile) {
          if (!_hasSupportedProductRole(restoredGoogle.user)) {
            await _repository.clearCurrentUser();
            _completeInitialization(
              currentUser: null,
              providerKinds: const {},
              emailVerified: null,
            );
            return;
          }
          await _completeAuthoritativeInitialization(
            restoredGoogle.user,
            authUid: null,
          );
          return;
        }
      }
      final restoration = await _restorePersistedProfile(authUid);
      if (restoration.status == PersistedProfileRestorationStatus.unavailable) {
        final offlineSnapshot = authUid == null
            ? null
            : await _traineeProfileSnapshotStore.load(authUid);
        if (offlineSnapshot != null &&
            offlineSnapshot.userId == authUid &&
            offlineSnapshot.user.isTrainee) {
          _isOfflineRestoredTrainee = true;
          _completeInitialization(
            currentUser: offlineSnapshot.user,
            providerKinds: const {},
            emailVerified: offlineSnapshot.emailVerified,
          );
          return;
        }
        // A locally restored auth identity without a matching,
        // authoritative Trainee snapshot cannot enter the product offline.
        _completeInitialization(
          currentUser: null,
          providerKinds: const {},
          emailVerified: null,
        );
        return;
      }

      if (restoration.status == PersistedProfileRestorationStatus.signedOut ||
          restoration.status ==
              PersistedProfileRestorationStatus.invalidProfile) {
        _completeInitialization(
          currentUser: null,
          providerKinds: const {},
          emailVerified: null,
        );
        return;
      }

      final loadedUser = restoration.user;
      if (loadedUser != null && !_hasSupportedProductRole(loadedUser)) {
        // Preserve the existing fail-closed unsupported-role behavior without
        // publishing the malformed profile or emitting an intermediate ready
        // state while the persisted auth session is being cleared.
        await _repository.clearCurrentUser();
        _completeInitialization(
          currentUser: null,
          providerKinds: const {},
          emailVerified: null,
        );
        return;
      }

      // Teacher claim finalization remains mandatory. Nothing is published to
      // currentUser until this and the remaining restoration reads succeed.
      await _completeAuthoritativeInitialization(loadedUser, authUid: authUid);
    } catch (error, stackTrace) {
      _failInitialization(error, stackTrace);
    } finally {
      if (identical(_initializationInFlight, completer.future)) {
        _initializationInFlight = null;
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<PersistedProfileRestoration> _restorePersistedProfile(
    String? authUid,
  ) async {
    // The production repository exposes a typed outcome. The legacy path is
    // retained for existing focused test doubles, but it never permits a
    // cached offline fallback because it cannot prove the auth identity.
    final restorationRepository =
        _repository is PersistedProfileRestorationRepository
        ? _repository as PersistedProfileRestorationRepository
        : null;
    if (restorationRepository == null) {
      if (authUid == null || authUid.isEmpty) {
        return const PersistedProfileRestoration.signedOut();
      }
      final user = await _repository.loadPersistedUser().timeout(
        _profileRestorationTimeout,
        onTimeout: () => null,
      );
      return user == null
          ? const PersistedProfileRestoration.signedOut()
          : PersistedProfileRestoration.authoritative(user);
    }
    if (authUid == null || authUid.isEmpty) {
      return const PersistedProfileRestoration.signedOut();
    }
    return restorationRepository.restorePersistedProfile().timeout(
      _profileRestorationTimeout,
      onTimeout: () => const PersistedProfileRestoration.unavailable(),
    );
  }

  Future<void> _completeAuthoritativeInitialization(
    User? user, {
    required String? authUid,
  }) async {
    if (user != null) await _ensureTeacherRoleClaim(user);
    final providerKinds = await _loadProviderKinds(user);
    final emailVerified = await _loadEmailVerificationState(user);
    await _cacheAuthoritativeTraineeSnapshot(
      user,
      emailVerified: emailVerified == true,
      expectedAuthUid: authUid,
    );
    _completeInitialization(
      currentUser: user,
      providerKinds: providerKinds,
      emailVerified: emailVerified,
    );
  }

  Future<void> _waitForInitialAuthState() {
    final existing = _firstAuthState;
    if (existing != null) return existing.future;

    final firstState = Completer<void>();
    _firstAuthState = firstState;
    final stream =
        _authUidChangesOverride ??
        ElixrSupabase.client.auth.onAuthStateChange.map(
          (state) => state.session?.user.id,
        );
    _authUidSubscription = stream.listen(
      (authUid) {
        if (!firstState.isCompleted) firstState.complete();
        _handleAuthIdentityChanged(authUid);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!firstState.isCompleted) {
          firstState.completeError(error, stackTrace);
        } else if (kDebugMode) {
          debugPrint('Auth state listener failed: $error');
          debugPrint('$stackTrace');
        }
      },
    );
    return firstState.future;
  }

  @visibleForTesting
  void handleAuthIdentityChanged(String? authUid) {
    _handleAuthIdentityChanged(authUid);
  }

  void _handleAuthIdentityChanged(String? authUid) {
    if (_disposed) return;
    final productUid = _currentUser?.id?.trim();
    final normalizedAuthUid = authUid?.trim();
    if (productUid == null || productUid.isEmpty) return;
    if (normalizedAuthUid == productUid) return;

    _clearPendingEmailChange(clearError: true);
    _invalidatePublishedAccount();
    notifyListeners();
  }

  Future<void> _beginAuthTransition() async {
    if (_disposed) return;
    final hadPublishedAccount = _currentUser != null;
    final hadPendingProfile = _pendingGoogleProfile != null;
    final pendingEmailCheck = _pendingEmailCheckInFlight;
    final hadPendingEmailChange = _pendingEmailChange != null;
    _invalidatePublishedAccount();
    _pendingGoogleProfile = null;
    _clearPendingEmailChange(clearError: true);
    if (!hadPublishedAccount &&
        !hadPendingProfile &&
        !hadPendingEmailChange &&
        pendingEmailCheck == null) {
      return;
    }

    notifyListeners();
    await _accountScopeTeardownBarrier?.call();
    if (pendingEmailCheck != null) {
      try {
        await pendingEmailCheck;
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Abandoned pending email recovery failed: $error');
          debugPrint('$stackTrace');
        }
      }
    }
  }

  void _invalidatePublishedAccount() {
    _accountSessionGeneration++;
    _currentUser = null;
    _providerKinds = const {};
    _emailVerified = null;
    _isOfflineRestoredTrainee = false;
  }

  void _markAuthenticatedSessionReady() {
    _accountSessionGeneration++;
    _initializationFailure = null;
    _initializationState = AuthInitializationState.ready;
    _isLoading = false;
  }

  String? _readCurrentAuthUid() {
    try {
      return (_currentAuthUidOverride?.call() ??
              ElixrSupabase.client.auth.currentUser?.id)
          ?.trim();
    } catch (_) {
      return null;
    }
  }

  bool _isCurrentAccountTask({
    required String userId,
    required int generation,
  }) {
    return !_disposed &&
        generation == _accountSessionGeneration &&
        isAuthenticatedSessionReady &&
        _currentUser?.id?.trim() == userId &&
        _readCurrentAuthUid() == userId;
  }

  void _beginInitialization() {
    _accountSessionGeneration++;
    _currentUser = null;
    _pendingGoogleProfile = null;
    _providerKinds = const {};
    _emailVerified = null;
    _isOfflineRestoredTrainee = false;
    _clearTeacherAuthMessages();
    _initializationFailure = null;
    _initializationState = AuthInitializationState.loading;
    _isLoading = true;
    if (!_disposed) notifyListeners();
  }

  void _completeInitialization({
    required User? currentUser,
    PendingGoogleProfile? pendingGoogleProfile,
    required Set<AuthProviderKind> providerKinds,
    required bool? emailVerified,
  }) {
    if (_disposed) return;
    _currentUser = currentUser;
    _accountSessionGeneration++;
    _pendingGoogleProfile = pendingGoogleProfile;
    _providerKinds = Set.unmodifiable(providerKinds);
    _emailVerified = emailVerified;
    _initializationFailure = null;
    _initializationState = AuthInitializationState.ready;
    _isLoading = false;
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
    _scheduleLeaderboardPresenceTouch();
  }

  void _failInitialization(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _currentUser = null;
    _pendingGoogleProfile = null;
    _providerKinds = const {};
    _emailVerified = null;
    _isOfflineRestoredTrainee = false;
    _initializationFailure = _initializationFailureFor(error);
    _initializationState = AuthInitializationState.failed;
    _isLoading = false;
    if (kDebugMode) {
      debugPrint('Auth initialization failed: $error');
      debugPrint('$stackTrace');
    }
    notifyListeners();
  }

  AuthInitializationFailure _initializationFailureFor(Object error) {
    if (error is TeacherRoleClaimException) {
      final String message;
      switch (error.kind) {
        case TeacherRoleClaimFailureKind.invalidEvidence:
          message =
              'ELIXR could not verify your Teacher access. Check your account setup and try again.';
        case TeacherRoleClaimFailureKind.unavailable:
          message =
              'ELIXR could not refresh your Teacher authorization. Check your connection and try again.';
        case TeacherRoleClaimFailureKind.missingClaim:
          message =
              'ELIXR could not finish verifying your Teacher access. Please try again.';
      }
      return AuthInitializationFailure(
        kind: AuthInitializationFailureKind.teacherAuthorization,
        message: message,
      );
    }
    if (error is AuthFailure && error.kind == AuthFailureKind.missingProfile) {
      return const AuthInitializationFailure(
        kind: AuthInitializationFailureKind.authentication,
        message: TeacherAuthMessages.missingProfile,
      );
    }
    return const AuthInitializationFailure(
      kind: AuthInitializationFailureKind.unknown,
      message:
          "ELIXR couldn't finish preparing your session. Check your connection and try again.",
    );
  }

  Future<void> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required RegistrationLegalConsent legalConsent,
  }) async {
    await _beginAuthTransition();
    _clearTeacherAuthMessages();
    final user = await _repository.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      password: password,
      defaultRole: AppConstants.defaultRole,
      legalConsent: legalConsent,
    );
    _currentUser = user;
    _markAuthenticatedSessionReady();
    _pendingGoogleProfile = null;
    await _refreshProviderKinds();
    try {
      await _repository.requestCurrentEmailVerification();
      _teacherAuthInfoMessage = TeacherAuthMessages.verificationSent;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
    }
    await _refreshEmailVerificationState();
    notifyListeners();

    // Seed public visibility before achievement sync. Sync/repair paths create
    // private roots when missing; seeding first keeps new accounts public.
    final seedRepository = _publicProfileRepository;
    final seedUserId = user.id?.trim();
    if (seedRepository != null && seedUserId != null && seedUserId.isNotEmpty) {
      try {
        await seedRepository.seedNewAccountPublicProfile(
          userId: seedUserId,
          displayName: user.fullName,
          profilePictureUrl: user.profilePictureUrl,
          role: user.role,
        );
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'Public profile seed failed: userId=$seedUserId error=$error',
          );
          debugPrint('$stackTrace');
        }
      }
    }

    _scheduleClaimedAchievementProjectionSync();
    _scheduleLeaderboardPresenceTouch();
  }

  /// Explicit Teacher registration. Seeds the public-profile identity root
  /// (same default as Trainees) but does not seed trainee gamification docs.
  /// Requests email verification before shell access.
  Future<void> registerTeacher({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    await _beginAuthTransition();
    _clearTeacherAuthMessages();
    final user = await _repository.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      password: password,
      defaultRole: User.roleTeacher,
      teacherAccessCode: teacherAccessCode,
      legalConsent: legalConsent,
    );
    if (!user.isTeacher) {
      await logout();
      throw Exception(TeacherAuthMessages.notATeacher);
    }
    // Until the email is confirmed there is no auth session to verify; the
    // sign-up transaction already consumed the access code atomically, and
    // the claim is re-verified when the confirmed session is restored.
    if (_readCurrentAuthUid() == user.id?.trim()) {
      await _ensureTeacherRoleClaim(user);
    }
    _currentUser = user;
    _markAuthenticatedSessionReady();
    try {
      await _repository.requestCurrentEmailVerification();
      _teacherAuthInfoMessage = TeacherAuthMessages.verificationSent;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
    }
    await _refreshEmailVerificationState();
    notifyListeners();

    await _seedNewAccountPublicProfile(user);
    _scheduleLeaderboardPresenceTouch();
  }

  Future<void> login({required String email, required String password}) async {
    await _beginAuthTransition();
    _clearTeacherAuthMessages();
    User user;
    try {
      user = await _repository.login(email: email, password: password);
    } catch (error, stackTrace) {
      if (_isBackendAvailabilityFailure(error) &&
          await _restoreOfflineTraineeForLogin(email)) {
        return;
      }
      if (error is AuthFailure &&
          error.kind == AuthFailureKind.missingProfile &&
          error.pendingProfile != null) {
        _currentUser = null;
        _pendingGoogleProfile = error.pendingProfile;
        _providerKinds = const {AuthProviderKind.password};
        _emailVerified = null;
        notifyListeners();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!_hasSupportedProductRole(user)) {
      await _repository.clearCurrentUser();
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    await _ensureTeacherRoleClaim(user);
    _currentUser = user;
    _markAuthenticatedSessionReady();
    _pendingGoogleProfile = null;
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
    _scheduleLeaderboardPresenceTouch();
  }

  /// Re-enters a previously authenticated Trainee session after an online
  /// password sign-in cannot reach the auth server.
  ///
  /// The password is deliberately not checked or retained locally. The
  /// security boundary is the auth identity already persisted on this
  /// device, and both its UID and the entered email must match the locally
  /// cached authoritative profile. Explicit logout removes that profile and
  /// clears the auth identity, so it cannot use this path.
  Future<bool> _restoreOfflineTraineeForLogin(String email) async {
    if (_repository is! PersistedProfileRestorationRepository) return false;
    final authUid = _readCurrentAuthUid();
    if (authUid == null || authUid.isEmpty) return false;
    final snapshot = await _traineeProfileSnapshotStore.load(authUid);
    if (snapshot == null ||
        snapshot.userId != authUid ||
        !snapshot.user.isTrainee ||
        snapshot.user.email.trim().toLowerCase() !=
            email.trim().toLowerCase()) {
      return false;
    }
    _isOfflineRestoredTrainee = true;
    _currentUser = snapshot.user;
    _pendingGoogleProfile = null;
    _providerKinds = const {};
    _emailVerified = snapshot.emailVerified;
    _markAuthenticatedSessionReady();
    notifyListeners();
    return true;
  }

  bool _isBackendAvailabilityFailure(Object error) {
    if (error is AuthFailure) {
      if (error.kind == AuthFailureKind.network) return true;
      if (error.kind != AuthFailureKind.unknown) return false;
      final message = error.message.toLowerCase();
      return message.contains('network') ||
          message.contains('connection') ||
          message.contains('unavailable') ||
          message.contains('timed out');
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException) {
      return true;
    }
    return isBackendUnavailableError(error) ||
        error is sb.AuthRetryableFetchException;
  }

  Future<void> signInWithGoogle() async {
    await _beginAuthTransition();
    _clearTeacherAuthMessages();
    final googleRepository = _googleRepository;
    if (googleRepository == null) {
      throw Exception('Google sign-in is unavailable.');
    }
    final result = await googleRepository.signInWithGoogle();
    if (result is PendingGoogleSignIn) {
      _currentUser = null;
      _pendingGoogleProfile = result.profile.copyWith(
        intent: GoogleOnboardingIntent.trainee,
        clearTeacherAccessCode: true,
      );
      _providerKinds = const {AuthProviderKind.google};
      _emailVerified = true;
      notifyListeners();
      return;
    }
    final user = (result as ExistingGoogleProfile).user;
    if (!_hasSupportedProductRole(user)) {
      await _repository.clearCurrentUser();
      _providerKinds = const {};
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    await _ensureTeacherRoleClaim(user);
    _pendingGoogleProfile = null;
    _currentUser = user;
    _markAuthenticatedSessionReady();
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
    _scheduleLeaderboardPresenceTouch();
  }

  /// Validates the shared Teacher registration gate before the user chooses
  /// Google or email/password. The code is consumed only when the profile is
  /// created, so final registration still validates it atomically.
  Future<void> prevalidateTeacherAccessCode(String teacherAccessCode) async {
    _clearTeacherAuthMessages();
    final normalizedCode = CoachCode.tryNormalize(teacherAccessCode);
    if (normalizedCode == null) {
      throw Exception(TeacherAuthMessages.accessCodeInvalid);
    }
    // Format-only before authentication. The final authenticated transaction
    // performs authoritative validation and one-time consumption.
  }

  /// Starts the Teacher Google registration path after validating the
  /// one-time access code. The normalized code stays only in the pending
  /// in-memory Google profile until final completion.
  Future<void> signInWithGoogleTeacher({
    required String teacherAccessCode,
  }) async {
    await _beginAuthTransition();
    _clearTeacherAuthMessages();
    final normalizedCode = CoachCode.tryNormalize(teacherAccessCode);
    if (normalizedCode == null) {
      throw Exception(TeacherAuthMessages.accessCodeInvalid);
    }
    final googleRepository = _teacherGoogleRepository;
    if (googleRepository == null) {
      throw Exception('Google sign-in is unavailable.');
    }
    final result = await googleRepository.signInWithGoogleTeacher(
      teacherAccessCode: normalizedCode,
    );
    if (result is PendingGoogleSignIn) {
      _currentUser = null;
      _pendingGoogleProfile = result.profile.copyWith(
        intent: GoogleOnboardingIntent.teacher,
        teacherAccessCode: normalizedCode,
      );
      _providerKinds = const {AuthProviderKind.google};
      _emailVerified = true;
      notifyListeners();
      return;
    }

    final user = (result as ExistingGoogleProfile).user;
    if (user.isTrainee) {
      await _repository.clearCurrentUser();
      _providerKinds = const {};
      throw Exception(TeacherAuthMessages.googleRoleImmutable);
    }
    if (!_hasSupportedProductRole(user) || !user.isTeacher) {
      await _repository.clearCurrentUser();
      _providerKinds = const {};
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    await _ensureTeacherRoleClaim(user);
    _pendingGoogleProfile = null;
    _currentUser = user;
    _markAuthenticatedSessionReady();
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
    _scheduleLeaderboardPresenceTouch();
  }

  Future<void> completeGoogleProfile({
    required String firstName,
    String? middleName,
    required String lastName,
    required RegistrationLegalConsent legalConsent,
  }) async {
    final pending = _pendingGoogleProfile;
    if (pending == null) {
      throw Exception('No Google profile is waiting for completion.');
    }
    if (pending.intent == GoogleOnboardingIntent.teacher) {
      throw Exception(
        'Complete this Google account as a Teacher and provide the access code.',
      );
    }
    final googleRepository = _googleRepository;
    if (googleRepository == null) {
      throw Exception('Google profile completion is unavailable.');
    }
    final user = await googleRepository.completeGoogleProfile(
      pendingProfile: pending,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      legalConsent: legalConsent,
    );
    if (!user.isTrainee) {
      await _repository.clearCurrentUser();
      _pendingGoogleProfile = null;
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    _pendingGoogleProfile = null;
    _currentUser = user;
    _markAuthenticatedSessionReady();
    await _refreshProviderKinds();
    if (pending.identityProvider == ProfileIdentityProvider.google) {
      _emailVerified = true;
    } else {
      await _refreshEmailVerificationState();
    }
    notifyListeners();
    await _seedNewAccountPublicProfile(user);
    _scheduleClaimedAchievementProjectionSync();
    _scheduleLeaderboardPresenceTouch();
  }

  /// Completes Google onboarding as a Teacher. The repository performs the
  /// final atomic access-code consumption and profile creation. Seeds the
  /// public-profile identity root (same default as Trainees) but does not
  /// seed trainee gamification documents.
  Future<void> completeGoogleTeacherProfile({
    required String firstName,
    String? middleName,
    required String lastName,
    required String teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    final pending = _pendingGoogleProfile;
    if (pending == null) {
      throw Exception('No Google profile is waiting for completion.');
    }
    final normalizedCode = CoachCode.tryNormalize(teacherAccessCode);
    if (normalizedCode == null) {
      throw Exception(TeacherAuthMessages.accessCodeInvalid);
    }
    final googleRepository = _teacherGoogleRepository;
    if (googleRepository == null) {
      throw Exception('Google profile completion is unavailable.');
    }
    final user = await googleRepository.completeGoogleTeacherProfile(
      pendingProfile: pending,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      teacherAccessCode: normalizedCode,
      legalConsent: legalConsent,
    );
    if (!user.isTeacher) {
      await _repository.clearCurrentUser();
      _pendingGoogleProfile = null;
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    await _ensureTeacherRoleClaim(user);
    _pendingGoogleProfile = null;
    _currentUser = user;
    _markAuthenticatedSessionReady();
    await _refreshProviderKinds();
    if (pending.identityProvider == ProfileIdentityProvider.google) {
      _emailVerified = true;
    } else {
      await _refreshEmailVerificationState();
    }
    notifyListeners();
    await _seedNewAccountPublicProfile(user);
    _scheduleLeaderboardPresenceTouch();
  }

  Future<void> cancelGoogleOnboarding() async {
    final pending = _pendingGoogleProfile;
    await _beginAuthTransition();
    try {
      if (pending != null) {
        final googleRepository = _googleRepository;
        if (googleRepository != null) {
          await googleRepository.cancelGoogleOnboarding(pending);
        } else {
          await _repository.clearCurrentUser();
        }
      } else {
        await _repository.clearCurrentUser();
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> _refreshProviderKinds() async {
    _providerKinds = await _loadProviderKinds(_currentUser);
  }

  Future<Set<AuthProviderKind>> _loadProviderKinds(User? user) async {
    if (user == null) return const {};
    return await _googleRepository?.currentProviderKinds() ??
        const {AuthProviderKind.password};
  }

  Future<void> _seedNewAccountPublicProfile(User user) async {
    final repository = _publicProfileRepository;
    final userId = user.id?.trim();
    if (repository == null || userId == null || userId.isEmpty) return;
    try {
      await repository.seedNewAccountPublicProfile(
        userId: userId,
        displayName: user.fullName,
        profilePictureUrl: user.profilePictureUrl,
        role: user.role,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Public profile seed failed: userId=$userId error=$error');
        debugPrint('$stackTrace');
      }
    }
  }

  /// Requests a password-reset email for [email].
  ///
  /// Does not change [currentUser]. Callers should show a generic success
  /// message so account existence is not revealed. After the user completes
  /// the email link, [hasConfirmedPasswordResetLink] becomes true.
  Future<void> sendPasswordResetEmail({required String email}) async {
    _passwordResetConfirmed = false;
    _awaitingPasswordResetCallback = true;
    String? continueUrl;
    try {
      final base = await _ensureEmailCallbackServer();
      continueUrl = _continueUri(base, mode: 'reset').toString();
    } catch (_) {
      // Auto-detect is best-effort; the email can still be sent.
    }
    try {
      await _repository.sendPasswordResetEmail(
        email: email,
        continueUrl: continueUrl,
      );
    } catch (_) {
      _awaitingPasswordResetCallback = false;
      if (!_emailVerificationWatchActive) {
        unawaited(_stopEmailCallbackServerAfterRequestFailure());
      }
      rethrow;
    }
    notifyListeners();
  }

  Future<void> endPasswordResetWatch() async {
    _awaitingPasswordResetCallback = false;
    if (!_emailVerificationWatchActive) {
      await _stopEmailCallbackServer();
    }
  }

  /// Best-effort last-active write for an existing leaderboard document.
  ///
  /// Never fails authentication or creates a ranking row. Safe to call from
  /// successful auth restore/login and from application foreground resume.
  void touchLeaderboardPresence() {
    _scheduleLeaderboardPresenceTouch();
  }

  void _scheduleLeaderboardPresenceTouch() {
    final userId = _currentUser?.id?.trim();
    if (userId == null || userId.isEmpty) return;

    final repository = _leaderboardRepository;
    if (repository == null) return;
    final generation = _accountSessionGeneration;

    unawaited(
      Future<void>.microtask(() async {
        if (!_isCurrentAccountTask(userId: userId, generation: generation)) {
          return;
        }
        try {
          await repository.touchLastActive(userId: userId);
        } catch (error, stackTrace) {
          if (kDebugMode) {
            debugPrint(
              'Leaderboard last-active touch failed: '
              'requestedUserId=$userId '
              'authUserId=${_readCurrentAuthUid()} '
              'productUserId=${_currentUser?.id?.trim()} error=$error',
            );
            debugPrint('$stackTrace');
          }
        }
      }),
    );
  }

  /// Best-effort owner-side repair of missing public achievement projections.
  ///
  /// Never fails authentication. Concurrent calls for the same user are
  /// coalesced by [PublicProfileRepository.syncClaimedAchievementProjections].
  void _scheduleClaimedAchievementProjectionSync() {
    final user = _currentUser;
    final userId = user?.id?.trim();
    if (user == null || user.isTeacher || userId == null || userId.isEmpty) {
      return;
    }

    final repository = _publicProfileRepository;
    if (repository == null) return;
    final generation = _accountSessionGeneration;

    unawaited(
      Future<void>.microtask(() async {
        if (!_isCurrentAccountTask(userId: userId, generation: generation)) {
          return;
        }
        try {
          await repository.syncClaimedAchievementProjections(
            userId: userId,
            displayName: user.fullName,
            profilePictureUrl: user.profilePictureUrl,
            isCurrentIdentity: () =>
                _isCurrentAccountTask(userId: userId, generation: generation),
          );
        } catch (error, stackTrace) {
          if (kDebugMode) {
            debugPrint(
              'Public achievement projection sync failed: '
              'userId=$userId error=$error',
            );
            debugPrint('$stackTrace');
          }
        }
      }),
    );
  }

  Future<void> logout() async {
    final userId = _currentUser?.id?.trim();
    await _beginAuthTransition();
    _clearPendingEmailChange(clearError: true);
    _clearTeacherAuthMessages();
    _emailVerified = null;
    _stopEmailVerificationPolling();
    _emailVerificationWatchActive = false;
    _awaitingPasswordResetCallback = false;
    _passwordResetConfirmed = false;
    _clearVerificationResendCooldown();
    await _stopEmailCallbackServer();
    await _repository.clearCurrentUser();
    if (userId != null && userId.isNotEmpty) {
      await _purgeTraineeProfileSnapshot(userId);
      await _purgeTraineeProgressionSnapshot(userId);
    }
  }

  Future<bool> resendVerificationEmail() async {
    final user = _currentUser;
    if (user == null || !_hasSupportedProductRole(user)) return false;
    if (!canResendVerification) return false;
    _clearTeacherAuthMessages();
    try {
      await requestCurrentEmailVerification();
      _teacherAuthInfoMessage = TeacherAuthMessages.verificationSent;
      notifyListeners();
      return true;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkEmailVerification() async {
    final user = _currentUser;
    if (user == null || !_hasSupportedProductRole(user)) return false;
    final expectTeacher = user.isTeacher;
    _clearTeacherAuthMessages();
    try {
      await _ensureTeacherRoleClaim(user);
      final verified = await _repository.isCurrentEmailVerified();
      if (!verified) {
        _teacherAuthErrorMessage = TeacherAuthMessages.emailNotVerifiedYet;
        notifyListeners();
        return false;
      }
      final refreshed = await _repository.refreshAuthenticatedUser();
      if (refreshed == null || !_hasSupportedProductRole(refreshed)) {
        await logout();
        _teacherAuthErrorMessage = TeacherAuthMessages.unsupportedRole;
        notifyListeners();
        return false;
      }
      if (expectTeacher && !refreshed.isTeacher) {
        await logout();
        _teacherAuthErrorMessage = TeacherAuthMessages.notATeacher;
        notifyListeners();
        return false;
      }
      _currentUser = refreshed;
      await _refreshEmailVerificationState();
      notifyListeners();
      return true;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
      notifyListeners();
      return false;
    }
  }

  /// Ensures a Teacher session has a server-verified Teacher role and a
  /// confirmed email before privileged writes.
  ///
  /// Reuses [AuthRepositoryBase.isCurrentEmailVerified], which reloads the
  /// auth user. Trainee sessions and missing users fail closed. Transient
  /// repository errors fail closed without signing the Teacher out.
  Future<bool> ensureTeacherAuthorizationFresh() async {
    final user = _currentUser;
    if (user == null || !user.isTeacher) {
      return false;
    }

    try {
      await _ensureTeacherRoleClaim(user);
      final verified = await _repository.isCurrentEmailVerified();
      if (!verified) {
        final changed = _emailVerified != false;
        _emailVerified = false;
        if (changed) {
          notifyListeners();
        }
        return false;
      }

      final previousVerified = _emailVerified;
      _emailVerified = true;
      final refreshed = await _repository.refreshAuthenticatedUser();
      if (refreshed == null || !refreshed.isTeacher) {
        await logout();
        _teacherAuthErrorMessage = TeacherAuthMessages.notATeacher;
        notifyListeners();
        return false;
      }

      _currentUser = refreshed;
      if (previousVerified != true) {
        notifyListeners();
      }
      return true;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
      notifyListeners();
      return false;
    }
  }

  void clearTeacherAuthMessages() => _clearTeacherAuthMessages();

  Future<void> _refreshEmailVerificationState() async {
    _emailVerified = await _loadEmailVerificationState(_currentUser);
    await _cacheAuthoritativeTraineeSnapshot(
      _currentUser,
      emailVerified: _emailVerified == true,
      expectedAuthUid: _readCurrentAuthUid(),
    );
  }

  Future<bool?> _loadEmailVerificationState(User? user) async {
    if (user == null || !_hasSupportedProductRole(user)) return null;
    try {
      return await _repository.isCurrentEmailVerified();
    } catch (_) {
      return false;
    }
  }

  Future<void> _cacheAuthoritativeTraineeSnapshot(
    User? user, {
    required bool emailVerified,
    required String? expectedAuthUid,
  }) async {
    // Only the production typed restoration capability proves the semantics
    // required for an offline-auth cache. Legacy repositories remain online
    // only and therefore cannot create one.
    if (_repository is! PersistedProfileRestorationRepository) return;
    if (user == null || !user.isTrainee) return;
    final userId = user.id?.trim();
    // An explicit expected UID is supplied on production cold start. Never
    // write a cache entry until the auth and ELIXR identities agree.
    if (userId == null || userId.isEmpty) return;
    if (expectedAuthUid != null && expectedAuthUid != userId) return;
    if (expectedAuthUid == null &&
        _currentAuthUidOverride == null &&
        _readCurrentAuthUid() != userId) {
      return;
    }
    final snapshot = TraineeProfileSnapshot.fromAuthoritativeUser(
      user,
      emailVerified: emailVerified,
    );
    if (snapshot == null) return;
    try {
      await _traineeProfileSnapshotStore.save(snapshot);
    } catch (error) {
      // Snapshot persistence is an availability enhancement, never an
      // authorization dependency. A local-storage failure must not invalidate
      // an otherwise authoritative auth session.
      if (kDebugMode) {
        debugPrint('Trainee profile snapshot write failed: $error');
      }
    }
  }

  Future<void> _purgeTraineeProfileSnapshot(String userId) async {
    if (_repository is! PersistedProfileRestorationRepository) return;
    try {
      await _traineeProfileSnapshotStore.purge(userId);
    } catch (error) {
      // Account deletion/sign-out has already changed auth state; local
      // cache cleanup remains best effort and cannot resurrect that identity.
      if (kDebugMode) {
        debugPrint('Trainee profile snapshot purge failed: $error');
      }
    }
  }

  Future<void> _purgeTraineeProgressionSnapshot(String userId) async {
    try {
      await _traineeProgressionSnapshotStore.purge(userId);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Trainee progression snapshot purge failed: $error');
      }
    }
  }

  void _clearTeacherAuthMessages() {
    _teacherAuthInfoMessage = null;
    _teacherAuthErrorMessage = null;
  }

  bool _hasSupportedProductRole(User user) => user.isTrainee || user.isTeacher;

  Future<void> _ensureTeacherRoleClaim(User user) async {
    if (!user.isTeacher) return;
    final repository = _teacherAuthorizationRepository;
    if (repository == null) {
      throw const TeacherRoleClaimException(
        TeacherRoleClaimFailureKind.unavailable,
        'Teacher authorization is unavailable. Please try again.',
      );
    }
    await repository.ensureTeacherRoleClaim();
  }

  String _sanitizeTeacherAuthError(Object error) {
    if (error is MissingUserProfileException) {
      return TeacherAuthMessages.missingProfile;
    }
    var message = error.toString();
    const prefix = 'Exception: ';
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length);
    }
    if (message.trim().isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return message;
  }

  /// Updates the display name and, optionally, uploads a new profile
  /// avatar to private Storage.
  ///
  /// When [newProfileImageBytes] and [newProfileImageContentType] are both
  /// provided, the image is uploaded first; the profile is only updated after
  /// the upload succeeds. A name-only update never touches Storage.
  ///
  /// Prefer [updateProfilePicture] for image-only updates so unsaved name or
  /// email edits are never written as a side effect.
  Future<void> updateProfileDetails({
    required String firstName,
    String? middleName,
    required String lastName,
    Uint8List? newProfileImageBytes,
    String? newProfileImageContentType,
  }) async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }
    final userId = _currentUser!.id!;
    final previousUser = _currentUser!;

    ProfilePictureUpdate? pictureUpdate;
    if (newProfileImageBytes != null && newProfileImageContentType != null) {
      pictureUpdate = await _uploadProfilePicture(
        userId: userId,
        bytes: newProfileImageBytes,
        contentType: newProfileImageContentType,
      );
    }

    try {
      _currentUser = await _repository.updateProfileDetails(
        userId: userId,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        profilePictureUpdate: pictureUpdate,
      );
    } catch (error) {
      if (pictureUpdate != null) {
        // The database did not accept the new image reference; do not leave an
        // orphaned object in Storage, and keep the previous profile intact.
        await _bestEffortDeleteImage(userId, pictureUpdate.storagePath!);
      }
      rethrow;
    }

    notifyListeners();
    await _afterSuccessfulPictureUpdate(
      userId: userId,
      previousUser: previousUser,
      pictureUpdate: pictureUpdate,
    );
  }

  /// Uploads and persists a new profile avatar without writing name or email.
  ///
  /// Reuses [ProfileImageRepository] upload/delete rules (content type, 5 MB
  /// limit, ownership paths) and refreshes [currentUser] + listeners so all
  /// avatar consumers update.
  Future<void> updateProfilePicture({
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }
    final userId = _currentUser!.id!;
    final previousUser = _currentUser!;

    final pictureUpdate = await _uploadProfilePicture(
      userId: userId,
      bytes: bytes,
      contentType: contentType,
    );

    try {
      _currentUser = await _repository.updateProfilePicture(
        userId: userId,
        profilePictureUpdate: pictureUpdate,
      );
    } catch (error) {
      await _bestEffortDeleteImage(userId, pictureUpdate.storagePath!);
      rethrow;
    }

    notifyListeners();
    await _afterSuccessfulPictureUpdate(
      userId: userId,
      previousUser: previousUser,
      pictureUpdate: pictureUpdate,
    );
  }

  /// Persists the authenticated Teacher's profile border independently from
  /// trainee leaderboard and achievement cosmetics.
  ///
  /// A missing or blank value clears the preference. The catalog check here is
  /// defense in depth; database policies remain the authoritative boundary for
  /// modified clients.
  Future<void> updateTeacherProfileBorder({String? profileBorderId}) async {
    final current = _currentUser;
    final userId = current?.id?.trim();
    if (current == null ||
        !current.isTeacher ||
        userId == null ||
        userId.isEmpty) {
      throw Exception(
        'Only an authenticated Teacher can update an avatar frame.',
      );
    }

    final trimmed = profileBorderId?.trim() ?? '';
    final normalized = trimmed.isEmpty ? null : trimmed;
    if (normalized != null && !isKnownProfileBorderId(normalized)) {
      throw ArgumentError('Unknown avatar frame.');
    }

    final repository = _teacherProfileBorderRepository;
    if (repository == null) {
      throw Exception('Avatar frame updates are unavailable.');
    }

    final updated = await repository.updateTeacherProfileBorder(
      userId: userId,
      profileBorderId: normalized,
    );
    if (_currentUser?.id?.trim() != userId || _currentUser?.isTeacher != true) {
      throw StateError(
        'The active account changed while updating the avatar frame.',
      );
    }
    if (updated.id != userId || !updated.isTeacher) {
      throw StateError(
        'The saved avatar frame belongs to a different account.',
      );
    }
    _currentUser = updated;
    notifyListeners();
  }

  /// Removes the current profile avatar without touching name or email edits.
  ///
  /// The database references are cleared first. The previous Storage
  /// object is then deleted using only its recorded, owner-scoped path.
  Future<void> removeProfilePicture() async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }

    final userId = _currentUser!.id!;
    final previousUser = _currentUser!;
    final hasPicture = [
      previousUser.profilePictureUrl,
      previousUser.profilePictureStoragePath,
      previousUser.profilePicturePath,
    ].any((value) => value?.trim().isNotEmpty == true);
    if (!hasPicture) return;

    const removal = ProfilePictureUpdate.remove();
    _currentUser = await _repository.updateProfilePicture(
      userId: userId,
      profilePictureUpdate: removal,
    );
    notifyListeners();
    await _afterSuccessfulPictureUpdate(
      userId: userId,
      previousUser: previousUser,
      pictureUpdate: removal,
    );
  }

  Future<ProfilePictureUpdate> _uploadProfilePicture({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uploaded = await _profileImageRepository.uploadProfileImage(
      userId: userId,
      bytes: bytes,
      contentType: contentType,
    );
    return ProfilePictureUpdate(
      url: uploaded.downloadUrl,
      storagePath: uploaded.storagePath,
    );
  }

  Future<void> _afterSuccessfulPictureUpdate({
    required String userId,
    required User previousUser,
    required ProfilePictureUpdate? pictureUpdate,
  }) async {
    final previousStoragePath = previousUser.profilePictureStoragePath;
    final isRemoval = pictureUpdate?.isRemoval == true;
    final replacedObjectPath =
        pictureUpdate != null &&
            !isRemoval &&
            previousStoragePath != null &&
            previousStoragePath.isNotEmpty &&
            previousStoragePath != pictureUpdate.storagePath
        ? previousStoragePath
        : null;

    // Every visible projection is updated before the previous object is
    // deleted, so no projection can reference a deleted object. On
    // replacement, the old object is kept whenever a projection may still
    // reference it (its sync failed); it is orphaned rather than broken.
    var leaderboardSynced = true;
    try {
      await _leaderboardRepository?.syncPublicProfile(
        userId: userId,
        displayName: _currentUser?.fullName ?? '',
        profilePictureUrl: _currentUser?.profilePictureUrl,
        clearProfilePicture: pictureUpdate?.isRemoval ?? false,
      );
    } catch (error, stackTrace) {
      leaderboardSynced = false;
      if (kDebugMode) {
        debugPrint(
          'Leaderboard public profile sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }

    // The public identity root is the only cross-account-safe source for a
    // saved avatar. Unlike leaderboard presence, a failed write here is a
    // correctness failure: the private profile would otherwise appear saved
    // while every Teacher still sees a stale avatar. Let it reach the caller
    // so the save is not reported as successful. A later authenticated
    // session will also repair the projection through the existing owner-side
    // projection sync.
    var publicIdentitySynced = false;
    try {
      await _publicProfileRepository?.updatePublicIdentity(
        userId: userId,
        displayName: _currentUser?.fullName ?? '',
        profilePictureUrl: _currentUser?.profilePictureUrl,
        role: _currentUser?.role,
        clearProfilePicture: isRemoval,
      );
      publicIdentitySynced = true;
    } finally {
      if (isRemoval &&
          previousStoragePath != null &&
          previousStoragePath.isNotEmpty) {
        // The user asked for the photo to be gone; delete it regardless.
        await _bestEffortDeleteImage(userId, previousStoragePath);
      } else if (replacedObjectPath != null &&
          leaderboardSynced &&
          publicIdentitySynced) {
        await _bestEffortDeleteImage(userId, replacedObjectPath);
      }
    }
  }

  /// Best-effort Storage cleanup. Intentionally swallows failures: a
  /// dangling object is a minor storage-cost issue, not a correctness bug,
  /// and must never surface as a profile-save failure to the user.
  Future<void> _bestEffortDeleteImage(String userId, String storagePath) async {
    try {
      await _profileImageRepository.deleteProfileImage(
        authenticatedUid: userId,
        storagePath: storagePath,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Profile image cleanup failed: userId=$userId path=$storagePath error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  Future<bool> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    String? continueUrl;
    try {
      final base = await _ensureEmailCallbackServer();
      continueUrl = _continueUri(base, mode: 'verify').toString();
    } catch (_) {}
    final result = await _repository.requestEmailChange(
      newEmail: newEmail,
      currentPassword: currentPassword,
      continueUrl: continueUrl,
    );
    if (result == EmailChangeRequestResult.verificationSent) {
      final uid = _currentUser?.id;
      if (uid != null) {
        _beginPendingEmailChange(
          originalUid: uid,
          originalEmail: _currentUser?.email ?? '',
          pendingEmail: newEmail.trim(),
          password: currentPassword,
        );
      }
      _startVerificationResendCooldown();
      return true;
    }
    return false;
  }

  Future<bool> isCurrentEmailVerified() {
    return _repository.isCurrentEmailVerified();
  }

  Future<void> requestCurrentEmailVerification() async {
    String? continueUrl;
    try {
      final base = await _ensureEmailCallbackServer();
      continueUrl = _continueUri(base, mode: 'verify').toString();
    } catch (_) {}
    await _repository.requestCurrentEmailVerification(continueUrl: continueUrl);
    _startVerificationResendCooldown();
  }

  Future<bool> resendPendingEmailChange({
    required String currentPassword,
  }) async {
    final email = pendingEmail;
    if (email == null || !canResendVerification) return false;
    return requestEmailChange(
      newEmail: email,
      currentPassword: currentPassword,
    );
  }

  /// Starts polling the auth server and listening for the email link so
  /// register verification completes when the user clicks the link.
  Future<void> beginEmailVerificationWatch() async {
    if (_disposed || _emailVerificationWatchActive) return;
    _emailVerificationWatchActive = true;
    _startEmailVerificationPolling();
    try {
      await _ensureEmailCallbackServer();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Email callback server unavailable: $error');
      }
    }
  }

  Future<void> endEmailVerificationWatch() async {
    _emailVerificationWatchActive = false;
    _stopEmailVerificationPolling();
    if (!_awaitingPasswordResetCallback) {
      await _stopEmailCallbackServer();
    }
  }

  /// Reloads email-verified state after the window is focused again.
  Future<void> refreshEmailVerificationOnForeground() {
    return _refreshEmailVerificationQuietly();
  }

  @visibleForTesting
  void handleEmailActionCallback(Uri uri) {
    if (kDebugMode) {
      debugPrint('Auth email action callback: $uri');
    }
    final action =
        (uri.queryParameters['elixr_action'] ??
                uri.queryParameters['mode'] ??
                '')
            .toLowerCase();
    final code = uri.queryParameters['code']?.trim() ?? '';
    if (code.isNotEmpty && !action.startsWith('reset')) {
      unawaited(_completeEmailLink(code));
      return;
    }
    final isReset =
        action == 'reset' ||
        action == 'resetpassword' ||
        action == 'recoveremail';
    if (hasPendingEmailChange &&
        (action == 'verify' || action == 'verifyemail' || action.isEmpty)) {
      unawaited(checkPendingEmailChange());
      return;
    }
    if (isReset) {
      // The loopback new-password form completes the reset through
      // [_completePasswordResetFromLink]; a bare redirect proves nothing.
      return;
    }

    if (action == 'verify' ||
        action == 'verifyemail' ||
        _emailVerificationWatchActive) {
      unawaited(_refreshEmailVerificationQuietly());
    }
  }

  /// Exchanges an email-link PKCE code (sign-up confirmation or email change)
  /// for a session, then refreshes verification or pending-change state.
  Future<void> _completeEmailLink(String code) async {
    final repository = _emailLinkRepository;
    if (repository == null) return;
    try {
      await repository.completeEmailVerificationLink(code);
    } catch (error) {
      // The link may have been opened in another browser profile (missing
      // verifier) or already used; polling still observes the outcome.
      if (kDebugMode) debugPrint('Email link exchange failed: $error');
    }
    if (_disposed) return;
    if (hasPendingEmailChange) {
      await checkPendingEmailChange();
    } else {
      await _refreshEmailVerificationQuietly();
    }
  }

  Future<String?> _verificationRedirectUrl() async {
    final base = await _ensureEmailCallbackServer();
    return _continueUri(base, mode: 'verify').toString();
  }

  /// Completes a recovery link from the loopback new-password form. Returns
  /// a presentation-safe error, or null on success.
  Future<String?> _completePasswordResetFromLink(
    String code,
    String newPassword,
  ) async {
    final repository = _emailLinkRepository;
    if (repository == null) return 'Password reset is unavailable.';
    final invalid = validateRegistrationPassword(newPassword);
    if (invalid != null) return invalid;
    try {
      await repository.completePasswordReset(
        code: code,
        newPassword: newPassword,
      );
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      return message.trim().isEmpty
          ? 'This reset link is invalid or has expired. Request a new one.'
          : message;
    }
    _passwordResetConfirmed = true;
    _awaitingPasswordResetCallback = false;
    if (!_disposed) notifyListeners();
    return null;
  }

  Future<Uri> _ensureEmailCallbackServer() async {
    final existing = _emailCallbackBaseUri;
    if (existing != null && _emailCallbackSubscription != null) {
      return existing;
    }
    final base = await _emailCallbackServer.start();
    _emailCallbackBaseUri = base;
    await _emailCallbackSubscription?.cancel();
    _emailCallbackSubscription = _emailCallbackServer.callbacks.listen(
      handleEmailActionCallback,
    );
    return base;
  }

  Future<void> _stopEmailCallbackServer() async {
    final subscription = _emailCallbackSubscription;
    _emailCallbackSubscription = null;
    _emailCallbackBaseUri = null;
    await _emailCallbackServer.stop();
    await subscription?.cancel();
  }

  Future<void> _stopEmailCallbackServerAfterRequestFailure() async {
    try {
      await _stopEmailCallbackServer();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Could not stop failed reset callback server: $error');
        debugPrint('$stackTrace');
      }
    }
  }

  Uri _continueUri(Uri base, {required String mode, String? token}) {
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'elixr_action': mode,
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );
  }

  void _startEmailVerificationPolling() {
    _emailVerificationPollTimer?.cancel();
    _emailVerificationPollTimer = Timer.periodic(
      _emailVerificationPollInterval,
      (_) => unawaited(_refreshEmailVerificationQuietly()),
    );
    unawaited(_refreshEmailVerificationQuietly());
  }

  void _stopEmailVerificationPolling() {
    _emailVerificationPollTimer?.cancel();
    _emailVerificationPollTimer = null;
  }

  void _startVerificationResendCooldown() {
    _verificationCooldownTimer?.cancel();
    _verificationResendAvailableAt = DateTime.now().add(
      _verificationResendCooldown,
    );
    _verificationCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (_disposed || canResendVerification) {
        timer.cancel();
        _verificationCooldownTimer = null;
      }
      if (!_disposed) notifyListeners();
    });
    if (!_disposed) notifyListeners();
  }

  void _clearVerificationResendCooldown() {
    _verificationCooldownTimer?.cancel();
    _verificationCooldownTimer = null;
    _verificationResendAvailableAt = null;
  }

  Future<void> _refreshEmailVerificationQuietly() async {
    if (_disposed || _currentUser == null) return;
    if (!_hasSupportedProductRole(_currentUser!)) return;
    try {
      final verified = await _repository.isCurrentEmailVerified();
      if (_emailVerified == verified) {
        if (verified) _stopEmailVerificationPolling();
        return;
      }
      _emailVerified = verified;
      if (verified) {
        final refreshed = await _repository.refreshAuthenticatedUser();
        if (refreshed != null) _currentUser = refreshed;
        _stopEmailVerificationPolling();
      }
      if (!_disposed) notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Quiet email verification refresh failed: $error');
      }
    }
  }

  Future<User?> refreshAuthenticatedUser() async {
    if (hasPendingEmailChange) {
      await checkPendingEmailChange();
      return _currentUser;
    }

    final previousUserId = _currentUser?.id?.trim();
    final refreshed = await _repository.refreshAuthenticatedUser().timeout(
      _profileRestorationTimeout,
    );
    final authUid = _readCurrentAuthUid();
    final mustValidateAuthIdentity =
        _repository is PersistedProfileRestorationRepository;
    if (refreshed != null &&
        (previousUserId == null ||
            previousUserId.isEmpty ||
            refreshed.id?.trim() != previousUserId ||
            (mustValidateAuthIdentity && authUid != previousUserId))) {
      _invalidatePublishedAccount();
      notifyListeners();
      return null;
    }
    _currentUser = refreshed;
    if (refreshed != null) {
      _isOfflineRestoredTrainee = false;
      await _refreshEmailVerificationState();
    }
    notifyListeners();
    return _currentUser;
  }

  /// A bounded, foreground-only attempt to replace an offline snapshot with
  /// the authoritative profile. Failure leaves the valid offline Trainee
  /// session intact; no polling loop is started.
  Future<void> refreshAuthoritativeProfileOnForeground() async {
    if (!_isOfflineRestoredTrainee || _currentUser?.isTrainee != true) return;
    try {
      await refreshAuthenticatedUser();
    } on TimeoutException {
      // Offline or an unavailable backend: retain the verified local session.
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Authoritative foreground profile refresh failed: $error');
      }
    }
  }

  Future<PendingEmailChangeRecoveryStatus?> checkPendingEmailChange({
    bool manual = false,
  }) async {
    if (_pendingEmailCheckInFlight != null) {
      await _pendingEmailCheckInFlight;
      return _latestPendingEmailStatus(manual: manual);
    }

    if (_pendingEmailChange == null) {
      return null;
    }

    if (_isPendingEmailExpired) {
      _onPendingEmailTimeout();
      return PendingEmailChangeRecoveryStatus.failed;
    }

    final check = _runPendingEmailCheck(manual: manual);
    _pendingEmailCheckInFlight = check;
    try {
      await check;
    } finally {
      if (identical(_pendingEmailCheckInFlight, check)) {
        _pendingEmailCheckInFlight = null;
      }
    }
    return _latestPendingEmailStatus(manual: manual);
  }

  PendingEmailChangeRecoveryStatus? _latestPendingEmailStatus({
    required bool manual,
  }) {
    if (hasPendingEmailChange) {
      return PendingEmailChangeRecoveryStatus.pending;
    }
    if (_pendingEmailRecoveryError != null) {
      return PendingEmailChangeRecoveryStatus.failed;
    }
    if (_pendingEmailChangeSuccessMessage != null || !manual) {
      return PendingEmailChangeRecoveryStatus.completed;
    }
    return null;
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _repository.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Permanently deletes the signed-in account and associated cloud data.
  ///
  /// On success, clears local auth state the same way [logout] does and
  /// queues a one-shot message for [takeAccountDeletedMessage].
  Future<void> deleteAccount({
    String? password,
    AccountReauthentication? reauthentication,
    required String confirmationPhrase,
  }) async {
    final user = _currentUser;
    final userId = user?.id?.trim() ?? '';
    if (user == null || userId.isEmpty) {
      throw Exception('Not authenticated');
    }
    final expectedPhrase = accountDeletionConfirmationPhraseFor(user.email);
    if (confirmationPhrase.trim() != expectedPhrase) {
      throw Exception(accountDeletionRequiresTypedConfirmationMessage);
    }
    final auth =
        reauthentication ?? AccountReauthentication.password(password ?? '');
    if (auth.kind == AuthProviderKind.google) {
      final googleRepository = _googleRepository;
      if (googleRepository == null) {
        throw Exception('Google verification is unavailable.');
      }
      await googleRepository.deleteAccountWithReauthentication(
        reauthentication: auth,
        expectedUserId: userId,
      );
    } else {
      await _repository.deleteAccount(
        password: auth.password ?? '',
        expectedUserId: userId,
      );
    }
    _accountDeletedMessage =
        'Your account and associated data have been permanently deleted.';
    // The remote deletion is authoritative. Publish the signed-out state
    // before best-effort local cache cleanup so a slow filesystem operation
    // cannot leave the deleted account visible as authenticated.
    _clearPendingEmailChange(clearError: true);
    _invalidatePublishedAccount();
    await _repository.clearCurrentUser();
    notifyListeners();
    // Normal sign-out intentionally retains account-scoped pending attempts:
    // the same auth UID may authenticate later and finish their replay.
    // Permanent deletion is different: remove this UID's local outbox and
    // temporary evidence only after the authoritative account deletion wins.
    await _purgePendingSessions?.call(userId);
    await _purgeTraineeProfileSnapshot(userId);
    await _purgeTraineeProgressionSnapshot(userId);
  }

  void _beginPendingEmailChange({
    required String originalUid,
    required String originalEmail,
    required String pendingEmail,
    required String password,
  }) {
    _clearPendingEmailChange(clearError: true);
    _pendingEmailChange = _PendingEmailChangeState(
      originalUid: originalUid,
      originalEmail: originalEmail,
      pendingEmail: pendingEmail,
      password: password,
      expiresAt: DateTime.now().add(_pendingEmailTimeout),
    );
    _schedulePendingEmailPolling();
    notifyListeners();
    unawaited(checkPendingEmailChange());
  }

  void _schedulePendingEmailPolling() {
    _pendingEmailPollTimer?.cancel();
    _pendingEmailPollTimer = Timer.periodic(_pendingEmailPollInterval, (_) {
      if (_pendingEmailChange == null) {
        _pendingEmailPollTimer?.cancel();
        _pendingEmailPollTimer = null;
        return;
      }
      if (_isPendingEmailExpired) {
        _onPendingEmailTimeout();
        return;
      }
      unawaited(checkPendingEmailChange());
    });
  }

  Future<void> _runPendingEmailCheck({required bool manual}) async {
    if (_checkingPendingEmail || _pendingEmailChange == null) {
      return;
    }

    final pending = _pendingEmailChange!;
    final generation = _accountSessionGeneration;
    if (_isPendingEmailExpired) {
      _onPendingEmailTimeout();
      return;
    }

    _checkingPendingEmail = true;
    if (!_disposed) {
      notifyListeners();
    }

    try {
      final result = await _repository.checkAndRecoverPendingEmailChange(
        originalUid: pending.originalUid,
        pendingEmail: pending.pendingEmail,
        recoveryPassword: pending.password,
        originalEmail: pending.originalEmail,
      );
      final stale =
          _disposed ||
          generation != _accountSessionGeneration ||
          _pendingEmailChange?.originalUid != pending.originalUid ||
          _readCurrentAuthUid() != pending.originalUid;
      if (stale) {
        if (!_disposed && _readCurrentAuthUid() == pending.originalUid) {
          try {
            await _repository.clearCurrentUser();
          } catch (error, stackTrace) {
            if (kDebugMode) {
              debugPrint('Failed to clear a stale recovered session: $error');
              debugPrint('$stackTrace');
            }
          }
        }
        return;
      }
      _handlePendingEmailRecoveryResult(result, manual: manual);
    } finally {
      _checkingPendingEmail = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _handlePendingEmailRecoveryResult(
    PendingEmailChangeRecoveryResult result, {
    required bool manual,
  }) {
    switch (result.status) {
      case PendingEmailChangeRecoveryStatus.pending:
      case PendingEmailChangeRecoveryStatus.transientFailure:
        return;
      case PendingEmailChangeRecoveryStatus.completed:
        final user = result.user;
        if (user == null || user.id != _pendingEmailChange?.originalUid) {
          _failPendingEmailRecovery(
            'Could not verify your account after the email change. '
            'Sign in with your verified email.',
          );
          return;
        }
        _currentUser = user;
        _markAuthenticatedSessionReady();
        _clearPendingEmailChange(clearError: true);
        if (!manual) {
          _pendingEmailChangeSuccessMessage =
              'Your verified email has been updated.';
        }
        if (!_disposed) {
          notifyListeners();
        }
        return;
      case PendingEmailChangeRecoveryStatus.failed:
        _failPendingEmailRecovery(
          result.message ??
              'Could not restore your session automatically. '
                  'Sign in with your verified email.',
        );
    }
  }

  void _failPendingEmailRecovery(String message) {
    _pendingEmailRecoveryError = message;
    _clearPendingEmailChange(clearError: false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onPendingEmailTimeout() {
    _pendingEmailRecoveryError =
        'Email change verification timed out. If you completed verification, '
        'sign in with your new email.';
    _clearPendingEmailChange(clearError: false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _clearPendingEmailChange({required bool clearError}) {
    _pendingEmailPollTimer?.cancel();
    _pendingEmailPollTimer = null;
    _pendingEmailChange?.clearPassword();
    _pendingEmailChange = null;
    if (clearError) {
      _pendingEmailRecoveryError = null;
      _pendingEmailChangeSuccessMessage = null;
    }
  }

  void cancelPendingEmailChange() {
    if (_pendingEmailChange == null) return;
    _clearPendingEmailChange(clearError: true);
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _accountSessionGeneration++;
    if (_joinLinkService?.authCallbackHandler == handleEmailActionCallback) {
      _joinLinkService?.authCallbackHandler = null;
    }
    _clearPendingEmailChange(clearError: true);
    _stopEmailVerificationPolling();
    _clearVerificationResendCooldown();
    _emailVerificationWatchActive = false;
    _awaitingPasswordResetCallback = false;
    unawaited(_authUidSubscription?.cancel());
    _authUidSubscription = null;
    unawaited(_stopEmailCallbackServer());
    super.dispose();
  }
}
