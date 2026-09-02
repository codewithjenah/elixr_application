import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_scaffold_page.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/elix_toast.dart';
import 'trainee_activity_controller.dart';

class TraineeActivityCenterScreen extends StatefulWidget {
  const TraineeActivityCenterScreen({super.key});

  @override
  State<TraineeActivityCenterScreen> createState() =>
      _TraineeActivityCenterScreenState();
}

class _TraineeActivityCenterScreenState
    extends State<TraineeActivityCenterScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TraineeActivityController>();
    final visible = _unreadOnly
        ? controller.activities.where((activity) => !activity.isRead).toList()
        : controller.activities;
    return ElixScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: 'Activity Center',
        eyebrow: 'TRAINEE WORKSPACE',
        subtitle: 'Assignments, deadlines, grades, and classroom updates.',
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.check_mark),
              label: const Text('Mark all read'),
              onPressed: controller.unreadCount == 0
                  ? null
                  : () => _markAllRead(controller),
            ),
          ],
        ),
      ),
      padding: EdgeInsets.zero,
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
                          : 'Read status is temporary',
                    ),
                    content: Text(
                      controller.persistenceMessage ??
                          'Some classroom updates may be missing. Try again.',
                    ),
                    action: controller.hasStreamError
                        ? Button(
                            onPressed: controller.retry,
                            child: const Text('Try again'),
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
                ? _EmptyState(
                    unreadOnly: _unreadOnly,
                    hasError: controller.hasStreamError,
                    onRetry: controller.retry,
                  )
                : ListView.separated(
                    key: const Key('trainee_activity_list'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final activity = visible[index];
                      return _ActivityRow(
                        activity: activity,
                        onOpen: () async {
                          await controller.markRead(activity);
                          if (context.mounted) {
                            context.push(activity.destination);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead(TraineeActivityController controller) async {
    final saved = await controller.markAllRead();
    if (saved && mounted) {
      ElixToast.showSuccess(context, message: 'Marked all activity as read.');
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.unreadOnly,
    required this.hasError,
    required this.onRetry,
  });

  final bool unreadOnly;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          isError: true,
          message: 'Activity could not be loaded.',
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ElixStatusPanel(
        key: const Key('trainee_activity_empty'),
        icon: unreadOnly ? FluentIcons.check_mark : FluentIcons.activity_feed,
        title: "You're caught up.",
        message: unreadOnly
            ? 'There are no unread updates.'
            : 'New assignments, grades, and classroom updates will appear here.',
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.onOpen});

  final TraineeActivity activity;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: activity.title,
      child: HoverButton(
        key: Key('trainee_activity_${activity.id}'),
        cursor: SystemMouseCursors.click,
        onPressed: onOpen,
        builder: (context, states) => ElixPanelCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon(activity.type),
                color: activity.isRead
                    ? context.elixTextSecondary
                    : AppColors.accent,
              ),
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
                  decoration: const BoxDecoration(
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

  static IconData _icon(TraineeActivityType type) => switch (type) {
    TraineeActivityType.newAssignment => FluentIcons.task_list,
    TraineeActivityType.dueSoon => FluentIcons.calendar,
    TraineeActivityType.overdue => FluentIcons.warning,
    TraineeActivityType.newAnnouncement => FluentIcons.megaphone,
    TraineeActivityType.pinnedAnnouncement => FluentIcons.pinned,
    TraineeActivityType.submissionChecked => FluentIcons.completed,
    TraineeActivityType.workReturned => FluentIcons.refresh,
    TraineeActivityType.joinApproved => FluentIcons.people_add,
  };
}
