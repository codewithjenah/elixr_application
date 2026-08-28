import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/leaderboard_period.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../profile/profile_route_args.dart';
import 'leaderboard_list_controller.dart';
import 'leaderboard_presentation.dart';
import 'widgets/leaderboard_header.dart';
import 'widgets/leaderboard_podium.dart';
import 'widgets/leaderboard_rankings_section.dart';

abstract final class LeaderboardScreenLayout {
  static const double maxContentWidth = 1480;

  static double horizontalPaddingFor(double width) {
    if (width < 640) return AppSpacing.md;
    if (width < 1120) return 20;
    if (width < 1680) return 28;
    return 36;
  }
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.repository, this.controller});

  final LeaderboardRepository? repository;
  final LeaderboardListController? controller;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final LeaderboardRepository _repository;
  late final LeaderboardListController _controller;
  late final bool _ownsController;
  bool _didBootstrap = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LeaderboardRepository();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        LeaderboardListController(
          fetchPageForPeriod: ({required period, startAfter}) => _repository
              .fetchPlayersPage(period: period, startAfter: startAfter),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didBootstrap) return;
    _didBootstrap = true;
    _controller.loadInitial();
    _startBackgroundSync();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _startBackgroundSync({bool force = false}) {
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (userId == null || userId.isEmpty) return;

    _controller.startBackgroundSync(
      force: force,
      userId: userId,
      syncUser: () async {
        final result = await _repository.syncCurrentUserLeaderboard(
          userId: userId,
          displayName: user!.fullName,
          profilePictureUrl: user.profilePictureUrl,
        );
        await PublicProfileRepository().ensurePublicProfile(
          userId: userId,
          displayName: user.fullName,
          profilePictureUrl: user.profilePictureUrl,
          role: user.role,
        );
        return result;
      },
    );
  }

  void _onRefresh() {
    _controller.refresh();
    _startBackgroundSync(force: true);
  }

  void _onPeriodChanged(LeaderboardPeriod period) {
    _controller.setPeriod(period);
  }

  void _onTapPlayer(LeaderboardEntry entry, int rank) {
    context.push(
      '/profile/${entry.userId}',
      extra: ProfileRouteArgs(
        entry: entry,
        rank: LeaderboardPresentation.profileRankForNavigation(
          period: _controller.period,
          selectedPeriodRank: rank,
        ),
      ),
    );
  }

  Widget _centered(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LeaderboardScreenLayout.maxContentWidth,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final horizontalPadding =
                LeaderboardScreenLayout.horizontalPaddingFor(
                  viewportConstraints.maxWidth,
                );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.pageTopInset,
                horizontalPadding,
                0,
              ),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final entries = _controller.entries;
                  final period = _controller.period;
                  final currentUser = context.read<AuthService>().currentUser;
                  final currentUserId = currentUser?.id;
                  final currentUserProfilePictureUrl =
                      currentUser?.profilePictureUrl;

                  if (_controller.isInitialLoading && entries.isEmpty) {
                    return _centered(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LeaderboardHeader(
                            period: period,
                            onPeriodChanged: _onPeriodChanged,
                            refreshEnabled: false,
                            onRefresh: _onRefresh,
                          ),
                          const Expanded(
                            child: Center(
                              child: ProgressRing(
                                activeColor: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_controller.initialError != null && entries.isEmpty) {
                    return _centered(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LeaderboardHeader(
                            period: period,
                            onPeriodChanged: _onPeriodChanged,
                            refreshEnabled: !_controller.isInitialLoading,
                            onRefresh: _onRefresh,
                          ),
                          Expanded(
                            child: _InitialErrorState(onRetry: _onRefresh),
                          ),
                        ],
                      ),
                    );
                  }

                  if (entries.isEmpty) {
                    return _centered(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LeaderboardHeader(
                            period: period,
                            onPeriodChanged: _onPeriodChanged,
                            refreshEnabled: !_controller.isInitialLoading,
                            onRefresh: _onRefresh,
                          ),
                          const Expanded(child: _EmptyState()),
                        ],
                      ),
                    );
                  }

                  final podium = LeaderboardPresentation.podiumOf(entries);
                  final rows = LeaderboardPresentation.rankedRowsOf(entries);
                  final loadMoreFooter = _LoadMoreFooter(
                    hasMore: _controller.hasMore,
                    isLoadingMore: _controller.isLoadingMore,
                    loadMoreError: _controller.loadMoreError,
                    onLoadMore: _controller.loadMore,
                  );

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _centered(
                          LeaderboardHeader(
                            period: period,
                            onPeriodChanged: _onPeriodChanged,
                            refreshEnabled: !_controller.isInitialLoading,
                            onRefresh: _onRefresh,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.lg),
                      ),
                      SliverToBoxAdapter(
                        child: _centered(
                          LeaderboardPodium(
                            podium: podium,
                            currentUserId: currentUserId,
                            currentUserProfilePictureUrl:
                                currentUserProfilePictureUrl,
                            period: period,
                            variant: LeaderboardPodiumVariant.full,
                            onTapPlayer: _onTapPlayer,
                          ),
                        ),
                      ),
                      if (rows.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.lg),
                        ),
                        SliverToBoxAdapter(
                          child: _centered(
                            LeaderboardRankingsSection(
                              rows: rows,
                              currentUserId: currentUserId,
                              currentUserProfilePictureUrl:
                                  currentUserProfilePictureUrl,
                              period: period,
                              footer: loadMoreFooter,
                              onTapPlayer: _onTapPlayer,
                            ),
                          ),
                        ),
                      ] else ...[
                        SliverToBoxAdapter(child: _centered(loadMoreFooter)),
                      ],
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.xl),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InitialErrorState extends StatelessWidget {
  const _InitialErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Leaderboard is temporarily unavailable.',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No players on the leaderboard yet.',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final Object? loadMoreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Column(
          children: [
            Text(
              'Could not load more players.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Button(onPressed: onLoadMore, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (!hasMore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: isLoadingMore
            ? const ProgressRing(activeColor: AppColors.primary)
            : Button(onPressed: onLoadMore, child: const Text('Load more')),
      ),
    );
  }
}
