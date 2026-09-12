import 'dart:async';

import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/utils/user_name.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/message_unread_badge.dart';
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the rail visible at medium desktop widths. The dashboard
            // cards are designed for this split; only narrow windows become a
            // single document column.
            final wide = constraints.maxWidth >= 760;
            final gettingStarted = _GettingStartedModel.from(
              controller: controller,
              analyticsController: analyticsController,
              activityController: activityController,
            );
            final onboarding = gettingStarted?.isEarlyOnboarding == true
                ? gettingStarted
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TeacherCommandHeader(teacher: teacher),
                const SizedBox(height: AppSpacing.md),
                _TeacherKpiGrid(
                  controller: controller,
                  reviewCount: activityController?.pendingReviewCount ?? 0,
                  activityLoading: activityController?.loading ?? false,
                  wide: wide,
                ),
                const SizedBox(height: AppSpacing.md),
                _DashboardContent(
                  controller: controller,
                  analyticsController: analyticsController,
                  activityController: activityController,
                  gettingStarted: onboarding,
                  wide: wide,
                ),
              ],
            );
          },
        ),
      ),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final identity = Row(
            children: [
              ProfileAvatarWidget(
                key: const Key('teacher_dashboard_avatar'),
                radius: 22,
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
                    Text(
                      'Welcome back, $displayName',
                      style: AppTheme.cardTitle(color: context.elixTextPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Your classroom overview for today.',
                      style: AppTheme.caption.copyWith(
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
              const _TeacherNotificationButton(),
              ElixPrimaryButton(
                key: const Key('teacher_dashboard_to_review'),
                onPressed: () => context.go(AppRoutePaths.teacherToReview),
                label: 'Review work',
                expanded: false,
                dense: true,
              ),
              _TeacherClassroomsButton(
                onPressed: () => context.go(AppRoutePaths.teacherGroups),
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

class _TeacherClassroomsButton extends StatelessWidget {
  const _TeacherClassroomsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const key = Key('teacher_dashboard_open_classrooms');
    if (shad.ShadTheme.maybeOf(context) == null) {
      return Button(
        key: key,
        onPressed: onPressed,
        child: const Text('Classrooms'),
      );
    }
    return shad.ShadButton.outline(
      key: key,
      onPressed: onPressed,
      child: const Text('Classrooms'),
    );
  }
}

class _TeacherNotificationButton extends StatefulWidget {
  const _TeacherNotificationButton();

  @override
  State<_TeacherNotificationButton> createState() =>
      _TeacherNotificationButtonState();
}

class _TeacherNotificationButtonState
    extends State<_TeacherNotificationButton> {
  final _flyoutController = FlyoutController();

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _showNotifications() {
    _flyoutController.showFlyout<void>(
      placementMode: FlyoutPlacementMode.bottomRight,
      additionalOffset: AppSpacing.sm,
      builder: (flyoutContext) => _TeacherNotificationsFlyout(
        controller: context.read<TeacherActivityController?>(),
        onOpen: (activity) async {
          Flyout.of(flyoutContext).close();
          final controller = context.read<TeacherActivityController?>();
          if (controller == null) return;
          await controller.markRead(activity);
          if (mounted) context.push(activity.destination);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        context.watch<TeacherActivityController?>()?.unreadCount ?? 0;
    final label = unreadCount == 0
        ? 'Notifications'
        : 'Notifications, $unreadCount unread';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: FlyoutTarget(
          controller: _flyoutController,
          child: Button(
            key: const Key('teacher_dashboard_notifications'),
            onPressed: _showNotifications,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      FluentIcons.ringer,
                      size: 18,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: MessageUnreadBadge(
                            key: const ValueKey(
                              'teacher-dashboard-notification-unread-badge',
                            ),
                            count: unreadCount,
                            compact: true,
                            semanticLabel: '$unreadCount unread notifications',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherNotificationsFlyout extends StatefulWidget {
  const _TeacherNotificationsFlyout({
    required this.controller,
    required this.onOpen,
  });

  final TeacherActivityController? controller;
  final Future<void> Function(TeacherActivity activity) onOpen;

  @override
  State<_TeacherNotificationsFlyout> createState() =>
      _TeacherNotificationsFlyoutState();
}

class _TeacherNotificationsFlyoutState
    extends State<_TeacherNotificationsFlyout> {
  static const _maxItems = 5;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final activities =
        controller?.activities.take(_maxItems).toList() ??
        const <TeacherActivity>[];
    return FlyoutContent(
      key: const ValueKey('teacher-dashboard-notifications-flyout'),
      color: context.elixCardSurface,
      useAcrylic: false,
      constraints: const BoxConstraints.tightFor(width: 360),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.elixBorder),
      ),
      child: SizedBox(
        height: 410,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  Text(
                    'Notifications',
                    style: AppTheme.body.copyWith(
                      color: context.elixTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if ((controller?.unreadCount ?? 0) > 0)
                    Container(
                      key: const ValueKey(
                        'teacher-dashboard-notification-unread-count',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.elixColors.brandSecondary.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${controller!.unreadCount} new',
                        style: AppTheme.caption.copyWith(
                          color: context.elixColors.brandSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(style: DividerThemeData(thickness: 1)),
            Expanded(
              child: controller == null || controller.loading
                  ? const Center(child: ProgressRing())
                  : activities.isEmpty
                  ? _TeacherNotificationsEmptyState(
                      hasError: controller.hasStreamError,
                      onRetry: controller.retry,
                    )
                  : ListView.separated(
                      key: const ValueKey(
                        'teacher-dashboard-notifications-list',
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: activities.length,
                      separatorBuilder: (_, _) => Divider(
                        style: DividerThemeData(
                          thickness: 1,
                          decoration: BoxDecoration(color: context.elixBorder),
                        ),
                      ),
                      itemBuilder: (context, index) =>
                          _TeacherNotificationPreview(
                            activity: activities[index],
                            onPressed: () =>
                                unawaited(widget.onOpen(activities[index])),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherNotificationsEmptyState extends StatelessWidget {
  const _TeacherNotificationsEmptyState({
    required this.hasError,
    required this.onRetry,
  });

  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasError ? FluentIcons.warning : FluentIcons.ringer,
          size: 28,
          color: context.elixTextSecondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          hasError
              ? 'Notifications could not be refreshed.'
              : "You're all caught up.",
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: context.elixTextPrimary),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Button(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    ),
  );
}

class _TeacherNotificationPreview extends StatelessWidget {
  const _TeacherNotificationPreview({
    required this.activity,
    required this.onPressed,
  });

  final TeacherActivity activity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${activity.isRead ? 'Read' : 'Unread'} notification: ${activity.title}',
    child: HoverButton(
      key: Key('teacher_dashboard_notification_${activity.id}'),
      onPressed: onPressed,
      builder: (context, states) => Container(
        color: states.isHovered
            ? context.elixPanelSurface
            : activity.isRead
            ? Colors.transparent
            : context.elixColors.brandSecondary.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _iconFor(activity.type),
              size: 17,
              color: activity.isRead
                  ? context.elixTextSecondary
                  : context.elixColors.brandSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body.copyWith(
                      color: context.elixTextPrimary,
                      fontWeight: activity.isRead
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    activity.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatElixrDateTime(activity.occurredAt),
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!activity.isRead)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 8, top: 5),
                decoration: BoxDecoration(
                  color: context.elixColors.brandSecondary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  static IconData _iconFor(TeacherActivityType type) => switch (type) {
    TeacherActivityType.joinRequest => FluentIcons.people_add,
    TeacherActivityType.newSubmission => FluentIcons.upload,
    TeacherActivityType.retryResubmission => FluentIcons.refresh,
    TeacherActivityType.message => FluentIcons.chat,
    TeacherActivityType.upcomingDeadline => FluentIcons.calendar,
    TeacherActivityType.movementCompleted => FluentIcons.completed,
  };
}

class _TeacherKpiGrid extends StatelessWidget {
  const _TeacherKpiGrid({
    required this.controller,
    required this.reviewCount,
    required this.activityLoading,
    required this.wide,
  });

  final TeacherDashboardController controller;
  final int reviewCount;
  final bool activityLoading;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _DashboardMetric(
        label: 'Work to review',
        value: activityLoading ? '—' : '$reviewCount',
        icon: FluentIcons.review_request_solid,
        tone: context.elixColors.brandPrimary,
        emphasis: true,
        onTap: () => context.go(AppRoutePaths.teacherToReview),
      ),
      _DashboardMetric(
        label: 'Pending requests',
        value: '${controller.pendingRequestCount}',
        icon: FluentIcons.people_add,
        tone: context.elixColors.warning,
        onTap: () => context.go(AppRoutePaths.teacherGroups),
      ),
      _DashboardMetric(
        label: 'Active classrooms',
        value: '${controller.activeGroupCount}',
        icon: FluentIcons.education,
        tone: context.elixColors.brandSecondary,
      ),
      _DashboardMetric(
        label: 'Students',
        value: '${controller.approvedStudentCount}',
        icon: FluentIcons.contact,
        tone: context.elixColors.success,
      ),
    ];
    return wide
        ? Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(child: _DashboardMetricCard(metric: metrics[index])),
                if (index < metrics.length - 1)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 470 ? 1 : 2;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * AppSpacing.sm) /
                  columns;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(metric: metric),
                    ),
                ],
              );
            },
          );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.emphasis = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final bool emphasis;
  final VoidCallback? onTap;
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final card = ElixPanelCard(
      accent: metric.tone,
      showAccentBar: metric.emphasis,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? Colors.transparent
                  : metric.tone.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(metric.icon, color: metric.tone, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value,
                  style: AppTheme.cardTitle(color: context.elixTextPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final onTap = metric.onTap;
    return onTap == null
        ? card
        : ElixHoverSurface(
            semanticLabel: '${metric.label}: ${metric.value}',
            borderRadius: 18,
            onTap: onTap,
            child: card,
          );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.controller,
    required this.analyticsController,
    required this.activityController,
    required this.gettingStarted,
    required this.wide,
  });

  final TeacherDashboardController controller;
  final TeacherAnalyticsController? analyticsController;
  final TeacherActivityController? activityController;
  final _GettingStartedModel? gettingStarted;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final groups = _WorkspaceSection(
      heading: 'Your classrooms',
      eyebrow: 'CLASSROOMS',
      subtitle: 'Manage students and class activity.',
      action: context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
          ? Button(
              onPressed: () => context.go(AppRoutePaths.teacherGroups),
              child: const Text('View classrooms'),
            )
          : shad.ShadButton.outline(
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
                for (final summary in controller.groupSummaries.take(3))
                  _GroupOverviewRow(summary: summary),
              ],
            ),
    );
    final main = Column(
      children: [
        if (gettingStarted != null) _GettingStartedCard(model: gettingStarted!),
        if (gettingStarted != null && controller.activeGroupCount > 0)
          const SizedBox(height: AppSpacing.md),
        if (analyticsController != null && controller.activeGroupCount > 0)
          TeacherAnalyticsSummary(controller: analyticsController!),
        if (analyticsController != null && controller.activeGroupCount > 0)
          const SizedBox(height: AppSpacing.md),
        if (controller.activeGroupCount > 0) groups,
      ],
    );
    final rail = Column(
      children: [
        _NeedsAttentionCard(
          controller: controller,
          activityController: activityController,
        ),
        const SizedBox(height: AppSpacing.md),
        _ActivityPreview(activityController: activityController),
      ],
    );
    if (!wide) {
      return Column(
        children: [
          rail,
          const SizedBox(height: AppSpacing.md),
          main,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: main),
        const SizedBox(width: AppSpacing.lg),
        Expanded(flex: 2, child: rail),
      ],
    );
  }
}

class _NeedsAttentionCard extends StatelessWidget {
  const _NeedsAttentionCard({
    required this.controller,
    required this.activityController,
  });

  final TeacherDashboardController controller;
  final TeacherActivityController? activityController;

  @override
  Widget build(BuildContext context) {
    final activityLoading = activityController?.loading ?? false;
    final reviewCount = activityController?.pendingReviewCount ?? 0;
    return _WorkspaceSection(
      heading: 'Needs attention',
      eyebrow: 'PRIORITY QUEUE',
      subtitle: activityLoading
          ? 'Loading the latest review activity.'
          : reviewCount > 0 || controller.pendingQueue.isNotEmpty
          ? 'Start with the work waiting on you.'
          : 'Nothing is waiting for a decision.',
      action: context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
          ? Button(
              onPressed: () => context.go(AppRoutePaths.teacherToReview),
              child: const Text('Review work'),
            )
          : shad.ShadButton.outline(
              onPressed: () => context.go(AppRoutePaths.teacherToReview),
              child: const Text('Review work'),
            ),
      child: Column(
        children: [
          if (activityLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: ProgressBar(),
            )
          else
            ElixHoverSurface(
              semanticLabel: '$reviewCount items of work to review',
              borderRadius: 14,
              onTap: () => context.go(AppRoutePaths.teacherToReview),
              child: ElixPanelCard(
                accent: context.elixColors.brandPrimary,
                showAccentBar: reviewCount > 0,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      reviewCount > 0
                          ? FluentIcons.review_request_solid
                          : FluentIcons.completed_solid,
                      color: reviewCount > 0
                          ? context.elixColors.brandPrimary
                          : context.elixColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        reviewCount == 0
                            ? 'Review queue is clear'
                            : '$reviewCount ${reviewCount == 1 ? 'submission is' : 'submissions are'} ready to review',
                        style: AppTheme.body.copyWith(
                          color: context.elixTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(FluentIcons.chevron_right, size: 12),
                  ],
                ),
              ),
            ),
          if (controller.pendingQueue.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final membership in controller.pendingQueue.take(2))
              _PendingRequestRow(membership: membership),
          ],
        ],
      ),
    );
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.activityController});

  final TeacherActivityController? activityController;

  @override
  Widget build(BuildContext context) {
    final controller = activityController;
    final loading = controller?.loading ?? false;
    final activities = controller?.activities.take(2).toList() ?? const [];
    return _WorkspaceSection(
      heading: 'Recent activity',
      eyebrow: 'NOTIFICATIONS',
      subtitle: loading
          ? 'Loading recent classroom activity.'
          : controller == null
          ? 'Activity will appear as classrooms become active.'
          : '${controller.unreadCount} unread notification${controller.unreadCount == 1 ? '' : 's'}',
      action: context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
          ? Button(
              onPressed: () => context.go(AppRoutePaths.teacherActivityCenter),
              child: const Text('View all'),
            )
          : shad.ShadButton.outline(
              onPressed: () => context.go(AppRoutePaths.teacherActivityCenter),
              child: const Text('View all'),
            ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: ProgressBar(),
            )
          : controller?.hasStreamError == true
          ? Row(
              children: [
                Icon(FluentIcons.warning, color: context.elixColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Activity could not be refreshed.',
                    style: AppTheme.supporting(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
              ],
            )
          : activities.isEmpty
          ? Text(
              'No new classroom activity yet.',
              style: AppTheme.supporting(color: context.elixTextSecondary),
            )
          : Column(
              children: [
                for (final activity in activities)
                  _ActivityPreviewRow(
                    activity: activity,
                    controller: controller!,
                  ),
              ],
            ),
    );
  }
}

class _ActivityPreviewRow extends StatelessWidget {
  const _ActivityPreviewRow({required this.activity, required this.controller});

  final TeacherActivity activity;
  final TeacherActivityController controller;

  @override
  Widget build(BuildContext context) {
    final actor = activity.actorDisplayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ElixHoverSurface(
        semanticLabel: activity.title,
        borderRadius: 12,
        onTap: () async {
          await controller.markRead(activity);
          if (context.mounted) context.push(activity.destination);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              actor == null
                  ? Icon(_activityIcon(activity.type), size: 18)
                  : ProfileAvatarWidget(
                      radius: 17,
                      showBorder: false,
                      initials: userInitials(actor),
                      networkImageUrl: activity.actorProfilePictureUrl,
                    ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextPrimary,
                        fontWeight: activity.isRead
                            ? FontWeight.w600
                            : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activity.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatElixrDateTime(activity.occurredAt),
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!activity.isRead)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5, left: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: context.elixColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _activityIcon(TeacherActivityType type) => switch (type) {
  TeacherActivityType.joinRequest => FluentIcons.people_add,
  TeacherActivityType.newSubmission => FluentIcons.upload,
  TeacherActivityType.retryResubmission => FluentIcons.refresh,
  TeacherActivityType.message => FluentIcons.chat,
  TeacherActivityType.upcomingDeadline => FluentIcons.calendar,
  TeacherActivityType.movementCompleted => FluentIcons.completed,
};

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
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final identity = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: context.elixColors.brandPrimary.withValues(
                      alpha: context.isHighContrast ? 0 : 0.14,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    FluentIcons.education,
                    size: 16,
                    color: context.elixColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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
            final action = Button(
              onPressed: () => context.go(AppRoutePaths.teacherGroups),
              child: const Text('Open classroom'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: AppSpacing.sm),
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

  /// Later workflow prompts already have dedicated dashboard destinations:
  /// review work belongs in Needs attention and assignments in Classrooms.
  /// Keep this compact helper limited to genuine first-time setup.
  bool get isEarlyOnboarding => switch (step) {
    _GettingStartedStep.createClassroom ||
    _GettingStartedStep.inviteStudents ||
    _GettingStartedStep.approveStudent => true,
    _ => false,
  };

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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model.title,
                style: AppTheme.cardTitle(color: context.elixTextPrimary),
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
