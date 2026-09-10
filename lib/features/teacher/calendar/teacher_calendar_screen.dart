import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/manila_day.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../../calendar/utils/calendar_metrics.dart';
import '../../calendar/widgets/calendar_chrome.dart';
import '../../calendar/widgets/calendar_header.dart';
import 'teacher_calendar_models.dart';

typedef TeacherCalendarAssignmentsLoader =
    Stream<List<GroupAssignment>> Function({required String teacherId});
typedef TeacherCalendarGroupsLoader =
    Stream<List<ElixrGroup>> Function({required String teacherId});

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
  String _classroomId = '';
  TeacherDeadlineFilter _deadlineFilter = TeacherDeadlineFilter.all;

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
    _assignmentsSub = assignments(teacherId: teacherId).listen((value) {
      if (!mounted) return;
      setState(() {
        _assignments = List.unmodifiable(value);
        _assignmentsReady = true;
      });
    }, onError: (_, _) => _setError('Could not load classroom deadlines.'));
    _groupsSub = groups(teacherId: teacherId).listen((value) {
      if (!mounted) return;
      setState(() {
        _groups = List.unmodifiable(value);
        _groupsReady = true;
        final activeIds = {
          for (final group in value)
            if (group.isActive) group.id,
        };
        if (_classroomId.isNotEmpty && !activeIds.contains(_classroomId)) {
          _classroomId = '';
        }
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

  void _clearFilters() {
    setState(() {
      _classroomId = '';
      _deadlineFilter = TeacherDeadlineFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = teacherCalendarEvents(
      assignments: _assignments,
      authorizedGroups: _groups,
      now: _now,
    );
    final classroomFiltered = filterTeacherCalendarEvents(
      events,
      classroomId: _classroomId,
    );
    final visibleEvents = filterTeacherCalendarEvents(
      classroomFiltered,
      deadlineFilter: _deadlineFilter,
    );
    final selectedEvents = teacherCalendarEventsForDay(
      visibleEvents,
      _selectedDate,
    );
    final overview = teacherCalendarOverview(
      events: classroomFiltered,
      visibleMonth: _visibleMonth,
      today: _today,
    );
    final classrooms = teacherCalendarClassroomOptions(_groups);
    final filtersActive =
        _classroomId.isNotEmpty || _deadlineFilter != TeacherDeadlineFilter.all;

    return TeacherScaffoldPage(
      header: const ElixEditorialPageHeader(
        heading: 'Calendar',
        eyebrow: 'TEACHER WORKSPACE',
        subtitle: 'See what is due, overdue, and coming up across classrooms.',
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
                const SizedBox(height: AppSpacing.md),
                _TeacherWorkloadOverview(overview: overview),
                const SizedBox(height: AppSpacing.md),
                _TeacherCalendarFilters(
                  classrooms: classrooms,
                  classroomId: _classroomId,
                  deadlineFilter: _deadlineFilter,
                  onClassroomChanged: (value) =>
                      setState(() => _classroomId = value ?? ''),
                  onDeadlineChanged: (value) => setState(
                    () => _deadlineFilter = value ?? TeacherDeadlineFilter.all,
                  ),
                ),
                if (events.isEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const ElixStatusPanel(
                    key: Key('teacher_calendar_empty'),
                    title: 'No assignment deadlines yet',
                    message:
                        'Assignment deadlines from your classrooms will appear here.',
                    icon: FluentIcons.calendar,
                  ),
                ] else if (visibleEvents.isEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  ElixStatusPanel(
                    key: const Key('teacher_calendar_filter_empty'),
                    title: 'No deadlines match these filters',
                    message: filtersActive
                        ? 'Try another classroom or deadline state, or clear filters to see every assignment.'
                        : 'No assignment deadlines match the current view.',
                    icon: FluentIcons.filter,
                    actionLabel: filtersActive ? 'Clear filters' : null,
                    onAction: filtersActive ? _clearFilters : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final grid = _TeacherCalendarGrid(
                      visibleMonth: _visibleMonth,
                      selectedDate: _selectedDate,
                      today: _today,
                      events: visibleEvents,
                      onDateSelected: _selectDate,
                    );
                    final details = _SelectedDeadlinePanel(
                      date: _selectedDate,
                      events: selectedEvents,
                      filtersActive: filtersActive,
                      hasAnyDeadlines: events.isNotEmpty,
                      onClearFilters: filtersActive ? _clearFilters : null,
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

class _TeacherWorkloadOverview extends StatelessWidget {
  const _TeacherWorkloadOverview({required this.overview});

  final TeacherCalendarOverview overview;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        key: const Key('teacher_calendar_due_today'),
        icon: FluentIcons.clock,
        label: 'Due today',
        value: overview.dueTodayCount,
        tone: ElixTone.warning,
      ),
      (
        key: const Key('teacher_calendar_overdue'),
        icon: FluentIcons.warning,
        label: 'Overdue',
        value: overview.overdueCount,
        tone: ElixTone.error,
      ),
      (
        key: const Key('teacher_calendar_upcoming'),
        icon: FluentIcons.calendar,
        label: 'Upcoming this month',
        value: overview.upcomingThisMonthCount,
        tone: ElixTone.selected,
      ),
      (
        key: const Key('teacher_calendar_classrooms'),
        icon: FluentIcons.education,
        label: 'Classrooms this month',
        value: overview.visibleClassroomCount,
        tone: ElixTone.milestone,
      ),
    ];

    return Semantics(
      container: true,
      label: 'Classroom workload overview',
      child: Container(
        key: const Key('teacher_calendar_overview'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            if (wide) {
              return Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _OverviewChip(
                        chipKey: items[i].key,
                        icon: items[i].icon,
                        label: items[i].label,
                        value: items[i].value,
                        tone: items[i].tone,
                        detail:
                            items[i].key ==
                                const Key('teacher_calendar_upcoming')
                            ? '${overview.upcomingThisWeekCount} this week'
                            : null,
                      ),
                    ),
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _OverviewChip(
                        chipKey: items[0].key,
                        icon: items[0].icon,
                        label: items[0].label,
                        value: items[0].value,
                        tone: items[0].tone,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _OverviewChip(
                        chipKey: items[1].key,
                        icon: items[1].icon,
                        label: items[1].label,
                        value: items[1].value,
                        tone: items[1].tone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _OverviewChip(
                        chipKey: items[2].key,
                        icon: items[2].icon,
                        label: items[2].label,
                        value: items[2].value,
                        tone: items[2].tone,
                        detail: '${overview.upcomingThisWeekCount} this week',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _OverviewChip(
                        chipKey: items[3].key,
                        icon: items[3].icon,
                        label: items[3].label,
                        value: items[3].value,
                        tone: items[3].tone,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.chipKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
  });

  final Key chipKey;
  final IconData icon;
  final String label;
  final int value;
  final ElixTone tone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final color = ElixToneCues.color(context.elixColors, tone);
    final highContrast = context.isHighContrast;
    return ElixPanelCard(
      key: chipKey,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: highContrast ? context.elixTextPrimary : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.label(color: context.elixTextSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  '$value',
                  style: ElixTypography.cardTitle(
                    color: context.elixTextPrimary,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherCalendarFilters extends StatelessWidget {
  const _TeacherCalendarFilters({
    required this.classrooms,
    required this.classroomId,
    required this.deadlineFilter,
    required this.onClassroomChanged,
    required this.onDeadlineChanged,
  });

  final List<TeacherCalendarClassroomOption> classrooms;
  final String classroomId;
  final TeacherDeadlineFilter deadlineFilter;
  final ValueChanged<String?> onClassroomChanged;
  final ValueChanged<TeacherDeadlineFilter?> onDeadlineChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _FilterField(
          label: 'Classroom',
          child: ComboBox<String>(
            key: const Key('teacher_calendar_classroom_filter'),
            value: classroomId,
            isExpanded: true,
            items: [
              const ComboBoxItem<String>(
                value: '',
                child: Text('All classrooms'),
              ),
              for (final classroom in classrooms)
                ComboBoxItem<String>(
                  value: classroom.id,
                  child: Text(classroom.name),
                ),
            ],
            onChanged: onClassroomChanged,
          ),
        ),
        _FilterField(
          label: 'Deadline',
          child: ComboBox<TeacherDeadlineFilter>(
            key: const Key('teacher_calendar_deadline_filter'),
            value: deadlineFilter,
            isExpanded: true,
            items: [
              for (final filter in TeacherDeadlineFilter.values)
                ComboBoxItem<TeacherDeadlineFilter>(
                  value: filter,
                  child: Text(filter.label),
                ),
            ],
            onChanged: onDeadlineChanged,
          ),
        ),
      ],
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ElixTypography.label(color: context.elixTextSecondary),
          ),
          const SizedBox(height: 6),
          child,
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
    final byDay = teacherCalendarEventsByDay(events);
    final dates = monthGridDates(visibleMonth.year, visibleMonth.month);
    return CalendarSurface(
      child: Column(
        key: const Key('teacher_calendar_grid'),
        children: [
          const CalendarWeekdayHeader(),
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
                        dayEvents: byDay[dates[week * 7 + day]] ?? const [],
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
    required this.dayEvents,
    required this.isOutsideMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final List<TeacherCalendarEvent> dayEvents;
  final bool isOutsideMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = dayEvents.length;
    final states = {for (final event in dayEvents) event.state};
    final label = StringBuffer('${date.day}');
    if (isToday) label.write(', today');
    if (isSelected) label.write(', selected');
    if (count > 0) {
      label.write(', $count assignment${count == 1 ? '' : 's'} due');
      if (states.contains(TeacherDeadlineState.overdue)) {
        label.write(', includes overdue');
      }
      if (states.contains(TeacherDeadlineState.dueToday)) {
        label.write(', includes due today');
      }
    }

    return CalendarDayFrame(
      onTap: onTap,
      semanticLabel: label.toString(),
      isSelected: isSelected,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CalendarDayNumber(
            day: date.day,
            isToday: isToday,
            isSelected: isSelected,
            isOutsideMonth: isOutsideMonth,
          ),
          const SizedBox(height: 6),
          if (count > 0)
            _DayDeadlineMarks(
              count: count,
              states: states,
              dimmed: isOutsideMonth,
            ),
        ],
      ),
    );
  }
}

class _DayDeadlineMarks extends StatelessWidget {
  const _DayDeadlineMarks({
    required this.count,
    required this.states,
    required this.dimmed,
  });

  final int count;
  final Set<TeacherDeadlineState> states;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CountBadge(count: count, dimmed: dimmed),
            if (states.contains(TeacherDeadlineState.overdue))
              _StateGlyph(
                icon: FluentIcons.warning,
                color: colors.error,
                tooltip: 'Overdue',
                dimmed: dimmed,
              ),
            if (states.contains(TeacherDeadlineState.dueToday))
              _StateGlyph(
                icon: FluentIcons.clock,
                color: colors.warning,
                tooltip: 'Due today',
                dimmed: dimmed,
              ),
            if (states.contains(TeacherDeadlineState.upcoming))
              _StateGlyph(
                icon: FluentIcons.calendar,
                color: colors.brandSecondary,
                tooltip: 'Upcoming',
                dimmed: dimmed,
              ),
          ],
        ),
        if (count >= 3) ...[
          const SizedBox(height: 4),
          _DensityBar(count: count, dimmed: dimmed),
        ],
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.dimmed});

  final int count;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceInteractive,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: context.elixTextPrimary.withValues(alpha: dimmed ? 0.55 : 1),
        ),
      ),
    );
  }
}

class _StateGlyph extends StatelessWidget {
  const _StateGlyph({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.dimmed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 10,
        color: color.withValues(alpha: dimmed ? 0.45 : 1),
      ),
    );
  }
}

class _DensityBar extends StatelessWidget {
  const _DensityBar({required this.count, required this.dimmed});

  final int count;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final filled = count.clamp(1, 4);
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 2),
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: i < filled
                      ? colors.brandSecondary.withValues(
                          alpha: dimmed ? 0.35 : 0.85,
                        )
                      : colors.borderSubtle.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectedDeadlinePanel extends StatelessWidget {
  const _SelectedDeadlinePanel({
    required this.date,
    required this.events,
    required this.filtersActive,
    required this.hasAnyDeadlines,
    required this.onOpen,
    this.onClearFilters,
  });

  final DateTime date;
  final List<TeacherCalendarEvent> events;
  final bool filtersActive;
  final bool hasAnyDeadlines;
  final ValueChanged<TeacherCalendarEvent> onOpen;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      key: const Key('teacher_calendar_selected_day'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.MMMMEEEEd().format(date),
            style: ElixTypography.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            events.isEmpty
                ? 'No deadlines on this date'
                : '${events.length} deadline${events.length == 1 ? '' : 's'}',
            style: ElixTypography.label(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (events.isEmpty)
            _SelectedDayEmpty(
              filtersActive: filtersActive,
              hasAnyDeadlines: hasAnyDeadlines,
              onClearFilters: onClearFilters,
            )
          else
            for (final event in events) ...[
              _DeadlineCard(event: event, onOpen: () => onOpen(event)),
              if (event != events.last) const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _SelectedDayEmpty extends StatelessWidget {
  const _SelectedDayEmpty({
    required this.filtersActive,
    required this.hasAnyDeadlines,
    this.onClearFilters,
  });

  final bool filtersActive;
  final bool hasAnyDeadlines;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final title = filtersActive
        ? 'No matching deadlines'
        : 'No assignment deadlines on this date.';
    final message = filtersActive
        ? 'Nothing on this date matches the current classroom or deadline filters.'
        : hasAnyDeadlines
        ? 'Select a date with a count badge to inspect classroom work.'
        : 'Published assignment deadlines will appear here.';
    return Container(
      key: const Key('teacher_calendar_selected_empty'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.calendar, color: context.elixColors.brandSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: ElixTypography.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          if (onClearFilters != null) ...[
            const SizedBox(height: AppSpacing.md),
            Button(
              onPressed: onClearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({required this.event, required this.onOpen});

  final TeacherCalendarEvent event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dueAt = event.assignment.dueAt!.toUtc().add(const Duration(hours: 8));
    final colors = context.elixColors;
    final (label, color, icon) = switch (event.state) {
      TeacherDeadlineState.upcoming => (
        event.state.label,
        colors.brandSecondary,
        FluentIcons.calendar,
      ),
      TeacherDeadlineState.dueToday => (
        event.state.label,
        colors.warning,
        FluentIcons.clock,
      ),
      TeacherDeadlineState.overdue => (
        event.state.label,
        colors.error,
        FluentIcons.warning,
      ),
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
          border: Border.all(color: color.withValues(alpha: 0.38)),
          color: color.withValues(
            alpha: context.isHighContrast
                ? 0
                : context.isDarkTheme
                ? 0.08
                : 0.06,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.assignment.displayTitle,
              style: AppTheme.body.copyWith(
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  FluentIcons.education,
                  size: 12,
                  color: context.elixTextSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event.classroomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  FluentIcons.clock,
                  size: 12,
                  color: context.elixTextSecondary,
                ),
                Text(
                  DateFormat.jm().format(dueAt),
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                ElixPill(text: label, color: color, compact: true),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      'Open classwork',
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
