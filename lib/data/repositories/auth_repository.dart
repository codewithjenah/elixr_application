import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../database/firestore_helper.dart';
import '../models/user.dart';
import '../../core/constants/app_constants.dart';

enum EmailChangeRequestResult { unchanged, verificationSent }

enum _AuthErrorContext { login, reauthentication, emailChange }

class AuthRepository {
  AuthRepository({fb.FirebaseAuth? auth, FirestoreHelper? db})
    : _auth = auth ?? fb.FirebaseAuth.instance,
      _db = db ?? FirestoreHelper.instance;

  static const _authOperationTimeout = Duration(seconds: 30);
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final fb.FirebaseAuth _auth;
  final FirestoreHelper _db;

  Future<User> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      final user = User(
        id: uid,
        fullName: fullName,
        email: email,
        role: AppConstants.defaultRole,
      );
      await _db.upsertUserProfile(user);
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

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

  Future<User?> loadPersistedUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    return _loadUserProfile(
      firebaseUser,
      reload: true,
      tolerateReloadFailure: true,
    );
  }

  Future<void> clearCurrentUser() {
    return _auth.signOut();
  }

  Future<User> updateProfileDetails({
    required String userId,
    required String fullName,
    String? profilePicturePath,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');
    if (firebaseUser.uid != userId) {
      throw Exception('Authenticated user does not match the profile.');
    }

    final fields = <String, dynamic>{
      'full_name': fullName,
      'profile_picture_path': profilePicturePath,
    };
    await _db.updateUserProfileField(userId, fields);

    final updated = await _db.getUserById(userId);
    if (updated == null) throw Exception('User profile not found');
    return updated;
  }

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

  Future<User?> refreshAuthenticatedUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    return _loadUserProfile(firebaseUser, reload: true);
  }

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
      final user = User(
        id: firebaseUser.uid,
        fullName: firebaseUser.displayName ?? 'Trainee',
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
