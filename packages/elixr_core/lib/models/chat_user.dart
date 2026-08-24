class ChatUser {
  const ChatUser({
    required this.id,
    required this.displayName,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String role;
  final String? avatarUrl;

  bool get isTeacher => role == 'Teacher';
  bool get isTrainee => role == 'Trainee';

  static ChatUser? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final resolvedId = id ?? map['id'];
    final name = map['display_name'];
    final role = map['role'];
    final avatar = map['avatar_url'];
    if (resolvedId is! String ||
        resolvedId.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        (role != 'Teacher' && role != 'Trainee') ||
        (avatar != null && avatar is! String)) {
      return null;
    }
    return ChatUser(
      id: resolvedId,
      displayName: name.trim(),
      role: role,
      avatarUrl: avatar is String && avatar.trim().isNotEmpty
          ? avatar.trim()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'display_name': displayName,
    'role': role,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}
