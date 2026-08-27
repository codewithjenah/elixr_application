import 'package:elixr_core/models/user.dart';

/// Visibility for a player's public profile directory document.
enum ProfileVisibility {
  public,
  private;

  static ProfileVisibility fromFirestore(dynamic value) {
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'public':
          return ProfileVisibility.public;
        case 'private':
          return ProfileVisibility.private;
      }
    }
    return ProfileVisibility.private;
  }

  String get firestoreValue => switch (this) {
    ProfileVisibility.public => 'public',
    ProfileVisibility.private => 'private',
  };
}

/// Safe signed-in-readable directory document at `public_profiles/{userId}`.
class PublicProfile {
  const PublicProfile({
    required this.userId,
    required this.displayName,
    required this.visibility,
    this.profilePictureUrl,
    this.role,
    this.createdAt,
    this.updatedAt,
    this.schemaVersion = 1,
  });

  final String userId;
  final String displayName;
  final ProfileVisibility visibility;
  final String? profilePictureUrl;
  final String? role;
  final String? createdAt;
  final String? updatedAt;
  final int schemaVersion;

  bool get isPublic => visibility == ProfileVisibility.public;
  bool get isTeacher => role == User.roleTeacher;

  static PublicProfile? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final userId = _readString(map['user_id']) ?? id;
    if (userId == null || userId.isEmpty) return null;

    final displayName = _readString(map['display_name'])?.trim();
    if (displayName == null || displayName.isEmpty) return null;

    return PublicProfile(
      userId: userId,
      displayName: displayName,
      visibility: ProfileVisibility.fromFirestore(map['visibility']),
      profilePictureUrl: _readProfilePictureUrl(map['profile_picture_url']),
      role: _readNonEmptyString(map['role']),
      createdAt: _readTimestampString(map['created_at']),
      updatedAt: _readTimestampString(map['updated_at']),
      schemaVersion: _readInt(map['schema_version']) ?? 1,
    );
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String? _readProfilePictureUrl(dynamic value) {
    return _readNonEmptyString(value);
  }

  static String? _readNonEmptyString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _readTimestampString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toIso8601String();
      }
    } catch (_) {
      // Fall through for plain maps in unit tests.
    }
    return null;
  }
}
