import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/elix_toast.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/assignment_review_state.dart';
import 'teacher_activity_controller.dart';

enum TeacherActivityCenterView { activity, toReview }

class TeacherActivityCenterScreen extends StatefulWidget {
  const TeacherActivityCenterScreen({
    super.key,
    this.initialView = TeacherActivityCenterView.activity,
  });

  final TeacherActivityCenterView initialView;

  @override
  State<TeacherActivityCenterScreen> createState() =>
      _TeacherActivityCenterScreenState();
}

class _TeacherActivityCenterScreenState
    extends State<TeacherActivityCenterScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TeacherActivityController>();
    final showPending =
        widget.initialView == TeacherActivityCenterView.toReview;
    final visible = _unreadOnly
        ? controller.activities.where((activity) => !activity.isRead).toList()
        : controller.activities;
    final relevantStreamError = showPending
        ? controller.hasPendingReviewStreamError
        : controller.hasStreamError;

    return TeacherScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: showPending ? 'Review Work' : 'Notifications',
        eyebrow: 'TEACHER WORKSPACE',
        subtitle: showPending
            ? 'Submitted work that still needs your review.'
            : 'Recent activity across your classrooms.',
        commandBar: null,
      ),
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    showPending
                        ? _ReviewQueueIntro(
                            count: controller.pendingReviewCount,
                          )
                        : _ActivityInboxToolbar(
                            loading: controller.loading,
                            unreadCount: controller.unreadCount,
                            unreadOnly: _unreadOnly,
                            onFilterChanged: () =>
                                setState(() => _unreadOnly = !_unreadOnly),
                            onMarkAllRead: controller.unreadCount == 0
                                ? null
                                : () async {
                                    final saved = await controller
                                        .markAllRead();
                                    if (saved && context.mounted) {
                                      ElixToast.showSuccess(
                                        context,
                                        message: 'Marked all activity as read.',
                                      );
                                    }
                                  },
                          ),
                    if (relevantStreamError ||
                        controller.persistenceMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      InfoBar(
                        severity: relevantStreamError
                            ? InfoBarSeverity.warning
                            : InfoBarSeverity.info,
                        title: Text(
                          relevantStreamError
                              ? showPending
                                    ? 'Pending work could not be refreshed'
                                    : 'Some activity could not be refreshed'
                              : 'Activity read state is temporary',
                        ),
                        content: Text(
                          controller.persistenceMessage ??
                              'Some information may be missing. Try refreshing.',
                        ),
                        action: relevantStreamError
                            ? Button(
                                onPressed: controller.retry,
                                child: const Text('Retry'),
                              )
                            : null,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: controller.loading
                ? const Center(child: ProgressRing())
                : showPending
                ? _PendingReviewList(controller: controller)
                : visible.isEmpty
                ? _EmptyActivityState(
                    unreadOnly: _unreadOnly,
                    isError: controller.hasStreamError,
                    onRetry: controller.retry,
                  )
                : _CenteredActivityList(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _ActivityRow(
                      activity: visible[index],
                      onOpen: () async {
                        final activity = visible[index];
                        await controller.markRead(activity);
                        if (context.mounted) context.push(activity.destination);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityInboxToolbar extends StatelessWidget {
  const _ActivityInboxToolbar({
    required this.loading,
    required this.unreadCount,
    required this.unreadOnly,
    required this.onFilterChanged,
    required this.onMarkAllRead,
  });

  final bool loading;
  final int unreadCount;
  final bool unreadOnly;
  final VoidCallback onFilterChanged;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      accent: context.elixColors.brandSecondary,
      showAccentBar: !loading && unreadCount > 0,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final summary = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                loading
                    ? FluentIcons.sync
                    : unreadCount > 0
                    ? FluentIcons.circle_ring
                    : FluentIcons.completed_solid,
                color: loading || unreadCount > 0
                    ? context.elixColors.brandSecondary
                    : context.elixColors.success,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  loading
                      ? 'Loading classroom activity'
                      : unreadCount == 0
                      ? 'No unread notifications'
                      : '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Button(
                key: const Key('teacher_activity_unread_filter'),
                onPressed: loading ? null : onFilterChanged,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      unreadOnly
                          ? FluentIcons.filter_solid
                          : FluentIcons.filter,
                      size: 14,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(unreadOnly ? 'Unread only' : 'All activity'),
                  ],
                ),
              ),
              FilledButton(
                key: const Key('teacher_activity_mark_all_read'),
                onPressed: loading ? null : onMarkAllRead,
                child: const Text('Mark all read'),
              ),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: AppSpacing.md),
                    actions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: AppSpacing.md),
                    actions,
                  ],
                );
        },
      ),
    );
  }
}

