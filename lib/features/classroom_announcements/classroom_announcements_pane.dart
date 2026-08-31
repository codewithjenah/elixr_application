import 'package:elixr_core/models/classroom_announcement.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_status_panel.dart';
import 'classroom_announcements_controller.dart';

class ClassroomAnnouncementsPane extends StatelessWidget {
  const ClassroomAnnouncementsPane({
    super.key,
    required this.controller,
    required this.teacherDisplayName,
    required this.canManage,
    required this.groupIsActive,
  });

  final ClassroomAnnouncementsController controller;
  final String teacherDisplayName;
  final bool canManage;
  final bool groupIsActive;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const Center(child: ProgressRing());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Class announcements',
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            if (canManage)
              FilledButton(
                key: const Key('classroom_announcements_new'),
                onPressed: controller.busy || !groupIsActive
                    ? null
                    : () => _showEditor(context, controller),
                child: const Text('New announcement'),
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
        if (controller.actionMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          ElixStatusPanel(message: controller.actionMessage!),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (controller.items.isEmpty)
          const ElixStatusPanel(
            key: Key('classroom_announcements_empty'),
            icon: FluentIcons.megaphone,
            title: 'No announcements yet',
            message: 'New classroom updates will appear here.',
          )
        else ...[
          for (var index = 0; index < controller.items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            _AnnouncementCard(
              announcement: controller.items[index],
              teacherDisplayName: teacherDisplayName,
              canManage: canManage,
              groupIsActive: groupIsActive,
              busy: controller.busy,
              onEdit: () => _showEditor(
                context,
                controller,
                announcement: controller.items[index],
              ),
              onDelete: () =>
                  _confirmDelete(context, controller.items[index], controller),
            ),
          ],
          if (controller.hasMore) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.center,
              child: Button(
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

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.teacherDisplayName,
    required this.canManage,
    required this.groupIsActive,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final ClassroomAnnouncement announcement;
  final String teacherDisplayName;
  final bool canManage;
  final bool groupIsActive;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: context.elixCardSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.elixBorder.withValues(alpha: 0.8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                announcement.title,
                style: AppTheme.headingMedium.copyWith(
                  fontSize: 18,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            if (canManage)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  Button(
                    key: Key('classroom_announcement_edit_${announcement.id}'),
                    onPressed: busy || !groupIsActive ? null : onEdit,
                    child: const Text('Edit'),
                  ),
                  Button(
                    key: Key(
                      'classroom_announcement_delete_${announcement.id}',
                    ),
                    onPressed: busy ? null : onDelete,
                    child: const Text('Delete'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _metadata(announcement, teacherDisplayName),
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
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
    final stamp = created == null
        ? 'Just now'
        : '${created.month}/${created.day}/${created.year} '
              '${created.hour.toString().padLeft(2, '0')}:'
              '${created.minute.toString().padLeft(2, '0')}';
    return announcement.isEdited
        ? '$teacherDisplayName · $stamp · Edited'
        : '$teacherDisplayName · $stamp';
  }
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
  String? validationMessage;
  final result = await showDialog<_AnnouncementDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: Text(
          announcement == null ? 'New announcement' : 'Edit announcement',
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextBox(
                key: const Key('classroom_announcement_title'),
                controller: titleController,
                placeholder: 'Title',
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              TextBox(
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
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('classroom_announcement_save'),
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
              Navigator.pop(
                dialogContext,
                _AnnouncementDraft(
                  title: titleController.text,
                  body: bodyController.text,
                ),
              );
            },
            child: Text(announcement == null ? 'Publish' : 'Save changes'),
          ),
        ],
      ),
    ),
  );
  titleController.dispose();
  bodyController.dispose();
  if (result == null) return;
  final success = announcement == null
      ? await controller.create(title: result.title, body: result.body)
      : await controller.update(
          announcement,
          title: result.title,
          body: result.body,
        );
  if (!success || !context.mounted) return;
}

Future<void> _confirmDelete(
  BuildContext context,
  ClassroomAnnouncement announcement,
  ClassroomAnnouncementsController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: const Text('Delete announcement?'),
      content: const Text(
        'This announcement will be removed for the whole class.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('classroom_announcement_confirm_delete'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.delete(announcement);
}

class _AnnouncementDraft {
  const _AnnouncementDraft({required this.title, required this.body});

  final String title;
  final String body;
}
