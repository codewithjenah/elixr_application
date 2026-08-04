import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../data/models/session.dart';
import '../progress/training_recommendation.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../calendar/utils/calendar_metrics.dart';
import 'widgets/dashboard_calendar_card.dart';
import 'widgets/dashboard_leaderboard.dart';
import 'widgets/dashboard_panel_card.dart';
import 'widgets/dashboard_quest_card.dart';
import 'widgets/recommended_practice_card.dart';

// Neon accent palette used only on the dashboard.
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _cyan = AppColors.primarySoft;
const _amber = AppColors.warning;

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

  // ---- derived data -------------------------------------------------------

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

  int? get _weeklyTrendPercent {
    final today = normalizeDate(DateTime.now());
    double? avgBetween(int fromDaysAgo, int toDaysAgo) {
      final scores = _sessions
          .where((s) {
            final d = parseSessionLocalDate(s);
            if (d == null) return false;
            final diff = today.difference(d).inDays;
            return diff >= toDaysAgo && diff <= fromDaysAgo;
          })
          .map((s) => s.score);
      if (scores.isEmpty) return null;
      return scores.reduce((a, b) => a + b) / scores.length;
    }

    final thisWeek = avgBetween(6, 0);
    final lastWeek = avgBetween(13, 7);
    if (thisWeek == null || lastWeek == null || lastWeek == 0) return null;
    return (((thisWeek - lastWeek) / lastWeek) * 100).round();
  }

  /// The movement of the best-scoring session (for Top Performance).
  Session? get _bestSession {
    Session? best;
    for (final s in _sessions) {
      if (best == null || s.score > best.score) best = s;
    }
    return best;
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final firstName = user?.fullName.split(' ').first ?? 'Trainee';

    if (_loading) {
      return const ScaffoldPage(
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

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: mainColumn),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(width: 320, child: rightRail),
                ],
              );
            }
            return Column(
              children: [
                mainColumn,
                const SizedBox(height: AppSpacing.md),
                rightRail,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main column
// ---------------------------------------------------------------------------

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
    final avg = stats?.averageScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroBanner(
          firstName: firstName,
          greeting: greeting,
          sessionCount: stats?.totalSessions ?? 0,
        ),
        const SizedBox(height: AppSpacing.md),
        RecommendedPracticeCard(
          recommendation: trainingRecommendation,
          loading: recommendationLoading,
        ),
        const SizedBox(height: AppSpacing.md),
        // Stat cards
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Total Sessions',
                  value: '${stats?.totalSessions ?? 0}',
                  subLabel: sessionsThisWeek > 0
                      ? '↑ $sessionsThisWeek this week'
                      : 'Start practicing!',
                  icon: FluentIcons.timer,
                  accent: _purple,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  label: 'Average Score',
                  value: avg != null ? avg.toStringAsFixed(0) : '—',
                  valueSuffix: avg != null ? ' /100' : null,
                  subLabel: weeklyTrendPercent != null
                      ? '${weeklyTrendPercent! >= 0 ? '↑' : '↓'} ${weeklyTrendPercent!.abs()}% vs last week'
                      : 'All time',
                  icon: FluentIcons.favorite_star_fill,
                  accent: _violet,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  label: 'Best Score',
                  value: stats?.bestScore?.toString() ?? '—',
                  subLabel: 'Personal record',
                  icon: FluentIcons.trophy2_solid,
                  accent: _amber,
                  badge: (stats?.bestScore ?? 0) >= 100 ? 'New!' : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  label: 'Top Move',
                  value: stats?.mostPracticedMovement ?? '—',
                  subLabel: 'Most practiced',
                  icon: FluentIcons.crown_solid,
                  accent: _cyan,
                  smallValue: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        DashboardLeaderboard(
          currentUserId: currentUserId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero banner
// ---------------------------------------------------------------------------

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.firstName,
    required this.greeting,
    required this.sessionCount,
  });

  final String firstName;
  final String greeting;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          border: Border.all(color: _purple.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/banner.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            // Left-to-right vignette for readability
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.55, 1.0],
                  colors: [
                    const Color(0xEE13091F),
                    const Color(0x9913091F),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xCCFFFFFF),
                      ),
                      children: [
                        TextSpan(text: '$greeting, '),
                        TextSpan(
                          text: firstName,
                          style: const TextStyle(
                            color: AppColors.primarySoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: '! 👋'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Train. Flip. Master.',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: _pink,
                      height: 1.05,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your journey to flair excellence starts here.',
                    style: TextStyle(fontSize: 14, color: Color(0xCCFFFFFF)),
                  ),
                  const SizedBox(height: 14),
                  DashboardPill(
                    text: '🔥 $sessionCount Sessions Completed',
                    color: _pink,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _HeroActionButton(
                        label: 'Start Practicing',
                        icon: FluentIcons.play_solid,
                        primary: true,
                        onPressed: () => context.go('/movements'),
                      ),
                      const SizedBox(width: 12),
                      _HeroActionButton(
                        label: 'Browse Movements',
                        icon: FluentIcons.grid_view_medium,
                        onPressed: () => context.go('/movements'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Quote, bottom right
            Positioned(
              right: 28,
              bottom: 22,
              child: LayoutBuilder(
                builder: (context, _) {
                  final width = MediaQuery.of(context).size.width;
                  if (width < 1100) return const SizedBox.shrink();
                  return const Text(
                    '“Great flair starts with great practice.”',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _pink,
                      shadows: [
                        Shadow(color: Color(0x668B5CF6), blurRadius: 12),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: widget.primary
          ? LinearGradient(
              colors: _hovered
                  ? const [AppColors.primarySoft, _violet]
                  : const [_pink, _purple],
            )
          : null,
      color: widget.primary
          ? null
          : Colors.white.withValues(alpha: _hovered ? 0.16 : 0.08),
      border: widget.primary
          ? null
          : Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.45 : 0.25),
            ),
      boxShadow: widget.primary
          ? [
              BoxShadow(
                color: _pink.withValues(alpha: _hovered ? 0.5 : 0.35),
                blurRadius: _hovered ? 22 : 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 13, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: widget.primary
            ? content
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: content,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.accent,
    this.valueSuffix,
    this.badge,
    this.smallValue = false,
  });

  final String label;
  final String value;
  final String subLabel;
  final IconData icon;
  final Color accent;
  final String? valueSuffix;
  final String? badge;
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    return DashboardPanelCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) DashboardPill(text: badge!, color: accent),
            ],
          ),
          const SizedBox(height: 14),
          RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: smallValue ? 16 : 26,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    height: 1.1,
                  ),
                ),
                if (valueSuffix != null)
                  TextSpan(
                    text: valueSuffix,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subLabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right rail
// ---------------------------------------------------------------------------

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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (userId != null)
          DashboardQuestCard(
            userId: userId!,
            sessions: sessions,
            streakDays: streakDays,
          ),
        const SizedBox(height: AppSpacing.md),
        DashboardCalendarCard(
          practicedDays: practicedDays,
          onViewCalendar: () => context.go('/calendar'),
          onDateSelected: (date) {
            final value = DateFormat('yyyy-MM-dd').format(date);
            context.go('/calendar?date=$value');
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _TopPerformanceCard(bestSession: bestSession),
      ],
    );
  }
}

// ---- Top Performance --------------------------------------------------------

class _TopPerformanceCard extends StatelessWidget {
  const _TopPerformanceCard({required this.bestSession});

  final Session? bestSession;

  @override
  Widget build(BuildContext context) {
    return DashboardPanelCard(
      accent: _amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(FluentIcons.trophy2_solid, size: 14, color: _amber),
              SizedBox(width: 6),
              Text(
                'Top Performance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          bestSession == null
              ? const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Complete a session to set your first record.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bestSession!.score}',
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: _amber,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Best Score',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            bestSession!.movementName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 84,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _amber.withValues(alpha: 0.18),
                            _pink.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('👑', style: TextStyle(fontSize: 18)),
                          SizedBox(height: 2),
                          Text('🍾', style: TextStyle(fontSize: 32)),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
