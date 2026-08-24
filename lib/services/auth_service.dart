import 'dart:async';

import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../core/auth/teacher_auth_messages.dart';
import '../core/constants/app_constants.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/profile_image_repository.dart';
import '../data/repositories/public_profile_repository.dart';
import '../firebase_options.dart';
import 'auth_email_callback_server.dart';
import 'join_link_service.dart';
import 'windows_google_oauth_flow.dart';

/// Account-scoped phrase used as a deliberate-action safeguard in the UI.
///
/// This is not authentication; Firebase password reauthentication remains the
/// security boundary for account deletion.
String accountDeletionConfirmationPhraseFor(String email) {
  return 'delete ${email.trim().toLowerCase()}';
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
  }) : _repository =
           repository ??
           AuthRepository(
             createMissingProfile: false,
             // Firebase's native Windows app options do not preserve the
             // web-only authDomain needed by the browser OAuth page. Use the
             // generated source configuration directly instead of reading the
             // options back through Firebase.app().
             googleOAuthFlow: WindowsGoogleOAuthFlow(
               firebaseOptions: DefaultFirebaseOptions.currentPlatform,
             ),
           ),
       _leaderboardRepository = leaderboardRepository,
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
       _awaitInitialAuthState = awaitInitialAuthState {
    _joinLinkService?.authCallbackHandler = handleEmailActionCallback;
  }

  final AuthRepositoryBase _repository;
  GoogleAuthRepositoryBase? get _googleRepository =>
      _repository is GoogleAuthRepositoryBase
      ? _repository as GoogleAuthRepositoryBase
      : null;
  TeacherGoogleAuthRepositoryBase? get _teacherGoogleRepository =>
      _repository is TeacherGoogleAuthRepositoryBase
      ? _repository as TeacherGoogleAuthRepositoryBase
      : null;
  TeacherRegistrationRepositoryBase? get _teacherRegistrationRepository =>
      _repository is TeacherRegistrationRepositoryBase
      ? _repository as TeacherRegistrationRepositoryBase
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

  // Lazily constructed so tests that never touch profile-image upload do not
  // need Firebase Storage initialized.
  ProfileImageRepositoryBase? _explicitProfileImageRepository;
  ProfileImageRepositoryBase get _profileImageRepository =>
      _explicitProfileImageRepository ??= ProfileImageRepository();

  User? _currentUser;
  PendingGoogleProfile? _pendingGoogleProfile;
  Set<AuthProviderKind> _providerKinds = const {};
  bool _isLoading = true;
  bool? _emailVerified;
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
    _providerKinds = const {AuthProviderKind.password};
    _isLoading = false;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    final awaitInitialAuthState = _awaitInitialAuthState;
    if (awaitInitialAuthState != null) {
      await awaitInitialAuthState();
    } else {
      await fb.FirebaseAuth.instance.authStateChanges().first;
    }
    final restoredGoogle = await _googleRepository?.restoreGoogleSignIn();
    if (restoredGoogle is PendingGoogleSignIn) {
      // The access code is deliberately not durable. A restored incomplete
      // flow must make the user choose a role again and re-enter the code for
      // Teacher completion.
      _pendingGoogleProfile = restoredGoogle.profile.copyWith(
        intent: GoogleOnboardingIntent.unspecified,
        clearTeacherAccessCode: true,
      );
      _currentUser = null;
      _providerKinds = const {AuthProviderKind.google};
      _isLoading = false;
      notifyListeners();
      return;
    }
    final loadedUser = restoredGoogle is ExistingGoogleProfile
        ? restoredGoogle.user
        : await _repository.loadPersistedUser();
    if (loadedUser != null && !_hasSupportedProductRole(loadedUser)) {
      await logout();
      _isLoading = false;
      notifyListeners();
      return;
    }
    _currentUser = loadedUser;
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    _isLoading = false;
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
  }

  Future<void> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    _clearTeacherAuthMessages();
    final user = await _repository.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      password: password,
      defaultRole: AppConstants.defaultRole,
    );
    _currentUser = user;
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
  }

  /// Explicit Teacher registration. Does not seed trainee social/gamification
  /// documents and requests email verification before shell access.
  Future<void> registerTeacher({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String teacherAccessCode,
  }) async {
    _clearTeacherAuthMessages();
    final user = await _repository.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      password: password,
      defaultRole: User.roleTeacher,
      teacherAccessCode: teacherAccessCode,
    );
    if (!user.isTeacher) {
      await logout();
      throw Exception(TeacherAuthMessages.notATeacher);
    }
    _currentUser = user;
    try {
      await _repository.requestCurrentEmailVerification();
      _teacherAuthInfoMessage = TeacherAuthMessages.verificationSent;
    } catch (error) {
      _teacherAuthErrorMessage = _sanitizeTeacherAuthError(error);
    }
    await _refreshEmailVerificationState();
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    _clearTeacherAuthMessages();
    final user = await _repository.login(email: email, password: password);
    if (!_hasSupportedProductRole(user)) {
      await _repository.clearCurrentUser();
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    _currentUser = user;
    _pendingGoogleProfile = null;
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
  }

  Future<void> signInWithGoogle() async {
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
    _pendingGoogleProfile = null;
    _currentUser = user;
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
    _scheduleClaimedAchievementProjectionSync();
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
    final registrationRepository = _teacherRegistrationRepository;
    if (registrationRepository == null) {
      throw Exception('Teacher registration is unavailable.');
    }
    await registrationRepository.assertTeacherAccessCodeRedeemable(
      normalizedCode,
    );
  }

  /// Starts the Teacher Google registration path after validating the
  /// one-time access code. The normalized code stays only in the pending
  /// in-memory Google profile until final completion.
  Future<void> signInWithGoogleTeacher({
    required String teacherAccessCode,
  }) async {
    _clearTeacherAuthMessages();
    final normalizedCode = CoachCode.tryNormalize(teacherAccessCode);
    if (normalizedCode == null) {
      throw Exception(TeacherAuthMessages.accessCodeInvalid);
    }
    final googleRepository = _teacherGoogleRepository;
    if (googleRepository == null) {
      throw Exception('Google sign-in is unavailable.');
    }
    await prevalidateTeacherAccessCode(normalizedCode);
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
    _pendingGoogleProfile = null;
    _currentUser = user;
    await _refreshProviderKinds();
    await _refreshEmailVerificationState();
    notifyListeners();
  }

  Future<void> completeGoogleProfile({
    required String firstName,
    String? middleName,
    required String lastName,
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
    );
    if (!user.isTrainee) {
      await _repository.clearCurrentUser();
      _pendingGoogleProfile = null;
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    _pendingGoogleProfile = null;
    _currentUser = user;
    _emailVerified = true;
    await _refreshProviderKinds();
    notifyListeners();
    await _seedNewTraineePublicProfile(user);
    _scheduleClaimedAchievementProjectionSync();
  }

  /// Completes Google onboarding as a Teacher. The repository performs the
  /// final atomic access-code consumption and profile creation; this service
  /// deliberately does not seed Trainee-only public or gamification state.
  Future<void> completeGoogleTeacherProfile({
    required String firstName,
    String? middleName,
    required String lastName,
    required String teacherAccessCode,
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
    );
    if (!user.isTeacher) {
      await _repository.clearCurrentUser();
      _pendingGoogleProfile = null;
      throw Exception(TeacherAuthMessages.unsupportedRole);
    }
    _pendingGoogleProfile = null;
    _currentUser = user;
    _emailVerified = true;
    await _refreshProviderKinds();
    notifyListeners();
  }

  Future<void> cancelGoogleOnboarding() async {
    final pending = _pendingGoogleProfile;
    _pendingGoogleProfile = null;
    _currentUser = null;
    _emailVerified = null;
    _providerKinds = const {};
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
    if (_currentUser == null) {
      _providerKinds = const {};
      return;
    }
    _providerKinds =
        await _googleRepository?.currentProviderKinds() ??
        const {AuthProviderKind.password};
  }

  Future<void> _seedNewTraineePublicProfile(User user) async {
    final repository = _publicProfileRepository;
    final userId = user.id?.trim();
    if (repository == null || userId == null || userId.isEmpty) return;
    try {
      await repository.seedNewAccountPublicProfile(
        userId: userId,
        displayName: user.fullName,
        profilePictureUrl: user.profilePictureUrl,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Public profile seed failed: userId=$userId error=$error');
        debugPrint('$stackTrace');
      }
    }
  }

  /// Requests a Firebase Auth password-reset email for [email].
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

    unawaited(() async {
      try {
        await repository.syncClaimedAchievementProjections(
          userId: userId,
          displayName: user.fullName,
          profilePictureUrl: user.profilePictureUrl,
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
    }());
  }

  Future<void> logout() async {
    _clearPendingEmailChange(clearError: true);
    _clearTeacherAuthMessages();
    _emailVerified = null;
    _stopEmailVerificationPolling();
    _emailVerificationWatchActive = false;
    _awaitingPasswordResetCallback = false;
    _passwordResetConfirmed = false;
    _clearVerificationResendCooldown();
    await _stopEmailCallbackServer();
    _currentUser = null;
    _pendingGoogleProfile = null;
    _providerKinds = const {};
    await _repository.clearCurrentUser();
    notifyListeners();
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

  /// Ensures a Teacher session has a fresh `email_verified` ID-token claim
  /// before privileged Firestore writes.
  ///
  /// Reuses [AuthRepositoryBase.isCurrentEmailVerified], which reloads the
  /// Firebase User and force-refreshes a stale cached token. Does not mint a
  /// new token when the claim is already verified. Trainee sessions and
  /// missing users fail closed. Transient repository errors fail closed
  /// without signing the Teacher out.
  Future<bool> ensureTeacherAuthorizationFresh() async {
    final user = _currentUser;
    if (user == null || !user.isTeacher) {
      return false;
    }

    try {
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
    final user = _currentUser;
    if (user == null || !_hasSupportedProductRole(user)) {
      _emailVerified = null;
      return;
    }
    try {
      _emailVerified = await _repository.isCurrentEmailVerified();
    } catch (_) {
      _emailVerified = false;
    }
  }

  void _clearTeacherAuthMessages() {
    _teacherAuthInfoMessage = null;
    _teacherAuthErrorMessage = null;
  }

  bool _hasSupportedProductRole(User user) => user.isTrainee || user.isTeacher;

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
  /// avatar to Firebase Cloud Storage.
  ///
  /// When [newProfileImageBytes] and [newProfileImageContentType] are both
  /// provided, the image is uploaded first; Firestore is only updated after
  /// the upload succeeds. A name-only update never touches Cloud Storage.
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
        // Firestore did not accept the new image reference; do not leave an
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

  /// Removes the current profile avatar without touching name or email edits.
  ///
  /// The Firestore references are cleared first. The previous Cloud Storage
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

    // Removal clears every visible projection first. This prevents a stale
    // public URL from briefly restoring the deleted avatar while Storage
    // cleanup is still in flight. Replacement retains the existing cleanup
    // ordering and policy.
    if (pictureUpdate?.isRemoval != true &&
        previousStoragePath != null &&
        previousStoragePath.isNotEmpty) {
      await _bestEffortDeleteImage(userId, previousStoragePath);
    }

    try {
      await _leaderboardRepository?.syncPublicProfile(
        userId: userId,
        displayName: _currentUser?.fullName ?? '',
        profilePictureUrl: _currentUser?.profilePictureUrl,
        clearProfilePicture: pictureUpdate?.isRemoval ?? false,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Leaderboard public profile sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }

    try {
      await _publicProfileRepository?.updatePublicIdentity(
        userId: userId,
        displayName: _currentUser?.fullName ?? '',
        profilePictureUrl: _currentUser?.profilePictureUrl,
        clearProfilePicture: pictureUpdate?.isRemoval ?? false,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Public profile identity sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }

    if (pictureUpdate?.isRemoval == true &&
        previousStoragePath != null &&
        previousStoragePath.isNotEmpty) {
      await _bestEffortDeleteImage(userId, previousStoragePath);
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

  /// Starts polling Firebase and listening for the email continue URL so
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

  /// Reloads Firebase email-verified state after the window is focused again.
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
    final token = uri.queryParameters['token'] ?? '';
    final isReset =
        action == 'reset' ||
        action == 'resetpassword' ||
        action == 'recoveremail';
    if (hasPendingEmailChange &&
        (action == 'verify' || action == 'verifyemail' || action.isEmpty)) {
      unawaited(checkPendingEmailChange());
      return;
    }
    if (_awaitingPasswordResetCallback &&
        (token.isEmpty || isReset || action.isEmpty)) {
      _passwordResetConfirmed = true;
      _awaitingPasswordResetCallback = false;
      if (!_disposed) notifyListeners();
      return;
    }

    if (action == 'verify' ||
        action == 'verifyemail' ||
        _emailVerificationWatchActive) {
      unawaited(_refreshEmailVerificationQuietly());
    }
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
    await _emailCallbackSubscription?.cancel();
    _emailCallbackSubscription = null;
    _emailCallbackBaseUri = null;
    await _emailCallbackServer.stop();
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

    final refreshed = await _repository.refreshAuthenticatedUser();
    _currentUser = refreshed;
    notifyListeners();
    return _currentUser;
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
    _clearPendingEmailChange(clearError: true);
    _currentUser = null;
    _providerKinds = const {};
    await _repository.clearCurrentUser();
    notifyListeners();
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
    if (_joinLinkService?.authCallbackHandler == handleEmailActionCallback) {
      _joinLinkService?.authCallbackHandler = null;
    }
    _clearPendingEmailChange(clearError: true);
    _stopEmailVerificationPolling();
    _clearVerificationResendCooldown();
    _emailVerificationWatchActive = false;
    _awaitingPasswordResetCallback = false;
    unawaited(_stopEmailCallbackServer());
    super.dispose();
  }
}
