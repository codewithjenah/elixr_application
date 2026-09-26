import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart' as sb;

import '../database/supabase_support.dart';
import '../database/user_profile_store.dart';
import '../models/coach_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import '../privacy/privacy_consent.dart';
import '../utils/user_name.dart';
import 'supabase_teacher_access_code_repository.dart';
import 'teacher_access_code_repository.dart';

export '../privacy/privacy_consent.dart';

/// A profile-picture mutation to persist alongside a profile update.
class ProfilePictureUpdate {
  const ProfilePictureUpdate({required this.url, required this.storagePath})
    : isRemoval = false;

  const ProfilePictureUpdate.remove()
    : url = null,
      storagePath = null,
      isRemoval = true;

  final String? url;
  final String? storagePath;
  final bool isRemoval;
}

enum EmailChangeRequestResult { unchanged, verificationSent }

/// Sign-in capabilities of the active identity.
enum AuthProviderKind { password, google }

/// The product role the user selected before Google onboarding started.
///
/// [unspecified] is intentionally used when a Google identity is restored
/// after an interrupted onboarding flow. It prevents the client from making
/// a silent Trainee choice after an app restart.
enum GoogleOnboardingIntent { trainee, teacher, unspecified }

enum ProfileIdentityProvider { password, google }

class PendingGoogleProfile {
  const PendingGoogleProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.isNewUser,
    this.intent = GoogleOnboardingIntent.unspecified,
    this.teacherAccessCode,
    this.identityProvider = ProfileIdentityProvider.google,
  });

  final String uid;
  final String email;
  final String firstName;
  final String? middleName;
  final String lastName;
  final bool isNewUser;
  final GoogleOnboardingIntent intent;
  final String? teacherAccessCode;
  final ProfileIdentityProvider identityProvider;

  PendingGoogleProfile copyWith({
    GoogleOnboardingIntent? intent,
    String? teacherAccessCode,
    bool clearTeacherAccessCode = false,
  }) {
    return PendingGoogleProfile(
      uid: uid,
      email: email,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      isNewUser: isNewUser,
      intent: intent ?? this.intent,
      teacherAccessCode: clearTeacherAccessCode
          ? null
          : (teacherAccessCode ?? this.teacherAccessCode),
      identityProvider: identityProvider,
    );
  }
}

sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

class ExistingGoogleProfile extends GoogleSignInResult {
  const ExistingGoogleProfile(this.user);

  final User user;
}

class PendingGoogleSignIn extends GoogleSignInResult {
  const PendingGoogleSignIn(this.profile);

  final PendingGoogleProfile profile;
}

class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();

  @override
  String toString() => 'Google sign-in was cancelled.';
}

/// Result of a platform-specific interactive Google OAuth flow: the PKCE
/// authorization code returned to the loopback redirect.
class GoogleOAuthCredential {
  const GoogleOAuthCredential({required this.authorizationCode});

  final String authorizationCode;
}

/// Builds the provider authorization URL for a loopback [redirectUri].
typedef OAuthAuthorizationUrlBuilder = Future<Uri> Function(Uri redirectUri);

abstract class GoogleOAuthFlow {
  Future<GoogleOAuthCredential> authenticate(
    OAuthAuthorizationUrlBuilder authorizationUrlFor,
  );
}

class GoogleOAuthFlowException implements Exception {
  const GoogleOAuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountReauthentication {
  const AccountReauthentication.password(this.password)
    : kind = AuthProviderKind.password;

  const AccountReauthentication.google()
    : kind = AuthProviderKind.google,
      password = null;

  final AuthProviderKind kind;
  final String? password;
}

enum PendingEmailChangeRecoveryStatus {
  pending,
  completed,
  failed,
  transientFailure,
}

class PendingEmailChangeRecoveryResult {
  const PendingEmailChangeRecoveryResult._({
    required this.status,
    this.user,
    this.message,
  });

  final PendingEmailChangeRecoveryStatus status;
  final User? user;
  final String? message;

  static PendingEmailChangeRecoveryResult pending() {
    return const PendingEmailChangeRecoveryResult._(
      status: PendingEmailChangeRecoveryStatus.pending,
    );
  }

  static PendingEmailChangeRecoveryResult completed(User user) {
    return PendingEmailChangeRecoveryResult._(
      status: PendingEmailChangeRecoveryStatus.completed,
      user: user,
    );
  }

  static PendingEmailChangeRecoveryResult failed(String message) {
    return PendingEmailChangeRecoveryResult._(
      status: PendingEmailChangeRecoveryStatus.failed,
      message: message,
    );
  }

  static PendingEmailChangeRecoveryResult transientFailure() {
    return const PendingEmailChangeRecoveryResult._(
      status: PendingEmailChangeRecoveryStatus.transientFailure,
    );
  }
}

/// The outcome of restoring an already-persisted auth identity's ELIXR
/// profile. This deliberately distinguishes an unavailable backend from an
/// invalid account so callers can make a safe offline decision.
enum PersistedProfileRestorationStatus {
  authoritative,
  signedOut,
  unavailable,
  invalidProfile,
}

class PersistedProfileRestoration {
  const PersistedProfileRestoration._(this.status, [this.user]);

  final PersistedProfileRestorationStatus status;
  final User? user;

  const PersistedProfileRestoration.authoritative(User user)
    : this._(PersistedProfileRestorationStatus.authoritative, user);

  const PersistedProfileRestoration.signedOut()
    : this._(PersistedProfileRestorationStatus.signedOut);

  const PersistedProfileRestoration.unavailable()
    : this._(PersistedProfileRestorationStatus.unavailable);

  const PersistedProfileRestoration.invalidProfile()
    : this._(PersistedProfileRestorationStatus.invalidProfile);
}

/// A locally retained session was rejected by the auth server for a reason
/// other than backend availability. It must never authorize an offline cache.
class InvalidPersistedAuthIdentityException implements Exception {
  const InvalidPersistedAuthIdentityException();
}

abstract class AuthRepositoryBase {
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  });

  Future<User> login({required String email, required String password});

  /// Sends a password-reset email.
  ///
  /// Must not reveal whether [email] is registered. Callers should show a
  /// generic success message after this completes without error.
  ///
  /// When [continueUrl] is set, the recovery link redirects there so the
  /// desktop app can complete the reset locally.
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  });

  Future<User?> loadPersistedUser();

  Future<void> clearCurrentUser();

  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  });

  /// Persists a Storage avatar mutation for [userId].
  ///
  /// Does not write name or email fields. Retires the legacy local
  /// `profile_picture_path` once a cloud URL exists.
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  });

  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  });

  /// Refreshes the auth user from the server and returns whether its email is
  /// confirmed. Server authorization reads confirmation from `auth.users`, so
  /// no token refresh is needed after confirmation.
  Future<bool> isCurrentEmailVerified();

  Future<void> requestCurrentEmailVerification({String? continueUrl});

  Future<User?> refreshAuthenticatedUser();

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Re-authenticates with [password], then erases the account server-side
  /// (data, Storage objects, then the auth user). Nothing is deleted when the
  /// re-authentication fails.
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  });

  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  });
}

