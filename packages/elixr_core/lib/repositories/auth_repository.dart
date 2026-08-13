import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../database/firestore_collections.dart';
import '../database/user_profile_store.dart';
import '../models/user.dart';
import '../utils/manila_day.dart';
import '../utils/user_name.dart';
import 'profile_image_repository.dart';

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
    required String defaultRole,
  });

  Future<User> login({required String email, required String password});

  /// Sends a Firebase Auth password-reset email.
  ///
  /// Must not reveal whether [email] is registered. Callers should show a
  /// generic success message after this completes without error.
  Future<void> sendPasswordResetEmail({required String email});

  Future<User?> loadPersistedUser();

  Future<void> clearCurrentUser();

  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  });

  /// Persists a Cloud Storage avatar mutation for [userId].
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

  /// Reloads the Firebase user and returns whether the current email is verified.
  ///
  /// Firestore rules read `request.auth.token.email_verified` from the ID
  /// token, not `User.emailVerified`. When the user is verified, this also
  /// force-refreshes a stale token so roster writes are not denied after
  /// `reload()` alone.
  Future<bool> isCurrentEmailVerified();

  Future<void> requestCurrentEmailVerification();

  Future<User?> refreshAuthenticatedUser();

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Re-authenticates with [password], purges the user's Firestore/Storage
  /// data, then deletes the Firebase Auth user. Does not delete Auth if the
  /// data purge fails.
  Future<void> deleteAccount({required String password});

  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  });
}

enum _AuthErrorContext { login, reauthentication, emailChange }

