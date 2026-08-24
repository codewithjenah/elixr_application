import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../database/firestore_collections.dart';
import '../database/user_profile_store.dart';
import '../models/coach_code.dart';
import '../models/teacher_access_code_exception.dart';
import '../models/user.dart';
import '../utils/manila_day.dart';
import '../utils/user_name.dart';
import 'firebase_teacher_access_code_repository.dart';
import 'profile_image_repository.dart';
import 'teacher_access_code_repository.dart';

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

/// Sign-in capabilities reported by Firebase for the active identity.
enum AuthProviderKind { password, google }

class PendingGoogleProfile {
  const PendingGoogleProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.isNewUser,
  });

  final String uid;
  final String email;
  final String firstName;
  final String? middleName;
  final String lastName;
  final bool isNewUser;
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

abstract class AuthRepositoryBase {
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
  });

  Future<User> login({required String email, required String password});

  /// Sends a Firebase Auth password-reset email.
  ///
  /// Must not reveal whether [email] is registered. Callers should show a
  /// generic success message after this completes without error.
  ///
  /// When [continueUrl] is set, Firebase redirects there after the reset
  /// action so the desktop app can detect completion.
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
    String? continueUrl,
  });

  /// Reloads the Firebase user and returns whether the current email is verified.
  ///
  /// Firestore rules read `request.auth.token.email_verified` from the ID
  /// token, not `User.emailVerified`. When the user is verified, this also
  /// force-refreshes a stale token so roster writes are not denied after
  /// `reload()` alone.
  Future<bool> isCurrentEmailVerified();

  Future<void> requestCurrentEmailVerification({String? continueUrl});

  Future<User?> refreshAuthenticatedUser();

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Re-authenticates with [password], purges the user's Firestore/Storage
  /// data, then deletes the Firebase Auth user. Does not delete Auth if the
  /// data purge fails.
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
  });

  Future<void> cancelGoogleOnboarding(PendingGoogleProfile pendingProfile);

  Future<Set<AuthProviderKind>> currentProviderKinds();

  Future<void> deleteAccountWithReauthentication({
    required AccountReauthentication reauthentication,
    required String expectedUserId,
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

const accountDeletionRequiresTypedConfirmationMessage =
    'Type the displayed confirmation phrase before deleting your account.';

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

/// Purges Phase 2 `groups`, `group_invites`, and `group_memberships` data for
/// account erasure. Trainees lose their memberships; Teachers lose owned groups,
/// active group invites (derived from group pointers), and related memberships.
@visibleForTesting
Future<void> purgePhase2GroupDataForAccountErasure({
  required FirebaseFirestore firestore,
  required Future<void> Function(List<DocumentReference>) commitDeletes,
  required String uid,
}) async {
  final refs = <String, DocumentReference>{};

  final asTraineeMemberships = await firestore
      .collection(FirestoreCollections.groupMemberships)
      .where('trainee_id', isEqualTo: uid)
      .get();
  for (final doc in asTraineeMemberships.docs) {
    refs[doc.reference.path] = doc.reference;
  }

  final ownedGroups = await firestore
      .collection(FirestoreCollections.groups)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final doc in ownedGroups.docs) {
    final inviteCode = doc.data()['invite_code'];
    if (inviteCode is String &&
        inviteCode.isNotEmpty &&
        CoachCode.isNormalized(inviteCode)) {
      final inviteRef = firestore
          .collection(FirestoreCollections.groupInvites)
          .doc(inviteCode);
      refs[inviteRef.path] = inviteRef;
    }
    refs[doc.reference.path] = doc.reference;
  }

  final asTeacherMemberships = await firestore
      .collection(FirestoreCollections.groupMemberships)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final doc in asTeacherMemberships.docs) {
    refs[doc.reference.path] = doc.reference;
  }

  await commitDeletes(refs.values.toList());
}

/// Purges Teacher-owned Phase 5 classroom definitions before the users
/// document is removed. Ordinary Teachers keep delete permission on their
/// own movement/assignment documents while verified; this path also works
/// after the users document is gone.
@visibleForTesting
Future<void> purgePhase5ClassroomOwnedDataForAccountErasure({
  required FirebaseFirestore firestore,
  required Future<void> Function(List<DocumentReference>) commitDeletes,
  required String uid,
}) async {
  final refs = <String, DocumentReference>{};

  final ownedMovements = await firestore
      .collection(FirestoreCollections.teacherMovements)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final movement in ownedMovements.docs) {
    final revisions = await movement.reference
        .collection(FirestoreCollections.teacherMovementRevisions)
        .get();
    for (final revision in revisions.docs) {
      refs[revision.reference.path] = revision.reference;
    }
    refs[movement.reference.path] = movement.reference;
  }

  final ownedAssignments = await firestore
      .collection(FirestoreCollections.groupAssignments)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final assignment in ownedAssignments.docs) {
    refs[assignment.reference.path] = assignment.reference;
  }

  await commitDeletes(refs.values.toList());
}

