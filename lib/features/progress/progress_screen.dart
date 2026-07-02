import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_stat_card.dart';
import '../../data/repositories/progress_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _repo = ProgressRepository();
  ProgressStats? _stats;
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
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;

    final stats = await _repo.getStatsForUser(userId);
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: SafeArea(
        child: _loading
            ? const Center(child: ProgressRing())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Progress', style: AppTheme.headingLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Track your training performance over time',
                      style: AppTheme.bodySecondary,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_stats!.totalSessions == 0)
                      _EmptyState()
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElixStatCard(
                              label: 'Avg Score',
                              value: _stats!.averageScore?.toStringAsFixed(0) ?? '—',
                              icon: FluentIcons.favorite_star_fill,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: ElixStatCard(
                              label: 'Total Sessions',
                              value: '${_stats!.totalSessions}',
                              icon: FluentIcons.clock,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: ElixStatCard(
                              label: 'Best Score',
                              value: _stats!.bestScore?.toString() ?? '—',
                              icon: FluentIcons.trophy2_solid,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: ElixStatCard(
                              label: 'Most Practiced',
                              value: _stats!.mostPracticedMovement ?? '—',
                              icon: FluentIcons.more_sports,
                              smallValue: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Sessions by Movement', style: AppTheme.headingMedium),
                      const SizedBox(height: AppSpacing.md),
                      ElixCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: SizedBox(
                          height: 220,
                          child: _MovementChart(
                            data: _stats!.sessionsByMovement,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElixCard(
      child: Column(
        children: [
          Icon(
            FluentIcons.bar_chart_vertical_fill,
            size: 48,
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('No progress data yet', style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Complete practice sessions to unlock charts and stats.',
            style: AppTheme.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MovementChart extends StatelessWidget {
  const _MovementChart({required this.data});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY.toDouble() + 1,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: AppTheme.caption,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                final name = entries[index].key;
                final short = name.length > 8 ? '${name.substring(0, 7)}…' : name;
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(short, style: AppTheme.caption),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: AppColors.primary,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
