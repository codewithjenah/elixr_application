import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_award_plan.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../leaderboard_presentation.dart';

const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _amber = AppColors.warning;
const _silver = Color(0xFFB8C0CC);
const _bronze = Color(0xFFCD7F32);

/// Dashboard Top 10 XP leaderboard. Owns its Firestore subscriptions so the
/// rest of the Dashboard can load independently.
class DashboardLeaderboard extends StatefulWidget {
  const DashboardLeaderboard({
    super.key,
    required this.currentUserId,
    required this.displayName,
    LeaderboardRepository? repository,
  }) : _repository = repository;

  final String? currentUserId;
  final String displayName;
  final LeaderboardRepository? _repository;

  @override
  State<DashboardLeaderboard> createState() => _DashboardLeaderboardState();
}

class _DashboardLeaderboardState extends State<DashboardLeaderboard> {
  late final LeaderboardRepository _repository;
  StreamSubscription<List<LeaderboardEntry>>? _topSub;
  StreamSubscription<LeaderboardEntry?>? _playerSub;

  bool _loading = true;
  Object? _error;
  List<LeaderboardEntry> _topPlayers = const [];
  LeaderboardEntry? _currentUserEntry;
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
      _playerSub?.cancel();
      _listenPlayer();
      _startBackgroundSync();
    }
  }

  void _startBackgroundSync() {
    final userId = widget.currentUserId;
    if (userId == null || userId.isEmpty) return;
    if (_syncStartedForUserId == userId) return;
    _syncStartedForUserId = userId;

    // Non-blocking: streams already render; sync repairs missing awards.
    unawaited(
      _repository
          .syncCurrentUserLeaderboard(
            userId: userId,
            displayName: widget.displayName,
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
        .watchTopPlayers(limit: 10)
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
    _listenPlayer();
  }

  void _listenPlayer() {
    final userId = widget.currentUserId;
    if (userId == null || userId.isEmpty) {
      _currentUserEntry = null;
      return;
    }
    _playerSub = _repository
        .watchPlayer(userId)
        .listen(
          (entry) {
            if (!mounted) return;
            setState(() => _currentUserEntry = entry);
          },
          onError: (_) {
            // Non-fatal: Top 10 can still render without personal standing.
          },
        );
  }

  @override
  void dispose() {
    _topSub?.cancel();
    _playerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FluentIcons.trophy2_solid, size: 16, color: _violet),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Leaderboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _amber.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'All Time',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _amber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          _LeaderboardPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: ProgressRing(activeColor: _pink.withValues(alpha: 0.85)),
              ),
            ),
          )
        else if (_error != null)
          const _LeaderboardPanel(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Leaderboard is temporarily unavailable.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          )
        else if (_topPlayers.isEmpty)
          const _LeaderboardPanel(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No rankings yet. Complete a practice session to get started.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          )
        else
          _LeaderboardContent(
            topPlayers: _topPlayers,
            currentUserId: widget.currentUserId,
            standingOutside: LeaderboardPresentation.standingOutsideTop(
              topPlayers: _topPlayers,
              currentUserId: widget.currentUserId,
              currentUserEntry: _currentUserEntry,
            ),
          ),
      ],
    );
  }
}

class _LeaderboardContent extends StatelessWidget {
  const _LeaderboardContent({
    required this.topPlayers,
    required this.currentUserId,
    required this.standingOutside,
  });

  final List<LeaderboardEntry> topPlayers;
  final String? currentUserId;
  final LeaderboardEntry? standingOutside;

  @override
  Widget build(BuildContext context) {
    final podium = LeaderboardPresentation.podiumOf(topPlayers);
    final rows = LeaderboardPresentation.compactRowsOf(topPlayers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Podium(podium: podium, currentUserId: currentUserId),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) ...[
            _RankRow(
              rank: row.rank,
              entry: row.entry,
              isCurrentUser: row.entry.userId == currentUserId,
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (standingOutside != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _YourStandingRow(entry: standingOutside!),
        ],
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.podium, required this.currentUserId});

  final List<LeaderboardEntry> podium;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (podium.isEmpty) return const SizedBox.shrink();

    Widget cardFor(int index) {
      final entry = podium[index];
      final rank = index + 1;
      return _PodiumCard(
        rank: rank,
        entry: entry,
        isCurrentUser: entry.userId == currentUserId,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 720 && podium.length == 3) {
          // Emphasize 1st in the center visually: 2nd | 1st | 3rd
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: cardFor(1)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 12, child: cardFor(0)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: cardFor(2)),
            ],
          );
        }
        if (width >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < podium.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(flex: i == 0 ? 12 : 10, child: cardFor(i)),
              ],
            ],
          );
        }
        if (width >= 480 && podium.length >= 2) {
          return Column(
            children: [
              cardFor(0),
              if (podium.length > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: cardFor(1)),
                    if (podium.length > 2) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: cardFor(2)),
                    ],
                  ],
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < podium.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cardFor(i),
            ],
          ],
        );
      },
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  Color get _accent {
    switch (rank) {
      case 1:
        return _amber;
      case 2:
        return _silver;
      case 3:
        return _bronze;
      default:
        return _purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final accent = _accent;
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, isFirst ? 18 : 14, 14, 14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentUser
              ? _pink.withValues(alpha: 0.7)
              : accent.withValues(alpha: isFirst ? 0.55 : 0.35),
          width: isCurrentUser || isFirst ? 1.6 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: isFirst ? 0.18 : 0.10),
            panel.withValues(alpha: 0.2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isFirst ? 0.18 : 0.08),
            blurRadius: isFirst ? 22 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isFirst)
            const Text('👑', style: TextStyle(fontSize: 18))
          else
            Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          if (isFirst) const SizedBox(height: 4),
          if (isFirst)
            Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          const SizedBox(height: 8),
          _InitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(entry.displayName),
            accent: accent,
            size: isFirst ? 48 : 40,
          ),
          const SizedBox(height: 10),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lv. ${entry.level}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${entry.totalXp} XP',
            style: TextStyle(
              fontSize: isFirst ? 16 : 14,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          if (isCurrentUser) ...[const SizedBox(height: 8), const _YouBadge()],
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _pink.withValues(alpha: context.isDarkTheme ? 0.10 : 0.08)
            : panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? _pink.withValues(alpha: 0.65)
              : _purple.withValues(alpha: 0.22),
          width: isCurrentUser ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.elixTextSecondary,
              ),
            ),
          ),
          _InitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(entry.displayName),
            accent: _purple,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextPrimary,
                    ),
                  ),
                ),
                if (isCurrentUser) ...[
                  const SizedBox(width: 8),
                  const _YouBadge(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Lv. ${entry.level}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              '${entry.totalXp} XP',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _pink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YourStandingRow extends StatelessWidget {
  const _YourStandingRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _pink.withValues(alpha: context.isDarkTheme ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _pink.withValues(alpha: 0.65), width: 1.4),
      ),
      child: Row(
        children: [
          _InitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(entry.displayName),
            accent: _pink,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Your standing',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _YouBadge(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Not currently in the Top 10.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Lv. ${entry.level}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.totalXp} XP',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _pink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YouBadge extends StatelessWidget {
  const _YouBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _pink.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _pink.withValues(alpha: 0.55)),
      ),
      child: const Text(
        'YOU',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: _pink,
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.initials,
    required this.accent,
    required this.size,
  });

  final String initials;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.35),
            _pink.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: context.elixTextPrimary,
        ),
      ),
    );
  }
}

class _LeaderboardPanel extends StatelessWidget {
  const _LeaderboardPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