/// Optional capability so existing product-specific repositories and test
/// doubles remain source compatible while the production implementation can
/// expose safe offline-restoration semantics.
abstract class PersistedProfileRestorationRepository {
  Future<PersistedProfileRestoration> restorePersistedProfile();
}

/// Optional provider-aware contract kept separate so existing password-only
/// clients and test doubles remain source compatible.
abstract class GoogleAuthRepositoryBase {
  Future<GoogleSignInResult> signInWithGoogle();

  Future<GoogleSignInResult?> restoreGoogleSignIn();

  Future<User> completeGoogleProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
    required RegistrationLegalConsent legalConsent,
  });

  Future<void> cancelGoogleOnboarding(PendingGoogleProfile pendingProfile);

  Future<Set<AuthProviderKind>> currentProviderKinds();

  Future<void> deleteAccountWithReauthentication({
    required AccountReauthentication reauthentication,
    required String expectedUserId,
  });
}

/// Optional contract for validating the bearer code that gates every Teacher
/// registration method.
abstract class TeacherRegistrationRepositoryBase {
  Future<void> assertTeacherAccessCodeRedeemable(String code);
}

/// Server-authoritative Teacher authorization exposed separately so callers
/// can verify Teacher evidence without changing Trainee repository contracts.
abstract class TeacherAuthorizationRepositoryBase {
  Future<void> ensureTeacherRoleClaim();
}

/// Optional authenticated profile operation for the Teacher-only border
/// preference. Kept separate so existing AuthRepository test doubles and
/// shared clients do not need to implement a Teacher-specific mutation.
abstract class TeacherProfileBorderRepositoryBase {
  Future<User> updateTeacherProfileBorder({
    required String userId,
    required String? profileBorderId,
  });
}

/// Optional extension of [GoogleAuthRepositoryBase] for the explicit Teacher
/// registration flow. Keeping this separate preserves source compatibility
/// for repositories that only support Trainee Google sign-in.
abstract class TeacherGoogleAuthRepositoryBase {
  /// Starts Google onboarding with an explicit Teacher intent. A valid code
  /// is carried only in memory until the final profile transaction.
  Future<GoogleSignInResult> signInWithGoogleTeacher({
    required String teacherAccessCode,
  });

  /// Atomically consumes [teacherAccessCode] with creation of the Teacher
  /// profile. Implementations must reconcile an uncertain transaction result
  /// before reporting failure.
  Future<User> completeGoogleTeacherProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
    required String teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  });
}

/// Optional email-link capabilities of the Supabase PKCE flow: an email
/// verification or recovery link returns an authorization code to the
/// desktop loopback callback.
abstract class EmailLinkAuthRepositoryBase {
  /// Exchanges a verification-link code for a session.
  Future<void> completeEmailVerificationLink(String code);

  /// Exchanges a recovery-link code, sets [newPassword], then signs out so
  /// the user signs in again with the new credential.
  Future<void> completePasswordReset({
    required String code,
    required String newPassword,
  });
}

/// User-facing message when server-side erasure fails before the auth user
/// is deleted.
const accountErasurePurgeFailedMessage =
    "We couldn't finish deleting all of your account data, so your sign-in "
    'account was not removed. Please try again.';

const accountDeletionRequiresTypedConfirmationMessage =
    'Type the displayed confirmation phrase before deleting your account.';

/// Runs the server-side erasure; a failure is reported with a stable message
/// and leaves the sign-in account intact.
@visibleForTesting
Future<void> runAccountErasure(Future<void> Function() erase) async {
  try {
    await erase();
  } catch (error) {
    if (kDebugMode) debugPrint('Account erasure failed: $error');
    throw Exception(accountErasurePurgeFailedMessage);
  }
}

/// Thrown when an authenticated session has no ELIXR profile and the client
/// is not allowed to synthesize a Trainee profile.
class MissingUserProfileException implements Exception {
  const MissingUserProfileException();

  static const message = 'Account profile not found. Please register first.';

  @override
  String toString() => message;
}

enum AuthFailureKind {
  invalidCredentials,
  disabledAccount,
  rateLimited,
  network,
  missingProfile,
  provisioning,
  reauthentication,
  unknown,
}

/// A presentation-safe authentication failure. [message] never includes raw
/// backend details or account-existence information.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message, {this.pendingProfile});

  final AuthFailureKind kind;
  final String message;
  final PendingGoogleProfile? pendingProfile;

  @override
  String toString() => message;
}

enum TeacherRoleClaimFailureKind { invalidEvidence, unavailable, missingClaim }

class TeacherRoleClaimException implements Exception {
  const TeacherRoleClaimException(this.kind, this.message);

