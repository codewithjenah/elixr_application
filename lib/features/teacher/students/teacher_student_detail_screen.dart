import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../services/auth_service.dart';
import '../../profile/widgets/completed_movements_section.dart';
import '../../profile/widgets/profile_achievements_section.dart';
import '../../profile/widgets/profile_stats_section.dart';
import 'teacher_student_detail_controller.dart';

/// Lightweight overview. Classwork streams only start after its entry opens.
class TeacherStudentDetailScreen extends StatefulWidget {
  const TeacherStudentDetailScreen({
    super.key,
    required this.traineeId,
    this.preferredGroupId,
    this.evidenceRepository,
    this.leaderboardRepository,
  });
  final String traineeId;
  final String? preferredGroupId;
  final TeacherEvidenceRepository? evidenceRepository;
  final LeaderboardRepository? leaderboardRepository;
  @override
  State<TeacherStudentDetailScreen> createState() =>
      _TeacherStudentDetailScreenState();
}

class _TeacherStudentDetailScreenState
    extends State<TeacherStudentDetailScreen> {
  TeacherStudentDetailController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final teacherId = auth.currentUser?.id;
    if (teacherId == null) return;
    _controller = TeacherStudentDetailController(
      groupRepository: context.read(),
      progressRepository: context.read(),
      publicProfileRepository: context.read<PublicProfileRepository>(),
      teacherId: teacherId,
      traineeId: widget.traineeId,
      preferredGroupId: widget.preferredGroupId,
      initialPracticePageSize: 3,
      evidenceRepository: widget.evidenceRepository ?? _maybeEvidence(context),
      leaderboardRepository:
          widget.leaderboardRepository ?? _maybeLeaderboard(context),
    )..start();
  }

  LeaderboardRepository? _maybeLeaderboard(BuildContext context) {
    try {
      return context.read<LeaderboardRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  TeacherEvidenceRepository? _maybeEvidence(BuildContext context) {
    try {
      return context.read<TeacherEvidenceRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null)
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Student',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Center(child: ProgressRing()),
      );
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Student details',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.chat),
                label: const Text('Message student'),
                onPressed:
                    controller.state == TeacherStudentDetailState.unauthorized
                    ? null
                    : () => context.go(
                        Uri(
                          path: AppRoutePaths.teacherMessages,
                          queryParameters: {
                            'userId': controller.traineeId,
                            'name': controller.displayName,
                            'role': 'Trainee',
                          },
                        ).toString(),
                      ),
              ),
            ],
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              key: const Key('teacher_student_back'),
              label: widget.preferredGroupId == null ? 'Students' : 'Classroom',
              tooltip: 'Back',
              semanticLabel: 'Back',
              onPressed: () => context.go(
                widget.preferredGroupId == null
                    ? AppRoutePaths.teacherStudents
                    : AppRoutePaths.teacherGroup(widget.preferredGroupId!),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _IdentityHeader(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _Body(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.controller});
  final TeacherStudentDetailController controller;
  @override
  Widget build(BuildContext context) => ElixPanelCard(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ProfileAvatarWidget(
          key: const Key('teacher_student_detail_avatar'),
          radius: 32,
          showBorder: false,
          initials: userInitials(controller.displayName),
          networkImageUrl: controller.profileRoot?.profilePictureUrl,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(controller.displayName, style: AppTheme.headingMedium),
              if (controller.classroomGroupCaption != null)
                Text(
                  controller.classroomGroupCaption!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (controller.hasClassroomAuthorization)
          const _Chip(label: 'Approved', color: AppColors.success),
        if (controller.isPrivateProfile)
          const _Chip(label: 'Profile locked', color: AppColors.warning),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});
  final TeacherStudentDetailController controller;
  @override
  Widget build(BuildContext context) => switch (controller.state) {
    TeacherStudentDetailState.loadingClassroom ||
    TeacherStudentDetailState.loadingProgress => const Center(
      child: ProgressRing(),
    ),
    TeacherStudentDetailState.unauthorized => const _Message(
      title: 'Not authorized',
      body:
          'This student is not in any of your groups. Classroom membership is required before you can view details.',
    ),
    TeacherStudentDetailState.pending => const _Message(
      title: 'Pending approval',
      body: 'Approve this student in Groups before viewing learning progress.',
    ),
    TeacherStudentDetailState.relationshipRemoved => const _Message(
      title: 'Membership inactive',
      body: 'This student no longer has an approved classroom membership.',
    ),
    TeacherStudentDetailState.connectionRequired => _Message(
      title: 'Connection required',
      body:
          'Could not verify classroom membership. Check your connection and try again.',
      action: controller.refresh,
    ),
    TeacherStudentDetailState.error => _Message(
      title: 'Something went wrong',
      body: 'History could not be loaded.',
      action: controller.refresh,
    ),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.isPrivateProfile) ...[
          const _LockedProfileNotice(),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Learning', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        _LearningEntries(controller: controller),
        if (controller.profileRoot?.isPublic == true) ...[
          const SizedBox(height: AppSpacing.xl),
          _ProfileHighlights(controller: controller),
        ],
      ],
    ),
  };
}

