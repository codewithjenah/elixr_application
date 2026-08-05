import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_award_plan.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_podium.dart';
import '../../profile/profile_route_args.dart';

const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _amber = AppColors.warning;

/// Dashboard Top 3 XP leaderboard preview. Owns its Firestore subscription so
/// the rest of the Dashboard can load independently.
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

    // Non-blocking: streams already render; sync repairs missing awards.
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LeaderboardPodium(
                podium: LeaderboardPresentation.podiumOf(_topPlayers),
                currentUserId: widget.currentUserId,
                currentUserProfilePictureUrl: widget.profilePictureUrl,
                variant: LeaderboardPodiumVariant.compact,
                onTapPlayer: (entry, rank) {
                  context.push(
                    '/profile/${entry.userId}',
                    extra: ProfileRouteArgs(entry: entry, rank: rank),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              HyperlinkButton(
                onPressed: () => context.go('/leaderboard'),
                child: const Text('View Full Leaderboard'),
              ),
            ],
          ),
      ],
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
