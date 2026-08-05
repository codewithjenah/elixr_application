/// Unique visitor record at `profile_visits/{profileOwnerId}/visitors/{viewerId}`.
class ProfileVisit {
  const ProfileVisit({
    required this.profileOwnerId,
    required this.viewerId,
    this.firstViewedAt,
    this.lastViewedAt,
  });

  final String profileOwnerId;
  final String viewerId;
  final String? firstViewedAt;
  final String? lastViewedAt;

  static ProfileVisit? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final profileOwnerId = _readString(map['profile_owner_id']);
    final viewerId = _readString(map['viewer_id']) ?? id;
    if (profileOwnerId == null ||
        profileOwnerId.isEmpty ||
        viewerId == null ||
        viewerId.isEmpty) {
      return null;
    }

    return ProfileVisit(
      profileOwnerId: profileOwnerId,
      viewerId: viewerId,
      firstViewedAt: _readTimestampString(map['first_viewed_at']),
      lastViewedAt: _readTimestampString(map['last_viewed_at']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
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
    } catch (_) {}
    return null;
  }
}

/// Visitor row hydrated with identity from `public_profiles/{viewerId}`.
class ProfileVisitDisplay {
  const ProfileVisitDisplay({
    required this.visit,
    required this.displayName,
    this.profilePictureUrl,
  });

  final ProfileVisit visit;
  final String displayName;
  final String? profilePictureUrl;
}
