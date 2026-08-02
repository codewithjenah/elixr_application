import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'models/calendar_day_summary.dart';
import 'utils/calendar_metrics.dart';
import 'widgets/calendar_header.dart';
import 'widgets/calendar_month_grid.dart';
import 'widgets/calendar_summary_cards.dart';
import 'widgets/selected_day_panel.dart';

typedef CalendarSessionsLoader = Future<List<Session>> Function(String userId);

const _pink = AppColors.primary;
const _violet = AppColors.accentSoft;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.initialDate, this.sessionsLoader});

  /// Optional `YYYY-MM-DD` query value from `/calendar?date=...`.
  final String? initialDate;

  /// Test seam for loading sessions without Firebase.
  final CalendarSessionsLoader? sessionsLoader;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  SessionRepository? _sessionRepo;

  List<Session> _sessions = const [];
  Map<DateTime, CalendarDaySummary> _byDate = const {};
  bool _loading = true;
  bool _hasError = false;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  SessionService? _sessionService;

  @override
  void initState() {
    super.initState();
    final fallback = normalizeDate(DateTime.now());
    final parsed = parseCalendarQueryDate(widget.initialDate);
    _selectedDate = parsed ?? fallback;
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSessions();
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
  void dispose() {
    _sessionService?.removeListener(_onSessionSaved);
    super.dispose();
  }

  void _onSessionSaved() => _loadSessions();

  Future<void> _loadSessions() async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = false;
          _sessions = const [];
          _byDate = const {};
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    try {
      final loader =
          widget.sessionsLoader ??
          (_sessionRepo ??= SessionRepository()).getSessionsForUser;
      final sessions = await loader(userId);
      if (!mounted) return;
      setState(() {
        _sessions = List<Session>.unmodifiable(sessions);
        _byDate = groupSessionsByDate(_sessions);
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
    });
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
    });
  }

  void _goToToday() {
    final today = normalizeDate(DateTime.now());
    setState(() {
      _selectedDate = today;
      _visibleMonth = DateTime(today.year, today.month);
    });
  }

  void _onDateSelected(DateTime date) {
    final normalized = normalizeDate(date);
    setState(() {
      _selectedDate = normalized;
      if (normalized.year != _visibleMonth.year ||
          normalized.month != _visibleMonth.month) {
        _visibleMonth = DateTime(normalized.year, normalized.month);
      }
    });
  }

  CalendarDaySummary get _selectedSummary {
    return _byDate[_selectedDate] ??
        CalendarDaySummary(date: _selectedDate, sessions: const []);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: _loading
            ? const Center(child: ProgressRing())
            : _hasError
            ? _CalendarErrorState(onRetry: _loadSessions)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(
                              alpha: context.isDarkTheme ? 0.18 : 0.10,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.26),
                            ),
                          ),
                          child: const Icon(
                            FluentIcons.calendar,
                            size: 20,
                            color: _violet,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Training Calendar',
                                style: AppTheme.headingLarge.copyWith(
                                  color: _pink,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Review your consistency and daily practice activity',
                                style: AppTheme.bodySecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    CalendarHeader(
                      visibleMonth: _visibleMonth,
                      onPreviousMonth: _goToPreviousMonth,
                      onNextMonth: _goToNextMonth,
                      onToday: _goToToday,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    CalendarSummaryCards(
                      activeDays: monthlyActiveDayCount(
                        _sessions,
                        year: _visibleMonth.year,
                        month: _visibleMonth.month,
                      ),
                      monthlySessions: monthlySessionCount(
                        _sessions,
                        year: _visibleMonth.year,
                        month: _visibleMonth.month,
                      ),
                      currentStreak: currentStreak(practicedDates(_sessions)),
                      bestDay: bestTrainingDay(
                        _byDate,
                        year: _visibleMonth.year,
                        month: _visibleMonth.month,
                      ),
                    ),
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
                          summariesByDate: _byDate,
                          onDateSelected: _onDateSelected,
                        );
                        final panel = SelectedDayPanel(
                          summary: _selectedSummary,
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
            const Text(
              'Unable to load your training calendar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
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