class _LearningEntries extends StatelessWidget {
  const _LearningEntries({required this.controller});
  final TeacherStudentDetailController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entries = [
        _LearningEntry(
          key: const Key('teacher_student_classwork_entry'),
          icon: FluentIcons.completed_solid,
          title: 'Classwork',
          detail:
              'Classroom assignments, submissions, review, grading, and feedback.',
          onOpen: () {
            final groupId = controller.selectedGroupId;
            if (groupId != null)
              context.push(
                AppRoutePaths.teacherStudentClasswork(
                  controller.traineeId,
                  groupId: groupId,
                ),
              );
          },
        ),
        _LearningEntry(
          key: const Key('teacher_student_practice_entry'),
          icon: FluentIcons.timeline,
          title: 'History',
          detail:
              'Independent and Guided Practice sessions, separate from assigned Classwork.',
          onOpen: () => context.push(
            AppRoutePaths.teacherStudentPracticeHistory(
              controller.traineeId,
              groupId: controller.selectedGroupId,
            ),
          ),
        ),
      ];
      return constraints.maxWidth < 640
          ? Column(
              children: [
                entries[0],
                const SizedBox(height: AppSpacing.sm),
                entries[1],
              ],
            )
          : Row(
              children: [
                Expanded(child: entries[0]),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: entries[1]),
              ],
            );
    },
  );
}

class _LearningEntry extends StatelessWidget {
  const _LearningEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onOpen,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open $title',
    child: HoverButton(
      cursor: SystemMouseCursors.click,
      onPressed: onOpen,
      builder: (context, states) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? context.elixColors.interactiveHover
              : context.elixPanelSurface,
          border: Border.all(
            color: states.contains(WidgetState.focused)
                ? context.elixColors.focusRing
                : context.elixColors.borderSubtle,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: context.elixColors.brandPrimary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(FluentIcons.chevron_right, size: 12),
          ],
        ),
      ),
    ),
  );
}

class _LockedProfileNotice extends StatelessWidget {
  const _LockedProfileNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: context.elixPanelSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: context.elixColors.brandSecondary.withValues(alpha: .28),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.lock,
          size: 16,
          color: context.elixColors.brandSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Text(
            'Profile locked. Public achievements and player details are hidden. Classroom-authorized History and Classwork remain available.',
          ),
        ),
      ],
    ),
  );
}

class _ProfileHighlights extends StatelessWidget {
  const _ProfileHighlights({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Profile highlights', style: AppTheme.headingMedium),
      const SizedBox(height: AppSpacing.sm),
      if (controller.leaderboardEntry != null) ...[
        ProfileStatsSection(
          leaderboardEntry: controller.leaderboardEntry,
          rank: controller.leaderboardRank,
          rankState: controller.leaderboardRankState,
          summary: controller.summary,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (controller.profileHighlightsLoading)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: ProgressRing(),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final achievements = ProfileAchievementsSection(
              achievements: controller.claimedAchievements,
              showViewAll: false,
            );
            final movements = CompletedMovementsSection(
              movementNames:
                  controller.summary?.completedMovementNames ?? const [],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  achievements,
                  const SizedBox(height: AppSpacing.lg),
                  movements,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: achievements),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: movements),
              ],
            );
          },
        ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .45)),
    ),
    child: Text(label, style: AppTheme.caption.copyWith(color: color)),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, this.action});
  final String title;
  final String body;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => ElixStatusPanel(
    title: title,
    message: body,
    actionLabel: action == null ? null : 'Retry',
    onAction: action,
  );
}