/// Deletes known + listed profile Storage objects for [uid].
///
/// `object-not-found` is treated as already-clean; every other
/// [FirebaseException] is rethrown so account erasure can fail closed.
@visibleForTesting
Future<void> deleteProfileStorageObjects({
  required String uid,
  String? storagePath,
  required ProfileImageRepositoryBase profileImages,
  required Future<List<String>> Function(String uid) listObjectPaths,
}) async {
  if (storagePath != null && storagePath.isNotEmpty) {
    await profileImages.deleteProfileImage(
      authenticatedUid: uid,
      storagePath: storagePath,
    );
  }

  try {
    final paths = await listObjectPaths(uid);
    for (final path in paths) {
      await profileImages.deleteProfileImage(
        authenticatedUid: uid,
        storagePath: path,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code == 'object-not-found') return;
    rethrow;
  }
}

/// Force-refreshes the Firebase ID token when `User.emailVerified` is true but
/// the cached JWT still has `email_verified: false`.
///
/// `User.reload()` updates the User object; Firestore still evaluates
/// `request.auth.token` until `getIdToken(true)` mints a new token.
@visibleForTesting
Future<void> refreshStaleEmailVerifiedIdToken({
  required bool emailVerified,
  required Future<Map<String, dynamic>?> Function() readClaims,
  required Future<void> Function() forceRefreshIdToken,
}) async {
  if (!emailVerified) return;
  var claimVerified = false;
  try {
    final claims = await readClaims();
    claimVerified = claims?['email_verified'] == true;
  } catch (_) {
    // Inspecting the cached JWT failed. Force a refresh so Firestore
    // sees the same verification state as User.emailVerified.
    claimVerified = false;
  }
  if (claimVerified) return;
  await forceRefreshIdToken();
}

/// User-facing message when Firestore/Storage purge fails before Auth delete.
const accountErasurePurgeFailedMessage =
    "We couldn't finish deleting all of your account data, so your sign-in "
    'account was not removed. Please try again.';

/// Thrown from a purge stage so debug logs can identify where erasure failed.
@visibleForTesting
class AccountPurgeStageException implements Exception {
  AccountPurgeStageException({required this.stage, required this.cause});

  final String stage;
  final Object cause;

  @override
  String toString() => 'AccountPurgeStageException($stage): $cause';
}

String _describeAccountPurgeError(Object error) {
  if (error is FirebaseException) {
    return 'plugin=${error.plugin} code=${error.code} '
        'message=${error.message ?? '(none)'}';
  }
  if (error is AccountPurgeStageException) {
    return 'stage=${error.stage}; ${_describeAccountPurgeError(error.cause)}';
  }
  return error.toString();
}

void _logAccountPurgeFailure(Object error) {
  if (!kDebugMode) return;
  debugPrint(
    'Account erasure purge failed: ${_describeAccountPurgeError(error)}',
  );
}

/// Purges account data then deletes Auth. Auth deletion runs only after a
/// successful purge.
@visibleForTesting
Future<void> finishAccountDeletionAfterPurge({
  required Future<void> Function() purgeUserData,
  required Future<void> Function() deleteAuthUser,
}) async {
  try {
    await purgeUserData();
  } catch (e) {
    _logAccountPurgeFailure(e);
    throw Exception(accountErasurePurgeFailedMessage);
  }
  await deleteAuthUser();
}

/// Thrown when a Firebase Auth session has no Firestore `users/{uid}` document
/// and the client is not allowed to synthesize a Trainee profile.
class MissingUserProfileException implements Exception {
  const MissingUserProfileException();

  static const message = 'Account profile not found. Please register first.';

  @override
  String toString() => message;
}

class AuthRepository implements AuthRepositoryBase {
  AuthRepository({
    fb.FirebaseAuth? auth,
    UserProfileStore? db,
    FirebaseFirestore? firestore,
    ProfileImageRepositoryBase? profileImageRepository,
    FirebaseStorage? storage,
    Future<List<String>> Function(String userId)? listProfileStorageObjectPaths,
    this.createMissingProfile = true,
  }) : _auth = auth ?? fb.FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _db =
           db ??
           FirebaseUserProfileStore(
             firestore: firestore ?? FirebaseFirestore.instance,
           ),
       _profileImages = profileImageRepository ?? ProfileImageRepository(),
       _storage = storage ?? FirebaseStorage.instance,
       _listProfileStorageObjectPaths = listProfileStorageObjectPaths;

  static const _authOperationTimeout = Duration(seconds: 30);
  static const _batchLimit = 500;
  static const _whereInLimit = 30;
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final fb.FirebaseAuth _auth;
  final UserProfileStore _db;
  final FirebaseFirestore _firestore;
  final ProfileImageRepositoryBase _profileImages;
  final FirebaseStorage _storage;
  final Future<List<String>> Function(String userId)?
  _listProfileStorageObjectPaths;

  /// When false, a Firebase session without a Firestore profile is signed out
  /// instead of synthesizing a Trainee document. Teacher clients pass false
  /// so a missing profile cannot become a Trainee user written from this app.
  final bool createMissingProfile;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
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
        role: defaultRole,
      );
      await _db.upsertUserProfile(user, includePrivacyConsent: true);
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
      return await _loadUserProfile(credential.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on MissingUserProfileException {
      await _signOutIgnoringErrors();
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Email cannot be empty.');
    }
    if (!_emailPattern.hasMatch(trimmedEmail)) {
      throw Exception('Invalid email address');
    }

    try {
      await _auth
          .sendPasswordResetEmail(email: trimmedEmail)
          .timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
      // Avoid leaking whether an account exists for this address.
      if (e.code == 'user-not-found') return;
      throw Exception(_messageForAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Password reset timed out. Check your internet connection and try again.',
      );
    }
  }

  @override
  Future<User?> loadPersistedUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    try {
      return await _loadUserProfile(
        firebaseUser,
        reload: true,
        tolerateReloadFailure: true,
      );
    } on MissingUserProfileException {
      await _signOutIgnoringErrors();
      return null;
    }
  }

  @override
  Future<void> clearCurrentUser() {
    return _auth.signOut();
  }

  Future<void> _signOutIgnoringErrors() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort: the caller still treats the session as unusable.
    }
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
      if (profilePictureUpdate.isRemoval) {
        fields['profile_picture_url'] = FieldValue.delete();
        fields['profile_picture_storage_path'] = FieldValue.delete();
        fields['profile_picture_path'] = FieldValue.delete();
      } else {
        fields['profile_picture_url'] = profilePictureUpdate.url;
        fields['profile_picture_storage_path'] =
            profilePictureUpdate.storagePath;
        // Retire the legacy local-path field now that a cross-device URL exists.
        fields['profile_picture_path'] = FieldValue.delete();
      }
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

    final fields = profilePictureUpdate.isRemoval
        ? <String, dynamic>{
            'profile_picture_url': FieldValue.delete(),
            'profile_picture_storage_path': FieldValue.delete(),
            'profile_picture_path': FieldValue.delete(),
          }
        : <String, dynamic>{
            'profile_picture_url': profilePictureUpdate.url,
            'profile_picture_storage_path': profilePictureUpdate.storagePath,
            // Retire the legacy local-path field now that a cross-device URL exists.
            'profile_picture_path': FieldValue.delete(),
          };
    await _db.updateUserProfileField(userId, fields);

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
      await _refreshStaleVerifiedEmailIdToken(firebaseUser);
      return firebaseUser.emailVerified;
    } on TimeoutException {
      await _refreshStaleVerifiedEmailIdToken(firebaseUser);
      return firebaseUser.emailVerified;
    }

    final activeUser = _auth.currentUser ?? firebaseUser;
    await _refreshStaleVerifiedEmailIdToken(activeUser);
    return activeUser.emailVerified;
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
    try {
      return await _loadUserProfile(firebaseUser, reload: true);
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

  @override
  Future<void> deleteAccount({required String password}) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');

    final email = firebaseUser.email;
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
    final uid = activeUser.uid;

    await finishAccountDeletionAfterPurge(
      purgeUserData: () => _purgeUserData(uid),
      deleteAuthUser: () async {
        try {
          await activeUser.delete().timeout(_authOperationTimeout);
        } on fb.FirebaseAuthException catch (e) {
          throw Exception(
            'Your data was removed, but deleting the sign-in account failed: '
            '${_messageForAuthError(e, context: _AuthErrorContext.reauthentication)}. '
            'Try signing in again or contact support.',
          );
        } on TimeoutException {
          throw Exception(
            'Your data was removed, but deleting the sign-in account timed out. '
            'Try signing in again or contact support.',
          );
        }
      },
    );
  }

  Future<void> _purgeUserData(String uid) async {
    final sessionSnap = await _runPurgeStage('sessions query', () {
      return _firestore
          .collection(FirestoreCollections.sessions)
          .where('user_id', isEqualTo: uid)
          .get();
    });
    final sessionIds = sessionSnap.docs.map((d) => d.id).toList();

    // Feedbacks must be deleted while parent sessions still exist (rules get()).
    await _runPurgeStage('feedback purge', () async {
      final feedbackRefs = <DocumentReference>[];
      for (var i = 0; i < sessionIds.length; i += _whereInLimit) {
        final chunk = sessionIds.sublist(
          i,
          math.min(i + _whereInLimit, sessionIds.length),
        );
        final feedbackSnap = await _firestore
            .collection(FirestoreCollections.feedbacks)
            .where('session_id', whereIn: chunk)
            .get();
        feedbackRefs.addAll(feedbackSnap.docs.map((d) => d.reference));
      }
      await _commitDeletes(feedbackRefs);
    });

    await _runPurgeStage('sessions purge', () {
      return _commitDeletes(sessionSnap.docs.map((d) => d.reference).toList());
    });

    await _runPurgeStage('leaderboard marker purge', () async {
      final markerSnap = await _firestore
          .collection(FirestoreCollections.leaderboardProcessedSessions)
          .where('user_id', isEqualTo: uid)
          .get();
      await _commitDeletes(markerSnap.docs.map((d) => d.reference).toList());
    });

    final profile = await _runPurgeStage('daily quest board purge', () async {
      final loaded = await _db.getUserById(uid);
      final createdAt =
          DateTime.tryParse(loaded?.createdAt ?? '')?.toUtc() ??
          ManilaDay.boardEnumerationFallbackStartUtc;
      final boardIds = ManilaDay.enumerateDailyQuestBoardIds(
        userId: uid,
        createdAtUtc: createdAt,
        nowUtc: DateTime.now().toUtc(),
      );
      await _commitDeletes([
        for (final id in boardIds)
          _firestore.collection(FirestoreCollections.dailyQuestBoards).doc(id),
      ]);
      return loaded;
    });

    await _runPurgeStage('daily quest claim purge', () async {
      final claimSnap = await _firestore
          .collection(FirestoreCollections.dailyQuestClaims)
          .where('user_id', isEqualTo: uid)
          .get();
      await _commitDeletes(claimSnap.docs.map((d) => d.reference).toList());
    });

    await _runPurgeStage('achievement claim purge', () async {
      final achievementSnap = await _firestore
          .collection(FirestoreCollections.achievementClaims)
          .where('user_id', isEqualTo: uid)
          .get();
      await _commitDeletes(
        achievementSnap.docs.map((d) => d.reference).toList(),
      );
    });

    await _runPurgeStage('cosmetics/leaderboard purge', () {
      return _commitDeletes([
        _firestore.collection(FirestoreCollections.userCosmetics).doc(uid),
        _firestore.collection(FirestoreCollections.leaderboard).doc(uid),
      ]);
    });

    await _runPurgeStage('public profile purge', () async {
      final publicRoot = _firestore
          .collection(FirestoreCollections.publicProfiles)
          .doc(uid);
      final publicSessions = await publicRoot.collection('sessions').get();
      final publicAchievements = await publicRoot
          .collection('achievements')
          .get();
      await _commitDeletes([
        ...publicSessions.docs.map((d) => d.reference),
        ...publicAchievements.docs.map((d) => d.reference),
        publicRoot.collection('details').doc('summary'),
        publicRoot,
      ]);
    });

    await _runPurgeStage('inbound visits purge', () async {
      final inboundVisits = await _firestore
          .collection(FirestoreCollections.profileVisits)
          .doc(uid)
          .collection('visitors')
          .get();
      await _commitDeletes(inboundVisits.docs.map((d) => d.reference).toList());
    });

    await _runPurgeStage('outbound visits purge', () async {
      final outboundVisits = await _firestore
          .collectionGroup('visitors')
          .where('viewer_id', isEqualTo: uid)
          .get();
      await _commitDeletes(
        outboundVisits.docs.map((d) => d.reference).toList(),
      );
    });

    await _runPurgeStage('teacher invite purge', () async {
      final userSnap = await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      final code = userSnap.data()?['teacher_invite_code'];
      if (code is String && code.isNotEmpty) {
        await _commitDeletes([
          _firestore.collection(FirestoreCollections.teacherInvites).doc(code),
        ]);
      }
    });

    await _runPurgeStage('teacher-student link purge', () async {
      final asTrainee = await _firestore
          .collection(FirestoreCollections.teacherStudentLinks)
          .where('trainee_id', isEqualTo: uid)
          .get();
      final asTeacher = await _firestore
          .collection(FirestoreCollections.teacherStudentLinks)
          .where('teacher_id', isEqualTo: uid)
          .get();
      await _commitDeletes([
        ...asTrainee.docs.map((d) => d.reference),
        ...asTeacher.docs.map((d) => d.reference),
      ]);
    });

    await _runPurgeStage('users document purge', () {
      return _commitDeletes([
        _firestore.collection(FirestoreCollections.users).doc(uid),
      ]);
    });

    await _runPurgeStage('profile Storage purge', () {
      return _deleteProfileStorage(uid, profile?.profilePictureStoragePath);
    });
  }

  Future<T> _runPurgeStage<T>(String stage, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, st) {
      final wrapped = AccountPurgeStageException(stage: stage, cause: e);
      if (kDebugMode) {
        debugPrint(
          'Account erasure failed at stage "$stage": '
          '${_describeAccountPurgeError(e)}',
        );
      }
      Error.throwWithStackTrace(wrapped, st);
    }
  }

  Future<void> _deleteProfileStorage(String uid, String? storagePath) {
    return deleteProfileStorageObjects(
      uid: uid,
      storagePath: storagePath,
      profileImages: _profileImages,
      listObjectPaths: _listProfileObjectPaths,
    );
  }

  Future<List<String>> _listProfileObjectPaths(String uid) async {
    final override = _listProfileStorageObjectPaths;
    if (override != null) return override(uid);

    final listed = await _storage
        .ref(ProfileImageRepository.profilePrefixForUser(uid))
        .listAll();
    return [for (final item in listed.items) item.fullPath];
  }

  Future<void> _commitDeletes(List<DocumentReference> refs) async {
    if (refs.isEmpty) return;
    for (var i = 0; i < refs.length; i += _batchLimit) {
      final batch = _firestore.batch();
      final end = math.min(i + _batchLimit, refs.length);
      for (var j = i; j < end; j++) {
        batch.delete(refs[j]);
      }
      await batch.commit();
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

  Future<void> _refreshStaleVerifiedEmailIdToken(fb.User firebaseUser) async {
    try {
      await refreshStaleEmailVerifiedIdToken(
        emailVerified: firebaseUser.emailVerified,
        readClaims: () async {
          final result = await firebaseUser.getIdTokenResult().timeout(
            _authOperationTimeout,
          );
          return result.claims;
        },
        forceRefreshIdToken: () async {
          await firebaseUser.getIdToken(true).timeout(_authOperationTimeout);
        },
      );
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Account refresh timed out. Check your internet connection and try again.',
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
      if (!createMissingProfile) {
        throw const MissingUserProfileException();
      }
      final parsed = parseLegacyFullName(firebaseUser.displayName ?? 'Trainee');
      final user = User(
        id: firebaseUser.uid,
        firstName: parsed.firstName,
        middleName: parsed.middleName,
        lastName: parsed.lastName,
        email: authEmail,
        role: User.roleTrainee,
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
