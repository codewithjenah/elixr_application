import 'package:elixr_core/utils/manila_day.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/session.dart';
import '../../data/models/training_plan.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/training_plan_repository.dart';
import '../../features/training/training_view.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'models/training_day_snapshot.dart';
import 'utils/calendar_metrics.dart';
import 'utils/training_plan_progress.dart';
import 'widgets/calendar_header.dart';
import 'widgets/calendar_month_grid.dart';
import 'widgets/calendar_summary_cards.dart';
import 'widgets/selected_day_panel.dart';

typedef CalendarSessionsLoader = Future<List<Session>> Function(String userId);
typedef CalendarPlansLoader =
    Future<List<TrainingPlan>> Function(
      String userId, {
      required String startDayKey,
      required String endDayKey,
    });
typedef CalendarPlanSaver = Future<void> Function(TrainingPlan plan);
typedef CalendarPlanRemover =
    Future<void> Function({required String userId, required String dayKey});

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.initialDate,
    this.sessionsLoader,
    this.plansLoader,
    this.planSaver,
    this.planRemover,
    this.now,
    this.embedded = false,
  });

  /// Optional `YYYY-MM-DD` query value from `/training?view=planner&date=...`.
  final String? initialDate;

  /// When true, render Planner content without a page scaffold or heading.
  final bool embedded;

  /// Test seam for loading sessions without Firebase.
  final CalendarSessionsLoader? sessionsLoader;

  /// Test seam for loading plans without Firebase.
  final CalendarPlansLoader? plansLoader;

  final CalendarPlanSaver? planSaver;
  final CalendarPlanRemover? planRemover;

  /// Injectable clock. Production uses `DateTime.now()`.
  final DateTime Function()? now;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  SessionRepository? _sessionRepo;
  TrainingPlanRepository? _planRepo;

  List<Session> _sessions = const [];
  List<TrainingPlan> _plans = const [];
  Map<DateTime, TrainingDaySnapshot> _byDate = const {};
  bool _loading = true;
  bool _hasError = false;
  bool _editing = false;
  bool _saving = false;
  String? _actionError;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  SessionService? _sessionService;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  String get _todayKey => ManilaDay.dayKeyFor(_now.toUtc());

  DateTime get _todayCivil => ManilaDay.civilDateFromDayKey(_todayKey);

  @override
  void initState() {
    super.initState();
    final fallback = _todayCivil;
    final parsed = parseCalendarQueryDate(widget.initialDate);
    _selectedDate = parsed ?? fallback;
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCalendar(fullScreen: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SessionService>();
    if (service != _sessionService) {
      _sessionService?.removeListener(_onSessionSaved);
      _sessionService = service..addListener(_onSessionSaved);
    }
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate == oldWidget.initialDate) return;
    final parsed = parseCalendarQueryDate(widget.initialDate);
    if (parsed == null) return;
    setState(() {
      _selectedDate = parsed;
      _visibleMonth = DateTime(parsed.year, parsed.month);
      _editing = false;
      _actionError = null;
    });
    _loadCalendar(fullScreen: false);
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionSaved);
    super.dispose();
  }

  void _onSessionSaved() => _loadCalendar(fullScreen: false);

  (String, String) _visibleRange() {
    final dates = monthGridDates(_visibleMonth.year, _visibleMonth.month);
    return (
      ManilaDay.dayKeyFromCivil(
        year: dates.first.year,
        month: dates.first.month,
        day: dates.first.day,
      ),
      ManilaDay.dayKeyFromCivil(
        year: dates.last.year,
        month: dates.last.month,
        day: dates.last.day,
      ),
    );
  }

  void _rebuildSnapshots() {
    final dates = monthGridDates(_visibleMonth.year, _visibleMonth.month);
    final byKey = buildTrainingDaySnapshots(
      civilDates: dates,
      plans: _plans,
      sessions: _sessions,
      todayKey: _todayKey,
    );
    _byDate = {
      for (final snapshot in byKey.values) snapshot.civilDate: snapshot,
    };
  }

  Future<void> _loadCalendar({required bool fullScreen}) async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = false;
          _sessions = const [];
          _plans = const [];
          _byDate = const {};
        });
      }
      return;
    }

    if (fullScreen && mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    try {
      final sessionLoader =
          widget.sessionsLoader ??
          (_sessionRepo ??= SessionRepository()).getSessionsForUser;
      final planLoader =
          widget.plansLoader ??
          (user, {required startDayKey, required endDayKey}) {
            return (_planRepo ??= TrainingPlanRepository()).getPlansInRange(
              userId: user,
              startDayKey: startDayKey,
              endDayKey: endDayKey,
            );
          };
      final range = _visibleRange();
      final sessionsFuture = sessionLoader(userId);
      final plansFuture = planLoader(
        userId,
        startDayKey: range.$1,
        endDayKey: range.$2,
      );
      final sessions = await sessionsFuture;
      final plans = await plansFuture;
      if (!mounted) return;
      setState(() {
        _sessions = List<Session>.unmodifiable(sessions);
        _plans = List<TrainingPlan>.unmodifiable(plans);
        _rebuildSnapshots();
        _loading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  void _goToPreviousMonth() {
    final previous = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    setState(() {
      _visibleMonth = previous;
      _selectedDate = clampSelectedDay(
        _selectedDate,
        year: previous.year,
        month: previous.month,
      );
      _editing = false;
    });
    _loadCalendar(fullScreen: false);
  }

  void _goToNextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    setState(() {
      _visibleMonth = next;
      _selectedDate = clampSelectedDay(
        _selectedDate,
        year: next.year,
        month: next.month,
      );
      _editing = false;
    });
    _loadCalendar(fullScreen: false);
  }

  void _goToToday() {
    final today = _todayCivil;
    setState(() {
      _selectedDate = today;
      _visibleMonth = DateTime(today.year, today.month);
      _editing = false;
    });
    _loadCalendar(fullScreen: false);
  }

  void _onDateSelected(DateTime date) {
    final normalized = normalizeDate(date);
    setState(() {
      _selectedDate = normalized;
      _editing = false;
      _actionError = null;
      if (normalized.year != _visibleMonth.year ||
          normalized.month != _visibleMonth.month) {
        _visibleMonth = DateTime(normalized.year, normalized.month);
        _loadCalendar(fullScreen: false);
      }
    });
  }

  TrainingDaySnapshot get _selectedSnapshot {
    return _byDate[_selectedDate] ??
        TrainingDaySnapshot(
          dayKey: ManilaDay.dayKeyFromCivil(
            year: _selectedDate.year,
            month: _selectedDate.month,
            day: _selectedDate.day,
          ),
          civilDate: _selectedDate,
          status: deriveTrainingDayStatus(
            plan: null,
            matchedDurationSeconds: 0,
            todayKey: _todayKey,
          ),
          matchedDurationSeconds: 0,
          hasUnplannedActivity: false,
        );
  }

  Future<void> _savePlan(TrainingPlan plan) async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;
    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      final saver =
          widget.planSaver ??
          (_planRepo ??= TrainingPlanRepository()).upsertPlan;
      await saver(plan);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      await _loadCalendar(fullScreen: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionError = 'Check your connection and try again.';
      });
    }
  }

  Future<void> _markRest() {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return Future.value();
    return _savePlan(
      TrainingPlan.rest(userId: userId, dayKey: _selectedSnapshot.dayKey),
    );
  }

  Future<void> _removePlan() async {
    final userId = context.read<AuthService>().currentUser?.id;
    final plan = _selectedSnapshot.plan;
    if (userId == null || plan == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('Remove this plan?'),
          content: const Text(
            'This day will become unplanned. Completed practice is unchanged.',
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove Plan'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      final remover =
          widget.planRemover ??
          (_planRepo ??= TrainingPlanRepository()).deletePlan;
      await remover(userId: userId, dayKey: plan.dayKey);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      await _loadCalendar(fullScreen: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionError = 'The plan could not be removed. Try again.';
      });
    }
  }

  void _startPractice() {
    final plan = _selectedSnapshot.plan;
    if (plan == null || !plan.isTraining) return;
    context.go(
      trainingPracticeLocation(
        movement: plan.movementName!,
        difficulty: plan.difficulty!,
        propProtocolValue: plan.propType!.protocolValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthService>().currentUser?.id ?? '';
    final monthKey =
        '${_visibleMonth.year.toString().padLeft(4, '0')}'
        '${_visibleMonth.month.toString().padLeft(2, '0')}';
    final metrics = computeTrainingAdherenceMetrics(
      plans: _plans,
      sessions: _sessions,
      todayKey: _todayKey,
      monthKey: monthKey,
    );

    final content = _loading
        ? const Center(child: ProgressRing())
        : _hasError
        ? _CalendarErrorState(onRetry: () => _loadCalendar(fullScreen: true))
        : SingleChildScrollView(
            padding: widget.embedded
                ? const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  )
                : const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.pageTopInset,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CalendarHeader(
                      visibleMonth: _visibleMonth,
                      onPreviousMonth: _goToPreviousMonth,
                      onNextMonth: _goToNextMonth,
                      onToday: _goToToday,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    CalendarSummaryCards(
                      plannedDays: metrics.plannedDays,
                      completedDays: metrics.completedDays,
                      adherencePercent: metrics.adherencePercent,
                      planStreak: metrics.planStreak,
                    ),
                    if (metrics.plannedDays == 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      InfoBar(
                        title: const Text('No training planned this month'),
                        content: const Text(
                          'Select a day to schedule practice or a rest day.',
                        ),
                        severity: InfoBarSeverity.info,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 980;
                        final grid = CalendarMonthGrid(
                          dates: monthGridDates(
                            _visibleMonth.year,
                            _visibleMonth.month,
                          ),
                          visibleMonth: _visibleMonth,
                          selectedDate: _selectedDate,
                          todayDate: _todayCivil,
                          snapshotsByDate: _byDate,
                          onDateSelected: _onDateSelected,
                        );
                        final panel = SelectedDayPanel(
                          snapshot: _selectedSnapshot,
                          todayKey: _todayKey,
                          userId: userId,
                          isEditing: _editing,
                          isSaving: _saving,
                          actionError: _actionError,
                          onStartEditing: () => setState(() => _editing = true),
                          onCancelEditing: () =>
                              setState(() => _editing = false),
                          onSavePlan: _savePlan,
                          onMarkRest: _markRest,
                          onRemovePlan: _removePlan,
                          onStartPractice: _startPractice,
                          onViewHistory: () => context.go(
                            trainingLocation(
                              view: TrainingView.history,
                              date: formatCalendarQueryDate(_selectedDate),
                            ),
                          ),
                        );

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: grid),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(flex: 2, child: panel),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            grid,
                            const SizedBox(height: AppSpacing.md),
                            panel,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );

    if (widget.embedded) return content;

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(child: content),
    );
  }
}

class _CalendarErrorState extends StatelessWidget {
  const _CalendarErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              FluentIcons.error_badge,
              size: 36,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unable to load your planner.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
