import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';

/// Thrown when a profile image operation cannot proceed for a reason the
/// caller should surface to the user (validation failure, ownership
/// mismatch, or an underlying Storage error).
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

/// Persists the authenticated user's avatar in the private `profile-images`
/// bucket under `users/{uid}/profile/`. The stored URL is a long-lived signed
/// URL: like the former Storage download token it is an unguessable bearer
/// URL that stops working when the object is deleted.
class ProfileImageRepository implements ProfileImageRepositoryBase {
  ProfileImageRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static const int maxUploadBytes = 5 * 1024 * 1024;
  static const bucket = 'profile-images';
  static const signedUrlLifetimeSeconds = 10 * 365 * 24 * 60 * 60;

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
    final storage = _client.storage.from(bucket);

    try {
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: normalizedType, upsert: false),
      );
      final downloadUrl = await storage.createSignedUrl(
        path,
        signedUrlLifetimeSeconds,
      );
      return ProfileImageUploadResult(
        downloadUrl: downloadUrl,
        storagePath: path,
      );
    } on StorageException catch (e) {
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
      // remove() succeeds for already-missing objects.
      await _client.storage.from(bucket).remove([storagePath]);
    } on StorageException catch (e) {
      if (isStorageObjectNotFound(e)) return;
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

  String _messageForStorageError(StorageException error) {
    if (isPermissionDeniedError(error)) {
      return 'You do not have permission to update this profile image.';
    }
    if (isStorageObjectNotFound(error)) {
      return 'The profile image could not be found.';
    }
    if (error.statusCode == '413') {
      return 'Image is too large. Choose a file smaller than 5 MB.';
    }
    return error.message.isEmpty
        ? 'Profile image operation failed.'
        : 'Network error while uploading the image. Try again.';
  }
}
