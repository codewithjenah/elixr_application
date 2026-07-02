import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_stat_card.dart';
import '../../data/models/session.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _progressRepo = ProgressRepository();
  final _sessionRepo = SessionRepository();
  int _sessionCount = 0;
  double? _avgScore;
  Session? _recentSession;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    context.read<SessionService>().addListener(_onSessionSaved);
  }

  @override
  void dispose() {
    context.read<SessionService>().removeListener(_onSessionSaved);
    super.dispose();
  }

  void _onSessionSaved() => _loadStats();

  Future<void> _loadStats() async {
    final user = context.read<AuthService>().currentUser;
    if (user?.id == null) return;

    final stats = await _progressRepo.getStatsForUser(user!.id!);
    final sessions = await _sessionRepo.getSessionsForUser(user.id!);
    if (mounted) {
      setState(() {
        _sessionCount = stats.totalSessions;
        _avgScore = stats.averageScore;
        _recentSession = sessions.isNotEmpty ? sessions.first : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final firstName = user?.fullName.split(' ').first ?? 'Trainee';

    return ScaffoldPage(
      content: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroCard(firstName: firstName),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: ElixStatCard(
                      label: 'Total Sessions',
                      value: _loading ? '—' : '$_sessionCount',
                      icon: FluentIcons.clock,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElixStatCard(
                      label: 'Avg Score',
                      value: _loading
                          ? '—'
                          : _avgScore != null
                              ? _avgScore!.toStringAsFixed(0)
                              : '—',
                      icon: FluentIcons.favorite_star_fill,
                    ),
                  ),
                ],
              ),
              if (_recentSession != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Activity', style: AppTheme.headingMedium),
                    HyperlinkButton(
                      onPressed: () => context.go('/history'),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _RecentSessionCard(session: _recentSession!),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text('Quick Actions', style: AppTheme.headingMedium),
              const SizedBox(height: AppSpacing.md),
              _QuickActionCard(
                title: 'Browse Movements',
                subtitle: 'Explore Easy, Medium, and Hard tricks',
                icon: FluentIcons.more_sports,
                accent: AppColors.primary,
                onTap: () => context.go('/movements'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuickActionCard(
                title: 'View History',
                subtitle: 'Review your past training sessions',
                icon: FluentIcons.history,
                accent: AppColors.primarySoft,
                onTap: () => context.go('/history'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuickActionCard(
                title: 'Track Progress',
                subtitle: 'See scores and practice trends',
                icon: FluentIcons.bar_chart_vertical_fill,
                accent: AppColors.success,
                onTap: () => context.go('/progress'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A1520),
            Color(0xFF1A1A1F),
            Color(0xFF151018),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $firstName',
            style: AppTheme.headingLarge.copyWith(fontSize: 32),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ready to sharpen your bottle flair skills?',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            label: 'Start Practicing',
            expanded: false,
            onPressed: () => context.go('/movements'),
          ),
        ],
      ),
    );
  }
}

class _RecentSessionCard extends StatelessWidget {
  const _RecentSessionCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      onTap: () => context.go('/history'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              FluentIcons.play_solid,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.movementName,
                  style: AppTheme.headingMedium.copyWith(fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${session.difficulty} · ${session.durationSeconds}s',
                  style: AppTheme.bodySecondary,
                ),
              ],
            ),
          ),
          _ScoreBadge(score: session.score),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  Color get _color {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withValues(alpha: 0.12),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: AppTheme.headingMedium.copyWith(
          color: _color,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.25),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.headingMedium.copyWith(fontSize: 16)),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: AppTheme.bodySecondary),
              ],
            ),
          ),
          Icon(
            FluentIcons.chevron_right,
            color: accent.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
