import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Thrown when a profile image operation cannot proceed for a reason the
/// caller should surface to the user (validation failure, ownership
/// mismatch, or an underlying Firebase Storage error).
class ProfileImageException implements Exception {
  ProfileImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfileImageUploadResult {
  const ProfileImageUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });

  final String downloadUrl;
  final String storagePath;
}

abstract class ProfileImageRepositoryBase {
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  });

  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  });
}

/// Persists the authenticated user's profile avatar in Firebase Cloud
/// Storage under `users/{uid}/profile/`, replacing the previous
/// local-file-path-only approach so avatars follow the account across
/// Windows machines.
class ProfileImageRepository implements ProfileImageRepositoryBase {
  ProfileImageRepository({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const int maxUploadBytes = 5 * 1024 * 1024;

  static const Map<String, String> _allowedContentTypeExtensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };

  static bool isAllowedContentType(String contentType) =>
      _allowedContentTypeExtensions.containsKey(contentType.toLowerCase());

  /// Returns the required storage prefix for [userId]'s profile images.
  static String profilePrefixForUser(String userId) => 'users/$userId/profile/';

  /// Uploads [bytes] as the profile avatar for [userId].
  ///
  /// Validates content type and size before performing any network call.
  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (userId.isEmpty) {
      throw ProfileImageException('Not authenticated.');
    }

    final normalizedType = contentType.toLowerCase();
    final extension = _allowedContentTypeExtensions[normalizedType];
    if (extension == null) {
      throw ProfileImageException(
        'Unsupported image type. Choose a JPEG, PNG, or WebP image.',
      );
    }

    if (bytes.isEmpty) {
      throw ProfileImageException('Selected image is empty.');
    }
    if (bytes.length > maxUploadBytes) {
      throw ProfileImageException(
        'Image is too large. Choose a file smaller than 5 MB.',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${profilePrefixForUser(userId)}avatar_$timestamp.$extension';
    final ref = _storage.ref().child(path);

    try {
      await ref.putData(bytes, SettableMetadata(contentType: normalizedType));
      final downloadUrl = await ref.getDownloadURL();
      return ProfileImageUploadResult(
        downloadUrl: downloadUrl,
        storagePath: path,
      );
    } on FirebaseException catch (e) {
      throw ProfileImageException(_messageForStorageError(e));
    }
  }

  /// Deletes the object at [storagePath], but only when it belongs to
  /// `users/{authenticatedUid}/profile/`. Silently ignores an already-missing
  /// object; surfaces any other Storage error.
  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {
    if (storagePath.isEmpty) return;
    if (!belongsToUserProfile(
      storagePath: storagePath,
      userId: authenticatedUid,
    )) {
      throw ProfileImageException(
        'Refusing to delete a file outside the current user\'s profile path.',
      );
    }

    try {
      await _storage.ref().child(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      throw ProfileImageException(_messageForStorageError(e));
    }
  }

  /// True when [storagePath] is scoped under `users/{userId}/profile/`.
  static bool belongsToUserProfile({
    required String storagePath,
    required String userId,
  }) {
    if (userId.isEmpty) return false;
    return storagePath.startsWith(profilePrefixForUser(userId));
  }

  String _messageForStorageError(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
        return 'You do not have permission to update this profile image.';
      case 'canceled':
        return 'Image upload was canceled.';
      case 'retry-limit-exceeded':
      case 'unknown':
        return 'Network error while uploading the image. Try again.';
      case 'object-not-found':
        return 'The profile image could not be found.';
      default:
        return error.message ?? 'Profile image operation failed.';
    }
  }
}
