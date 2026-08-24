import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import 'teacher_student_detail_controller.dart';
import 'teacher_student_models.dart';

class TeacherStudentDetailScreen extends StatefulWidget {
  const TeacherStudentDetailScreen({
    super.key,
    required this.traineeId,
    this.preferredGroupId,
  });

  final String traineeId;
  final String? preferredGroupId;

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
    final userId = auth.currentUser?.id;
    if (userId == null) return;
    _controller = TeacherStudentDetailController(
      groupRepository: context.read(),
      relationshipRepository: context.read(),
      progressRepository: context.read(),
      publicProfileRepository: context.read<PublicProfileRepository>(),
      teacherId: userId,
      traineeId: widget.traineeId,
      preferredGroupId: widget.preferredGroupId,
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ElixScaffoldPage(
        header: PageHeader(title: Text('Student')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          header: PageHeader(
            title: Text(controller.displayName),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.chat),
                  label: const Text('Message student'),
                  onPressed:
                      controller.state == TeacherStudentDetailState.unauthorized
                      ? null
                      : () {
                          final location = Uri(
                            path: AppRoutePaths.teacherMessages,
                            queryParameters: {
                              'userId': controller.traineeId,
                              'name': controller.displayName,
                              'role': 'Trainee',
                              if (controller.profileRoot?.profilePictureUrl !=
                                  null)
                                'avatar':
                                    controller.profileRoot!.profilePictureUrl,
                            },
                          ).toString();
                          context.go(location);
                        },
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.back),
                  label: const Text('Back to Students'),
                  onPressed: () => context.go(AppRoutePaths.teacherStudents),
                ),
              ],
            ),
          ),
          content: _DetailBody(controller: controller),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      TeacherStudentDetailState.loadingClassroom => const Center(
        child: ProgressRing(),
      ),
      TeacherStudentDetailState.unauthorized => _MessagePanel(
        title: 'Not authorized',
        body:
            'This student is not in any of your groups. Classroom membership is required before you can view details.',
        icon: FluentIcons.lock_solid,
      ),
      TeacherStudentDetailState.pending => _MembershipPanel(
        controller: controller,
        title: 'Pending approval',
        body:
            'This student has requested to join your classroom. Approve the membership in Groups before coaching or viewing progress.',
      ),
      TeacherStudentDetailState.relationshipRemoved => _MembershipPanel(
        controller: controller,
        title: 'Membership inactive',
        body:
            'This student no longer has an active approved membership in your groups.',
      ),
      TeacherStudentDetailState.connectionRequired => _MessagePanel(
        title: 'Connection required',
        body:
            'Could not verify classroom membership. Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      ),
      TeacherStudentDetailState.error => _MessagePanel(
        title: 'Something went wrong',
        body: 'Practice history could not be loaded.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      ),
      _ => _AuthorizedBody(controller: controller),
    };
  }
}

class _AuthorizedBody extends StatelessWidget {
  const _AuthorizedBody({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.isPrivateProfile) const _PrivateProfileBadge(),
        const SizedBox(height: AppSpacing.md),
        _ClassroomStatus(controller: controller),
        const SizedBox(height: AppSpacing.xl),
        _ProgressSection(controller: controller),
      ],
    );
  }
}

class _PrivateProfileBadge extends StatelessWidget {
  const _PrivateProfileBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.lock_solid, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Private public profile — classroom membership remains visible to you as the assigning Teacher.',
              style: AppTheme.body.copyWith(color: context.elixTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassroomStatus extends StatelessWidget {
  const _ClassroomStatus({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Classroom status', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Approved member in ${controller.approvedMemberships.length} group(s).',
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final membership in controller.approvedMemberships)
              _StatusBadge(label: teacherStudentStatusLabel(membership.status)),
          ],
        ),
      ],
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Practice progress', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.md),
        switch (controller.state) {
          TeacherStudentDetailState.waitingForAccess => _MessagePanel(
            title: 'Waiting for progress access',
            body:
                'This student is in your classroom but has not shared official practice progress yet. They can grant Progress Access from their ELIXR settings.',
            icon: FluentIcons.hour_glass,
          ),
          TeacherStudentDetailState.accessWithdrawn => _MessagePanel(
            title: 'Progress access withdrawn',
            body:
                'This student previously shared progress but has withdrawn access. Classroom membership is unchanged.',
            icon: FluentIcons.remove_filter,
          ),
          TeacherStudentDetailState.loadingProgress => const Center(
            child: ProgressRing(),
          ),
          TeacherStudentDetailState.empty => _MessagePanel(
            title: 'No practice history yet',
            body: 'Shared progress is empty so far.',
          ),
          TeacherStudentDetailState.ready => _ProgressReady(
            controller: controller,
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _ProgressReady extends StatelessWidget {
  const _ProgressReady({required this.controller});

  final TeacherStudentDetailController controller;
  static final _duration = NumberFormat.decimalPattern();

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null) ...[
          Text(
            'Total practice: ${_duration.format(summary.totalDurationSeconds)} seconds',
            style: AppTheme.body,
          ),
          if (summary.completedMovementNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Completed movements: ${summary.completedMovementNames.join(', ')}',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        if (controller.sessions.isEmpty)
          Text(
            'No sessions on this page.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          )
        else
          ...controller.sessions.map((session) {
            final scoreLabel = session.isRubricAssessed
                ? '${session.rubric!.total}/12'
                : '${session.legacyScore ?? 0}%';
            return ListTile(
              title: Text(session.movementName),
              subtitle: Text('${session.difficulty} · $scoreLabel'),
            );
          }),
        if (controller.paginationError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Could not load more sessions.', style: AppTheme.caption),
          Button(
            onPressed: controller.retryLoadMore,
            child: const Text('Retry load more'),
          ),
        ] else if (controller.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Button(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              child: controller.loadingMore
                  ? const ProgressRing()
                  : const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _MembershipPanel extends StatelessWidget {
  const _MembershipPanel({
    required this.controller,
    required this.title,
    required this.body,
  });

  final TeacherStudentDetailController controller;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.isPrivateProfile) const _PrivateProfileBadge(),
        const SizedBox(height: AppSpacing.md),
        _MessagePanel(title: title, body: body),
        const SizedBox(height: AppSpacing.lg),
        Text(controller.displayName, style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          teacherStudentStatusLabel(
            effectiveMembershipStatus(controller.classroomMemberships),
          ),
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(title, style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.elixBorder),
      ),
      child: Text(label, style: AppTheme.caption),
    );
  }
}
