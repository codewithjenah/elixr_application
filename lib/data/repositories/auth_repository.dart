import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../database/firestore_helper.dart';
import '../models/user.dart';
import '../../core/constants/app_constants.dart';

class AuthRepository {
  AuthRepository({fb.FirebaseAuth? auth, FirestoreHelper? db})
    : _auth = auth ?? fb.FirebaseAuth.instance,
      _db = db ?? FirestoreHelper.instance;

  static const _passwordUpdateTimeout = Duration(seconds: 30);

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
    return _loadUserProfile(firebaseUser);
  }

  Future<void> clearCurrentUser() {
    return _auth.signOut();
  }

  Future<User> updateProfile({
    required String userId,
    required String fullName,
    required String email,
    String? profilePicturePath,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');

    if (firebaseUser.email != email) {
      try {
        await firebaseUser.verifyBeforeUpdateEmail(email);
      } on fb.FirebaseAuthException catch (e) {
        throw Exception(_messageForAuthError(e));
      }
    }

    final fields = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'profile_picture_path': profilePicturePath,
    };
    await _db.updateUserProfileField(userId, fields);

    final updated = await _db.getUserById(userId);
    return updated!;
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
      // Re-validate the current password with the same sign-in path used at
      // login. `reauthenticateWithCredential` can hang on the Windows desktop
      // Firebase Auth plugin; signing in again refreshes the session safely.
      await _auth
          .signInWithEmailAndPassword(email: email, password: currentPassword)
          .timeout(_passwordUpdateTimeout);

      final activeUser = _auth.currentUser;
      if (activeUser == null) throw Exception('Not authenticated');

      await activeUser
          .updatePassword(newPassword)
          .timeout(_passwordUpdateTimeout);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Password update timed out. Check your internet connection and try again.',
      );
    }
  }

  Future<User> _loadUserProfile(fb.User firebaseUser) async {
    final profile = await _db.getUserById(firebaseUser.uid);
    if (profile != null) return profile;

    final user = User(
      id: firebaseUser.uid,
      fullName: firebaseUser.displayName ?? 'Trainee',
      email: firebaseUser.email ?? '',
      role: AppConstants.defaultRole,
    );
    await _db.upsertUserProfile(user);
    return user;
  }

  String _messageForAuthError(fb.FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'email-already-in-use':
        return 'Email already registered';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'requires-recent-login':
        return 'Please sign out and sign in again before changing your password';
      default:
        return error.message ?? 'Authentication failed';
    }
  }
}
