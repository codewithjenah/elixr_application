import 'package:elixr_core/models/classroom_announcement.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/elix_toast.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/group_assignment.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'classroom_announcements_controller.dart';

class ClassroomAnnouncementsPane extends StatelessWidget {
  const ClassroomAnnouncementsPane({
    super.key,
    required this.controller,
    required this.teacherDisplayName,
    required this.canManage,
    required this.groupIsActive,
    this.teacherProfilePictureUrl,
    this.assignments = const [],
    this.onOpenAssignment,
  });

  final ClassroomAnnouncementsController controller;
  final String teacherDisplayName;
  final bool canManage;
  final bool groupIsActive;
  final String? teacherProfilePictureUrl;
  final List<GroupAssignment> assignments;
  final ValueChanged<GroupAssignment>? onOpenAssignment;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const Center(child: ProgressRing());
    final pinned = controller.items.where((item) => item.isPinned).toList();
    final chronological = controller.items
        .where((item) => !item.isPinned)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Stream',
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            if (canManage)
              ElixPrimaryButton(
                key: const Key('classroom_announcements_new'),
                onPressed: controller.busy || !groupIsActive
                    ? null
                    : () => _showEditor(context, controller),
                label: 'New announcement',
                icon: FluentIcons.add,
                expanded: false,
                dense: true,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          canManage
              ? (groupIsActive
                    ? 'Share an update with every student currently in this class.'
                    : 'This classroom is archived. Existing announcements remain available.')
              : 'Updates from $teacherDisplayName will appear here.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          ElixStatusPanel(message: controller.errorMessage!, isError: true),
        ],
        const SizedBox(height: AppSpacing.lg),
        for (final announcement in pinned) ...[
          _AnnouncementCard(
            announcement: announcement,
            teacherDisplayName: teacherDisplayName,
            teacherProfilePictureUrl: teacherProfilePictureUrl,
            canManage: canManage,
            groupIsActive: groupIsActive,
            busy: controller.busy,
            onPinToggle: () => _togglePin(context, announcement, controller),
            onEdit: () =>
                _showEditor(context, controller, announcement: announcement),
            onDelete: () => _confirmDelete(context, announcement, controller),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (assignments.isNotEmpty) ...[
          for (final assignment in assignments.take(5)) ...[
            _AssignmentStreamCard(
              assignment: assignment,
              teacherDisplayName: teacherDisplayName,
              onOpen: onOpenAssignment == null
                  ? null
                  : () => onOpenAssignment!(assignment),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (controller.items.isEmpty && assignments.isEmpty)
          const ElixStatusPanel(
            key: Key('classroom_announcements_empty'),
            icon: FluentIcons.megaphone,
            title: 'No announcements yet',
            message: 'New classroom updates will appear here.',
          )
        else ...[
          for (var index = 0; index < chronological.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            _AnnouncementCard(
              announcement: chronological[index],
              teacherDisplayName: teacherDisplayName,
              teacherProfilePictureUrl: teacherProfilePictureUrl,
              canManage: canManage,
              groupIsActive: groupIsActive,
              busy: controller.busy,
              onPinToggle: () =>
                  _togglePin(context, chronological[index], controller),
              onEdit: () => _showEditor(
                context,
                controller,
                announcement: chronological[index],
              ),
              onDelete: () =>
                  _confirmDelete(context, chronological[index], controller),
            ),
          ],
          if (controller.hasMore) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.center,
              child: _AnnouncementOutlineButton(
                key: const Key('classroom_announcements_load_more'),
                onPressed: controller.loadingMore ? null : controller.loadMore,
                child: controller.loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(),
                      )
                    : const Text('Load older'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _AssignmentStreamCard extends StatelessWidget {
  const _AssignmentStreamCard({
    required this.assignment,
    required this.teacherDisplayName,
    this.onOpen,
  });

  final GroupAssignment assignment;
  final String teacherDisplayName;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final card = ElixPanelCard(
      accent: AppColors.primary,
      showAccentBar: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(FluentIcons.task_list, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$teacherDisplayName posted a new assignment',
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  assignment.displayTitle,
                  style: AppTheme.headingMedium.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  assignment.dueAt == null
                      ? 'Assigned'
                      : 'Due ${formatElixrDate(assignment.dueAt!)}',
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
    if (onOpen == null) return card;
    return ElixHoverSurface(
      onTap: onOpen!,
      semanticLabel: 'Open assignment ${assignment.displayTitle}',
      child: card,
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.teacherDisplayName,
    this.teacherProfilePictureUrl,
    required this.canManage,
    required this.groupIsActive,
    required this.busy,
    required this.onPinToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ClassroomAnnouncement announcement;
  final String teacherDisplayName;
  final String? teacherProfilePictureUrl;
  final bool canManage;
  final bool groupIsActive;
  final bool busy;
  final VoidCallback onPinToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ElixPanelCard(
    accent: announcement.isPinned ? AppColors.accent : null,
    showAccentBar: announcement.isPinned,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    announcement.title,
                    style: AppTheme.headingMedium.copyWith(
                      fontSize: 18,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  if (announcement.isPinned)
                    ElixPill(
                      text: 'Pinned',
                      key: Key(
                        'classroom_announcement_pinned_${announcement.id}',
                      ),
                      color: AppColors.accent,
                      compact: true,
                    ),
                  if (canManage &&
                      !announcement.isPublishedAt(DateTime.now().toUtc()))
                    ElixPill(
                      text:
                          'Scheduled ${_formatManilaDateTime(announcement.publishAt!)}',
                      color: AppColors.primary,
                      compact: true,
                    ),
                ],
              ),
            ),
            if (canManage)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  _AnnouncementIconAction(
                    key: Key('classroom_announcement_pin_${announcement.id}'),
                    onPressed:
                        busy ||
                            !groupIsActive ||
                            !announcement.isPublishedAt(DateTime.now().toUtc())
                        ? null
                        : onPinToggle,
                    icon: announcement.isPinned
                        ? FluentIcons.pinned_solid
                        : FluentIcons.pinned,
                    tooltip: announcement.isPinned
                        ? 'Unpin announcement'
                        : 'Pin announcement',
                  ),
                  _AnnouncementIconAction(
                    key: Key('classroom_announcement_edit_${announcement.id}'),
                    onPressed: busy || !groupIsActive ? null : onEdit,
                    icon: FluentIcons.edit,
                    tooltip: 'Edit announcement',
                  ),
                  _AnnouncementIconAction(
                    key: Key(
                      'classroom_announcement_delete_${announcement.id}',
                    ),
                    onPressed: busy ? null : onDelete,
                    icon: FluentIcons.delete,
                    tooltip: 'Delete announcement',
                    destructive: true,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            ProfileAvatarWidget(
              key: Key(
                'classroom_announcement_author_avatar_${announcement.id}',
              ),
              radius: 16,
              showBorder: false,
              initials: userInitials(teacherDisplayName),
              networkImageUrl: teacherProfilePictureUrl,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _metadata(announcement, teacherDisplayName),
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableText(
          announcement.body,
          style: AppTheme.body.copyWith(
            color: context.elixTextPrimary,
            height: 1.45,
          ),
        ),
      ],
    ),
  );

  static String _metadata(
    ClassroomAnnouncement announcement,
    String teacherDisplayName,
  ) {
    final created = announcement.createdAt?.toLocal();
    final stamp = created == null ? 'Just now' : formatElixrDateTime(created);
    return announcement.isEdited
        ? '$teacherDisplayName · $stamp · Edited'
        : '$teacherDisplayName · $stamp';
  }
}

Future<void> _togglePin(
  BuildContext context,
  ClassroomAnnouncement announcement,
  ClassroomAnnouncementsController controller,
) async {
  final success = announcement.isPinned
      ? await controller.unpin(announcement)
      : await controller.pin(announcement);
  if (!success || !context.mounted) return;
  final message = controller.consumeActionMessage();
  if (message != null) ElixToast.showSuccess(context, message: message);
}

Future<void> _showEditor(
  BuildContext context,
  ClassroomAnnouncementsController controller, {
  ClassroomAnnouncement? announcement,
}) async {
  final titleController = TextEditingController(
    text: announcement?.title ?? '',
  );
  final bodyController = TextEditingController(text: announcement?.body ?? '');
  // Once the scheduled instant has passed it is a normal published item.
  // Keeping scheduling enabled here would force the old, now-past timestamp
  // through the future-only write contract.
  var schedule =
      announcement?.publishAt?.toUtc().isAfter(DateTime.now().toUtc()) ?? false;
  final initialManila = (announcement?.publishAt ?? DateTime.now().toUtc())
      .toUtc()
      .add(const Duration(hours: 8));
  var publishDate = DateTime(
    initialManila.year,
    initialManila.month,
    initialManila.day,
  );
  var publishHour = announcement == null ? 9 : initialManila.hour;
  var publishMinute = announcement == null ? 0 : initialManila.minute;
  String? validationMessage;
  final result = await showDialog<_AnnouncementDraft>(
    context: context,
    builder: (dialogContext) => ElixShadThemeBridge(
      child: StatefulBuilder(
        builder: (context, setDialogState) => ElixDialog(
          title: announcement == null
              ? 'New announcement'
              : 'Edit announcement',
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
          // Keep the field area independently scrollable at large text scales
          // and on short desktop windows without nesting ElixDialog's flexible
          // Shad viewport.
          scrollableContent: false,
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .52,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Title',
                    style: AppTheme.label(color: context.elixTextPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _AnnouncementInput(
                    key: const Key('classroom_announcement_title'),
                    controller: titleController,
                    placeholder: 'Title',
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _AnnouncementCheckbox(
                    value: schedule,
                    onChanged: (value) =>
                        setDialogState(() => schedule = value),
                  ),
                  if (schedule) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _AnnouncementDatePicker(
                      selected: publishDate,
                      onChanged: (value) => setDialogState(() {
                        publishDate = value;
                      }),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Publication time',
                      style: AppTheme.label(color: context.elixTextPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manila time',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        SizedBox(
                          width: 116,
                          child: _AnnouncementSelect<int>(
                            key: const Key(
                              'classroom_announcement_publish_hour',
                            ),
                            value: _to12Hour(publishHour),
                            values: [
                              for (var value = 1; value <= 12; value++) value,
                            ],
                            label: (value) => value.toString(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(
                                  () => publishHour = _from12Hour(
                                    value,
                                    _periodForHour(publishHour),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 130,
                          child: _AnnouncementSelect<int>(
                            key: const Key(
                              'classroom_announcement_publish_minute',
                            ),
                            value: publishMinute,
                            values: const [0, 15, 30, 45],
                            label: (value) => value.toString().padLeft(2, '0'),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => publishMinute = value);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: _AnnouncementSelect<String>(
                            key: const Key(
                              'classroom_announcement_publish_period',
                            ),
                            value: _periodForHour(publishHour),
                            values: const ['AM', 'PM'],
                            label: (value) => value,
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(
                                  () => publishHour = _from12Hour(
                                    _to12Hour(publishHour),
                                    value,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Announcement',
                    style: AppTheme.label(color: context.elixTextPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _AnnouncementTextarea(
                    key: const Key('classroom_announcement_body'),
                    controller: bodyController,
                    placeholder: 'Write your announcement',
                    minLines: 5,
                    maxLines: 8,
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      validationMessage!,
                      style: AppTheme.caption.copyWith(color: AppColors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            _AnnouncementOutlineButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElixPrimaryButton(
              key: const Key('classroom_announcement_save'),
              label: schedule
                  ? 'Schedule'
                  : (announcement == null ? 'Publish' : 'Save changes'),
              expanded: false,
              onPressed: () {
                final titleError = ClassroomAnnouncement.validateTitle(
                  titleController.text,
                );
                final bodyError = ClassroomAnnouncement.validateBody(
                  bodyController.text,
                );
                if (titleError != null || bodyError != null) {
                  setDialogState(
                    () => validationMessage = titleError ?? bodyError,
                  );
                  return;
                }
                final publishAt = DateTime.utc(
                  publishDate.year,
                  publishDate.month,
                  publishDate.day,
                  publishHour - 8,
                  publishMinute,
                );
                if (schedule && !publishAt.isAfter(DateTime.now().toUtc())) {
                  setDialogState(
                    () => validationMessage =
                        'Choose a future Manila publication date and time.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _AnnouncementDraft(
                    title: titleController.text,
                    body: bodyController.text,
                    publishAt: schedule ? publishAt : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  titleController.dispose();
  bodyController.dispose();
  if (result == null) return;
  final success = announcement == null
      ? await controller.create(
          title: result.title,
          body: result.body,
          publishAt: result.publishAt,
        )
      : await controller.update(
          announcement,
          title: result.title,
          body: result.body,
          publishAt: result.publishAt,
        );
  if (!success || !context.mounted) return;
  final message = controller.consumeActionMessage();
  if (message != null) ElixToast.showSuccess(context, message: message);
}

String _formatManilaDateTime(DateTime utc) => DateFormat(
  'MMM d, y · h:mm a',
).format(utc.toUtc().add(const Duration(hours: 8)));

int _to12Hour(int hour) => hour % 12 == 0 ? 12 : hour % 12;

String _periodForHour(int hour) => hour < 12 ? 'AM' : 'PM';

int _from12Hour(int hour, String period) {
  final normalized = hour == 12 ? 0 : hour;
  return period == 'PM' ? normalized + 12 : normalized;
}

class _AnnouncementOutlineButton extends StatelessWidget {
  const _AnnouncementOutlineButton({
    super.key,
    this.onPressed,
    required this.child,
  });
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? Button(onPressed: onPressed, child: child)
      : shad.ShadButton.outline(
          onPressed: onPressed,
          enabled: onPressed != null,
          child: child,
        );
}

class _AnnouncementDestructiveButton extends StatelessWidget {
  const _AnnouncementDestructiveButton({
    super.key,
    this.onPressed,
    required this.child,
  });
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? FilledButton(onPressed: onPressed, child: child)
      : shad.ShadButton.destructive(
          onPressed: onPressed,
          enabled: onPressed != null,
          child: child,
        );
}

class _AnnouncementIconAction extends StatelessWidget {
  const _AnnouncementIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.destructive = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final button =
        context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
        ? IconButton(
            icon: Icon(
              icon,
              color: destructive ? context.elixColors.error : null,
            ),
            onPressed: onPressed,
          )
        : shad.ShadIconButton.ghost(
            icon: Icon(
              icon,
              color: destructive ? context.elixColors.error : null,
            ),
            onPressed: onPressed,
            enabled: onPressed != null,
          );
    return shad.ShadTheme.maybeOf(context) == null
        ? Tooltip(message: tooltip, child: button)
        : shad.ShadTooltip(builder: (_) => Text(tooltip), child: button);
  }
}

class _AnnouncementInput extends StatelessWidget {
  const _AnnouncementInput({
    super.key,
    required this.controller,
    this.placeholder,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String? placeholder;
  final bool autofocus;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? TextBox(
          controller: controller,
          placeholder: placeholder,
          autofocus: autofocus,
        )
      : shad.ShadInput(
          controller: controller,
          placeholder: placeholder == null ? null : Text(placeholder!),
          autofocus: autofocus,
        );
}

class _AnnouncementTextarea extends StatelessWidget {
  const _AnnouncementTextarea({
    super.key,
    required this.controller,
    this.placeholder,
    this.minLines = 5,
    this.maxLines = 8,
  });
  final TextEditingController controller;
  final String? placeholder;
  final int minLines;
  final int maxLines;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? TextBox(
          controller: controller,
          placeholder: placeholder,
          minLines: minLines,
          maxLines: maxLines,
        )
      : shad.ShadTextarea(
          controller: controller,
          placeholder: placeholder == null ? null : Text(placeholder!),
          minHeight: 120,
          maxHeight: 190,
          resizable: false,
        );
}

class _AnnouncementCheckbox extends StatelessWidget {
  const _AnnouncementCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? Checkbox(
          checked: value,
          content: const Text('Schedule for later'),
          onChanged: (value) => onChanged(value ?? false),
        )
      : shad.ShadCheckbox(
          value: value,
          label: const Text('Schedule for later'),
          onChanged: onChanged,
        );
}

class _AnnouncementDatePicker extends StatelessWidget {
  const _AnnouncementDatePicker({
    required this.selected,
    required this.onChanged,
  });
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? DatePicker(selected: selected, onChanged: onChanged)
      : shad.ShadDatePicker(
          selected: selected,
          formatDate: (date) => DateFormat('MMM d, y').format(date),
          onChanged: (date) {
            if (date != null) onChanged(date);
          },
        );
}

class _AnnouncementSelect<T> extends StatelessWidget {
  const _AnnouncementSelect({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) =>
      context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
      ? ComboBox<T>(
          value: value,
          items: [
            for (final item in values)
              ComboBoxItem(value: item, child: Text(label(item))),
          ],
          onChanged: onChanged,
        )
      : shad.ShadSelect<T>(
          initialValue: value,
          options: [
            for (final item in values)
              shad.ShadOption(value: item, child: Text(label(item))),
          ],
          selectedOptionBuilder: (context, item) => Text(label(item)),
          onChanged: onChanged,
        );
}

Future<void> _confirmDelete(
  BuildContext context,
  ClassroomAnnouncement announcement,
  ClassroomAnnouncementsController controller,
) async {
  final accepted = await ElixDialog.show<bool>(
    context,
    title: 'Delete announcement?',
    maxWidth: 440,
    content: const Text(
      'This announcement will be removed for the whole class.',
    ),
    actions: [
      _AnnouncementOutlineButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        child: const Text('Cancel'),
      ),
      _AnnouncementDestructiveButton(
        key: const Key('classroom_announcement_confirm_delete'),
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        child: const Text('Delete'),
      ),
    ],
  );
  if (accepted != true) return;
  final success = await controller.delete(announcement);
  if (!success || !context.mounted) return;
  final message = controller.consumeActionMessage();
  if (message != null) ElixToast.showSuccess(context, message: message);
}

class _AnnouncementDraft {
  const _AnnouncementDraft({
    required this.title,
    required this.body,
    this.publishAt,
  });

  final String title;
  final String body;
  final DateTime? publishAt;
}
