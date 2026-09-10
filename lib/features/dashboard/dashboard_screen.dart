import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/movements.dart';
import '../../core/progression/practice_variant.dart';
import '../../core/progression/progression_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/utils/user_name.dart';
import '../../core/utils/manila_day.dart';
import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import '../../data/models/session.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/gamification_repository.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../services/trainee_progression_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../calendar/utils/calendar_metrics.dart';
import '../trainee/activity_center/trainee_activity_controller.dart';
import '../progress/training_recommendation.dart';
import '../training/training_view.dart';
import 'dashboard_session_metrics.dart';
import 'dashboard_stats_loader.dart';
import 'widgets/dashboard_calendar_card.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/dashboard_panel_card.dart';
import 'widgets/dashboard_hero.dart';
import 'widgets/dashboard_leaderboard.dart';
import 'widgets/dashboard_quest_card.dart';
import 'widgets/dashboard_top_performance.dart';
import 'widgets/dashboard_training_overview.dart';
import 'widgets/recommended_practice_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.sessionRepository,
    this.leaderboardRepository,
    this.gamificationRepository,
  });

  final SessionRepository? sessionRepository;
  final LeaderboardRepository? leaderboardRepository;
  final GamificationRepository? gamificationRepository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final SessionRepository _sessionRepo;
  late final DashboardStatsLoader _loader;
  String? _authUserId;
  SessionService? _sessionService;
  AuthService? _authService;

  static const _maxContentWidth = 1440.0;
  static const _wideBreakpoint = 1080.0;
  static const _railWidth = 350.0;

  @override
  void initState() {
    super.initState();
    _sessionRepo = widget.sessionRepository ?? SessionRepository();
    _loader = DashboardStatsLoader(sessionRepository: _sessionRepo);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SessionService>();
    if (service != _sessionService) {
      _sessionService?.removeListener(_onSessionSaved);
      _sessionService = service..addListener(_onSessionSaved);
    }
    final auth = context.read<AuthService>();
    if (auth != _authService) {
      _authService?.removeListener(_onAuthChanged);
      _authService = auth..addListener(_onAuthChanged);
    }
    _syncUser(auth.currentUser?.id);
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionSaved);
    _authService?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onSessionSaved() => _loadStats();

  void _onAuthChanged() {
    _syncUser(_authService?.currentUser?.id);
  }

  void _syncUser(String? userId) {
    if (userId == _authUserId) return;
    _authUserId = userId;
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    final userId = context.read<AuthService>().currentUser?.id;
    final pending = _loader.load(
      userId,
      stillCurrent: () =>
          mounted && context.read<AuthService>().currentUser?.id == userId,
      buildRecommendation: (sessions) {
        return buildTrainingRecommendation(
          sessions: sessions,
          movements: movementCatalog,
          readyPracticeVariantFor: (movement) {
            final progression = context.read<TraineeProgressionService>();
            final tutorials = context.read<TutorialProgressService>();
            if (!progression.isReady || !tutorials.isInitialized) {
              return null;
            }
            for (final prop in movement.supportedProps) {
              final access = evaluatePersonal(
                variant: PracticeVariant(
                  movementName: movement.name,
                  trainingProp: prop,
                ),
                currentLevel: progression.currentLevelOrNull,
                tutorialCompleted: tutorials.hasCompletedLesson(
                  movement.name,
                  prop,
                ),
              );
              if (access == ProgressionAccessResult.personalReady) {
                return PracticeVariant(
                  movementName: movement.name,
                  trainingProp: prop,
                );
              }
            }
            return null;
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    await pending;
    if (!mounted) return;
    setState(() {});
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  DashboardSessionMetrics get _metrics =>
      DashboardSessionMetrics.fromSessions(_loader.sessions);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final userId = user?.id;
    final normalizedFirstName = normalizeNamePart(user?.firstName ?? '');
    final firstName = normalizedFirstName.isNotEmpty
        ? normalizedFirstName
        : 'Trainee';

    final firstLoadErrorForUser =
        _loader.showFullPageError && _loader.requestedUserId == userId;
    if (firstLoadErrorForUser) {
      return ElixScaffoldPage(
        padding: EdgeInsets.zero,
        content: Center(
          child: ElixStatusPanel(
            isError: true,
            icon: FluentIcons.warning,
            title: 'Dashboard unavailable',
            message: _loader.loadError!,
            actionLabel: 'Retry',
            onAction: _loadStats,
          ),
        ),
      );
    }

    if (userId != null && !_loader.hasDataFor(userId)) {
      return const ElixScaffoldPage(
        padding: EdgeInsets.zero,
        content: Center(
          child: ElixStatusPanel(
            isLoading: true,
            title: 'Loading your dashboard',
            message: 'Getting your latest training activity.',
          ),
        ),
      );
    }

    final metrics = _metrics;
    final rightRail = _RightRail(
      userId: user?.id,
      sessions: _loader.sessions,
      streakDays: metrics.currentStreak,
      practicedDays: metrics.practicedDays,
      bestSession: metrics.bestSession,
      gamificationRepository: widget.gamificationRepository,
    );

    final mainColumn = _MainColumn(
      stats: _loader.stats,
      sessionsThisWeek: metrics.sessionsThisWeek,
      weeklyComparison: metrics.weeklyComparison,
      currentUserId: user?.id,
      displayName: user?.fullName ?? 'Trainee',
      profilePictureUrl: user?.profilePictureUrl,
      trainingRecommendation: _loader.trainingRecommendation,
      recommendationLoading: _loader.loading,
      leaderboardRepository: widget.leaderboardRepository,
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
        child: Column(
          children: [
            if (_loader.showInlineError) ...[
              ElixStatusPanel(
                isError: true,
                icon: FluentIcons.warning,
                message: _loader.loadError!,
                actionLabel: 'Retry',
                onAction: _loadStats,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Column(
                  children: [
                    DashboardHeader(
                      firstName: firstName,
                      greeting: _timeGreeting(),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
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
                          children: [
                            mainColumn,
                            const SizedBox(height: 18),
                            rightRail,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn({
    required this.stats,
    required this.sessionsThisWeek,
    required this.weeklyComparison,
    required this.currentUserId,
    required this.displayName,
    required this.trainingRecommendation,
    required this.recommendationLoading,
    this.profilePictureUrl,
    this.leaderboardRepository,
  });

  final ProgressStats? stats;
  final int sessionsThisWeek;
  final ComparableRubricComparison weeklyComparison;
  final String? currentUserId;
  final String displayName;
  final TrainingRecommendation? trainingRecommendation;
  final bool recommendationLoading;
  final String? profilePictureUrl;
  final LeaderboardRepository? leaderboardRepository;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardHero(
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
          weeklyComparison: weeklyComparison,
        ),
        const SizedBox(height: 20),
        DashboardLeaderboard(
          currentUserId: currentUserId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
          repository: leaderboardRepository,
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
            complete: tutorial.hasCompletedLesson(
              'Normal Grip',
              TrainingProp.bottle,
            ),
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
    this.gamificationRepository,
  });

  final String? userId;
  final List<Session> sessions;
  final int streakDays;
  final Set<DateTime> practicedDays;
  final Session? bestSession;
  final GamificationRepository? gamificationRepository;

  @override
  Widget build(BuildContext context) {
    final classroomDays = context
        .watch<TraineeActivityController>()
        .classroomWork
        .where((item) => item.assignment.dueAt != null)
        .map(
          (item) => ManilaDay.civilDateFromDayKey(
            ManilaDay.dayKeyFor(item.assignment.dueAt!.toUtc()),
          ),
        )
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (userId != null)
          DashboardQuestCard(
            userId: userId!,
            sessions: sessions,
            streakDays: streakDays,
            repository: gamificationRepository,
          ),
        const SizedBox(height: 18),
        DashboardCalendarCard(
          practicedDays: practicedDays,
          classroomDays: classroomDays,
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
