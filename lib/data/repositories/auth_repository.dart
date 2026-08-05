import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../database/firestore_helper.dart';
import '../models/user.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/user_name.dart';

/// A newly uploaded Cloud Storage avatar to persist alongside a profile
/// update. Presence of this value is what tells the repository to write the
/// new fields and retire the legacy local-path field.
class ProfilePictureUpdate {
  const ProfilePictureUpdate({required this.url, required this.storagePath});

  final String url;
  final String storagePath;
}

enum EmailChangeRequestResult { unchanged, verificationSent }

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

abstract class AuthRepositoryBase {
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  });

  Future<User> login({required String email, required String password});

  Future<User?> loadPersistedUser();

  Future<void> clearCurrentUser();

  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  });

  /// Persists only Cloud Storage avatar fields for [userId].
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
  });

  Future<bool> isCurrentEmailVerified();

  Future<void> requestCurrentEmailVerification();

  Future<User?> refreshAuthenticatedUser();

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  });
}

enum _AuthErrorContext { login, reauthentication, emailChange }

class AuthRepository implements AuthRepositoryBase {
  AuthRepository({fb.FirebaseAuth? auth, FirestoreHelper? db})
    : _auth = auth ?? fb.FirebaseAuth.instance,
      _db = db ?? FirestoreHelper.instance;

  static const _authOperationTimeout = Duration(seconds: 30);
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final fb.FirebaseAuth _auth;
  final FirestoreHelper _db;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      final normalized = normalizeUserNameParts(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      );
      final user = User(
        id: uid,
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
        email: email,
        role: AppConstants.defaultRole,
      );
      await _db.upsertUserProfile(user);
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

