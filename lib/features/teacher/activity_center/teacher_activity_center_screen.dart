import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import 'teacher_activity_controller.dart';
import 'package:elixr_core/utils/user_name.dart';

class TeacherActivityCenterScreen extends StatefulWidget {
  const TeacherActivityCenterScreen({super.key});

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
    final visible = _unreadOnly
        ? controller.activities.where((activity) => !activity.isRead).toList()
        : controller.activities;

    return TeacherScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: 'Activity Center',
        eyebrow: 'TEACHER WORKSPACE',
        subtitle: 'Review what needs your attention across your classroom.',
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.check_mark),
              label: const Text('Mark all read'),
              onPressed: controller.unreadCount == 0
                  ? null
                  : controller.markAllRead,
            ),
          ],
        ),
      ),
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  checked: _unreadOnly,
                  onChanged: (value) {
                    setState(() => _unreadOnly = value ?? false);
                  },
                  content: const Text('Unread only'),
                ),
                if (controller.hasStreamError ||
                    controller.persistenceMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InfoBar(
                    severity: controller.hasStreamError
                        ? InfoBarSeverity.warning
                        : InfoBarSeverity.info,
                    title: Text(
                      controller.hasStreamError
                          ? 'Some activity could not be refreshed'
                          : 'Activity read state is temporary',
                    ),
                    content: Text(
                      controller.persistenceMessage ??
                          'Some activity may be missing. You can retry the stream.',
                    ),
                    action: controller.hasStreamError
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
          Expanded(
            child: controller.loading
                ? const Center(child: ProgressRing())
                : visible.isEmpty
                ? _EmptyActivityState(
                    unreadOnly: _unreadOnly,
                    isError: controller.hasStreamError,
                    onRetry: controller.retry,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _ActivityRow(
                      activity: visible[index],
                      onOpen: () async {
                        final activity = visible[index];
                        await controller.markRead(activity);
                        if (context.mounted) context.go(activity.destination);
                      },
                    ),
                  ),
          ),
        ],
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
    return Semantics(
      button: true,
      label: activity.title,
      child: HoverButton(
        onPressed: onOpen,
        builder: (context, states) => ElixPanelCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityLeadingVisual(activity: activity),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: AppTheme.body.copyWith(
                        color: context.elixTextPrimary,
                        fontWeight: activity.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
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
              if (!activity.isRead) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
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
    return Icon(
      _ActivityRow._iconFor(activity.type),
      color: activity.isRead ? context.elixTextSecondary : AppColors.accent,
    );
  }
}
