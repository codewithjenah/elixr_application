import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../data/models/leaderboard_award_plan.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_identity.dart';
import '../../profile/profile_route_args.dart';
import 'dashboard_panel_card.dart';

/// Dashboard Top 3 competition snapshot. Owns its Firestore subscription so
/// the rest of the Dashboard can load independently.
///
/// Intentionally not a podium — the full Leaderboard page owns that experience.
class DashboardLeaderboard extends StatefulWidget {
  const DashboardLeaderboard({
    super.key,
    required this.currentUserId,
    required this.displayName,
    this.profilePictureUrl,
    LeaderboardRepository? repository,
  }) : _repository = repository;

  final String? currentUserId;
  final String displayName;
  final String? profilePictureUrl;
  final LeaderboardRepository? _repository;

  @override
  State<DashboardLeaderboard> createState() => _DashboardLeaderboardState();
}

class _DashboardLeaderboardState extends State<DashboardLeaderboard> {
  late final LeaderboardRepository _repository;
  StreamSubscription<List<LeaderboardEntry>>? _topSub;

  bool _loading = true;
  Object? _error;
  List<LeaderboardEntry> _topPlayers = const [];
  String? _syncStartedForUserId;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? LeaderboardRepository();
    _subscribe();
    _startBackgroundSync();
  }

  @override
  void didUpdateWidget(covariant DashboardLeaderboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId) {
      _syncStartedForUserId = null;
    }
    if (oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.profilePictureUrl != widget.profilePictureUrl) {
      _startBackgroundSync(
        force: oldWidget.profilePictureUrl != widget.profilePictureUrl,
      );
    }
  }

  void _startBackgroundSync({bool force = false}) {
    final userId = widget.currentUserId;
    if (userId == null || userId.isEmpty) return;
    if (!force && _syncStartedForUserId == userId) return;
    _syncStartedForUserId = userId;

    unawaited(
      _repository
          .syncCurrentUserLeaderboard(
            userId: userId,
            displayName: widget.displayName,
            profilePictureUrl: widget.profilePictureUrl,
          )
          .catchError((Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              debugPrint(
                'Background leaderboard sync failed: userId=$userId error=$error',
              );
              debugPrint('$stackTrace');
            }
            return LeaderboardSyncResult.empty;
          }),
    );
  }

  void _subscribe() {
    _topSub = _repository
        .watchTopPlayers(limit: 3)
        .listen(
          (players) {
            if (!mounted) return;
            setState(() {
              _topPlayers = players;
              _loading = false;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = error;
            });
          },
        );
  }

  @override
  void dispose() {
    _topSub?.cancel();
    super.dispose();
  }

  void _openProfile(LeaderboardEntry entry, int rank) {
    context.push(
      '/profile/${entry.userId}',
      extra: ProfileRouteArgs(entry: entry, rank: rank),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElixSectionHeader(
          heading: 'Top Players',
          actions: [
            const DashboardPill(
              text: 'All Time',
              color: AppColors.warning,
              compact: true,
            ),
            HyperlinkButton(
              onPressed: () => context.go('/leaderboard'),
              child: const Text('View leaderboard'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const DashboardPanelCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: ProgressRing()),
            ),
          )
        else if (_error != null)
          DashboardPanelCard(
            child: Text(
              'Leaderboard is temporarily unavailable.',
              style: TextStyle(fontSize: 13, color: context.elixTextSecondary),
            ),
          )
        else if (_topPlayers.isEmpty)
          DashboardPanelCard(
            child: Text(
              'No rankings yet. Complete a practice session to get started.',
              style: TextStyle(fontSize: 13, color: context.elixTextSecondary),
            ),
          )
        else
          DashboardPanelCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                final first = _topPlayers.first;
                final rest = _topPlayers.skip(1).toList(growable: false);

                if (!wide) {
                  return Column(
                    children: [
                      for (var i = 0; i < _topPlayers.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _PlayerRow(
                          rank: i + 1,
                          entry: _topPlayers[i],
                          currentUserId: widget.currentUserId,
                          currentUserProfilePictureUrl:
                              widget.profilePictureUrl,
                          spotlight: i == 0,
                          onTap: () => _openProfile(_topPlayers[i], i + 1),
                        ),
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _PlayerSpotlight(
                        rank: 1,
                        entry: first,
                        currentUserId: widget.currentUserId,
                        currentUserProfilePictureUrl: widget.profilePictureUrl,
                        onTap: () => _openProfile(first, 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          for (var i = 0; i < rest.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _PlayerRow(
                              rank: i + 2,
                              entry: rest[i],
                              currentUserId: widget.currentUserId,
                              currentUserProfilePictureUrl:
                                  widget.profilePictureUrl,
                              onTap: () => _openProfile(rest[i], i + 2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PlayerSpotlight extends StatelessWidget {
  const _PlayerSpotlight({
    required this.rank,
    required this.entry,
    required this.currentUserId,
    required this.currentUserProfilePictureUrl,
    required this.onTap,
  });

  final int rank;
  final LeaderboardEntry entry;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isYou = currentUserId != null && entry.userId == currentUserId;
    final medal = LeaderboardRankStyle.medalForRank(context, rank);
    final pictureUrl = isYou
        ? currentUserProfilePictureUrl
        : entry.profilePictureUrl;

    return DashboardHoverSurface(
      onTap: onTap,
      borderRadius: 14,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isYou
              ? AppColors.primary.withValues(alpha: 0.06)
              : (context.isDarkTheme
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isYou
                ? AppColors.primary.withValues(alpha: 0.28)
                : context.elixBorder.withValues(
                    alpha: context.isDarkTheme ? 0.4 : 0.7,
                  ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RankMedal(rank: rank, color: medal, size: 28),
                const SizedBox(width: 8),
                Text(
                  'Rank #$rank',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: medal,
                  ),
                ),
                if (isYou) ...[
                  const SizedBox(width: 8),
                  const LeaderboardYouBadge(compact: true),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                LeaderboardInitialsAvatar(
                  initials: LeaderboardPresentation.initialsFor(
                    entry.displayName,
                  ),
                  accent: medal,
                  size: 52,
                  profilePictureUrl: pictureUrl,
                  equippedBorderId: entry.equippedBorderId,
                  highlightRing: isYou,
                  animateBorder: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.elixTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Level ${entry.level}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.totalXp} XP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  FluentIcons.chevron_right,
                  size: 12,
                  color: context.elixTextSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.rank,
    required this.entry,
    required this.currentUserId,
    required this.currentUserProfilePictureUrl,
    required this.onTap,
    this.spotlight = false,
  });

  final int rank;
  final LeaderboardEntry entry;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final VoidCallback onTap;
  final bool spotlight;

  @override
  Widget build(BuildContext context) {
    final isYou = currentUserId != null && entry.userId == currentUserId;
    final medal = LeaderboardRankStyle.medalForRank(context, rank);
    final pictureUrl = isYou
        ? (currentUserProfilePictureUrl ?? entry.profilePictureUrl)
        : entry.profilePictureUrl;
    final avatarSize = spotlight ? 40.0 : 34.0;

    return DashboardHoverSurface(
      onTap: onTap,
      borderRadius: 12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: spotlight ? 12 : 10,
        ),
        decoration: BoxDecoration(
          color: isYou
              ? AppColors.primary.withValues(alpha: 0.06)
              : (spotlight
                    ? (context.isDarkTheme
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.02))
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isYou
                ? AppColors.primary.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            _RankMedal(rank: rank, color: medal, size: spotlight ? 24 : 22),
            const SizedBox(width: 10),
            LeaderboardInitialsAvatar(
              initials: LeaderboardPresentation.initialsFor(entry.displayName),
              accent: medal,
              size: avatarSize,
              profilePictureUrl: pictureUrl,
              equippedBorderId: entry.equippedBorderId,
              highlightRing: isYou,
              animateBorder: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: spotlight ? 14 : 13,
                            fontWeight: FontWeight.w700,
                            color: context.elixTextPrimary,
                          ),
                        ),
                      ),
                      if (isYou) ...[
                        const SizedBox(width: 6),
                        const LeaderboardYouBadge(compact: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lv. ${entry.level} · ${entry.totalXp} XP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              FluentIcons.chevron_right,
              size: 12,
              color: context.elixTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RankMedal extends StatelessWidget {
  const _RankMedal({
    required this.rank,
    required this.color,
    required this.size,
  });

  final int rank;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
