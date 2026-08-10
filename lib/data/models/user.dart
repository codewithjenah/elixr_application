import '../../core/utils/user_name.dart';

class User {
  const User({
    this.id,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.email,
    this.role = 'Trainee',
    this.createdAt,
    this.profilePicturePath,
    this.profilePictureUrl,
    this.profilePictureStoragePath,
    this.privacyConsentAt,
    this.privacyPolicyVersion,
  });

  final String? id;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String email;
  final String role;
  final String? createdAt;

  /// Legacy local-filesystem path from the pre-Cloud-Storage avatar flow.
  /// Only meaningful on the Windows PC where the file was picked; retained
  /// for one-time migration and local preview, never for cross-device use.
  final String? profilePicturePath;

  /// Cloud Storage download URL for the current profile avatar. Preferred
  /// source of truth once set, since it works across devices.
  final String? profilePictureUrl;

  /// Cloud Storage object path backing [profilePictureUrl], used to delete
  /// the previous avatar when a new one is saved.
  final String? profilePictureStoragePath;

  /// When the user accepted the Privacy Policy / Terms at registration.
  final DateTime? privacyConsentAt;

  /// Privacy Policy version acknowledged at registration (e.g. `v1`).
  final String? privacyPolicyVersion;

  String get fullName => composeUserFullName(
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
  );

  User copyWith({
    String? id,
    String? firstName,
    String? middleName,
    bool clearMiddleName = false,
    String? lastName,
    String? email,
    String? role,
    String? createdAt,
    String? profilePicturePath,
    String? profilePictureUrl,
    String? profilePictureStoragePath,
    DateTime? privacyConsentAt,
    String? privacyPolicyVersion,
  }) {
    return User(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      middleName: clearMiddleName ? null : (middleName ?? this.middleName),
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      profilePictureStoragePath:
          profilePictureStoragePath ?? this.profilePictureStoragePath,
      privacyConsentAt: privacyConsentAt ?? this.privacyConsentAt,
      privacyPolicyVersion: privacyPolicyVersion ?? this.privacyPolicyVersion,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'email': email,
      'role': role,
      if (middleName != null && middleName!.isNotEmpty)
        'middle_name': middleName,
      if (profilePictureUrl != null) 'profile_picture_url': profilePictureUrl,
      if (profilePictureStoragePath != null)
        'profile_picture_storage_path': profilePictureStoragePath,
      if (profilePictureUrl == null && profilePicturePath != null)
        'profile_picture_path': profilePicturePath,
      if (privacyConsentAt != null)
        'privacy_consent_at': privacyConsentAt!.toIso8601String(),
      if (privacyPolicyVersion != null)
        'privacy_policy_version': privacyPolicyVersion,
    };

    if (createdAt != null) {
      map['created_at'] = createdAt;
    }

    return map;
  }

  static DateTime? _readPrivacyConsentAt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory User.fromMap(Map<String, dynamic> map) {
    final structuredFirst = map['first_name'];
    final structuredLast = map['last_name'];
    final privacyConsentAt = _readPrivacyConsentAt(map['privacy_consent_at']);
    final privacyPolicyVersion = map['privacy_policy_version'] as String?;

    if (structuredFirst is String && structuredLast is String) {
      final middle = map['middle_name'];
      return User(
        id: map['id'] as String?,
        firstName: structuredFirst,
        middleName: middle is String && middle.trim().isNotEmpty
            ? middle
            : null,
        lastName: structuredLast,
        email: map['email'] as String,
        role: map['role'] as String? ?? 'Trainee',
        createdAt: map['created_at'] as String?,
        profilePicturePath: map['profile_picture_path'] as String?,
        profilePictureUrl: map['profile_picture_url'] as String?,
        profilePictureStoragePath:
            map['profile_picture_storage_path'] as String?,
        privacyConsentAt: privacyConsentAt,
        privacyPolicyVersion: privacyPolicyVersion,
      );
    }

    final legacyFullName = map['full_name'] as String? ?? '';
    final parsed = parseLegacyFullName(legacyFullName);

    return User(
      id: map['id'] as String?,
      firstName: parsed.firstName,
      middleName: parsed.middleName,
      lastName: parsed.lastName,
      email: map['email'] as String,
      role: map['role'] as String? ?? 'Trainee',
      createdAt: map['created_at'] as String?,
      profilePicturePath: map['profile_picture_path'] as String?,
      profilePictureUrl: map['profile_picture_url'] as String?,
      profilePictureStoragePath: map['profile_picture_storage_path'] as String?,
      privacyConsentAt: privacyConsentAt,
      privacyPolicyVersion: privacyPolicyVersion,
    );
  }
}