  @override
  Future<User> login({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _loadUserProfile(credential.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

  @override
  Future<User?> loadPersistedUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    return _loadUserProfile(
      firebaseUser,
      reload: true,
      tolerateReloadFailure: true,
    );
  }

  @override
  Future<void> clearCurrentUser() {
    return _auth.signOut();
  }

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');
    if (firebaseUser.uid != userId) {
      throw Exception('Authenticated user does not match the profile.');
    }

    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    final fields = <String, dynamic>{
      'first_name': normalized.firstName,
      'last_name': normalized.lastName,
      'full_name': normalized.fullName,
      if (normalized.middleName != null)
        'middle_name': normalized.middleName
      else
        'middle_name': FieldValue.delete(),
    };
    if (profilePictureUpdate != null) {
      fields['profile_picture_url'] = profilePictureUpdate.url;
      fields['profile_picture_storage_path'] = profilePictureUpdate.storagePath;
      // Retire the legacy local-path field now that a cross-device URL exists.
      fields['profile_picture_path'] = FieldValue.delete();
    }
    await _db.updateUserProfileField(userId, fields);

    final updated = await _db.getUserById(userId);
    if (updated == null) throw Exception('User profile not found');
    return updated;
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');
    if (firebaseUser.uid != userId) {
      throw Exception('Authenticated user does not match the profile.');
    }

    await _db.updateUserProfileField(userId, {
      'profile_picture_url': profilePictureUpdate.url,
      'profile_picture_storage_path': profilePictureUpdate.storagePath,
      // Retire the legacy local-path field now that a cross-device URL exists.
      'profile_picture_path': FieldValue.delete(),
    });

    final updated = await _db.getUserById(userId);
    if (updated == null) throw Exception('User profile not found');
    return updated;
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');

    final trimmedEmail = newEmail.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Email cannot be empty.');
    }
    if (!_emailPattern.hasMatch(trimmedEmail)) {
      throw Exception('Invalid email address');
    }

    final currentAuthEmail = firebaseUser.email?.trim() ?? '';
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

    try {
      final activeUser = await _refreshRecentLogin(
        email: currentAuthEmail,
        password: currentPassword,
        errorContext: _AuthErrorContext.emailChange,
      );

      await activeUser
          .verifyBeforeUpdateEmail(trimmedEmail)
          .timeout(_authOperationTimeout);
      return EmailChangeRequestResult.verificationSent;
    } on fb.FirebaseAuthException catch (e) {
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
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return false;

    try {
      await firebaseUser.reload().timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException {
      return firebaseUser.emailVerified;
    } on TimeoutException {
      return firebaseUser.emailVerified;
    }

    return _auth.currentUser?.emailVerified ?? firebaseUser.emailVerified;
  }

  @override
  Future<void> requestCurrentEmailVerification() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');

    try {
      await firebaseUser.reload().timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Account refresh timed out. Check your internet connection and try again.',
      );
    }

    final activeUser = _auth.currentUser;
    if (activeUser == null) throw Exception('Not authenticated');
    if (activeUser.emailVerified) {
      throw Exception('Your email is already verified.');
    }

    final email = activeUser.email?.trim() ?? '';
    if (email.isEmpty) {
      throw Exception(
        'This account has no email address. Verification cannot be sent.',
      );
    }

    try {
      await activeUser.sendEmailVerification().timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
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
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    return _loadUserProfile(firebaseUser, reload: true);
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async {
    final trimmedPending = pendingEmail.trim();
    final trimmedOriginal = originalEmail?.trim() ?? '';
    var firebaseUser = _auth.currentUser;
    var needsRecoverySignIn = false;

    if (firebaseUser != null) {
      try {
        await firebaseUser.reload().timeout(_authOperationTimeout);
        firebaseUser = _auth.currentUser;
        if (firebaseUser == null) {
          needsRecoverySignIn = true;
        } else {
          final authEmail = firebaseUser.email?.trim() ?? '';
          if (!_emailsDiffer(authEmail, trimmedPending)) {
            final user = await _loadUserProfile(firebaseUser);
            if (user.id != originalUid) {
              return PendingEmailChangeRecoveryResult.failed(
                'Email verification completed for a different account. '
                'Sign in again.',
              );
            }
            return PendingEmailChangeRecoveryResult.completed(user);
          }
          if (trimmedOriginal.isNotEmpty &&
              !_emailsDiffer(authEmail, trimmedOriginal)) {
            return PendingEmailChangeRecoveryResult.pending();
          }
          return PendingEmailChangeRecoveryResult.pending();
        }
      } on fb.FirebaseAuthException catch (e) {
        if (_isRecoverableSessionInvalidation(e)) {
          needsRecoverySignIn = true;
        } else {
          return PendingEmailChangeRecoveryResult.transientFailure();
        }
      } on TimeoutException {
        return PendingEmailChangeRecoveryResult.transientFailure();
      }
    } else {
      needsRecoverySignIn = true;
    }

    if (!needsRecoverySignIn) {
      return PendingEmailChangeRecoveryResult.pending();
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
      final credential = await _auth
          .signInWithEmailAndPassword(
            email: pendingEmail,
            password: recoveryPassword,
          )
          .timeout(_authOperationTimeout);
      final recovered = credential.user;
      if (recovered == null) {
        return PendingEmailChangeRecoveryResult.failed(
          'Could not restore your session. Sign in with your verified email.',
        );
      }
      if (recovered.uid != originalUid) {
        await _auth.signOut();
        return PendingEmailChangeRecoveryResult.failed(
          'Email verification completed for a different account. '
          'Sign in again.',
        );
      }
      final user = await _loadUserProfile(recovered, reload: true);
      return PendingEmailChangeRecoveryResult.completed(user);
    } on fb.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return PendingEmailChangeRecoveryResult.failed(
            'Could not restore your session automatically. '
            'Sign in with your verified email and password.',
          );
        case 'user-not-found':
          return PendingEmailChangeRecoveryResult.pending();
        case 'too-many-requests':
        case 'network-request-failed':
          return PendingEmailChangeRecoveryResult.transientFailure();
        default:
          return PendingEmailChangeRecoveryResult.transientFailure();
      }
    } on TimeoutException {
      return PendingEmailChangeRecoveryResult.transientFailure();
    }
  }