  final TeacherRoleClaimFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

enum _AuthErrorContext { login, reauthentication, emailChange }

/// Maps a Teacher-evidence verification failure to the established typed
/// exception.
@visibleForTesting
TeacherRoleClaimException teacherRoleClaimExceptionFor(Object error) {
  if (error is TeacherRoleClaimException) return error;
  if (backendErrorCode(error) == 'teacher_evidence_invalid') {
    return const TeacherRoleClaimException(
      TeacherRoleClaimFailureKind.invalidEvidence,
      'ELIXR could not verify this account as a Teacher. Contact support if this account should have Teacher access.',
    );
  }
  return const TeacherRoleClaimException(
    TeacherRoleClaimFailureKind.unavailable,
    'Teacher authorization could not be refreshed. Check your connection and try again.',
  );
}

/// Supabase Auth + profile repository shared by ELIXR clients.
class AuthRepository
    implements
        AuthRepositoryBase,
        GoogleAuthRepositoryBase,
        TeacherRegistrationRepositoryBase,
        TeacherAuthorizationRepositoryBase,
        TeacherGoogleAuthRepositoryBase,
        TeacherProfileBorderRepositoryBase,
        PersistedProfileRestorationRepository,
        EmailLinkAuthRepositoryBase {
  AuthRepository({
    sb.SupabaseClient? client,
    UserProfileStore? db,
    TeacherAccessCodeRepository? teacherAccessCodeRepository,
    GoogleOAuthFlow? googleOAuthFlow,
    Future<void> Function(String userId)? eraseAccountOnServer,
    Future<String?> Function()? emailRedirectUrl,
    this.createMissingProfile = true,
  }) : _clientOverride = client,
       _dbOverride = db,
       _teacherAccessCodesOverride = teacherAccessCodeRepository,
       _googleOAuthFlow = googleOAuthFlow,
       _eraseAccountOverride = eraseAccountOnServer,
       _emailRedirectUrl = emailRedirectUrl;

  static const _authOperationTimeout = Duration(seconds: 30);
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final sb.SupabaseClient? _clientOverride;
  final UserProfileStore? _dbOverride;
  final TeacherAccessCodeRepository? _teacherAccessCodesOverride;
  final GoogleOAuthFlow? _googleOAuthFlow;
  final Future<void> Function(String userId)? _eraseAccountOverride;
  final Future<String?> Function()? _emailRedirectUrl;

  sb.SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;
  sb.GoTrueClient get _auth => _client.auth;
  UserProfileStore get _db =>
      _dbOverride ?? SupabaseUserProfileStore(client: _clientOverride);
  TeacherAccessCodeRepository get _teacherAccessCodes =>
      _teacherAccessCodesOverride ??
      SupabaseTeacherAccessCodeRepository(client: _clientOverride);

  /// Retained for source compatibility. A session without a profile is never
  /// given a synthesized profile: creation needs explicit legal consent, so
  /// the identity always goes through profile completion.
  final bool createMissingProfile;

  /// Credentials held in memory only while a new password registration waits
  /// for email confirmation (Supabase issues no session before then). Used to
  /// detect confirmation made from another device; cleared on success.
  ({String email, String password})? _pendingVerification;
  DateTime? _signupEmailSentAt;
  DateTime? _lastPendingVerificationProbe;
  static const _pendingVerificationProbeInterval = Duration(seconds: 10);

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    if (!legalConsent.isCurrent) {
      throw const AuthFailure(
        AuthFailureKind.provisioning,
        'Current Privacy Policy and Terms consent is required.',
      );
    }
    final isTeacher = defaultRole == User.roleTeacher;
    if (!isTeacher &&
        teacherAccessCode != null &&
        teacherAccessCode.trim().isNotEmpty) {
      throw Exception(
        'Teacher access codes cannot be used for Trainee registration.',
      );
    }
    final normalizedCode = isTeacher
        ? CoachCode.tryNormalize(teacherAccessCode ?? '')
        : null;
    if (isTeacher) {
      // Specific, presentation-safe errors before an account exists. The
      // sign-up transaction below remains the authoritative consumption.
      try {
        await _teacherAccessCodes.assertRedeemable(teacherAccessCode);
      } on TeacherAccessCodeException catch (e) {
        throw AuthFailure(
          AuthFailureKind.provisioning,
          e.message ?? e.toString(),
        );
      }
    }
    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    final trimmedEmail = email.trim();
    try {
      // The profile (and Teacher code consumption) is created atomically with
      // the auth user by the database sign-up trigger.
      final response = await _auth
          .signUp(
            email: trimmedEmail,
            password: password,
            emailRedirectTo: await _resolveEmailRedirect(),
            data: {
              'elixr_registration': 'v1',
              'role': defaultRole,
              'first_name': normalized.firstName,
              'middle_name': ?normalized.middleName,
              'last_name': normalized.lastName,
              'teacher_access_code': ?normalizedCode,
              'privacy_policy_version': legalConsent.privacyPolicyVersion,
              'terms_of_service_version': legalConsent.termsOfServiceVersion,
            },
          )
          .timeout(_authOperationTimeout);
      final created = response.user;
      if (created == null) {
        throw const AuthFailure(
          AuthFailureKind.provisioning,
          'ELIXR could not finish creating your profile. Sign in to resume or try again.',
        );
      }
      if (response.session == null) {
        _pendingVerification = (email: trimmedEmail, password: password);
        _signupEmailSentAt = DateTime.now();
      }
      return User(
        id: created.id,
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
        email: created.email?.trim().isNotEmpty == true
            ? created.email!.trim()
            : trimmedEmail,
        role: defaultRole,
        teacherAccessCode: normalizedCode,
      );
    } on sb.AuthException catch (e) {
      if (isTeacher && _isDatabaseSignupFailure(e)) {
        throw const AuthFailure(
          AuthFailureKind.provisioning,
          'That Teacher access code is invalid or has already been used.',
        );
      }
      throw _failureForAuthError(e);
    } on TimeoutException {
      throw const AuthFailure(
        AuthFailureKind.network,
        'Registration timed out. Check your internet connection and try again.',
      );
    } on SocketException {
      throw const AuthFailure(
        AuthFailureKind.network,
        'Network error. Check your connection and try again.',
      );
    }
  }

  static bool _isDatabaseSignupFailure(sb.AuthException error) =>
      error.code == 'unexpected_failure' ||
      error.message.toLowerCase().contains('database error');