/// Canonical assignment-submission object path from frozen attempt identity.
///
/// Used during account erasure when `video_storage_path` was never written
/// (abandoned drafts) and when the stored path is present. Throws if a
/// `teacher_review_submission` is missing frozen identity fields so erasure
/// fails closed instead of skipping an object that may still exist.
@visibleForTesting
String canonicalAssignmentSubmissionStoragePath({
  required String attemptId,
  required Map<String, dynamic> data,
}) {
  if (data['attempt_kind'] != 'teacher_review_submission') {
    throw StateError(
      'canonical assignment submission path requires teacher_review_submission',
    );
  }
  String readId(String key) {
    final value = data[key];
    if (value is! String) {
      throw StateError(
        'teacher_review_submission $attemptId is missing $key for Storage cleanup',
      );
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw StateError(
        'teacher_review_submission $attemptId is missing $key for Storage cleanup',
      );
    }
    return trimmed;
  }

  final id = attemptId.trim();
  if (id.isEmpty) {
    throw StateError(
      'teacher_review_submission is missing attempt id for Storage cleanup',
    );
  }
  return 'assignment_submissions/${readId('teacher_id')}/'
      '${readId('group_id')}/${readId('assignment_id')}/'
      '${readId('trainee_id')}/$id.mp4';
}

