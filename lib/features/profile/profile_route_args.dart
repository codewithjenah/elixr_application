import '../../data/models/leaderboard_entry.dart';

/// Optional navigation payload when opening a profile from leaderboard,
/// Faculties, or similar lists so identity can render without an extra first
/// read.
class ProfileRouteArgs {
  const ProfileRouteArgs({
    this.entry,
    this.rank,
    this.displayName,
    this.profilePictureUrl,
    this.role,
  });

  final LeaderboardEntry? entry;
  final int? rank;

  /// Directory identity when the target has no leaderboard row, e.g. Teacher
  /// → Teacher from Faculties. Used only if public profile and leaderboard
  /// snapshots are both empty.
  final String? displayName;
  final String? profilePictureUrl;

  /// Product role of the profile owner when already known (Faculties).
  /// Used for locked-profile copy; not an authorization signal.
  final String? role;
}
