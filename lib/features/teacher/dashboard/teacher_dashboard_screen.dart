import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_stat_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
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
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Dashboard',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.hero,
        ),
        content: Center(child: ProgressRing()),
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
            subtitle: 'Keep your groups and student activity in view.',
            variant: ElixEditorialHeaderVariant.hero,
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
                ),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.controller, this.analyticsController});

  final TeacherDashboardController controller;
  final TeacherAnalyticsController? analyticsController;

  @override
  Widget build(BuildContext context) {
    final hasData =
        controller.activeGroupCount > 0 || controller.memberships.isNotEmpty;
    if (!hasData) {
      return _EmptyDashboard(
        onOpenGroups: () {
          context.go(AppRoutePaths.teacherGroups);
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(
                    child: ElixStatCard(
                      label: 'Active groups',
                      value: '${controller.activeGroupCount}',
                      icon: FluentIcons.people,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElixStatCard(
                      label: 'Approved students',
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
                      label: 'Active groups',
                      value: '${controller.activeGroupCount}',
                      icon: FluentIcons.people,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: ElixStatCard(
                      label: 'Approved students',
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
            if (analyticsController != null) ...[
              const SizedBox(height: AppSpacing.xl),
              TeacherAnalyticsSummary(controller: analyticsController!),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElixSectionHeader(
              heading: 'Groups overview',
              eyebrow: 'CLASSROOM',
              subtitle: 'Manage your rosters and keep join requests moving.',
              actions: [
                Button(
                  onPressed: () => context.go(AppRoutePaths.teacherGroups),
                  child: const Text('Open groups'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (controller.groupSummaries.isEmpty)
              Text(
                'No active groups yet.',
                style: AppTheme.body.copyWith(color: context.elixTextSecondary),
              )
            else
              ...controller.groupSummaries.map(
                (summary) => _GroupOverviewRow(summary: summary),
              ),
            const SizedBox(height: AppSpacing.xl),
            const ElixSectionHeader(
              heading: 'Pending join requests',
              eyebrow: 'INBOX',
            ),
            const SizedBox(height: AppSpacing.md),
            if (controller.pendingQueue.isEmpty)
              Text(
                'No pending requests.',
                style: AppTheme.body.copyWith(color: context.elixTextSecondary),
              )
            else
              ...controller.pendingQueue.map(
                (membership) => _PendingRequestRow(membership: membership),
              ),
          ],
        );
      },
    );
  }
}

class _GroupOverviewRow extends StatelessWidget {
  const _GroupOverviewRow({required this.summary});

  final TeacherGroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasPending = summary.pendingCount > 0;
    final rosterLabel = summary.approvedCount == 1
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
                        rosterLabel,
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
                  ? '${summary.pendingCount} waiting'
                  : 'Roster up to date',
            );
            final action = FilledButton(
              onPressed: () => context.go(AppRoutePaths.teacherGroups),
              child: const Text('Manage group'),
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
            child: const Text('Review in Groups'),
          ),
        ),
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.onOpenGroups});

  final VoidCallback onOpenGroups;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ElixStatusPanel(
          icon: FluentIcons.people,
          title: 'Your classroom is ready',
          message:
              'Create a class, then share the join code with your students. '
              'Each class keeps its own student list.',
          actionLabel: 'Open Groups',
          onAction: onOpenGroups,
        ),
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
