import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/profile_visit.dart';
import '../../services/auth_service.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import 'profile_route_args.dart';
import 'user_profile_controller.dart';
import 'widgets/completed_movements_section.dart';
import 'widgets/private_profile_state.dart';
import 'widgets/profile_achievements_section.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_stats_section.dart';
import 'widgets/profile_visitors_section.dart';

/// Content max width for large Windows workspaces (sidebar visible).
const _kProfileContentMaxWidth = 1360.0;

/// Prefer two-column owner layout / side-by-side public sections.
const _kProfileWideBreakpoint = 1180.0;

/// Horizontal page padding on desktop.
const _kProfilePagePadding = 36.0;

/// Gap between profile cards and the vertical scrollbar (scroll body only).
const _kProfileScrollbarGutter = 12.0;

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
  bool _previewAsVisitor = false;

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

  void _openVisitorProfile(ProfileVisitDisplay visitor) {
    final visitorId = visitor.visit.viewerId.trim();
    if (visitorId.isEmpty) return;
    if (visitorId == widget.userId) return;
    context.push('/profile/$visitorId');
  }

  void _openAccountProfileSettings() {
    SettingsScreen.show(
      context,
      initialSection: SettingsSection.accountProfile,
    );
  }

  void _openPrivacySettings() {
    SettingsScreen.show(context, initialSection: SettingsSection.privacy);
  }

  void _enterPreviewAsVisitor() {
    setState(() => _previewAsVisitor = true);
  }

  void _exitPreviewAsVisitor() {
    setState(() => _previewAsVisitor = false);
  }

  /// Owner chrome is hidden while previewing as another player would see it.
  bool _showOwnerUi(UserProfileController controller) {
    return controller.isSelf && !_previewAsVisitor;
  }

  /// Preview mode applies public/private visibility as a visitor would.
  bool _effectiveCanViewDetails(UserProfileController controller) {
    if (controller.isSelf && _previewAsVisitor) {
      return controller.profileRoot?.isPublic ?? false;
    }
    return controller.canViewDetails;
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthService>().currentUser;
    final controller = _controller!;
    final pageTitle = controller.isSelf ? 'My Profile' : 'Player Profile';

    return ScaffoldPage(
      content: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kProfileContentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kProfilePagePadding,
                    vertical: AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfilePageHeader(title: pageTitle, onBack: _handleBack),
                      if (controller.isSelf && _previewAsVisitor) ...[
                        const SizedBox(height: AppSpacing.md),
                        _PreviewBanner(onExit: _exitPreviewAsVisitor),
                      ],
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
    final resolvedPicture = controller.isSelf
        ? currentUserPictureUrl
        : pictureUrl;
    final showOwnerUi = _showOwnerUi(controller);
    final canViewDetails = _effectiveCanViewDetails(controller);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kProfileWideBreakpoint;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(right: _kProfileScrollbarGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileHeader(
                displayName: displayName,
                profilePictureUrl: resolvedPicture,
                equippedBorderId: entry?.equippedBorderId,
                level: entry?.level,
                totalXp: entry?.totalXp,
                rank: controller.rank,
                showUnrankedLabel: entry != null && controller.rank == null,
                visibility: showOwnerUi ? root?.visibility : null,
                showOwnerActions: showOwnerUi,
                onEditProfile: showOwnerUi ? _openAccountProfileSettings : null,
                onPreviewProfile: showOwnerUi ? _enterPreviewAsVisitor : null,
                onPrivacy: showOwnerUi ? _openPrivacySettings : null,
                onEditAvatar: showOwnerUi ? _openAccountProfileSettings : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (canViewDetails && entry != null)
                ProfileStatsSection(
                  leaderboardEntry: entry,
                  rank: controller.rank,
                  summary: controller.summary,
                ),
              if (canViewDetails && entry != null)
                const SizedBox(height: AppSpacing.lg),
              if (!canViewDetails)
                const PrivateProfileState()
              else
                _ProfileContentLayout(
                  wide: wide,
                  showVisitorsColumn: showOwnerUi,
                  achievements: ProfileAchievementsSection(
                    achievements: controller.claimedAchievements,
                  ),
                  movements: CompletedMovementsSection(
                    movementNames:
                        controller.summary?.completedMovementNames ?? const [],
                  ),
                  visitors: showOwnerUi
                      ? ProfileVisitorsSection(
                          state: controller.visitorsState,
                          visitors: controller.visitors,
                          onVisitorTap: _openVisitorProfile,
                        )
                      : null,
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileContentLayout extends StatelessWidget {
  const _ProfileContentLayout({
    required this.wide,
    required this.showVisitorsColumn,
    required this.achievements,
    required this.movements,
    this.visitors,
  });

  final bool wide;
  final bool showVisitorsColumn;
  final Widget achievements;
  final Widget movements;
  final Widget? visitors;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          achievements,
          const SizedBox(height: AppSpacing.lg),
          movements,
          if (showVisitorsColumn && visitors != null) ...[
            const SizedBox(height: AppSpacing.lg),
            visitors!,
          ],
        ],
      );
    }

    if (showVisitorsColumn && visitors != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                achievements,
                const SizedBox(height: AppSpacing.lg),
                movements,
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(flex: 32, child: visitors!),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: achievements),
        const SizedBox(width: 22),
        Expanded(child: movements),
      ],
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.view,
            size: 14,
            color: AppColors.accentSoft.withValues(alpha: 0.95),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Previewing your profile as other players',
              style: AppTheme.caption.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          HyperlinkButton(onPressed: onExit, child: const Text('Exit Preview')),
        ],
      ),
    );
  }
}

class _ProfilePageHeader extends StatelessWidget {
  const _ProfilePageHeader({required this.title, required this.onBack});

  final String title;
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
            title,
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
