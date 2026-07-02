class User {
  const User({
    this.id,
    required this.fullName,
    required this.email,
    this.role = 'Trainee',
    this.createdAt,
    this.profilePicturePath,
  });

  final String? id;
  final String fullName;
  final String email;
  final String role;
  final String? createdAt;
  final String? profilePicturePath;

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    String? role,
    String? createdAt,
    String? profilePicturePath,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'full_name': fullName,
      'email': email,
      'role': role,
      if (profilePicturePath != null) 'profile_picture_path': profilePicturePath,
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
    );
  }
}
