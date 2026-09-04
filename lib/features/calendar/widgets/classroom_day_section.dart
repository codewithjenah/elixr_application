import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../models/calendar_classroom_assignment.dart';

class ClassroomDaySection extends StatelessWidget {
  const ClassroomDaySection({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<CalendarClassroomAssignment> items;
  final ValueChanged<CalendarClassroomAssignment> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          'CLASSROOM WORK',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items) ...[
          _ClassroomAssignmentTile(item: item, onOpen: () => onOpen(item)),
          if (item != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ClassroomAssignmentTile extends StatelessWidget {
  const _ClassroomAssignmentTile({required this.item, required this.onOpen});
  final CalendarClassroomAssignment item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dueAt = item.dueAt!;
    final overdue = item.isOverdue;
    final color = overdue ? AppColors.error : AppColors.accent;
    return Button(
      onPressed: onOpen,
      style: ButtonStyle(padding: WidgetStateProperty.all(EdgeInsets.zero)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .35)),
          color: color.withValues(alpha: .08),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(FluentIcons.education, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.assignment.displayTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.assignment.groupName} · Due ${DateFormat.jm().format(dueAt.toUtc().add(const Duration(hours: 8)))} Manila time',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.elixTextSecondary,
                    ),
                  ),
                  if (item.assignment.teacherDisplayName.isNotEmpty)
                    Text(
                      item.assignment.teacherDisplayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.elixTextSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                _StatusPill(label: item.statusLabel, color: color),
                if (item.isChecked) ...[
                  const SizedBox(height: 4),
                  _StatusPill(label: 'Checked', color: AppColors.success),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
    ),
  );
}
