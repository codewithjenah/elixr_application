import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../services/auth_service.dart';
import 'leaderboard_list_controller.dart';
import 'leaderboard_presentation.dart';
import 'widgets/leaderboard_header.dart';
import 'widgets/leaderboard_podium.dart';
import 'widgets/leaderboard_rank_row.dart';

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
          fetchPage: ({startAfter}) =>
              _repository.fetchPlayersPage(startAfter: startAfter),
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

  void _startBackgroundSync() {
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (userId == null || userId.isEmpty) return;

    _controller.startBackgroundSync(
      userId: userId,
      syncUser: () => _repository.syncCurrentUserLeaderboard(
        userId: userId,
        displayName: user!.fullName,
      ),
    );
  }

  void _onRefresh() => _controller.refresh();

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            0,
          ),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final entries = _controller.entries;
              final currentUserId = context.read<AuthService>().currentUser?.id;

              if (_controller.isInitialLoading && entries.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LeaderboardHeader(
                      refreshEnabled: false,
                      onRefresh: _onRefresh,
                    ),
                    const Expanded(
                      child: Center(
                        child: ProgressRing(activeColor: AppColors.primary),
                      ),
                    ),
                  ],
                );
              }

              if (_controller.initialError != null && entries.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LeaderboardHeader(
                      refreshEnabled: !_controller.isInitialLoading,
                      onRefresh: _onRefresh,
                    ),
                    Expanded(child: _InitialErrorState(onRetry: _onRefresh)),
                  ],
                );
              }

              if (entries.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LeaderboardHeader(
                      refreshEnabled: !_controller.isInitialLoading,
                      onRefresh: _onRefresh,
                    ),
                    const Expanded(child: _EmptyState()),
                  ],
                );
              }

              final podium = LeaderboardPresentation.podiumOf(entries);
              final rows = LeaderboardPresentation.rankedRowsOf(entries);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: LeaderboardHeader(
                      refreshEnabled: !_controller.isInitialLoading,
                      onRefresh: _onRefresh,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.lg),
                  ),
                  SliverToBoxAdapter(
                    child: LeaderboardPodium(
                      podium: podium,
                      currentUserId: currentUserId,
                    ),
                  ),
                  if (rows.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final row = rows[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index < rows.length - 1
                                ? AppSpacing.sm
                                : AppSpacing.md,
                          ),
                          child: LeaderboardRankRow(
                            rank: row.rank,
                            entry: row.entry,
                            isCurrentUser: row.entry.userId == currentUserId,
                          ),
                        );
                      }, childCount: rows.length),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: _LoadMoreFooter(
                      hasMore: _controller.hasMore,
                      isLoadingMore: _controller.isLoadingMore,
                      loadMoreError: _controller.loadMoreError,
                      onLoadMore: _controller.loadMore,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xl),
                  ),
                ],
              );
            },
          ),
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
            : Button(onPressed: onLoadMore, child: const Text('Load More')),
      ),
    );
  }
}
