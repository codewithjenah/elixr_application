import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'profile_route_args.dart';
import 'user_profile_controller.dart';
import 'widgets/completed_movements_section.dart';
import 'widgets/private_profile_state.dart';
import 'widgets/profile_achievements_section.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_stats_section.dart';
import 'widgets/profile_visitors_section.dart';
import 'widgets/public_practice_history_section.dart';

const _kProfileContentMaxWidth = 960.0;

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialArgs,
    this.controller,
  });

  final String userId;
  final ProfileRouteArgs? initialArgs;
  final UserProfileController? controller;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfileController? _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final currentUserId = context.read<AuthService>().currentUser?.id;
      _controller =
          widget.controller ??
          UserProfileController(
            userId: widget.userId,
            currentUserId: currentUserId,
            initialEntry: widget.initialArgs?.entry,
            initialRank: widget.initialArgs?.rank,
          );
    }
    if (!_initialized) {
      _initialized = true;
      final user = context.read<AuthService>().currentUser;
      _controller!.initialize(
        displayName: user?.fullName ?? 'Trainee',
        profilePictureUrl: user?.profilePictureUrl,
      );
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/leaderboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthService>().currentUser;

    return ScaffoldPage(
      content: SafeArea(
        child: ListenableBuilder(
          listenable: _controller!,
          builder: (context, _) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kProfileContentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfilePageHeader(onBack: _handleBack),
                      const SizedBox(height: AppSpacing.lg),
                      Expanded(
                        child: _buildBody(context, authUser?.profilePictureUrl),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String? currentUserPictureUrl) {
    final controller = _controller!;
    switch (controller.loadState) {
      case ProfileLoadState.loading:
        return const Center(
          child: ProgressRing(activeColor: AppColors.primary),
        );
      case ProfileLoadState.notFound:
        return _NotFoundState(onBack: _handleBack);
      case ProfileLoadState.error:
        return _ErrorState(onRetry: controller.retry);
      case ProfileLoadState.loaded:
        break;
    }

    final entry = controller.leaderboardEntry;
    final root = controller.profileRoot;
    final displayName = root?.displayName ?? entry?.displayName ?? 'Player';
    final pictureUrl = root?.profilePictureUrl ?? entry?.profilePictureUrl;
    final resolvedPicture =
        controller.isSelf && (pictureUrl == null || pictureUrl.isEmpty)
        ? currentUserPictureUrl
        : pictureUrl;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileHeader(
            displayName: displayName,
            isSelf: controller.isSelf,
            profilePictureUrl: resolvedPicture,
            equippedBorderId: entry?.equippedBorderId,
            level: entry?.level,
            totalXp: entry?.totalXp,
            rank: controller.rank,
            showUnrankedLabel: entry != null && controller.rank == null,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (controller.canViewDetails && entry != null)
            ProfileStatsSection(
              leaderboardEntry: entry,
              rank: controller.rank,
              summary: controller.summary,
            ),
          if (controller.canViewDetails && entry != null)
            const SizedBox(height: AppSpacing.lg),
          if (!controller.canViewDetails) ...[
            const PrivateProfileState(),
          ] else ...[
            ProfileAchievementsSection(
              achievements: controller.claimedAchievements,
            ),
            const SizedBox(height: AppSpacing.lg),
            CompletedMovementsSection(
              movementNames:
                  controller.summary?.completedMovementNames ?? const [],
            ),
            const SizedBox(height: AppSpacing.lg),
            PublicPracticeHistorySection(
              sessions: controller.sessions,
              hasMore: controller.hasMoreSessions,
              isLoadingMore: controller.isLoadingMoreSessions,
              onLoadMore: controller.loadMoreSessions,
            ),
          ],
          if (controller.isSelf) ...[
            const SizedBox(height: AppSpacing.lg),
            ProfileVisitorsSection(
              state: controller.visitorsState,
              visitors: controller.visitors,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _ProfilePageHeader extends StatelessWidget {
  const _ProfilePageHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: Tooltip(
            message: 'Back',
            child: IconButton(
              icon: Icon(
                FluentIcons.back,
                size: 14,
                color: context.elixTextPrimary,
              ),
              onPressed: onBack,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Player Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.elixTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Player not found.',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Button(onPressed: onBack, child: const Text('Go Back')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Could not load this profile.',
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