class _ReviewQueueIntro extends StatelessWidget {
  const _ReviewQueueIntro({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => ElixPanelCard(
    accent: context.elixColors.brandPrimary,
    showAccentBar: count > 0,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      children: [
        Icon(
          FluentIcons.review_request_solid,
          color: context.elixColors.brandPrimary,
          size: 20,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            count == 0
                ? 'Your review queue is clear'
                : '$count submission${count == 1 ? '' : 's'} need${count == 1 ? 's' : ''} your review',
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CenteredActivityList extends StatelessWidget {
  const _CenteredActivityList({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    itemCount: itemCount,
    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
    itemBuilder: (context, index) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: itemBuilder(context, index),
      ),
    ),
  );
}

class _PendingReviewList extends StatelessWidget {
  const _PendingReviewList({required this.controller});

  final TeacherActivityController controller;

  @override
  Widget build(BuildContext context) {
    final reviews = controller.pendingReviews;
    if (reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          key: const Key('teacher_to_review_empty'),
          isError: controller.hasPendingReviewStreamError,
          icon: controller.hasPendingReviewStreamError
              ? FluentIcons.error
              : FluentIcons.completed,
          title: controller.hasPendingReviewStreamError
              ? 'Pending work could not be loaded'
              : 'No submissions are waiting for review',
          message: controller.hasPendingReviewStreamError
              ? 'Try again to refresh outstanding submissions.'
              : 'New submitted work will appear here automatically.',
          actionLabel: controller.hasPendingReviewStreamError ? 'Retry' : null,
          onAction: controller.hasPendingReviewStreamError
              ? controller.retry
              : null,
        ),
      );
    }
    return ListView.separated(
      key: const Key('teacher_to_review_list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: reviews.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _PendingReviewRow(
        review: reviews[index],
        onOpen: () => context.push(reviews[index].destination),
      ),
    );
  }
}

class _PendingReviewRow extends StatelessWidget {
  const _PendingReviewRow({required this.review, required this.onOpen});

  final TeacherPendingReview review;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final deadline = switch (review.deadlineState) {
      AssignmentDeadlineState.submittedOnTime => 'On time',
      AssignmentDeadlineState.submittedLate => 'Late',
      _ => null,
    };
    return Semantics(
      button: true,
      label:
          '${review.traineeName}, ${review.assignment.displayTitle}, To Review',
      child: HoverButton(
        key: Key('teacher_to_review_${review.attempt.id}'),
        cursor: SystemMouseCursors.click,
        onPressed: onOpen,
        builder: (context, states) => ElixPanelCard(
          child: Row(
            children: [
              ExcludeSemantics(
                child: ProfileAvatarWidget(
                  key: Key(
                    'teacher_to_review_avatar_${review.attempt.traineeId}',
                  ),
                  radius: 22,
                  showBorder: false,
                  initials: userInitials(review.traineeName),
                  networkImageUrl: review.traineeProfilePictureUrl,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.traineeName,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      review.assignment.displayTitle,
                      style: AppTheme.body.copyWith(
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${review.assignment.groupName} · Submitted ${formatElixrDateTime(review.submittedAt)}'
                      '${deadline == null ? '' : ' · $deadline'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'To Review',
                style: AppTheme.caption.copyWith(
                  color: deadline == 'Late'
                      ? context.elixColors.warning
                      : context.elixColors.brandPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(FluentIcons.chevron_right, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState({
    required this.unreadOnly,
    required this.isError,
    required this.onRetry,
  });

  final bool unreadOnly;
  final bool isError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          isError: true,
          message: 'Activity could not be loaded.',
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ElixStatusPanel(
        icon: unreadOnly ? FluentIcons.check_mark : FluentIcons.activity_feed,
        title: unreadOnly ? 'You are all caught up' : 'No recent activity',
        message: unreadOnly
            ? 'New classroom activity will appear here when it arrives.'
            : 'Recent join requests, submissions, messages, deadlines, and completed work will appear here.',
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.onOpen});

  final TeacherActivity activity;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ElixHoverSurface(
      semanticLabel:
          '${activity.isRead ? 'Read' : 'Unread'} notification: ${activity.title}',
      borderRadius: 18,
      onTap: onOpen,
      child: ElixPanelCard(
        accent: context.elixColors.brandSecondary,
        showAccentBar: !activity.isRead,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActivityLeadingVisual(activity: activity),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          activity.title,
                          style: AppTheme.body.copyWith(
                            color: context.elixTextPrimary,
                            fontWeight: activity.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!activity.isRead) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ElixPill(
                          text: 'Unread',
                          color: context.elixColors.brandSecondary,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatElixrDateTime(activity.occurredAt),
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(FluentIcons.chevron_right, size: 12),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(TeacherActivityType type) => switch (type) {
    TeacherActivityType.joinRequest => FluentIcons.people_add,
    TeacherActivityType.newSubmission => FluentIcons.upload,
    TeacherActivityType.retryResubmission => FluentIcons.refresh,
    TeacherActivityType.message => FluentIcons.chat,
    TeacherActivityType.upcomingDeadline => FluentIcons.calendar,
    TeacherActivityType.movementCompleted => FluentIcons.completed,
  };
}

class _ActivityLeadingVisual extends StatelessWidget {
  const _ActivityLeadingVisual({required this.activity});

  final TeacherActivity activity;

  @override
  Widget build(BuildContext context) {
    final actorName = activity.actorDisplayName;
    if (actorName != null) {
      return ExcludeSemantics(
        child: ProfileAvatarWidget(
          key: Key('teacher_activity_avatar_${activity.id}'),
          radius: 20,
          showBorder: false,
          initials: userInitials(actorName),
          networkImageUrl: activity.actorProfilePictureUrl,
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? Colors.transparent
            : (activity.isRead
                  ? context.elixColors.surfaceInteractive
                  : context.elixColors.brandSecondary.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _ActivityRow._iconFor(activity.type),
        color: activity.isRead
            ? context.elixTextSecondary
            : context.elixColors.brandSecondary,
        size: 18,
      ),
    );
  }
}
