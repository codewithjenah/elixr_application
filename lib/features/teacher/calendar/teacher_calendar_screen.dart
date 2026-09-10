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
import '../../calendar/widgets/calendar_agenda_panel.dart';
import '../../calendar/widgets/calendar_chrome.dart';
import '../../calendar/widgets/calendar_header.dart';
import '../../calendar/widgets/calendar_metric_tile.dart';
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
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: CalendarLayout.maxContentWidth,
                ),
                child: Column(
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
                      trailing: _TeacherCalendarFilters(
                        classrooms: classrooms,
                        classroomId: _classroomId,
                        deadlineFilter: _deadlineFilter,
                        filtersActive: filtersActive,
                        onClassroomChanged: (value) =>
                            setState(() => _classroomId = value ?? ''),
                        onDeadlineChanged: (value) => setState(
                          () => _deadlineFilter =
                              value ?? TeacherDeadlineFilter.all,
                        ),
                        onClearFilters: filtersActive ? _clearFilters : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TeacherWorkloadOverview(overview: overview),
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
                    const SizedBox(height: AppSpacing.md),
                    CalendarWorkspaceSplit(
                      calendar: _TeacherCalendarGrid(
                        visibleMonth: _visibleMonth,
                        selectedDate: _selectedDate,
                        today: _today,
                        events: visibleEvents,
                        onDateSelected: _selectDate,
                      ),
                      agenda: _SelectedDeadlinePanel(
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _TeacherWorkloadOverview extends StatelessWidget {
  const _TeacherWorkloadOverview({required this.overview});

  final TeacherCalendarOverview overview;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      CalendarMetricTile(
        key: const Key('teacher_calendar_due_today'),
        icon: FluentIcons.clock,
        label: 'Due today',
        value: '${overview.dueTodayCount}',
        tone: ElixTone.warning,
      ),
      CalendarMetricTile(
        key: const Key('teacher_calendar_overdue'),
        icon: FluentIcons.warning,
        label: 'Overdue',
        value: '${overview.overdueCount}',
        tone: ElixTone.error,
      ),
      CalendarMetricTile(
        key: const Key('teacher_calendar_upcoming'),
        icon: FluentIcons.calendar,
        label: 'Upcoming this month',
        value: '${overview.upcomingThisMonthCount}',
        detail: '${overview.upcomingThisWeekCount} this week',
        tone: ElixTone.selected,
      ),
      CalendarMetricTile(
        key: const Key('teacher_calendar_classrooms'),
        icon: FluentIcons.education,
        label: 'Classrooms this month',
        value: '${overview.visibleClassroomCount}',
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
            if (constraints.maxWidth >= CalendarLayout.metricsPairBreakpoint) {
              return _MetricRow(tiles: tiles);
            }
            return Column(
              children: [
                _MetricRow(tiles: tiles.sublist(0, 2)),
                const SizedBox(height: AppSpacing.sm),
                _MetricRow(tiles: tiles.sublist(2)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: tiles[i]),
          ],
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
    required this.filtersActive,
    required this.onClassroomChanged,
    required this.onDeadlineChanged,
    this.onClearFilters,
  });

  final List<TeacherCalendarClassroomOption> classrooms;
  final String classroomId;
  final TeacherDeadlineFilter deadlineFilter;
  final bool filtersActive;
  final ValueChanged<String?> onClassroomChanged;
  final ValueChanged<TeacherDeadlineFilter?> onDeadlineChanged;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Align(
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(CalendarLayout.controlRadius),
          border: Border.all(
            color: filtersActive
                ? colors.borderInteractive
                : colors.borderSubtle,
            width: filtersActive && context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (filtersActive)
                ElixPill(
                  text: 'Filtered',
                  color: colors.brandSecondary,
                  compact: true,
                ),
              _ToolbarFilter(
                label: 'Classroom',
                width: 168,
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
              _ToolbarFilter(
                label: 'Deadline',
                width: 132,
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
              if (onClearFilters != null)
                Button(
                  onPressed: onClearFilters,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarFilter extends StatelessWidget {
  const _ToolbarFilter({
    required this.label,
    required this.child,
    required this.width,
  });

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ElixTypography.label(
              color: context.elixTextSecondary,
            ).copyWith(fontSize: 10),
          ),
          const SizedBox(height: 4),
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
    final colors = context.elixColors;
    final dates = monthGridDates(visibleMonth.year, visibleMonth.month);
    return CalendarMonthShell(
      dates: dates,
      visibleMonth: visibleMonth,
      selectedDate: selectedDate,
      todayDate: today,
      gridKey: const Key('teacher_calendar_grid'),
      footer: CalendarLegendBar(
        items: [
          (FluentIcons.warning, colors.error, 'Overdue'),
          (FluentIcons.clock, colors.warning, 'Due today'),
          (FluentIcons.calendar, colors.brandSecondary, 'Upcoming'),
        ],
      ),
      cellBuilder:
          (
            context,
            date, {
            required isOutsideMonth,
            required isSelected,
            required isToday,
          }) {
            return _TeacherCalendarDayCell(
              date: date,
              dayEvents: byDay[date] ?? const [],
              isOutsideMonth: isOutsideMonth,
              isSelected: isSelected,
              isToday: isToday,
              onTap: () => onDateSelected(date),
            );
          },
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CalendarDayNumber(
            day: date.day,
            isToday: isToday,
            isSelected: isSelected,
            isOutsideMonth: isOutsideMonth,
          ),
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
    final chips = <Widget>[
      CalendarMarkerChip(
        icon: FluentIcons.more,
        tooltip: '$count assignment${count == 1 ? '' : 's'}',
        color: colors.brandSecondary,
        count: count,
        dimmed: dimmed,
      ),
    ];
    if (states.contains(TeacherDeadlineState.overdue)) {
      chips.add(
        CalendarMarkerChip(
          icon: FluentIcons.warning,
          tooltip: 'Overdue',
          color: colors.error,
          label: 'Late',
          dimmed: dimmed,
        ),
      );
    }
    if (states.contains(TeacherDeadlineState.dueToday) && chips.length < 3) {
      chips.add(
        CalendarMarkerChip(
          icon: FluentIcons.clock,
          tooltip: 'Due today',
          color: colors.warning,
          label: 'Today',
          dimmed: dimmed,
        ),
      );
    }
    if (states.contains(TeacherDeadlineState.upcoming) && chips.length < 3) {
      chips.add(
        CalendarMarkerChip(
          icon: FluentIcons.calendar,
          tooltip: 'Upcoming',
          color: colors.brandSecondary,
          label: 'Soon',
          dimmed: dimmed,
        ),
      );
    }

    return Wrap(spacing: 3, runSpacing: 3, children: chips);
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
    return KeyedSubtree(
      key: const Key('teacher_calendar_selected_day'),
      child: CalendarAgendaPanel(
        date: date,
        subtitle: events.isEmpty
            ? 'No deadlines on this date'
            : '${events.length} deadline${events.length == 1 ? '' : 's'}',
        child: events.isEmpty
            ? _SelectedDayEmpty(
                filtersActive: filtersActive,
                hasAnyDeadlines: hasAnyDeadlines,
                onClearFilters: onClearFilters,
              )
            : Column(
                children: [
                  for (final event in events) ...[
                    _DeadlineCard(event: event, onOpen: () => onOpen(event)),
                    if (event != events.last)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
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
    return CalendarAgendaInset(
      child: Column(
        key: const Key('teacher_calendar_selected_empty'),
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
            style: ElixTypography.supporting(color: context.elixTextSecondary),
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
    return CalendarWorkRow(
      key: Key('teacher_calendar_event_${event.assignment.id}'),
      title: event.assignment.displayTitle,
      subtitle: event.classroomName,
      meta: DateFormat.jm().format(dueAt),
      leadingIcon: icon,
      accent: color,
      actionLabel: 'Open classwork',
      onOpen: onOpen,
      badges: [ElixPill(text: label, color: color, compact: true)],
    );
  }
}
