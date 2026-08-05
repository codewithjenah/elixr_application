import '../../data/models/leaderboard_entry.dart';

/// Optional navigation payload when opening a player profile from the
/// leaderboard so rank and entry can render without an extra first read.
class ProfileRouteArgs {
  const ProfileRouteArgs({this.entry, this.rank});

  final LeaderboardEntry? entry;
  final int? rank;
}
