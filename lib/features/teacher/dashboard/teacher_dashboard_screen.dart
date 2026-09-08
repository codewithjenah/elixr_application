import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/user_name.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_stat_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../activity_center/teacher_activity_controller.dart';
import '../analytics/teacher_analytics_controller.dart';
import '../analytics/teacher_analytics_summary.dart';
import '../students/teacher_student_models.dart';
import 'teacher_dashboard_controller.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  TeacherDashboardController? _controller;
  TeacherAnalyticsController? _analyticsController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    if (userId == null) return;
    _controller = TeacherDashboardController(
      repository: context.read<GroupRepository>(),
      teacherId: userId,
    )..start();
    final progress = _tryRead<TeacherProgressRepository>(context);
    final assignments = _tryRead<ClassroomAssignmentRepository>(context);
    if (progress != null && assignments != null) {
      _analyticsController = TeacherAnalyticsController(
        groupRepository: context.read<GroupRepository>(),
        assignmentRepository: assignments,
        progressRepository: progress,
        teacherId: userId,
      )..start();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _analyticsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityController = context.watch<TeacherActivityController?>();
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Dashboard',
          eyebrow: 'TEACHER WORKSPACE',
          subtitle: 'Your classrooms and review work in one place.',
          variant: ElixEditorialHeaderVariant.standard,
        ),
        content: Center(
          child: ElixStatusPanel(
            isError: true,
            icon: FluentIcons.warning,
            title: 'Sign-in required',
            message: 'Sign in to view your teacher dashboard.',
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        ...?(_analyticsController == null
            ? null
            : <Listenable>[_analyticsController!]),
      ]),
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: const ElixEditorialPageHeader(
            heading: 'Dashboard',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'Your classrooms and review work in one place.',
            variant: ElixEditorialHeaderVariant.standard,
          ),
          content: controller.loading
              ? const Center(child: ProgressRing())
              : controller.errorMessage != null
              ? _ErrorState(
                  message: controller.errorMessage!,
                  onRetry: controller.retry,
                )
              : _DashboardBody(
                  controller: controller,
                  analyticsController: _analyticsController,
                  activityController: activityController,
                  teacher: context.watch<AuthService>().currentUser,
                ),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.controller,
    required this.teacher,
    required this.activityController,
    this.analyticsController,
  });

  final TeacherDashboardController controller;
  final TeacherActivityController? activityController;
  final TeacherAnalyticsController? analyticsController;
  final User? teacher;

  @override
  Widget build(BuildContext context) {
    final hasData =
        controller.activeGroupCount > 0 || controller.memberships.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final gettingStarted = _GettingStartedModel.from(
          controller: controller,
          analyticsController: analyticsController,
          activityController: activityController,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TeacherCommandHeader(teacher: teacher),
            const SizedBox(height: AppSpacing.lg),
            if (wide)
              Row(
                children: [
                  Expanded(
                    child: ElixStatCard(
                      label: 'Active classrooms',
                      value: '${controller.activeGroupCount}',
                      icon: FluentIcons.people,
                      highlighted: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElixStatCard(
                      label: 'Students',
                      value: '${controller.approvedStudentCount}',
                      icon: FluentIcons.contact,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElixStatCard(
                      label: 'Pending requests',
                      value: '${controller.pendingRequestCount}',
                      icon: FluentIcons.inbox,
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: ElixStatCard(
                      label: 'Active classrooms',
                      value: '${controller.activeGroupCount}',
                      icon: FluentIcons.people,
                      highlighted: true,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: ElixStatCard(
                      label: 'Students',
                      value: '${controller.approvedStudentCount}',
                      icon: FluentIcons.contact,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: ElixStatCard(
                      label: 'Pending requests',
                      value: '${controller.pendingRequestCount}',
                      icon: FluentIcons.inbox,
                    ),
                  ),
                ],
              ),
            if (gettingStarted != null) ...[
              const SizedBox(height: AppSpacing.xl),
              _GettingStartedCard(model: gettingStarted),
            ],
            if (hasData) ...[
              if (analyticsController != null) ...[
                const SizedBox(height: AppSpacing.xl),
                TeacherAnalyticsSummary(controller: analyticsController!),
              ],
              const SizedBox(height: AppSpacing.xl),
              _DashboardWorkspace(controller: controller, wide: wide),
            ],
          ],
        );
      },
    );
  }
}

class _TeacherCommandHeader extends StatelessWidget {
  const _TeacherCommandHeader({required this.teacher});

  final User? teacher;

  @override
  Widget build(BuildContext context) {
    final name = teacher?.fullName.trim();
    final displayName = name == null || name.isEmpty ? 'Teacher' : name;
    return ElixPanelCard(
      accent: context.elixColors.brandPrimary,
      showAccentBar: true,
      variant: ElixPanelVariant.hero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final identity = Row(
            children: [
              ProfileAvatarWidget(
                key: const Key('teacher_dashboard_avatar'),
                radius: 28,
                networkImageUrl: teacher?.profilePictureUrl,
                legacyLocalPath: teacher?.profilePicturePath,
                initials: userInitials(displayName),
                equippedBorderId: teacher?.profileBorderId,
                animateBorder: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ElixEyebrow(label: 'TODAY'),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Welcome back, $displayName',
                      style: AppTheme.sectionTitle(
                        context,
                        color: context.elixTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Check classrooms, review student work, and keep your classes organized.',
                      style: AppTheme.supporting(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: const Key('teacher_dashboard_open_classrooms'),
                onPressed: () => context.go(AppRoutePaths.teacherGroups),
                child: const Text('Open Classrooms'),
              ),
              Button(
                key: const Key('teacher_dashboard_to_review'),
                onPressed: () => context.go(AppRoutePaths.teacherToReview),
                child: const Text('Review Work'),
              ),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.md),
                    actions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: AppSpacing.md),
                    actions,
                  ],
                );
        },
      ),
    );
  }
}

