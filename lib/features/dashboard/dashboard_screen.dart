import 'dart:math' as math;
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movement_visuals.dart';
import '../../data/models/session.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

// Neon accent palette used only on the dashboard.
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _cyan = AppColors.primarySoft;
const _amber = AppColors.warning;
const _panelColor = AppColors.panelSurface;

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
  bool _loading = true;
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
    if (user?.id == null) return;

    final stats = await _progressRepo.getStatsForUser(user!.id!);
    final sessions = await _sessionRepo.getSessionsForUser(user.id!);
    if (mounted) {
      setState(() {
        _stats = stats;
        _sessions = sessions;
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

  DateTime? _sessionDate(Session s) {
    if (s.createdAt == null) return null;
    return DateTime.tryParse(s.createdAt!)?.toLocal();
  }

  List<Session> get _sessionsToday {
    final now = DateTime.now();
    return _sessions.where((s) {
      final d = _sessionDate(s);
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).toList();
  }

  int get _sessionsThisWeek {
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return _sessions.where((s) {
      final d = _sessionDate(s);
      return d != null && !d.isBefore(startOfWeek);
    }).length;
  }

  Set<DateTime> get _practicedDays {
    return _sessions
        .map(_sessionDate)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
  }

  int get _streakDays {
    final days = _practicedDays;
    if (days.isEmpty) return 0;
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    // A streak may still be alive if today hasn't been practiced yet.
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int? get _weeklyTrendPercent {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    double? avgBetween(int fromDaysAgo, int toDaysAgo) {
      final scores = _sessions
          .where((s) {
            final d = _sessionDate(s);
            if (d == null) return false;
            final day = DateTime(d.year, d.month, d.day);
            final diff = today.difference(day).inDays;
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
      sessionsToday: _sessionsToday,
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
      recentSessions: _sessions.take(4).toList(),
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
    required this.recentSessions,
  });

  final String firstName;
  final String greeting;
  final ProgressStats? stats;
  final int sessionsThisWeek;
  final int? weeklyTrendPercent;
  final List<Session> recentSessions;

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
        // Recent Activity
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionHeader(
              icon: FluentIcons.lightning_bolt,
              title: 'Recent Activity',
            ),
            _LinkButton(label: 'View all', onTap: () => context.go('/history')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (recentSessions.isEmpty)
          const _PanelCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No sessions yet. Complete a practice session to see it here.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final session in recentSessions) ...[
            _ActivityRow(session: session),
            const SizedBox(height: AppSpacing.sm),
          ],
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
                  _Pill(
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

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.accent = _purple,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _violet),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HyperlinkButton(
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.primarySoft),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color.lerp(color, Colors.white, 0.35),
        ),
      ),
    );
  }
}

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
    return _PanelCard(
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
              if (badge != null) _Pill(text: badge!, color: accent),
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
// Recent Activity (main column)
// ---------------------------------------------------------------------------

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.session});

  final Session session;

  String _dateLabel(String? createdAt) {
    if (createdAt == null) return '';
    final date = DateTime.tryParse(createdAt)?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(date.year, date.month, date.day);
    if (sessionDay == today) {
      return 'Today · ${DateFormat.jm().format(date)}';
    }
    if (sessionDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday · ${DateFormat.jm().format(date)}';
    }
    return DateFormat('MMM d · h:mm a').format(date);
  }

  Color get _difficultyColor {
    switch (session.difficulty) {
      case 'Easy':
        return AppColors.success;
      case 'Medium':
        return _amber;
      case 'Hard':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color get _scoreColor {
    if (session.score >= 80) return AppColors.success;
    if (session.score >= 50) return _amber;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  _purple.withValues(alpha: 0.3),
                  _pink.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(color: _purple.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(
              MovementVisuals.emojiFor(session.movementName),
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.movementName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _difficultyColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        session.difficulty,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _difficultyColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _dateLabel(session.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _scoreColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _scoreColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${session.score}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _scoreColor,
              ),
            ),
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
    required this.sessionsToday,
    required this.streakDays,
    required this.practicedDays,
    required this.bestSession,
  });

  final List<Session> sessionsToday;
  final int streakDays;
  final Set<DateTime> practicedDays;
  final Session? bestSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _QuestCard(sessionsToday: sessionsToday, streakDays: streakDays),
        const SizedBox(height: AppSpacing.md),
        _CalendarCard(practicedDays: practicedDays),
        const SizedBox(height: AppSpacing.md),
        _TopPerformanceCard(bestSession: bestSession),
      ],
    );
  }
}

