import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/utils/user_name.dart';
import '../../data/models/session.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../calendar/utils/calendar_metrics.dart';
import '../progress/training_recommendation.dart';
import '../training/training_view.dart';
import 'widgets/dashboard_calendar_card.dart';
import 'widgets/dashboard_panel_card.dart';
import 'widgets/dashboard_hero.dart';
import 'widgets/dashboard_leaderboard.dart';
import 'widgets/dashboard_quest_card.dart';
import 'widgets/dashboard_top_performance.dart';
import 'widgets/dashboard_training_overview.dart';
import 'widgets/recommended_practice_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _progressRepo = ProgressRepository();
  final _sessionRepo = SessionRepository();
  ProgressStats? _stats;
  List<Session> _sessions = const [];
  TrainingRecommendation? _trainingRecommendation;
  bool _loading = true;
  String? _loadedUserId;
  SessionService? _sessionService;

  static const _maxContentWidth = 1440.0;
  static const _wideBreakpoint = 1080.0;
  static const _railWidth = 350.0;

  @override
  void initState() {
    super.initState();
    _loadStats();
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

  void _onSessionSaved() => _loadStats();

  Future<void> _loadStats() async {
    if (!mounted) return;
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _stats = null;
          _sessions = const [];
          _trainingRecommendation = null;
          _loadedUserId = null;
          _loading = false;
        });
      }
      return;
    }

    if (_loadedUserId != userId) {
      setState(() {
        _loading = true;
        _trainingRecommendation = null;
      });
    }

    final stats = await _progressRepo.getStatsForUser(userId);
    final sessions = await _sessionRepo.getSessionsForUser(userId);
    if (!mounted || context.read<AuthService>().currentUser?.id != userId) {
      return;
    }

    final recommendation = buildTrainingRecommendation(
      sessions: sessions,
      movements: movementCatalog,
    );
    if (mounted) {
      setState(() {
        _stats = stats;
        _sessions = sessions;
        _trainingRecommendation = recommendation;
        _loadedUserId = userId;
        _loading = false;
      });
    }
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  int get _sessionsThisWeek {
    final now = DateTime.now();
    final startOfWeek = normalizeDate(
      now,
    ).subtract(Duration(days: now.weekday - 1));
    return _sessions.where((s) {
      final d = parseSessionLocalDate(s);
      return d != null && !d.isBefore(startOfWeek);
    }).length;
  }

  Set<DateTime> get _practicedDays => practicedDates(_sessions);

  int get _streakDays => currentStreak(_practicedDays);

  /// Week-over-week change in average rubric total (Assessment V2 only).
  ///
  /// Legacy percentage sessions are excluded so the two scales never mix.
  int? get _weeklyTrendPercent {
    final today = normalizeDate(DateTime.now());
    double? avgBetween(int fromDaysAgo, int toDaysAgo) {
      final totals = <int>[
        for (final s in _sessions)
          if (s.isRubricAssessed)
            if (_isWithin(s, today, fromDaysAgo, toDaysAgo)) s.rubricTotal!,
      ];
      if (totals.isEmpty) return null;
      return totals.reduce((a, b) => a + b) / totals.length;
    }

    final thisWeek = avgBetween(6, 0);
    final lastWeek = avgBetween(13, 7);
    if (thisWeek == null || lastWeek == null || lastWeek == 0) return null;
    return (((thisWeek - lastWeek) / lastWeek) * 100).round();
  }

  static bool _isWithin(
    Session session,
    DateTime today,
    int fromDaysAgo,
    int toDaysAgo,
  ) {
    final date = parseSessionLocalDate(session);
    if (date == null) return false;
    final diff = today.difference(date).inDays;
    return diff >= toDaysAgo && diff <= fromDaysAgo;
  }

  /// Personal best, preferring the Assessment V2 cohort.
  ///
  /// A rubric total (0..12) is never compared against a legacy score (0..100),
  /// so legacy sessions are only considered when no V2 session exists.
  Session? get _bestSession {
    Session? bestRubric;
    Session? bestLegacy;
    for (final s in _sessions) {
      if (s.isRubricAssessed) {
        if (bestRubric == null || s.rubricTotal! > bestRubric.rubricTotal!) {
          bestRubric = s;
        }
      } else if (s.legacyScore != null) {
        if (bestLegacy == null || s.legacyScore! > bestLegacy.legacyScore!) {
          bestLegacy = s;
        }
      }
    }
    return bestRubric ?? bestLegacy;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final normalizedFirstName = normalizeNamePart(user?.firstName ?? '');
    final firstName = normalizedFirstName.isNotEmpty
        ? normalizedFirstName
        : 'Trainee';

    if (_loading) {
      return const ElixScaffoldPage(
        padding: EdgeInsets.zero,
        content: Center(child: ProgressRing()),
      );
    }

    final rightRail = _RightRail(
      userId: user?.id,
      sessions: _sessions,
      streakDays: _streakDays,
      practicedDays: _practicedDays,
      bestSession: _bestSession,
    );

    final mainColumn = _MainColumn(
      firstName: firstName,
      greeting: _timeGreeting(),
      stats: _stats,
      sessionsThisWeek: _sessionsThisWeek,
      weeklyTrendPercent: _weeklyTrendPercent,
      currentUserId: user?.id,
      displayName: user?.fullName ?? 'Trainee',
      profilePictureUrl: user?.profilePictureUrl,
      trainingRecommendation: _trainingRecommendation,
      recommendationLoading: _loading,
    );

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.pageTopInset,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: mainColumn),
                      const SizedBox(width: 18),
                      SizedBox(width: _railWidth, child: rightRail),
                    ],
                  );
                }
                return Column(
                  children: [mainColumn, const SizedBox(height: 18), rightRail],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn({
    required this.firstName,
    required this.greeting,
    required this.stats,
    required this.sessionsThisWeek,
    required this.weeklyTrendPercent,
    required this.currentUserId,
    required this.displayName,
    required this.trainingRecommendation,
    required this.recommendationLoading,
    this.profilePictureUrl,
  });

  final String firstName;
  final String greeting;
  final ProgressStats? stats;
  final int sessionsThisWeek;
  final int? weeklyTrendPercent;
  final String? currentUserId;
  final String displayName;
  final TrainingRecommendation? trainingRecommendation;
  final bool recommendationLoading;
  final String? profilePictureUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardHero(
          firstName: firstName,
          greeting: greeting,
          sessionCount: stats?.totalSessions ?? 0,
          recommendation: trainingRecommendation,
        ),
        const SizedBox(height: 18),
        if (stats?.totalSessions == 0) ...[
          const _QuickStartCard(),
          const SizedBox(height: 18),
        ],
        RecommendedPracticeCard(
          recommendation: trainingRecommendation,
          loading: recommendationLoading,
        ),
        const SizedBox(height: 18),
        DashboardTrainingOverview(
          stats: stats,
          sessionsThisWeek: sessionsThisWeek,
          weeklyTrendPercent: weeklyTrendPercent,
        ),
        const SizedBox(height: 20),
        DashboardLeaderboard(
          currentUserId: currentUserId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
        ),
      ],
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard();
  @override
  Widget build(BuildContext context) {
    final tutorial = context.watch<TutorialProgressService>();
    return DashboardPanelCard(
      accent: AppColors.primary,
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FluentIcons.rocket,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUICK START',
                      style: AppTheme.caption.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Complete your first session',
                      style: AppTheme.headingMedium.copyWith(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _QuickStartStep(
            label: 'Learn one Easy movement',
            complete: tutorial.hasCompletedLesson('Normal Grip'),
          ),
          _QuickStartStep(
            label: 'Complete camera setup',
            complete: tutorial.firstCameraSetupComplete,
          ),
          const _QuickStartStep(
            label: 'Complete and save a guided session',
            complete: false,
          ),
          const SizedBox(height: 6),
          HyperlinkButton(
            onPressed: () => context.go(
              '/learn/movement/Normal%20Grip?difficulty=Easy&prop=bottle',
            ),
            child: const Text('Learn Normal Grip'),
          ),
        ],
      ),
    );
  }
}

