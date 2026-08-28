import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../services/auth_service.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/leaderboard_screen.dart';
import '../../profile/profile_route_args.dart';
import '../../leaderboard/widgets/leaderboard_header.dart';
import '../../leaderboard/widgets/leaderboard_podium.dart';
import '../../leaderboard/widgets/leaderboard_rankings_section.dart';
import 'teacher_leaderboard_controller.dart';
import 'teacher_leaderboard_models.dart';

class TeacherLeaderboardScreen extends StatefulWidget {
  const TeacherLeaderboardScreen({super.key, this.controller});

  final TeacherLeaderboardController? controller;

  @override
  State<TeacherLeaderboardScreen> createState() =>
      _TeacherLeaderboardScreenState();
}

class _TeacherLeaderboardScreenState extends State<TeacherLeaderboardScreen> {
  TeacherLeaderboardController? _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;
    final repository = LeaderboardRepository();
    _controller = TeacherLeaderboardController(
      groupRepository: context.read<GroupRepository>(),
      teacherId: userId,
      fetchEntriesByUserIds: repository.fetchEntriesByUserIds,
      fetchGlobalPage: ({required period, startAfter}) =>
          repository.fetchPlayersPage(period: period, startAfter: startAfter),
    )..start();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  void _onTapPlayer(LeaderboardEntry entry) {
    context.push(
      AppRoutePaths.teacherProfile(entry.userId),
      extra: ProfileRouteArgs(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Leaderboard',
          eyebrow: 'TEACHER WORKSPACE',
        ),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([controller, controller.globalList]),
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: const ElixEditorialPageHeader(
            heading: 'Leaderboard',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'Celebrate steady training progress.',
          ),
          scrollable: false,
          contentPadding: EdgeInsets.zero,
          content: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  LeaderboardScreenLayout.horizontalPaddingFor(
                    constraints.maxWidth,
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Toolbar(controller: controller),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: controller.loading
                        ? const Center(child: ProgressRing())
                        : controller.errorMessage != null
                        ? _MessageState(
                            message: controller.errorMessage!,
                            actionLabel: 'Retry',
                            onAction: controller.retry,
                          )
                        : _Board(
                            controller: controller,
                            horizontalPadding: horizontalPadding,
                            onTapPlayer: _onTapPlayer,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final TeacherLeaderboardController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          label: 'Leaderboard scope',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final scope in TeacherLeaderboardScope.values)
                ToggleButton(
                  checked: controller.scope == scope,
                  onChanged: (_) => controller.setScope(scope),
                  child: Text(_scopeLabel(scope)),
                ),
            ],
          ),
        ),
        if (controller.showGroupPicker && controller.activeGroups.isNotEmpty)
          ComboBox<String>(
            value: controller.selectedGroupId,
            items: [
              for (final group in controller.activeGroups)
                ComboBoxItem(value: group.id, child: Text(group.name)),
            ],
            onChanged: controller.setSelectedGroupId,
          ),
      ],
    );
  }

  static String _scopeLabel(TeacherLeaderboardScope scope) {
    return switch (scope) {
      TeacherLeaderboardScope.global => 'Global',
      TeacherLeaderboardScope.myStudents => 'My Students',
      TeacherLeaderboardScope.group => 'Group',
    };
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.controller,
    required this.horizontalPadding,
    required this.onTapPlayer,
  });

  final TeacherLeaderboardController controller;
  final double horizontalPadding;
  final ValueChanged<LeaderboardEntry> onTapPlayer;

  Widget _padded(Widget child) => Padding(
    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    if (controller.hasNoActiveGroups) {
      return const _MessageState(
        message: 'No active classrooms yet. Create a group first.',
      );
    }

    if (!controller.isGlobal && controller.scopedLoading) {
      return const Center(child: ProgressRing());
    }

    final entries = controller.isGlobal
        ? controller.globalList.entries
        : controller.scopedEntries;
    final loading =
        controller.isGlobal &&
        controller.globalList.isInitialLoading &&
        entries.isEmpty;
    if (loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _padded(_PeriodHeader(controller: controller, refreshEnabled: false)),
          const Expanded(child: Center(child: ProgressRing())),
        ],
      );
    }

    final showBoardError = controller.isGlobal
        ? controller.globalList.initialError != null && entries.isEmpty
        : controller.scopedErrorMessage != null;

    if (showBoardError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _padded(_PeriodHeader(controller: controller)),
          Expanded(
            child: _MessageState(
              message: controller.isGlobal
                  ? 'Leaderboard is temporarily unavailable.'
                  : controller.scopedErrorMessage!,
              actionLabel: 'Retry',
              onAction: controller.refresh,
            ),
          ),
        ],
      );
    }

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _padded(_PeriodHeader(controller: controller)),
          Expanded(child: _MessageState(message: _emptyCopy(controller))),
        ],
      );
    }

    final podium = LeaderboardPresentation.podiumOf(entries);
    final rows = LeaderboardPresentation.rankedRowsOf(entries);
    return CustomScrollView(
      key: const Key('teacher_leaderboard_page_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _padded(_PeriodHeader(controller: controller)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        SliverToBoxAdapter(
          child: _padded(
            LeaderboardPodium(
              podium: podium,
              currentUserId: null,
              period: controller.period,
              onTapPlayer: (entry, _) => onTapPlayer(entry),
            ),
          ),
        ),
        if (rows.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          SliverToBoxAdapter(
            child: _padded(
              LeaderboardRankingsSection(
                rows: rows,
                currentUserId: null,
                period: controller.period,
                footer: controller.isGlobal
                    ? _LoadMoreFooter(controller: controller)
                    : const SizedBox.shrink(),
                onTapPlayer: (entry, _) => onTapPlayer(entry),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  static String _emptyCopy(TeacherLeaderboardController controller) {
    return switch (controller.scope) {
      TeacherLeaderboardScope.global => 'No players on the leaderboard yet.',
      TeacherLeaderboardScope.myStudents =>
        'No approved students yet. Approve join requests in Groups.',
      TeacherLeaderboardScope.group => 'No approved members in this classroom.',
    };
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.controller, this.refreshEnabled = true});

  final TeacherLeaderboardController controller;
  final bool refreshEnabled;

  @override
  Widget build(BuildContext context) {
    return LeaderboardHeader(
      period: controller.period,
      onPeriodChanged: controller.setPeriod,
      refreshEnabled: refreshEnabled && !controller.scopedLoading,
      onRefresh: controller.refresh,
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller});

  final TeacherLeaderboardController controller;

  @override
  Widget build(BuildContext context) {
    final list = controller.globalList;
    if (list.loadMoreError != null) {
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
            Button(onPressed: list.loadMore, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (!list.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: list.isLoadingMore
            ? const ProgressRing(activeColor: AppColors.primary)
            : Button(onPressed: list.loadMore, child: const Text('Load more')),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ElixStatusPanel(
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}
