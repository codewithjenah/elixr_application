import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../models/calendar_classroom_assignment.dart';
import 'calendar_agenda_panel.dart';

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
    return CalendarAgendaSection(
      title: 'CLASSROOM WORK',
      child: Column(
        children: [
          for (final item in items) ...[
            _ClassroomAssignmentTile(item: item, onOpen: () => onOpen(item)),
            if (item != items.last) const SizedBox(height: 8),
          ],
        ],
      ),
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
    final colors = context.elixColors;
    final color = overdue ? colors.error : colors.brandSecondary;
    final icon = overdue ? FluentIcons.warning : FluentIcons.education;
    return CalendarWorkRow(
      title: item.assignment.displayTitle,
      subtitle:
          '${item.assignment.groupName} · Due ${DateFormat.jm().format(dueAt.toUtc().add(const Duration(hours: 8)))} Manila time',
      meta: item.assignment.teacherDisplayName.isNotEmpty
          ? item.assignment.teacherDisplayName
          : null,
      leadingIcon: icon,
      accent: color,
      actionLabel: 'Open assignment',
      onOpen: onOpen,
      badges: [
        ElixPill(text: item.statusLabel, color: color, compact: true),
        if (item.isChecked)
          ElixPill(text: 'Checked', color: colors.success, compact: true),
      ],
    );
  }
}