  Future<String?> _resolveEmailRedirect([String? explicit]) async {
    final trimmed = explicit?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    try {
      return await _emailRedirectUrl?.call();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<User> login({required String email, required String password}) async {
    sb.AuthResponse? response;
    try {
      response = await _auth
          .signInWithPassword(email: email.trim(), password: password)
          .timeout(_authOperationTimeout);
      final authUser = response.user;
      if (authUser == null) {
        throw const AuthFailure(
          AuthFailureKind.unknown,
          'Authentication failed',
        );
      }
      _pendingVerification = null;
      return await _loadUserProfile(authUser);
    } on sb.AuthException catch (e) {
      if (e.code == 'email_not_confirmed') {
        // Unconfirmed accounts receive no session. Resend the link so the
        // user can finish verification, without revealing more.
        _pendingVerification = (email: email.trim(), password: password);
        try {
          await _auth.resend(
            type: sb.OtpType.signup,
            email: email.trim(),
            emailRedirectTo: await _resolveEmailRedirect(),
          );
        } catch (_) {}
        throw const AuthFailure(
          AuthFailureKind.unknown,
          'Verify your email address before signing in. We sent you a new verification link.',
        );
      }
      throw _failureForAuthError(e);
    } on MissingUserProfileException {
      final authUser = response?.user;
      throw AuthFailure(
        AuthFailureKind.missingProfile,
        'Your sign-in is valid, but your ELIXR profile is incomplete. Complete it to continue.',
        pendingProfile: authUser == null
            ? null
            : _pendingEmailProfile(authUser),
      );
    } on TimeoutException {
      throw const AuthFailure(
        AuthFailureKind.network,
        'Sign-in timed out. Check your internet connection and try again.',
      );
    } on SocketException {
      throw const AuthFailure(
        AuthFailureKind.network,
        'Network error. Check your connection and try again.',
      );
    }
  }

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    return _signInWithGoogle(intent: GoogleOnboardingIntent.trainee);
  }

  @override
  Future<void> assertTeacherAccessCodeRedeemable(String code) {
    return _teacherAccessCodes.assertRedeemable(code);
  }

  @override
  Future<void> ensureTeacherRoleClaim() async {
    if (_auth.currentUser == null) {
      throw const TeacherRoleClaimException(
        TeacherRoleClaimFailureKind.unavailable,
        'Teacher authorization could not be refreshed. Sign in and try again.',
      );
    }
    await _verifyTeacherEvidence();
  }

  Future<void> _ensureTeacherProfileAuthorized(User profile) async {
    if (!profile.isTeacher) return;
    final authUser = _auth.currentUser;
    if (authUser == null || authUser.id != profile.id) {
      throw const TeacherRoleClaimException(
        TeacherRoleClaimFailureKind.invalidEvidence,
        'ELIXR could not verify this account as a Teacher. Sign in again.',
      );
    }
    await _verifyTeacherEvidence();
  }

  /// The Teacher role is a server-owned profile column bound to a consumed
  /// access code; this confirms that evidence is intact.
  Future<void> _verifyTeacherEvidence() async {
    try {
      await _client
          .rpc<dynamic>('assert_teacher_authorized')
          .timeout(_authOperationTimeout);
    } on TimeoutException {
      throw const TeacherRoleClaimException(
        TeacherRoleClaimFailureKind.unavailable,
        'Teacher authorization timed out. Check your connection and try again.',
      );
    } catch (error) {
      throw teacherRoleClaimExceptionFor(error);
    }
  }

  @override
  Future<GoogleSignInResult> signInWithGoogleTeacher({
    required String teacherAccessCode,
  }) async {
    return _signInWithGoogle(
      intent: GoogleOnboardingIntent.teacher,
      teacherAccessCode: CoachCode.tryNormalize(teacherAccessCode),
    );
  }

  Future<sb.User> _authenticateWithGoogle() async {
    final flow = _googleOAuthFlow;
    if (flow == null) {
      throw const GoogleOAuthFlowException(
        'Google sign-in is unavailable in this build.',
      );
    }
    final credential = await flow.authenticate((redirectUri) async {
      final response = await _auth.getOAuthSignInUrl(
        provider: sb.OAuthProvider.google,
        redirectTo: redirectUri.toString(),
        queryParams: const {'prompt': 'select_account'},
      );
      return Uri.parse(response.url);
    });
    final session = await _auth
        .exchangeCodeForSession(credential.authorizationCode)
        .timeout(_authOperationTimeout);
    return session.session.user;
  }

  Future<GoogleSignInResult> _signInWithGoogle({
    required GoogleOnboardingIntent intent,
    String? teacherAccessCode,
  }) async {
    try {
      final authUser = await _authenticateWithGoogle();
      final profile = await _loadExistingGoogleProfile(authUser);
      if (profile != null) return ExistingGoogleProfile(profile);
      return PendingGoogleSignIn(
        _pendingGoogleProfile(
          authUser,
          isNewUser: _isNewlyCreated(authUser),
          intent: intent,
          teacherAccessCode: teacherAccessCode,
        ),
      );
    } on GoogleSignInCancelledException {
      rethrow;
    } on GoogleOAuthFlowException catch (e) {
      throw Exception(e.message);
    } on sb.AuthException catch (e) {
      throw Exception(_messageForGoogleAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Google sign-in timed out. Check your internet connection and try again.',
      );
    } on TeacherRoleClaimException {
      await _signOutIgnoringErrors();
      rethrow;
    } catch (error, stackTrace) {
      await _signOutIgnoringErrors();
      if (kDebugMode) {
        debugPrint('Google profile load failed: $error');
        debugPrint('$stackTrace');
      }
      throw Exception(
        'Your Google account was verified, but ELIXR could not load your profile. Check your connection and try again.',
      );
    }
  }

  /// A brand-new identity is created by this very sign-in.
  static bool _isNewlyCreated(sb.User user) {
    final created = DateTime.tryParse(user.createdAt);
    final lastSignIn = DateTime.tryParse(user.lastSignInAt ?? '');
    if (created == null || lastSignIn == null) return false;
    return lastSignIn.difference(created).inSeconds.abs() < 60;
  }

  @override
  Future<GoogleSignInResult?> restoreGoogleSignIn() async {
    final authUser = _auth.currentUser;
    if (authUser == null || !_hasProvider(authUser, 'google')) {
      return null;
    }
    try {
      final profile = await _loadExistingGoogleProfile(authUser);
      if (profile != null) return ExistingGoogleProfile(profile);
      return PendingGoogleSignIn(
        _pendingGoogleProfile(
          authUser,
          isNewUser: false,
          intent: GoogleOnboardingIntent.unspecified,
        ),
      );
    } catch (error, stackTrace) {
      if (isBackendUnavailableError(error)) rethrow;
      await _signOutIgnoringErrors();
      if (kDebugMode) {
        debugPrint('Google session restore failed: $error');
        debugPrint('$stackTrace');
      }
      return null;
    }
  }

  @override
  Future<void> deleteAccountWithReauthentication({
    required AccountReauthentication reauthentication,
    required String expectedUserId,
  }) async {
    if (reauthentication.kind == AuthProviderKind.password) {
      final password = reauthentication.password;
      if (password == null || password.isEmpty) {
        throw Exception('Current password is required.');
      }
      return deleteAccount(password: password, expectedUserId: expectedUserId);
    }

    final authUser = _auth.currentUser;
    if (authUser == null || authUser.id != expectedUserId) {
      throw Exception(
        'The active sign-in does not match this account. Sign in again.',
      );
    }

    final sb.User activeUser;
    try {
      activeUser = await _authenticateWithGoogle();
    } on GoogleSignInCancelledException {
      rethrow;
    } on GoogleOAuthFlowException catch (e) {
      throw Exception(e.message);
    } on sb.AuthException catch (e) {
      throw Exception(_messageForGoogleAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Google verification timed out. No account data was deleted.',
      );
    }
    if (activeUser.id != expectedUserId) {
      await _signOutIgnoringErrors();
      throw Exception(
        'Google verified a different account. No account data was deleted.',
      );
    }
    await runAccountErasure(() => _eraseAccount(expectedUserId));
    await _signOutIgnoringErrors();
  }

  Future<User?> _loadExistingGoogleProfile(sb.User authUser) async {
    var profile = await _db.getUserById(authUser.id);
    final authEmail = authUser.email?.trim() ?? '';
    if (profile != null &&
        authEmail.isNotEmpty &&
        _emailsDiffer(authEmail, profile.email)) {
      await _db.updateUserProfileField(authUser.id, {'email': authEmail});
      profile = profile.copyWith(email: authEmail);
    }
    if (profile != null) await _ensureTeacherProfileAuthorized(profile);
    return profile;
  }

  PendingGoogleProfile _pendingGoogleProfile(
    sb.User authUser, {
    required bool isNewUser,
    GoogleOnboardingIntent intent = GoogleOnboardingIntent.unspecified,
    String? teacherAccessCode,
  }) {
    final email = authUser.email?.trim() ?? '';
    if (email.isEmpty || authUser.emailConfirmedAt == null) {
      throw Exception(
        'Google must provide a verified email address to continue.',
      );
    }
    final parsed = parseLegacyFullName(_displayNameOf(authUser));
    return PendingGoogleProfile(
      uid: authUser.id,
      email: email,
      firstName: parsed.firstName,
      middleName: parsed.middleName,
      lastName: parsed.lastName,
      isNewUser: isNewUser,
      intent: intent,
      teacherAccessCode: teacherAccessCode,
    );
  }

  PendingGoogleProfile _pendingEmailProfile(sb.User authUser) {
    final parsed = parseLegacyFullName(_displayNameOf(authUser));
    return PendingGoogleProfile(
      uid: authUser.id,
      email: authUser.email?.trim() ?? '',
      firstName: parsed.firstName,
      middleName: parsed.middleName,
      lastName: parsed.lastName,
      isNewUser: false,
      identityProvider: ProfileIdentityProvider.password,
    );
  }

  static String _displayNameOf(sb.User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    for (final key in const ['full_name', 'name']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Future<sb.User> _requireMatchingActiveUser(
    PendingGoogleProfile pendingProfile, {
    required String changedMessage,
    required String mismatchMessage,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null || authUser.id != pendingProfile.uid) {
      await _signOutIgnoringErrors();
      throw Exception(changedMessage);
    }
    final sb.User activeUser;
    try {
      activeUser =
          (await _auth.getUser().timeout(_authOperationTimeout)).user ??
          authUser;
    } on sb.AuthException catch (e) {
      throw Exception(_messageForGoogleAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Account verification timed out. Check your connection and retry.',
      );
    }
    final activeEmail = activeUser.email?.trim() ?? '';
    if (activeUser.id != pendingProfile.uid ||
        (pendingProfile.identityProvider == ProfileIdentityProvider.google &&
            activeUser.emailConfirmedAt == null) ||
        _emailsDiffer(activeEmail, pendingProfile.email)) {
      await _signOutIgnoringErrors();
      throw Exception(mismatchMessage);
    }
    return activeUser;
  }

  @override
  Future<User> completeGoogleProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
    required RegistrationLegalConsent legalConsent,
  }) async {
    final activeUser = await _requireMatchingActiveUser(
      pendingProfile,
      changedMessage: 'The active sign-in changed. Sign in again.',
      mismatchMessage:
          'The active sign-in no longer matches this profile. Sign in again.',
    );
    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    final user = User(
      id: activeUser.id,
      firstName: normalized.firstName,
      middleName: normalized.middleName,
      lastName: normalized.lastName,
      email: activeUser.email?.trim() ?? pendingProfile.email,
      role: User.roleTrainee,
    );
    try {
      await _db.upsertUserProfile(user, legalConsent: legalConsent);
    } on sb.PostgrestException {
      throw Exception(
        'ELIXR could not create your profile. Check your connection and retry.',
      );
    }
    return user;
  }

  @override
  Future<User> completeGoogleTeacherProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
    required String teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    final activeUser = await _requireMatchingActiveUser(
      pendingProfile,
      changedMessage:
          'The active Google account changed. Sign in with Google again.',
      mismatchMessage:
          'The active Google account no longer matches this profile. Sign in again.',
    );
    final normalizedCode = CoachCode.tryNormalize(teacherAccessCode);
    if (normalizedCode == null) {
      throw const TeacherAccessCodeException(
        TeacherAccessCodeError.malformedCode,
        'That Teacher access code is invalid or has already been used.',
      );
    }
    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    final user = User(
      id: activeUser.id,
      firstName: normalized.firstName,
      middleName: normalized.middleName,
      lastName: normalized.lastName,
      email: activeUser.email?.trim() ?? pendingProfile.email,
      role: User.roleTeacher,
      teacherAccessCode: normalizedCode,
    );

    try {
      await _teacherAccessCodes.consumeAndCreateTeacherProfile(
        code: normalizedCode,
        user: user,
        legalConsent: legalConsent,
      );
    } on Object catch (error, stackTrace) {
      // A committed transaction can still surface a transport error. Read the
      // UID-scoped profile before reporting failure so a retry cannot report
      // a false failure for an already-consumed code.
      User? reconciled;
      try {
        reconciled = await _teacherAccessCodes.reconcileTeacherProfile(
          expectedUser: user,
          code: normalizedCode,
        );
      } catch (reconciliationError) {
        if (kDebugMode) {
          debugPrint(
            'Teacher profile reconciliation was inconclusive: '
            '$reconciliationError',
          );
        }
        throw const AuthFailure(
          AuthFailureKind.provisioning,
          'ELIXR could not confirm whether your Teacher profile was created. Check your connection and sign in again.',
        );
      }
      if (reconciled != null) {
        await _ensureTeacherProfileAuthorized(reconciled);
        return reconciled;
      }
      if (error is TeacherAccessCodeException) {
        throw Exception(error.message ?? error.toString());
      }
      if (error is sb.PostgrestException) {
        throw Exception(
          'ELIXR could not create your Teacher profile. Check your connection and retry.',
        );
      }
      if (kDebugMode) {
        debugPrint('Teacher Google profile creation failed: $error');
        debugPrint('$stackTrace');
      }
      rethrow;
    }
    await _ensureTeacherProfileAuthorized(user);
    return user;
  }