class _DashboardWorkspace extends StatelessWidget {
  const _DashboardWorkspace({required this.controller, required this.wide});
  final TeacherDashboardController controller;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final groups = _WorkspaceSection(
      heading: 'Your classrooms',
      eyebrow: 'CLASSROOMS',
      subtitle: 'Manage students and class activity.',
      action: Button(
        onPressed: () => context.go(AppRoutePaths.teacherGroups),
        child: const Text('View classrooms'),
      ),
      child: controller.groupSummaries.isEmpty
          ? Text(
              'No active classrooms yet.',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            )
          : Column(
              children: [
                for (final summary in controller.groupSummaries)
                  _GroupOverviewRow(summary: summary),
              ],
            ),
    );
    final attention = _WorkspaceSection(
      heading: 'Needs attention',
      eyebrow: 'INBOX',
      subtitle: 'Pending join requests need a decision.',
      child: controller.pendingQueue.isEmpty
          ? Row(
              children: [
                Icon(FluentIcons.completed, color: context.elixColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'You are all caught up.',
                    style: AppTheme.body.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (final membership in controller.pendingQueue)
                  _PendingRequestRow(membership: membership),
              ],
            ),
    );
    if (!wide) {
      return Column(
        children: [
          groups,
          const SizedBox(height: AppSpacing.lg),
          attention,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: groups),
        const SizedBox(width: AppSpacing.lg),
        Expanded(flex: 2, child: attention),
      ],
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({
    required this.heading,
    required this.eyebrow,
    required this.subtitle,
    required this.child,
    this.action,
  });
  final String heading;
  final String eyebrow;
  final String subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ElixPanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElixSectionHeader(
          heading: heading,
          eyebrow: eyebrow,
          subtitle: subtitle,
          actions: action == null ? const [] : [action!],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _GroupOverviewRow extends StatelessWidget {
  const _GroupOverviewRow({required this.summary});

  final TeacherGroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasPending = summary.pendingCount > 0;
    final studentLabel = summary.approvedCount == 1
        ? '1 student enrolled'
        : '${summary.approvedCount} students enrolled';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ElixPanelCard(
        accent: hasPending
            ? context.elixColors.warning
            : context.elixColors.brandPrimary,
        showAccentBar: hasPending,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final identity = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.elixColors.brandPrimary.withValues(
                      alpha: context.isHighContrast ? 0 : 0.14,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    FluentIcons.education,
                    size: 20,
                    color: context.elixColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.group.name,
                        style: AppTheme.cardTitle(
                          color: context.elixTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        studentLabel,
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final status = ElixPill(
              compact: true,
              color: hasPending
                  ? context.elixColors.warning
                  : context.elixColors.success,
              text: hasPending
                  ? '${summary.pendingCount} waiting to join'
                  : 'No pending requests',
            );
            final action = FilledButton(
              onPressed: () => context.go(AppRoutePaths.teacherGroups),
              child: const Text('Open classroom'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [status, action],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: AppSpacing.md),
                status,
                const SizedBox(width: AppSpacing.sm),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PendingRequestRow extends StatelessWidget {
  const _PendingRequestRow({required this.membership});

  final GroupMembership membership;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ElixPanelCard(
        child: ListTile(
          title: Text(membership.traineeDisplayName),
          subtitle: const Text('Wants to join a class'),
          trailing: Button(
            onPressed: () => context.go(AppRoutePaths.teacherGroups),
            child: const Text('Review request'),
          ),
        ),
      ),
    );
  }
}

enum _GettingStartedStep {
  createClassroom,
  inviteStudents,
  approveStudent,
  createAssignment,
  reviewSubmission,
  waitingForSubmission,
}

class _GettingStartedModel {
  const _GettingStartedModel({
    required this.step,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.route,
    required this.icon,
  });

  final _GettingStartedStep step;
  final String title;
  final String message;
  final String actionLabel;
  final String route;
  final IconData icon;

  static _GettingStartedModel? from({
    required TeacherDashboardController controller,
    required TeacherAnalyticsController? analyticsController,
    required TeacherActivityController? activityController,
  }) {
    final activeGroups = controller.groups.where((group) => group.isActive);
    final activeGroupIds = activeGroups.map((group) => group.id).toSet();
    if (activeGroupIds.isEmpty) {
      return const _GettingStartedModel(
        step: _GettingStartedStep.createClassroom,
        title: 'Create your first classroom',
        message:
            'Start with one classroom so students, assignments, and progress stay organized.',
        actionLabel: 'Create classroom',
        route: AppRoutePaths.teacherGroups,
        icon: FluentIcons.people,
      );
    }

    final pending = controller.pendingQueue
        .where((membership) => activeGroupIds.contains(membership.groupId))
        .toList();
    final firstGroupId = activeGroups.first.id;
    final firstActionGroupId = pending.isNotEmpty
        ? pending.first.groupId
        : firstGroupId;
    if (pending.isNotEmpty) {
      return _GettingStartedModel(
        step: _GettingStartedStep.approveStudent,
        title: 'Approve your first student',
        message:
            'A student is waiting to join. Review the request before they enter the classroom.',
        actionLabel: 'Review join request',
        route: '${AppRoutePaths.teacherGroup(firstActionGroupId)}?tab=people',
        icon: FluentIcons.people_add,
      );
    }

    final hasApprovedStudent = controller.memberships.any(
      (membership) =>
          activeGroupIds.contains(membership.groupId) && membership.isApproved,
    );
    if (!hasApprovedStudent) {
      return _GettingStartedModel(
        step: _GettingStartedStep.inviteStudents,
        title: 'Invite your students',
        message:
            'Share the classroom join code. Students will wait for your approval.',
        actionLabel: 'View and copy class code',
        route: '${AppRoutePaths.teacherGroup(firstGroupId)}?tab=overview',
        icon: FluentIcons.share,
      );
    }

    final analyticsReady =
        analyticsController != null &&
        !analyticsController.loading &&
        !analyticsController.hasStreamError;
    final assignments =
        analyticsController?.assignments
            .where(
              (assignment) =>
                  activeGroupIds.contains(assignment.groupId) &&
                  assignment.isActive,
            )
            .toList() ??
        const [];
    if (!analyticsReady || assignments.isEmpty) {
      return _GettingStartedModel(
        step: _GettingStartedStep.createAssignment,
        title: 'Create your first assignment',
        message:
            'Choose an ELIXR movement or your own activity, then set who should complete it.',
        actionLabel: 'Create assignment',
        route: '${AppRoutePaths.teacherGroup(firstGroupId)}?tab=classwork',
        icon: FluentIcons.add,
      );
    }

    if ((activityController?.pendingReviewCount ?? 0) > 0) {
      final destination = activityController?.pendingReviews.isNotEmpty == true
          ? activityController!.pendingReviews.first.destination
          : AppRoutePaths.teacherToReview;
      return _GettingStartedModel(
        step: _GettingStartedStep.reviewSubmission,
        title: 'Review your first submission',
        message:
            'A student has submitted work. Review the recording, score it, and leave feedback.',
        actionLabel: 'Review submission',
        route: destination,
        icon: FluentIcons.review_request_solid,
      );
    }

    final hasCheckedAttempt = analyticsController.attempts.any(
      (attempt) =>
          activeGroupIds.contains(attempt.groupId) && attempt.isChecked,
    );
    if (hasCheckedAttempt) return null;

    return _GettingStartedModel(
      step: _GettingStartedStep.waitingForSubmission,
      title: 'Your first assignment is ready',
      message:
          'When a student submits work, it will appear in Review Work for scoring and feedback.',
      actionLabel: 'Open Review Work',
      route: AppRoutePaths.teacherToReview,
      icon: FluentIcons.clock,
    );
  }
}

class _GettingStartedCard extends StatelessWidget {
  const _GettingStartedCard({required this.model});

  final _GettingStartedModel model;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      key: const Key('teacher_getting_started'),
      accent: context.elixColors.brandPrimary,
      showAccentBar: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ElixEyebrow(label: 'GETTING STARTED'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                model.title,
                style: AppTheme.sectionTitle(
                  context,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                model.message,
                style: AppTheme.supporting(color: context.elixTextSecondary),
              ),
            ],
          );
          final action = FilledButton(
            key: const Key('teacher_getting_started_action'),
            onPressed: () => context.go(model.route),
            child: Text(model.actionLabel),
          );
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(model.icon, color: context.elixColors.brandPrimary),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: copy),
              const SizedBox(width: AppSpacing.md),
              action,
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: AppSpacing.md),
                    action,
                  ],
                )
              : content;
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ElixStatusPanel(
          isError: true,
          message: message,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      ),
    );
  }
}

T? _tryRead<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
