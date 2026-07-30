class User {
  const User({
    this.id,
    required this.fullName,
    required this.email,
    this.role = 'Trainee',
    this.createdAt,
    this.profilePicturePath,
    this.profilePictureUrl,
    this.profilePictureStoragePath,
  });

  final String? id;
  final String fullName;
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

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    String? role,
    String? createdAt,
    String? profilePicturePath,
    String? profilePictureUrl,
    String? profilePictureStoragePath,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      profilePictureStoragePath:
          profilePictureStoragePath ?? this.profilePictureStoragePath,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'full_name': fullName,
      'email': email,
      'role': role,
      if (profilePictureUrl != null) 'profile_picture_url': profilePictureUrl,
      if (profilePictureStoragePath != null)
        'profile_picture_storage_path': profilePictureStoragePath,
      if (profilePictureUrl == null && profilePicturePath != null)
        'profile_picture_path': profilePicturePath,
    };

    if (createdAt != null) {
      map['created_at'] = createdAt;
    }

    return map;
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String?,
      fullName: map['full_name'] as String,
      email: map['email'] as String,
      role: map['role'] as String? ?? 'Trainee',
      createdAt: map['created_at'] as String?,
      profilePicturePath: map['profile_picture_path'] as String?,
      profilePictureUrl: map['profile_picture_url'] as String?,
      profilePictureStoragePath: map['profile_picture_storage_path'] as String?,
    );
  }
}