// ---- Today's Quest --------------------------------------------------------

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.sessionsToday, required this.streakDays});

  final List<Session> sessionsToday;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final quests = <({String title, int xp, bool done})>[
      (
        title: 'Complete 1 Practice Session',
        xp: 10,
        done: sessionsToday.isNotEmpty,
      ),
      (
        title: 'Score 80+ in a Session',
        xp: 15,
        done: sessionsToday.any((s) => s.score >= 80),
      ),
      (
        title: 'Practice 2 Different Movements',
        xp: 20,
        done: sessionsToday.map((s) => s.movementName).toSet().length >= 2,
      ),
    ];
    final doneCount = quests.where((q) => q.done).length;

    return _PanelCard(
      accent: _pink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(FluentIcons.lightning_bolt, size: 14, color: _amber),
                  SizedBox(width: 6),
                  Text(
                    "Today's Quest",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (streakDays > 0)
                _Pill(text: '🔥 $streakDays Day Streak', color: _amber),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final quest in quests) ...[
            _QuestTile(title: quest.title, xp: quest.xp, done: quest.done),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CustomPaint(
                  painter: _GaugePainter(progress: doneCount / quests.length),
                  child: Center(
                    child: Text(
                      '$doneCount/${quests.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doneCount == quests.length
                          ? 'All quests complete. Amazing work!'
                          : doneCount > 0
                          ? "Keep going! You're getting better!"
                          : 'Complete quests to earn XP.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          children: [
                            Container(color: AppColors.border),
                            FractionallySizedBox(
                              widthFactor: doneCount / quests.length,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_pink, _purple],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _QuestTile extends StatelessWidget {
  const _QuestTile({required this.title, required this.xp, required this.done});

  final String title;
  final int xp;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: done
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppColors.success : Colors.transparent,
              border: done
                  ? null
                  : Border.all(color: AppColors.textSecondary, width: 1.5),
            ),
            child: done
                ? const Icon(
                    FluentIcons.check_mark,
                    size: 10,
                    color: Color(0xFF0D0D0F),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: done ? AppColors.textSecondary : AppColors.textPrimary,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '+$xp XP',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const stroke = 10.0;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawCircle(center, radius, bg);

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: const [_pink, _violet, _purple, _cyan],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ---- Practice Calendar ------------------------------------------------------

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.practicedDays});

  final Set<DateTime> practicedDays;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // Sunday-first offset (DateTime.weekday: Mon=1..Sun=7)
    final leadingEmpty = firstOfMonth.weekday % 7;
    final today = DateTime(now.year, now.month, now.day);

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(FluentIcons.calendar, size: 14, color: _violet),
                  SizedBox(width: 6),
                  Text(
                    'Practice Calendar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                DateFormat.yMMMM().format(now),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final d in const [
                'Sun',
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
              ])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var week = 0; week * 7 < leadingEmpty + daysInMonth; week++) ...[
            Row(
              children: [
                for (var dow = 0; dow < 7; dow++)
                  Expanded(
                    child: _calendarCell(
                      week * 7 + dow - leadingEmpty + 1,
                      daysInMonth,
                      now,
                      today,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _calendarCell(int day, int daysInMonth, DateTime now, DateTime today) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: 30);
    }
    final date = DateTime(now.year, now.month, day);
    final practiced = practicedDays.contains(date);
    final isToday = date == today;

    return SizedBox(
      height: 30,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: isToday
              ? const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_pink, _purple]),
                )
              : practiced
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: _purple.withValues(alpha: 0.28),
                  border: Border.all(color: _purple.withValues(alpha: 0.55)),
                )
              : null,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday || practiced
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: isToday
                  ? Colors.white
                  : practiced
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Top Performance --------------------------------------------------------

class _TopPerformanceCard extends StatelessWidget {
  const _TopPerformanceCard({required this.bestSession});

  final Session? bestSession;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
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