/// Purges assignment-submission MP4s while the matching attempt documents
/// still exist. Storage rules authorize delete from the frozen Trainee or
/// assigning Teacher identity on those documents.
@visibleForTesting
Future<void> purgeAssignmentSubmissionVideosForAccountErasure({
  required FirebaseFirestore firestore,
  required Future<void> Function(String storagePath) deleteObject,
  required String uid,
}) async {
  final paths = <String>{};
  final asTrainee = await firestore
      .collection(FirestoreCollections.assignmentAttempts)
      .where('trainee_id', isEqualTo: uid)
      .get();
  final asTeacher = await firestore
      .collection(FirestoreCollections.assignmentAttempts)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final doc in [...asTrainee.docs, ...asTeacher.docs]) {
    final data = doc.data();
    if (data['attempt_kind'] == 'teacher_review_submission') {
      paths.add(
        canonicalAssignmentSubmissionStoragePath(attemptId: doc.id, data: data),
      );
    }
    final path = data['video_storage_path'];
    if (path is String && path.trim().isNotEmpty) {
      paths.add(path.trim());
    }
  }
  for (final path in paths) {
    try {
      await deleteObject(path);
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}

/// Purges `assignment_attempts` after the caller's users document is gone.
///
/// Rules allow this only during account erasure (`!exists(users/{uid})`).
/// Ordinary Teachers must not receive generic delete permission on trainee
/// classroom attempts.
@visibleForTesting
Future<void> purgePhase5AssignmentAttemptsForAccountErasure({
  required FirebaseFirestore firestore,
  required Future<void> Function(List<DocumentReference>) commitDeletes,
  required String uid,
}) async {
  final refs = <String, DocumentReference>{};
  final asTrainee = await firestore
      .collection(FirestoreCollections.assignmentAttempts)
      .where('trainee_id', isEqualTo: uid)
      .get();
  final asTeacher = await firestore
      .collection(FirestoreCollections.assignmentAttempts)
      .where('teacher_id', isEqualTo: uid)
      .get();
  for (final doc in asTrainee.docs) {
    refs[doc.reference.path] = doc.reference;
  }
  for (final doc in asTeacher.docs) {
    refs[doc.reference.path] = doc.reference;
  }
  await commitDeletes(refs.values.toList());
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

class AuthRepository implements AuthRepositoryBase, GoogleAuthRepositoryBase {
  AuthRepository({
    fb.FirebaseAuth? auth,
    UserProfileStore? db,
    FirebaseFirestore? firestore,
    ProfileImageRepositoryBase? profileImageRepository,
    FirebaseStorage? storage,
    TeacherAccessCodeRepository? teacherAccessCodeRepository,
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
       _teacherAccessCodes =
           teacherAccessCodeRepository ??
           FirebaseTeacherAccessCodeRepository(
             firestore: firestore ?? FirebaseFirestore.instance,
           ),
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
  final TeacherAccessCodeRepository _teacherAccessCodes;
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
    String? teacherAccessCode,
  }) async {
    final isTeacher = defaultRole == User.roleTeacher;
    if (isTeacher) {
      await _teacherAccessCodes.assertRedeemable(teacherAccessCode);
    } else if (teacherAccessCode != null &&
        teacherAccessCode.trim().isNotEmpty) {
      throw Exception(
        'Teacher access codes cannot be used for Trainee registration.',
      );
    }

    fb.UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
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
      if (isTeacher) {
        // TODO: After redemption, a Cloud Function should set a Teacher
        // custom claim so role is not trusted from the Firestore user doc.
        await _teacherAccessCodes.consumeAndCreateTeacherProfile(
          code: teacherAccessCode!,
          user: user,
        );
      } else {
        await _db.upsertUserProfile(user, includePrivacyConsent: true);
      }
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } on TeacherAccessCodeException catch (e) {
      await _deleteCreatedAuthUser(credential);
      throw Exception(e.message ?? e.toString());
    } catch (e) {
      if (isTeacher) {
        await _deleteCreatedAuthUser(credential);
      }
      rethrow;
    }
  }

  Future<void> _deleteCreatedAuthUser(fb.UserCredential? credential) async {
    final created = credential?.user;
    if (created == null) return;
    try {
      await created.delete();
    } catch (_) {
      try {
        await _auth.signOut();
      } catch (_) {}
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
  Future<GoogleSignInResult> signInWithGoogle() async {
    try {
      final credential = await _auth
          .signInWithProvider(fb.GoogleAuthProvider())
          .timeout(_authOperationTimeout);
      return await _googleResultForCredential(credential);
    } on fb.FirebaseAuthException catch (e) {
      if (_isGoogleCancellation(e.code)) {
        throw const GoogleSignInCancelledException();
      }
      throw Exception(_messageForGoogleAuthError(e));
    } on FirebaseException {
      await _signOutIgnoringErrors();
      throw Exception(
        'Your Google account was verified, but ELIXR could not load your profile. Check your connection and try again.',
      );
    } on TimeoutException {
      throw Exception(
        'Google sign-in timed out. Check your internet connection and try again.',
      );
    } catch (error, stackTrace) {
      await _signOutIgnoringErrors();
      if (kDebugMode) {
        debugPrint('Google profile load failed: $error');
        debugPrint('$stackTrace');
      }
      throw Exception(
        'ELIXR could not validate this account profile. Please try again.',
      );
    }
  }

  @override
  Future<GoogleSignInResult?> restoreGoogleSignIn() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || !_hasProvider(firebaseUser, 'google.com')) {
      return null;
    }
    try {
      final profile = await _loadExistingGoogleProfile(firebaseUser);
      if (profile != null) return ExistingGoogleProfile(profile);
      return PendingGoogleSignIn(
        _pendingGoogleProfile(firebaseUser, isNewUser: false),
      );
    } catch (error, stackTrace) {
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

    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || firebaseUser.uid != expectedUserId) {
      throw Exception(
        'The active sign-in does not match this account. Sign in again.',
      );
    }

    fb.UserCredential credential;
    try {
      credential = await _auth
          .signInWithProvider(fb.GoogleAuthProvider())
          .timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
      if (_isGoogleCancellation(e.code)) {
        throw const GoogleSignInCancelledException();
      }
      throw Exception(_messageForGoogleAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Google verification timed out. No account data was deleted.',
      );
    }

    final activeUser = credential.user;
    if (activeUser == null || activeUser.uid != expectedUserId) {
      await _signOutIgnoringErrors();
      throw Exception(
        'Google verified a different account. No account data was deleted.',
      );
    }
    await finishAccountDeletionAfterPurge(
      purgeUserData: () => _purgeUserData(expectedUserId),
      deleteAuthUser: () async {
        try {
          await activeUser.delete().timeout(_authOperationTimeout);
        } on fb.FirebaseAuthException catch (e) {
          throw Exception(
            'Your data was removed, but deleting the Google sign-in account failed: '
            '${_messageForGoogleAuthError(e)} Try signing in again or contact support.',
          );
        } on TimeoutException {
          throw Exception(
            'Your data was removed, but deleting the Google sign-in account timed out. Try signing in again or contact support.',
          );
        }
      },
    );
  }

  Future<GoogleSignInResult> _googleResultForCredential(
    fb.UserCredential credential,
  ) async {
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Google did not return an authenticated account.');
    }
    final profile = await _loadExistingGoogleProfile(firebaseUser);
    if (profile != null) return ExistingGoogleProfile(profile);
    return PendingGoogleSignIn(
      _pendingGoogleProfile(
        firebaseUser,
        isNewUser: credential.additionalUserInfo?.isNewUser == true,
      ),
    );
  }

  Future<User?> _loadExistingGoogleProfile(fb.User firebaseUser) async {
    var profile = await _db.getUserById(firebaseUser.uid);
    final authEmail = firebaseUser.email?.trim() ?? '';
    if (profile != null &&
        authEmail.isNotEmpty &&
        _emailsDiffer(authEmail, profile.email)) {
      await _db.updateUserProfileField(firebaseUser.uid, {'email': authEmail});
      profile = profile.copyWith(email: authEmail);
    }
    return profile;
  }

  PendingGoogleProfile _pendingGoogleProfile(
    fb.User firebaseUser, {
    required bool isNewUser,
  }) {
    final email = firebaseUser.email?.trim() ?? '';
    if (email.isEmpty || !firebaseUser.emailVerified) {
      throw Exception(
        'Google must provide a verified email address to continue.',
      );
    }
    final parsed = parseLegacyFullName(firebaseUser.displayName ?? '');
    return PendingGoogleProfile(
      uid: firebaseUser.uid,
      email: email,
      firstName: parsed.firstName,
      middleName: parsed.middleName,
      lastName: parsed.lastName,
      isNewUser: isNewUser,
    );
  }

  @override
  Future<User> completeGoogleProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || firebaseUser.uid != pendingProfile.uid) {
      await _signOutIgnoringErrors();
      throw Exception(
        'The active Google account changed. Sign in with Google again.',
      );
    }
    try {
      await firebaseUser.reload().timeout(_authOperationTimeout);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_messageForGoogleAuthError(e));
    } on TimeoutException {
      throw Exception(
        'Google account verification timed out. Check your connection and retry.',
      );
    }
    final activeUser = _auth.currentUser;
    final activeEmail = activeUser?.email?.trim() ?? '';
    if (activeUser == null ||
        activeUser.uid != pendingProfile.uid ||
        !activeUser.emailVerified ||
        _emailsDiffer(activeEmail, pendingProfile.email)) {
      await _signOutIgnoringErrors();
      throw Exception(
        'The active Google account no longer matches this profile. Sign in again.',
      );
    }
    final normalized = normalizeUserNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
    final user = User(
      id: activeUser.uid,
      firstName: normalized.firstName,
      middleName: normalized.middleName,
      lastName: normalized.lastName,
      email: activeEmail,
      role: User.roleTrainee,
    );
    try {
      await _db.upsertUserProfile(user, includePrivacyConsent: true);
    } on FirebaseException {
      throw Exception(
        'ELIXR could not create your profile. Check your connection and retry.',
      );
    }
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
          activeUser.uid == pendingProfile.uid &&
          !_emailsDiffer(activeUser.email ?? '', pendingProfile.email)) {
        await activeUser.delete().timeout(_authOperationTimeout);
      }
    } on Object catch (error, stackTrace) {
      // Cancellation must always clear local onboarding and sign out. A failed
      // best-effort deletion leaves the Firebase identity intact for recovery.
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
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return const {};
    final kinds = <AuthProviderKind>{};
    if (_hasProvider(firebaseUser, 'password')) {
      kinds.add(AuthProviderKind.password);
    }
    if (_hasProvider(firebaseUser, 'google.com')) {
      kinds.add(AuthProviderKind.google);
    }
    return kinds;
  }

  static bool _hasProvider(fb.User user, String providerId) {
    return user.providerData.any(
      (provider) => provider.providerId == providerId,
    );
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
      await _auth
          .sendPasswordResetEmail(
            email: trimmedEmail,
            actionCodeSettings: _actionCodeSettings(continueUrl: continueUrl),
          )
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
    String? continueUrl,
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
          .verifyBeforeUpdateEmail(
            trimmedEmail,
            _actionCodeSettings(continueUrl: continueUrl),
          )
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
  Future<void> requestCurrentEmailVerification({String? continueUrl}) {
    return _sendCurrentEmailVerification(
      allowIfAlreadyVerified: false,
      continueUrl: continueUrl,
    );
  }

  fb.ActionCodeSettings? _actionCodeSettings({String? continueUrl}) {
    final url = continueUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return fb.ActionCodeSettings(url: url, handleCodeInApp: false);
    }
    return null;
  }

  Future<void> _sendCurrentEmailVerification({
    required bool allowIfAlreadyVerified,
    String? continueUrl,
  }) async {
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
    if (activeUser.emailVerified && !allowIfAlreadyVerified) {
      throw Exception('Your email is already verified.');
    }

    final email = activeUser.email?.trim() ?? '';
    if (email.isEmpty) {
      throw Exception(
        'This account has no email address. Verification cannot be sent.',
      );
    }

    try {
      await activeUser
          .sendEmailVerification(_actionCodeSettings(continueUrl: continueUrl))
          .timeout(_authOperationTimeout);
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
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) throw Exception('Not authenticated');
    if (firebaseUser.uid != expectedUserId) {
      throw Exception(
        'The active sign-in does not match this account. Sign in again.',
      );
    }

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
    if (activeUser.uid != expectedUserId) {
      await _signOutIgnoringErrors();
      throw Exception(
        'Authentication changed accounts. Sign in again before deleting.',
      );
    }
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
    // Evidence can contain private annotated images and must be purged before
    // session documents/auth are removed. A non-not-found failure is allowed
    // to fail closed so account deletion never leaves known image data behind.
    await _runPurgeStage('session evidence Storage purge', () async {
      final listed = await _storage
          .ref('users/$uid/session_evidence')
          .listAll();
      for (final item in listed.items) {
        try {
          await item.delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') rethrow;
        }
      }
    });

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

    await _runPurgeStage('training plan purge', () async {
      final planSnap = await _firestore
          .collection(FirestoreCollections.trainingPlans)
          .where('user_id', isEqualTo: uid)
          .get();
      await _commitDeletes(planSnap.docs.map((d) => d.reference).toList());
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
      final data = userSnap.data();
      final codes = <String>{
        if (data?['teacher_roster_invite_code'] case final String value
            when value.isNotEmpty)
          value,
        if (data?['teacher_invite_code'] case final String value
            when value.isNotEmpty)
          value,
      };
      await _commitDeletes([
        for (final code in codes)
          _firestore.collection(FirestoreCollections.teacherInvites).doc(code),
      ]);
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

    await _runPurgeStage('group data purge', () {
      return purgePhase2GroupDataForAccountErasure(
        firestore: _firestore,
        commitDeletes: _commitDeletes,
        uid: uid,
      );
    });

    await _runPurgeStage('phase 5 classroom owned purge', () {
      return purgePhase5ClassroomOwnedDataForAccountErasure(
        firestore: _firestore,
        commitDeletes: _commitDeletes,
        uid: uid,
      );
    });

    // Submission MP4s must be deleted while assignment_attempts still exist
    // and the user is still authenticated. Storage rules match those docs.
    await _runPurgeStage('assignment submission Storage purge', () {
      return purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: _firestore,
        uid: uid,
        deleteObject: (path) async {
          try {
            await _storage.ref(path).delete();
          } on FirebaseException catch (error) {
            if (error.code != 'object-not-found') rethrow;
          }
        },
      );
    });

    await _runPurgeStage('users document purge', () {
      return _commitDeletes([
        _firestore.collection(FirestoreCollections.users).doc(uid),
      ]);
    });

    // Rules permit this cleanup only after the caller's own user document has
    // gone. Query both roles: a user may have authored and received notes.
    await _runPurgeStage('coaching notes purge', () async {
      final asTeacher = await _firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .where('teacher_id', isEqualTo: uid)
          .get();
      final asTrainee = await _firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .where('trainee_id', isEqualTo: uid)
          .get();
      final refs = <String, DocumentReference>{
        for (final doc in asTeacher.docs) doc.reference.path: doc.reference,
        for (final doc in asTrainee.docs) doc.reference.path: doc.reference,
      };
      await _commitDeletes(refs.values.toList());
    });

    await _runPurgeStage('phase 5 assignment attempts purge', () {
      return purgePhase5AssignmentAttemptsForAccountErasure(
        firestore: _firestore,
        commitDeletes: _commitDeletes,
        uid: uid,
      );
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

  static bool _isGoogleCancellation(String code) {
    return code == 'web-context-cancelled' ||
        code == 'popup-closed-by-user' ||
        code == 'cancelled-popup-request' ||
        code == 'canceled';
  }

  String _messageForGoogleAuthError(fb.FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
      case 'credential-already-in-use':
      case 'email-already-in-use':
        return 'This email already uses another sign-in method. Sign in with your existing method first.';
      case 'network-request-failed':
        return 'Could not reach Google. Check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Google sign-in could not be completed. Please try again.';
    }
  }
}