class _QuickStartStep extends StatelessWidget {
  const _QuickStartStep({required this.label, required this.complete});
  final String label;
  final bool complete;
  @override
  Widget build(BuildContext context) {
    final color = complete ? AppColors.success : context.elixTextSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color.withValues(alpha: complete ? 0.16 : 0.08),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              shape: BoxShape.circle,
            ),
            child: complete
                ? const Icon(
                    FluentIcons.check_mark,
                    size: 9,
                    color: AppColors.success,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: complete
                  ? context.elixTextSecondary
                  : context.elixTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RightRail extends StatelessWidget {
  const _RightRail({
    required this.userId,
    required this.sessions,
    required this.streakDays,
    required this.practicedDays,
    required this.bestSession,
  });

  final String? userId;
  final List<Session> sessions;
  final int streakDays;
  final Set<DateTime> practicedDays;
  final Session? bestSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (userId != null)
          DashboardQuestCard(
            userId: userId!,
            sessions: sessions,
            streakDays: streakDays,
          ),
        const SizedBox(height: 18),
        DashboardCalendarCard(
          practicedDays: practicedDays,
          onViewCalendar: () =>
              context.go(trainingLocation(view: TrainingView.planner)),
          onDateSelected: (date) {
            context.go(
              trainingLocation(
                view: TrainingView.planner,
                date: formatCalendarQueryDate(date),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        DashboardTopPerformance(bestSession: bestSession),
      ],
    );
  }
}
