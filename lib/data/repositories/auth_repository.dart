import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../database/firestore_helper.dart';
import '../models/user.dart';
import '../../core/constants/app_constants.dart';

class AuthRepository {
  AuthRepository({fb.FirebaseAuth? auth, FirestoreHelper? db})
    : _auth = auth ?? fb.FirebaseAuth.instance,
      _db = db ?? FirestoreHelper.instance;

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
    try {
      final credential = fb.EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: currentPassword,
      );
      await firebaseUser.reauthenticateWithCredential(credential);
      await firebaseUser.updatePassword(newPassword);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
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
      default:
        return error.message ?? 'Authentication failed';
    }
  }
}