  @override
  Future<void> cancelGoogleOnboarding(
    PendingGoogleProfile pendingProfile,
  ) async {
    final activeUser = _auth.currentUser;
    try {
      if (pendingProfile.isNewUser &&
          activeUser != null &&
          activeUser.id == pendingProfile.uid &&
          !_emailsDiffer(activeUser.email ?? '', pendingProfile.email)) {
        // The fresh identity has no profile or data; erasure removes it.
        await _eraseAccount(activeUser.id).timeout(_authOperationTimeout);
      }
    } on Object catch (error, stackTrace) {
      // Cancellation must always sign out. A failed best-effort deletion
      // leaves the identity intact for later recovery.
      if (kDebugMode) {
        debugPrint('New Google identity cleanup failed: $error');
        debugPrint('$stackTrace');
      }
    } finally {
      await _signOutIgnoringErrors();
    }
  }

  @override
  Future<Set<AuthProviderKind>> currentProviderKinds() async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      return _pendingVerification == null
          ? const {}
          : const {AuthProviderKind.password};
    }
    return {
      if (_hasProvider(authUser, 'email')) AuthProviderKind.password,
      if (_hasProvider(authUser, 'google')) AuthProviderKind.google,
    };
  }

  static bool _hasProvider(sb.User user, String provider) {
    final providers = user.appMetadata['providers'];
    if (providers is List && providers.contains(provider)) return true;
    if (user.appMetadata['provider'] == provider) return true;
    return user.identities?.any((identity) => identity.provider == provider) ??
        false;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Email cannot be empty.');
    }
    if (!_emailPattern.hasMatch(trimmedEmail)) {
      throw Exception('Invalid email address');
    }
    try {
      // Supabase does not reveal whether the address is registered.
      await _auth
          .resetPasswordForEmail(
            trimmedEmail,
            redirectTo: await _resolveEmailRedirect(continueUrl),
          )
          .timeout(_authOperationTimeout);
    } on sb.AuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Password reset timed out. Check your internet connection and try again.',
      );
    }
  }

  @override
  Future<void> completeEmailVerificationLink(String code) async {
    await _auth.exchangeCodeForSession(code).timeout(_authOperationTimeout);
    _pendingVerification = null;
  }

  @override
  Future<void> completePasswordReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      await _auth.exchangeCodeForSession(code).timeout(_authOperationTimeout);
      await _auth
          .updateUser(sb.UserAttributes(password: newPassword))
          .timeout(_authOperationTimeout);
    } on sb.AuthException catch (e) {
      throw Exception(
        _messageForAuthError(e, context: _AuthErrorContext.reauthentication),
      );
    } finally {
      await _signOutIgnoringErrors();
    }
  }

  @override
  Future<User?> loadPersistedUser() async {
    final result = await restorePersistedProfile();
    return result.user;
  }

  @override
  Future<PersistedProfileRestoration> restorePersistedProfile() async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      return const PersistedProfileRestoration.signedOut();
    }
    try {
      final user = await _loadUserProfile(
        authUser,
        reload: true,
        tolerateReloadFailure: true,
      );
      return PersistedProfileRestoration.authoritative(user);
    } on MissingUserProfileException {
      await _signOutIgnoringErrors();
      return const PersistedProfileRestoration.invalidProfile();
    } on InvalidPersistedAuthIdentityException {
      await _signOutIgnoringErrors();
      return const PersistedProfileRestoration.invalidProfile();
    } catch (error) {
      if (isBackendUnavailableError(error)) {
        return const PersistedProfileRestoration.unavailable();
      }
      rethrow;
    }
  }

  @override
  Future<void> clearCurrentUser() async {
    _pendingVerification = null;
    await _auth.signOut();
  }

  Future<void> _signOutIgnoringErrors() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort: the caller still treats the session as unusable.
    }
  }

  void _requireCurrentUser(String userId) {
    final authUser = _auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');
    if (authUser.id != userId) {
      throw Exception('Authenticated user does not match the profile.');
    }
  }

  Future<User> _reloadProfile(String userId) async {
    final updated = await _db.getUserById(userId);
    if (updated == null) throw Exception('User profile not found');
    return updated;
  }

  static Map<String, dynamic> _pictureFields(ProfilePictureUpdate update) =>
      update.isRemoval
      ? {
          'profile_picture_url': null,
          'profile_picture_storage_path': null,
          'profile_picture_path': null,
        }
      : {
          'profile_picture_url': update.url,
          'profile_picture_storage_path': update.storagePath,
          // Retire the legacy local-path field now that a cross-device URL
          // exists.
          'profile_picture_path': null,
        };

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    _requireCurrentUser(userId);
    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    await _db.updateUserProfileField(userId, {
      'first_name': normalized.firstName,
      'middle_name': normalized.middleName,
      'last_name': normalized.lastName,
      if (profilePictureUpdate != null) ..._pictureFields(profilePictureUpdate),
    });
    return _reloadProfile(userId);
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    _requireCurrentUser(userId);
    await _db.updateUserProfileField(
      userId,
      _pictureFields(profilePictureUpdate),
    );
    return _reloadProfile(userId);
  }

  @override
  Future<User> updateTeacherProfileBorder({
    required String userId,
    required String? profileBorderId,
  }) async {
    _requireCurrentUser(userId);
    final existing = await _reloadProfile(userId);
    if (!existing.isTeacher) {
      throw Exception('Only Teachers can update an avatar frame.');
    }
    final normalized = profileBorderId?.trim() ?? '';
    await _db.updateUserProfileField(userId, {
      'profile_border_id': normalized.isEmpty ? null : normalized,
    });
    final updated = await _reloadProfile(userId);
    if (!updated.isTeacher) {
      throw Exception('Teacher role changed while updating the avatar frame.');
    }
    return updated;
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');

    final trimmedEmail = newEmail.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Email cannot be empty.');
    }
    if (!_emailPattern.hasMatch(trimmedEmail)) {
      throw Exception('Invalid email address');
    }

    final currentAuthEmail = authUser.email?.trim() ?? '';
    if (!_emailsDiffer(trimmedEmail, currentAuthEmail)) {
      return EmailChangeRequestResult.unchanged;
    }
    if (currentPassword.isEmpty) {
      throw Exception('Current password is required to change your email.');
    }
    if (currentAuthEmail.isEmpty) {
      throw Exception(
        'This account has no email address. Email cannot be updated.',
      );
    }

    await _refreshRecentLogin(
      email: currentAuthEmail,
      password: currentPassword,
      errorContext: _AuthErrorContext.emailChange,
    );
    try {
      await _auth
          .updateUser(
            sb.UserAttributes(email: trimmedEmail),
            emailRedirectTo: await _resolveEmailRedirect(continueUrl),
          )
          .timeout(_authOperationTimeout);
      return EmailChangeRequestResult.verificationSent;
    } on sb.AuthException catch (e) {
      throw Exception(
        _messageForAuthError(e, context: _AuthErrorContext.emailChange),
      );
    } on TimeoutException {
      throw Exception(
        'Email update timed out. Check your internet connection and try again.',
      );
    }
  }

  @override
  Future<bool> isCurrentEmailVerified() async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      return _completePendingVerificationSignIn();
    }
    try {
      final refreshed = (await _auth.getUser().timeout(
        _authOperationTimeout,
      )).user;
      return (refreshed ?? authUser).emailConfirmedAt != null;
    } on sb.AuthException {
      return authUser.emailConfirmedAt != null;
    } on TimeoutException {
      return authUser.emailConfirmedAt != null;
    }
  }

  /// Confirmation completed elsewhere (another browser or device) is only
  /// observable by signing in with the held registration credentials.
  Future<bool> _completePendingVerificationSignIn() async {
    final pending = _pendingVerification;
    if (pending == null) return false;
    // Verification is polled frequently; sign-in attempts are rate limited by
    // the Auth server, so probe at most once per interval.
    final now = DateTime.now();
    final last = _lastPendingVerificationProbe;
    if (last != null &&
        now.difference(last) < _pendingVerificationProbeInterval) {
      return false;
    }
    _lastPendingVerificationProbe = now;
    try {
      await _auth
          .signInWithPassword(email: pending.email, password: pending.password)
          .timeout(_authOperationTimeout);
      _pendingVerification = null;
      return true;
    } on sb.AuthException {
      return false;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    }
  }

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {
    final authUser = _auth.currentUser;
    final email = authUser?.email?.trim() ?? _pendingVerification?.email ?? '';
    if (authUser == null && _pendingVerification == null) {
      throw Exception('Not authenticated');
    }
    if (authUser != null && authUser.emailConfirmedAt != null) {
      throw Exception('Your email is already verified.');
    }
    if (email.isEmpty) {
      throw Exception(
        'This account has no email address. Verification cannot be sent.',
      );
    }
    final sentAt = _signupEmailSentAt;
    if (sentAt != null &&
        DateTime.now().difference(sentAt) < const Duration(seconds: 60)) {
      // Sign-up already sent the confirmation email moments ago.
      return;
    }
    try {
      await _auth
          .resend(
            type: sb.OtpType.signup,
            email: email,
            emailRedirectTo: await _resolveEmailRedirect(continueUrl),
          )
          .timeout(_authOperationTimeout);
      _signupEmailSentAt = DateTime.now();
    } on sb.AuthException catch (e) {
      throw Exception(
        _messageForAuthError(e, context: _AuthErrorContext.emailChange),
      );
    } on TimeoutException {
      throw Exception(
        'Verification email timed out. Check your internet connection and try again.',
      );
    }
  }

  @override
  Future<User?> refreshAuthenticatedUser() async {
    final authUser = _auth.currentUser;
    if (authUser == null) return null;
    try {
      return await _loadUserProfile(authUser, reload: true);
    } on MissingUserProfileException {
      await _signOutIgnoringErrors();
      return null;
    }
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async {
    final trimmedPending = pendingEmail.trim();
    final authUser = _auth.currentUser;
    if (authUser != null) {
      try {
        final refreshed =
            (await _auth.getUser().timeout(_authOperationTimeout)).user ??
            authUser;
        final authEmail = refreshed.email?.trim() ?? '';
        if (!_emailsDiffer(authEmail, trimmedPending)) {
          final user = await _loadUserProfile(refreshed);
          if (user.id != originalUid) {
            return PendingEmailChangeRecoveryResult.failed(
              'Email verification completed for a different account. '
              'Sign in again.',
            );
          }
          return PendingEmailChangeRecoveryResult.completed(user);
        }
        return PendingEmailChangeRecoveryResult.pending();
      } on sb.AuthException catch (e) {
        if (!_isSessionInvalidation(e)) {
          return PendingEmailChangeRecoveryResult.transientFailure();
        }
      } on TimeoutException {
        return PendingEmailChangeRecoveryResult.transientFailure();
      }
    }
    return _recoverSessionWithVerifiedEmail(
      originalUid: originalUid,
      pendingEmail: trimmedPending,
      recoveryPassword: recoveryPassword,
    );
  }

  Future<PendingEmailChangeRecoveryResult> _recoverSessionWithVerifiedEmail({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
  }) async {
    try {
      final response = await _auth
          .signInWithPassword(email: pendingEmail, password: recoveryPassword)
          .timeout(_authOperationTimeout);
      final recovered = response.user;
      if (recovered == null) {
        return PendingEmailChangeRecoveryResult.failed(
          'Could not restore your session. Sign in with your verified email.',
        );
      }
      if (recovered.id != originalUid) {
        await _auth.signOut();
        return PendingEmailChangeRecoveryResult.failed(
          'Email verification completed for a different account. '
          'Sign in again.',
        );
      }
      final user = await _loadUserProfile(recovered, reload: true);
      return PendingEmailChangeRecoveryResult.completed(user);
    } on sb.AuthException catch (e) {
      if (e.code == 'invalid_credentials') {
        // The new address is not confirmed yet (or the password changed).
        return PendingEmailChangeRecoveryResult.pending();
      }
      return PendingEmailChangeRecoveryResult.transientFailure();
    } on TimeoutException {
      return PendingEmailChangeRecoveryResult.transientFailure();
    }
  }

  static bool _isSessionInvalidation(sb.AuthException error) =>
      error.statusCode == '401' ||
      error.statusCode == '403' ||
      error.code == 'user_not_found' ||
      error.code == 'session_not_found' ||
      error.code == 'bad_jwt';

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');

    final email = authUser.email;
    if (email == null || email.isEmpty) {
      throw Exception(
        'This account has no email address. Password cannot be updated.',
      );
    }

    await _refreshRecentLogin(
      email: email,
      password: currentPassword,
      errorContext: _AuthErrorContext.reauthentication,
    );
    try {
      await _auth
          .updateUser(sb.UserAttributes(password: newPassword))
          .timeout(_authOperationTimeout);
    } on sb.AuthException catch (e) {
      throw Exception(
        _messageForAuthError(e, context: _AuthErrorContext.reauthentication),
      );
    } on TimeoutException {
      throw Exception(
        'Password update timed out. Check your internet connection and try again.',
      );
    }
  }

  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');
    if (authUser.id != expectedUserId) {
      throw Exception(
        'The active sign-in does not match this account. Sign in again.',
      );
    }

    final email = authUser.email;
    if (email == null || email.isEmpty) {
      throw Exception(
        'This account has no email address. Account cannot be deleted.',
      );
    }

    final activeUser = await _refreshRecentLogin(
      email: email,
      password: password,
      errorContext: _AuthErrorContext.reauthentication,
    );
    if (activeUser.id != expectedUserId) {
      await _signOutIgnoringErrors();
      throw Exception(
        'Authentication changed accounts. Sign in again before deleting.',
      );
    }
    await runAccountErasure(() => _eraseAccount(activeUser.id));
    await _signOutIgnoringErrors();
  }

  /// Server-side erasure: the admin Edge Function verifies a recent sign-in,
  /// anonymizes retained chat, removes owned Storage objects, then deletes
  /// the auth user (all ELIXR rows cascade from it).
  Future<void> _eraseAccount(String uid) async {
    final override = _eraseAccountOverride;
    if (override != null) return override(uid);
    final response = await _client.functions
        .invoke('elixr-admin', body: const {'action': 'delete_account'})
        .timeout(const Duration(minutes: 5));
    if (response.status != 200) {
      throw StateError('Account erasure was not accepted.');
    }
  }

  Future<sb.User> _refreshRecentLogin({
    required String email,
    required String password,
    required _AuthErrorContext errorContext,
  }) async {
    // Re-validating the current password with a fresh sign-in also records a
    // recent sign-in, which sensitive server operations require.
    try {
      final response = await _auth
          .signInWithPassword(email: email, password: password)
          .timeout(_authOperationTimeout);
      final user = response.user;
      if (user == null) throw Exception('Not authenticated');
      return user;
    } on sb.AuthException catch (e) {
      throw Exception(_messageForAuthError(e, context: errorContext));
    } on TimeoutException {
      throw Exception(
        'Authentication timed out. Check your internet connection and try again.',
      );
    }
  }

  Future<User> _loadUserProfile(
    sb.User authUser, {
    bool reload = false,
    bool tolerateReloadFailure = false,
  }) async {
    var authEmail = authUser.email ?? '';
    if (reload) {
      try {
        final refreshed = (await _auth.getUser().timeout(
          _authOperationTimeout,
        )).user;
        authEmail = refreshed?.email ?? authEmail;
      } on sb.AuthRetryableFetchException {
        if (!tolerateReloadFailure) {
          throw Exception(
            'Network error. Check your connection and try again.',
          );
        }
      } on sb.AuthException catch (e) {
        if (tolerateReloadFailure) {
          throw const InvalidPersistedAuthIdentityException();
        }
        throw Exception(_messageForAuthError(e));
      } on TimeoutException {
        if (!tolerateReloadFailure) {
          throw Exception(
            'Account refresh timed out. Check your internet connection and try again.',
          );
        }
      } catch (error) {
        if (!(tolerateReloadFailure && isBackendUnavailableError(error))) {
          rethrow;
        }
      }
    }

    var profile = await _db.getUserById(authUser.id);
    if (profile == null) {
      // Profiles require explicit, versioned legal consent recorded by the
      // server, so a missing profile is never synthesized here; the caller
      // routes the identity through profile completion instead.
      throw const MissingUserProfileException();
    }

    final trimmedAuthEmail = authEmail.trim();
    if (trimmedAuthEmail.isNotEmpty &&
        _emailsDiffer(trimmedAuthEmail, profile.email)) {
      await _db.updateUserProfileField(authUser.id, {
        'email': trimmedAuthEmail,
      });
      profile = profile.copyWith(email: trimmedAuthEmail);
    }

    await _ensureTeacherProfileAuthorized(profile);
    return profile;
  }

  static bool _emailsDiffer(String a, String b) {
    return a.trim().toLowerCase() != b.trim().toLowerCase();
  }

  String _messageForAuthError(
    sb.AuthException error, {
    _AuthErrorContext context = _AuthErrorContext.login,
  }) {
    switch (error.code) {
      case 'validation_failed':
      case 'email_address_invalid':
        return 'Invalid email address';
      case 'user_banned':
        return 'This account has been disabled';
      case 'invalid_credentials':
      case 'user_not_found':
        if (context == _AuthErrorContext.login) {
          return 'Invalid email or password';
        }
        return 'The current password is incorrect.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Email already registered';
      case 'weak_password':
        return 'Password must be at least 6 characters';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Too many attempts. Try again later';
      case 'email_provider_disabled':
      case 'signup_disabled':
        return 'Email sign-in is disabled for this project. '
            'Check the Supabase Authentication settings.';
      case 'reauthentication_needed':
        if (context == _AuthErrorContext.emailChange) {
          return 'Please sign out and sign in again before changing your email';
        }
        return 'Please sign out and sign in again before changing your password';
      case 'same_password':
        return 'Choose a password different from your current password.';
    }
    if (error is sb.AuthRetryableFetchException) {
      return 'Network error. Check your connection and try again.';
    }
    final message = error.message.toLowerCase();
    if (message.contains('network') || message.contains('socket')) {
      return 'Network error. Check your connection and try again.';
    }
    return error.message.isEmpty ? 'Authentication failed' : error.message;
  }

  AuthFailure _failureForAuthError(
    sb.AuthException error, {
    _AuthErrorContext context = _AuthErrorContext.login,
  }) {
    final kind = switch (error.code) {
      'user_banned' => AuthFailureKind.disabledAccount,
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' => AuthFailureKind.rateLimited,
      'invalid_credentials' || 'user_not_found' =>
        context == _AuthErrorContext.login
            ? AuthFailureKind.invalidCredentials
            : AuthFailureKind.reauthentication,
      _ when error is sb.AuthRetryableFetchException => AuthFailureKind.network,
      _ => AuthFailureKind.unknown,
    };
    return AuthFailure(kind, _messageForAuthError(error, context: context));
  }

  String _messageForGoogleAuthError(sb.AuthException error) {
    switch (error.code) {
      case 'identity_already_exists':
      case 'email_exists':
      case 'user_already_exists':
        return 'This email already uses another sign-in method. Sign in with your existing method first.';
      case 'provider_disabled':
        return 'Google sign-in is not enabled for this project.';
      case 'user_banned':
        return 'This account has been disabled.';
      case 'bad_code_verifier':
      case 'flow_state_expired':
      case 'flow_state_not_found':
        return 'Google sign-in expired. Please try again.';
    }
    if (error is sb.AuthRetryableFetchException) {
      return 'Could not reach Google. Check your internet connection and try again.';
    }
    return 'Google sign-in could not be completed. Please try again.';
  }
}
