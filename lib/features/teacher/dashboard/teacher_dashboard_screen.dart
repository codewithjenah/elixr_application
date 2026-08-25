import 'package:elixr_core/models/group_membership.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../services/auth_service.dart';
import '../students/teacher_student_models.dart';
import 'teacher_dashboard_controller.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  TeacherDashboardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    if (userId == null) return;
    _controller = TeacherDashboardController(
      repository: context.read(),
      teacherId: userId,
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
      return const TeacherScaffoldPage(
        header: PageHeader(title: Text('Dashboard')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: const PageHeader(title: Text('Dashboard')),
          content: controller.loading
              ? const Center(child: ProgressRing())
              : controller.errorMessage != null
              ? _ErrorState(
                  message: controller.errorMessage!,
                  onRetry: controller.retry,
                )
              : _DashboardBody(controller: controller),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.controller});

  final TeacherDashboardController controller;

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
                    child: _MetricCard(
                      label: 'Active groups',
                      value: '${controller.activeGroupCount}',
                      icon: FluentIcons.people,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _MetricCard(
                      label: 'Approved students',
                      value: '${controller.approvedStudentCount}',
                      icon: FluentIcons.contact,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _MetricCard(
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
                  _MetricCard(
                    label: 'Active groups',
                    value: '${controller.activeGroupCount}',
                    icon: FluentIcons.people,
                  ),
                  _MetricCard(
                    label: 'Approved students',
                    value: '${controller.approvedStudentCount}',
                    icon: FluentIcons.contact,
                  ),
                  _MetricCard(
                    label: 'Pending requests',
                    value: '${controller.pendingRequestCount}',
                    icon: FluentIcons.inbox,
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.xl),
            Text('Groups overview', style: AppTheme.headingMedium),
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
            Text('Pending join requests', style: AppTheme.headingMedium),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: ElixPanelCard(
        expand: false,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, size: 28, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppTheme.headingLarge.copyWith(
                      color: context.elixTextPrimary,
                    ),
                  ),
                  Text(
                    label,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupOverviewRow extends StatelessWidget {
  const _GroupOverviewRow({required this.summary});

  final TeacherGroupSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ElixPanelCard(
        child: ListTile(
          title: Text(summary.group.name),
          subtitle: Text(
            '${summary.approvedCount} approved · ${summary.pendingCount} pending',
          ),
          trailing: Button(
            onPressed: () => context.go(AppRoutePaths.teacherGroups),
            child: const Text('Manage'),
          ),
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
          subtitle: const Text('Requested group membership'),
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
              'Create a group and share an invite code to start building your roster.',
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