  static bool _isRecoverableSessionInvalidation(
    fb.FirebaseAuthException error,
  ) {
    switch (error.code) {
      case 'user-token-expired':
      case 'invalid-user-token':
      case 'user-disabled':
        return true;
      default:
        return false;
    }
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');

    final email = firebaseUser.email;
    if (email == null || email.isEmpty) {
      throw Exception(
        'This account has no email address. Password cannot be updated.',
      );
    }

    try {
      final activeUser = await _refreshRecentLogin(
        email: email,
        password: currentPassword,
        errorContext: _AuthErrorContext.reauthentication,
      );

      await activeUser
          .updatePassword(newPassword)
          .timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(
        _messageForAuthError(e, context: _AuthErrorContext.reauthentication),
      );
    } on TimeoutException {
      throw Exception(
        'Password update timed out. Check your internet connection and try again.',
      );
    }
  }

  Future<fb.User> _refreshRecentLogin({
    required String email,
    required String password,
    required _AuthErrorContext errorContext,
  }) async {
    // Re-validate the current password with the same sign-in path used at
    // login. `reauthenticateWithCredential` can hang on the Windows desktop
    // Firebase Auth plugin; signing in again refreshes the session safely.
    try {
      final credential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(_authOperationTimeout);
      final user = credential.user;
      if (user == null) throw Exception('Not authenticated');
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e, context: errorContext));
    } on TimeoutException {
      throw Exception(
        'Authentication timed out. Check your internet connection and try again.',
      );
    }
  }

  Future<User> _loadUserProfile(
    fb.User firebaseUser, {
    bool reload = false,
    bool tolerateReloadFailure = false,
  }) async {
    var authEmail = firebaseUser.email ?? '';
    if (reload) {
      try {
        await firebaseUser.reload().timeout(_authOperationTimeout);
      } on fb.FirebaseAuthException catch (e) {
        if (!tolerateReloadFailure) {
          throw Exception(_messageForAuthError(e));
        }
      } on TimeoutException {
        if (!tolerateReloadFailure) {
          throw Exception(
            'Account refresh timed out. Check your internet connection and try again.',
          );
        }
      }
      authEmail = _auth.currentUser?.email ?? authEmail;
    }

    var profile = await _db.getUserById(firebaseUser.uid);
    if (profile == null) {
      final parsed = parseLegacyFullName(firebaseUser.displayName ?? 'Trainee');
      final user = User(
        id: firebaseUser.uid,
        firstName: parsed.firstName,
        middleName: parsed.middleName,
        lastName: parsed.lastName,
        email: authEmail,
        role: AppConstants.defaultRole,
      );
      await _db.upsertUserProfile(user);
      return user;
    }

    final trimmedAuthEmail = authEmail.trim();
    if (trimmedAuthEmail.isNotEmpty &&
        _emailsDiffer(trimmedAuthEmail, profile.email)) {
      await _db.updateUserProfileField(firebaseUser.uid, {
        'email': trimmedAuthEmail,
      });
      profile = profile.copyWith(email: trimmedAuthEmail);
    }

    return profile;
  }

  static bool _emailsDiffer(String a, String b) {
    return a.trim().toLowerCase() != b.trim().toLowerCase();
  }

  String _messageForAuthError(
    fb.FirebaseAuthException error, {
    _AuthErrorContext context = _AuthErrorContext.login,
  }) {
    switch (error.code) {
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        if (context == _AuthErrorContext.login) {
          return 'Invalid email or password';
        }
        return 'The current password is incorrect.';
      case 'email-already-in-use':
        return 'Email already registered';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'operation-not-allowed':
        return 'Email verification is disabled for this Firebase project. '
            'Check Authentication settings in the Firebase console.';
      case 'requires-recent-login':
        if (context == _AuthErrorContext.emailChange) {
          return 'Please sign out and sign in again before changing your email';
        }
        return 'Please sign out and sign in again before changing your password';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        final message = error.message?.toLowerCase() ?? '';
        if (message.contains('network')) {
          return 'Network error. Check your connection and try again.';
        }
        return error.message ?? 'Authentication failed';
    }
  }
}
