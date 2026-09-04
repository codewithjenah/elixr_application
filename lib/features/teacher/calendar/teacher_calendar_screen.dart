import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/manila_day.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../../calendar/utils/calendar_metrics.dart';
import '../../calendar/widgets/calendar_header.dart';
import 'teacher_calendar_models.dart';

typedef TeacherCalendarAssignmentsLoader =
    Stream<List<GroupAssignment>> Function(String teacherId);
typedef TeacherCalendarGroupsLoader =
    Stream<List<ElixrGroup>> Function(String teacherId);

class TeacherCalendarScreen extends StatefulWidget {
  const TeacherCalendarScreen({
    super.key,
    this.assignmentsLoader,
    this.groupsLoader,
    this.now,
  });

  final TeacherCalendarAssignmentsLoader? assignmentsLoader;
  final TeacherCalendarGroupsLoader? groupsLoader;
  final DateTime Function()? now;

  @override
  State<TeacherCalendarScreen> createState() => _TeacherCalendarScreenState();
}

class _TeacherCalendarScreenState extends State<TeacherCalendarScreen> {
  StreamSubscription<List<GroupAssignment>>? _assignmentsSub;
  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  List<GroupAssignment> _assignments = const [];
  List<ElixrGroup> _groups = const [];
  bool _assignmentsReady = false;
  bool _groupsReady = false;
  String? _error;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  DateTime get _today =>
      ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(_now.toUtc()));
  bool get _loading => !_assignmentsReady || !_groupsReady;

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _assignmentsSub?.cancel();
    _groupsSub?.cancel();
    super.dispose();
  }

  void _start() {
    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null) {
      setState(() {
        _assignmentsReady = true;
        _groupsReady = true;
      });
      return;
    }
    final assignments =
        widget.assignmentsLoader ??
        context.read<ClassroomAssignmentRepository>().watchTeacherAssignments;
    final groups =
        widget.groupsLoader ??
        context.read<GroupRepository>().watchTeacherGroups;
    _assignmentsSub?.cancel();
    _groupsSub?.cancel();
    setState(() {
      _assignmentsReady = false;
      _groupsReady = false;
      _error = null;
    });
    _assignmentsSub = assignments(teacherId).listen((value) {
      if (!mounted) return;
      setState(() {
        _assignments = List.unmodifiable(value);
        _assignmentsReady = true;
      });
    }, onError: (_, _) => _setError('Could not load classroom deadlines.'));
    _groupsSub = groups(teacherId).listen((value) {
      if (!mounted) return;
      setState(() {
        _groups = List.unmodifiable(value);
        _groupsReady = true;
      });
    }, onError: (_, _) => _setError('Could not load your classrooms.'));
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _assignmentsReady = true;
      _groupsReady = true;
    });
  }

  void _selectDate(DateTime date) {
    final normalized = normalizeDate(date);
    setState(() {
      _selectedDate = normalized;
      if (normalized.month != _visibleMonth.month ||
          normalized.year != _visibleMonth.year) {
        _visibleMonth = DateTime(normalized.year, normalized.month);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = teacherCalendarEvents(
      assignments: _assignments,
      authorizedGroups: _groups,
      now: _now,
    );
    final selectedEvents = teacherCalendarEventsForDay(events, _selectedDate);
    return TeacherScaffoldPage(
      header: const ElixEditorialPageHeader(
        heading: 'Calendar',
        eyebrow: 'TEACHER WORKSPACE',
        subtitle: 'Assignment deadlines across your classrooms.',
      ),
      content: _loading
          ? const Center(child: ProgressRing())
          : _error != null
          ? ElixStatusPanel(
              title: 'Calendar unavailable',
              message: _error!,
              isError: true,
              actionLabel: 'Retry',
              onAction: _start,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalendarHeader(
                  visibleMonth: _visibleMonth,
                  onPreviousMonth: () => setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month - 1,
                    );
                  }),
                  onNextMonth: () => setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + 1,
                    );
                  }),
                  onToday: () => _selectDate(_today),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (events.isEmpty)
                  const ElixStatusPanel(
                    key: Key('teacher_calendar_empty'),
                    title: 'No assignment deadlines yet',
                    message:
                        'Assignment deadlines from your classrooms will appear here.',
                    icon: FluentIcons.calendar,
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 980;
                      final grid = _TeacherCalendarGrid(
                        visibleMonth: _visibleMonth,
                        selectedDate: _selectedDate,
                        today: _today,
                        events: events,
                        onDateSelected: _selectDate,
                      );
                      final details = _SelectedDeadlinePanel(
                        date: _selectedDate,
                        events: selectedEvents,
                        onOpen: (event) => context.push(
                          AppRoutePaths.teacherGroupClasswork(
                            event.assignment.groupId,
                            event.assignment.id,
                          ),
                        ),
                      );
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: grid),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(flex: 2, child: details),
                              ],
                            )
                          : Column(
                              children: [
                                grid,
                                const SizedBox(height: AppSpacing.lg),
                                details,
                              ],
                            );
                    },
                  ),
              ],
            ),
    );
  }
}

