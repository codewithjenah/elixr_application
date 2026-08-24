import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import '../privacy/privacy_consent.dart';
import 'firestore_collections.dart';

/// Persistence for `users/{uid}` profile documents.
abstract class UserProfileStore {
  Future<void> upsertUserProfile(
    User user, {
    bool includePrivacyConsent = false,
  });

  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  );

  Future<User?> getUserById(String id);
}

/// Firestore-backed [UserProfileStore] shared by ELIXR clients.
class FirebaseUserProfileStore implements UserProfileStore {
  FirebaseUserProfileStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String? readCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is String) return value;
    return null;
  }

  /// Builds the Firestore payload for [upsertUserProfile].
  ///
  /// When [includePrivacyConsent] is true, registration consent markers are
  /// included. [serverTimestamp] defaults to `FieldValue.serverTimestamp()`.
  static Map<String, dynamic> userProfileWriteData(
    User user, {
    bool includePrivacyConsent = false,
    Object Function()? serverTimestamp,
  }) {
    final timestamp = serverTimestamp ?? () => FieldValue.serverTimestamp();
    return {
      'first_name': user.firstName,
      if (user.middleName != null && user.middleName!.isNotEmpty)
        'middle_name': user.middleName,
      'last_name': user.lastName,
      'full_name': user.fullName,
      'email': user.email,
      'role': user.role,
      if (user.teacherAccessCode != null)
        'teacher_access_code': user.teacherAccessCode,
      'created_at': timestamp(),
      if (user.profilePictureUrl != null)
        'profile_picture_url': user.profilePictureUrl,
      if (user.profilePictureStoragePath != null)
        'profile_picture_storage_path': user.profilePictureStoragePath,
      if (user.profilePictureUrl == null && user.profilePicturePath != null)
        'profile_picture_path': user.profilePicturePath,
      if (includePrivacyConsent)
        ...RegistrationPrivacyConsent.documentFields(
          consentTimestamp: timestamp(),
        ),
    };
  }

  Map<String, dynamic> userFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'first_name': data['first_name'],
      'middle_name': data['middle_name'],
      'last_name': data['last_name'],
      'full_name': data['full_name'],
      'email': data['email'],
      'role': data['role'],
      'teacher_access_code': data['teacher_access_code'],
      'created_at': readCreatedAt(data['created_at']),
      'profile_picture_path': data['profile_picture_path'],
      'profile_picture_url': data['profile_picture_url'],
      'profile_picture_storage_path': data['profile_picture_storage_path'],
      'privacy_consent_at': readCreatedAt(data['privacy_consent_at']),
      'privacy_policy_version': data['privacy_policy_version'],
      'session_evidence_enabled': data['session_evidence_enabled'],
    };
  }

  @override
  Future<void> upsertUserProfile(
    User user, {
    bool includePrivacyConsent = false,
  }) async {
    if (user.id == null) {
      throw ArgumentError('User id is required');
    }
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(user.id)
        .set(
          userProfileWriteData(
            user,
            includePrivacyConsent: includePrivacyConsent,
          ),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .update(fields);
  }

  @override
  Future<User?> getUserById(String id) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    return User.fromMap(userFromDoc(doc));
  }
}
