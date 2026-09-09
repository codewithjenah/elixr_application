import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/message_unread_badge.dart';
import '../../trainee/activity_center/trainee_activity_controller.dart';

/// Welcome and quick-navigation chrome above the trainee dashboard.
class DashboardHeader extends StatefulWidget {
  const DashboardHeader({
    super.key,
    required this.firstName,
    required this.greeting,
  });

  final String firstName;
  final String greeting;

  @override
  State<DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<DashboardHeader> {
  final _notificationsFlyout = FlyoutController();

  @override
  void dispose() {
    _notificationsFlyout.dispose();
    super.dispose();
  }

  void _showNotifications() {
    _notificationsFlyout.showFlyout<void>(
      placementMode: FlyoutPlacementMode.bottomRight,
      additionalOffset: AppSpacing.sm,
      builder: (flyoutContext) => _NotificationsFlyout(
        onOpen: (activity) async {
          Flyout.of(flyoutContext).close();
          final controller = context.read<TraineeActivityController?>();
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
        context.watch<TraineeActivityController?>()?.unreadCount ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The header slogan is a persistent piece of dashboard chrome. Text
        // yields space before it does, so sidebar state never makes the slogan
        // disappear.
        const showSlogan = true;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.greeting}, ${widget.firstName} 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sectionTitle(
                      context,
                      color: context.elixTextPrimary,
                    ).copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Keep going. Every pour builds a better you.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.supporting(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FlyoutTarget(
              controller: _notificationsFlyout,
              child: _HeaderIconButton(
                key: const ValueKey('dashboard-header-notifications'),
                icon: FluentIcons.ringer,
                tooltip: unreadCount == 0
                    ? 'Notifications'
                    : 'Notifications, $unreadCount unread',
                unreadCount: unreadCount,
                onPressed: _showNotifications,
              ),
            ),
            if (showSlogan && !context.isHighContrast) ...[
              const SizedBox(width: 18),
              const _HeaderSlogan(),
            ],
          ],
        );
      },
    );
  }
}

/// Compact activity panel intentionally anchored to the dashboard bell, so
/// trainees can inspect notifications without leaving their current work.
class _NotificationsFlyout extends StatelessWidget {
  const _NotificationsFlyout({required this.onOpen});

  static const _maxItems = 5;

  final Future<void> Function(TraineeActivity activity) onOpen;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TraineeActivityController?>();
    final activities =
        controller?.activities.take(_maxItems).toList() ?? const [];
    return FlyoutContent(
      key: const ValueKey('dashboard-notifications-flyout'),
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
                        'dashboard-notification-unread-count',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${controller!.unreadCount} new',
                        style: AppTheme.caption.copyWith(
                          color: AppColors.accent,
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
                  ? _NotificationsEmptyState(
                      hasError: controller.hasStreamError,
                    )
                  : ListView.separated(
                      key: const ValueKey('dashboard-notifications-list'),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: activities.length,
                      separatorBuilder: (_, _) => Divider(
                        style: DividerThemeData(
                          thickness: 1,
                          decoration: BoxDecoration(color: context.elixBorder),
                        ),
                      ),
                      itemBuilder: (context, index) => _NotificationPreview(
                        activity: activities[index],
                        onPressed: () => unawaited(onOpen(activities[index])),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState({required this.hasError});

  final bool hasError;

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
      ],
    ),
  );
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.activity, required this.onPressed});

  final TraineeActivity activity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HoverButton(
    key: Key('dashboard_notification_${activity.id}'),
    onPressed: onPressed,
    builder: (context, states) => Container(
      color: states.isHovered
          ? context.elixPanelSurface
          : activity.isRead
          ? Colors.transparent
          : AppColors.accent.withValues(alpha: 0.07),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(activity.type), size: 17, color: AppColors.accent),
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
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    ),
  );

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

class _HeaderSlogan extends StatelessWidget {
  const _HeaderSlogan();

  @override
  Widget build(BuildContext context) {
    // Keep the tall three-line artwork contained in the compact header slot.
    final artwork = Image.asset(
      'assets/slogan_1.png',
      key: const ValueKey('dashboard-header-slogan'),
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    return Semantics(
      image: true,
      label: 'Skills pour further',
      child: SizedBox(width: 92, height: 76, child: artwork),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.unreadCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int unreadCount;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : isDark
                    ? const Color(
                        0xFF171424,
                      ).withValues(alpha: _hovered ? 0.96 : 0.82)
                    : context.elixCardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highContrast
                      ? context.elixBorder
                      : isDark
                      ? AppColors.accent.withValues(
                          alpha: _hovered ? 0.42 : 0.20,
                        )
                      : context.elixBorder,
                  width: highContrast ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  if (widget.unreadCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: MessageUnreadBadge(
                            key: const ValueKey(
                              'dashboard-header-notification-unread-badge',
                            ),
                            count: widget.unreadCount,
                            compact: true,
                            semanticLabel:
                                '${widget.unreadCount} unread notifications',
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