class _TeacherCalendarGrid extends StatelessWidget {
  const _TeacherCalendarGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.events,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final List<TeacherCalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final counts = <DateTime, int>{};
    for (final event in events) {
      counts[event.civilDate] = (counts[event.civilDate] ?? 0) + 1;
    }
    final dates = monthGridDates(visibleMonth.year, visibleMonth.month);
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Container(
      key: const Key('teacher_calendar_grid'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final weekday in weekdays)
                Expanded(
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var week = 0; week < dates.length ~/ 7; week++) ...[
            if (week > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: day == 6 ? 0 : 6),
                      child: _TeacherCalendarDayCell(
                        date: dates[week * 7 + day],
                        count: counts[dates[week * 7 + day]] ?? 0,
                        isOutsideMonth:
                            dates[week * 7 + day].month != visibleMonth.month,
                        isSelected: dates[week * 7 + day] == selectedDate,
                        isToday: dates[week * 7 + day] == today,
                        onTap: () => onDateSelected(dates[week * 7 + day]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TeacherCalendarDayCell extends StatelessWidget {
  const _TeacherCalendarDayCell({
    required this.date,
    required this.count,
    required this.isOutsideMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final int count;
  final bool isOutsideMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Button(
    onPressed: onTap,
    style: ButtonStyle(
      padding: WidgetStateProperty.all(const EdgeInsets.all(8)),
      backgroundColor: WidgetStateProperty.all(
        isSelected
            ? AppColors.primary.withValues(alpha: .14)
            : Colors.transparent,
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? AppColors.primary
                : isToday
                ? AppColors.accent.withValues(alpha: .7)
                : context.elixBorder.withValues(alpha: .55),
          ),
        ),
      ),
    ),
    child: SizedBox(
      height: 54,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${date.day}',
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: isOutsideMonth
                  ? context.elixTextSecondary.withValues(alpha: .45)
                  : context.elixTextPrimary,
            ),
          ),
          const Spacer(),
          if (count > 0)
            Text(
              '$count due',
              style: AppTheme.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    ),
  );
}

class _SelectedDeadlinePanel extends StatelessWidget {
  const _SelectedDeadlinePanel({
    required this.date,
    required this.events,
    required this.onOpen,
  });

  final DateTime date;
  final List<TeacherCalendarEvent> events;
  final ValueChanged<TeacherCalendarEvent> onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('teacher_calendar_selected_day'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: context.elixPanelSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.elixBorder.withValues(alpha: .6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.MMMMEEEEd().format(date),
          style: AppTheme.headingMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (events.isEmpty)
          const Text('No assignment deadlines on this date.')
        else
          for (final event in events) ...[
            _DeadlineCard(event: event, onOpen: () => onOpen(event)),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    ),
  );
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({required this.event, required this.onOpen});

  final TeacherCalendarEvent event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dueAt = event.assignment.dueAt!.toUtc().add(const Duration(hours: 8));
    final (label, color) = switch (event.state) {
      TeacherDeadlineState.upcoming => ('Upcoming', AppColors.accent),
      TeacherDeadlineState.dueToday => ('Due today', AppColors.warning),
      TeacherDeadlineState.overdue => ('Overdue', AppColors.error),
    };
    return Button(
      key: Key('teacher_calendar_event_${event.assignment.id}'),
      onPressed: onOpen,
      style: ButtonStyle(padding: WidgetStateProperty.all(EdgeInsets.zero)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.assignment.displayTitle, style: AppTheme.body),
            const SizedBox(height: 2),
            Text(event.classroomName, style: AppTheme.caption),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.jm().format(dueAt)} · $label',
              style: AppTheme.caption.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
