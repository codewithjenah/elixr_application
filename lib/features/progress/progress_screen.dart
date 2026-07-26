import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/session.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

// Neon accent palette shared with the dashboard.
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _cyan = AppColors.primarySoft;
const _amber = AppColors.warning;
const _panelColor = AppColors.panelSurface;

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _repo = ProgressRepository();
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
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;

    final stats = await _repo.getStatsForUser(userId);
    final sessions = await _sessionRepo.getSessionsForUser(userId);
    if (mounted) {
      setState(() {
        _stats = stats;
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  /// Sessions oldest-first with a valid score, for the trend line.
  List<Session> get _chronological {
    final list = _sessions.where((s) => s.createdAt != null).toList()
      ..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
    return list;
  }

  Map<String, int> get _difficultyBreakdown {
    final map = <String, int>{'Easy': 0, 'Medium': 0, 'Hard': 0};
    for (final s in _sessions) {
      map[s.difficulty] = (map[s.difficulty] ?? 0) + 1;
    }
    return map;
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
                    Text(
                      'Progress',
                      style: AppTheme.headingLarge.copyWith(color: _pink),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Track your training performance over time',
                      style: AppTheme.bodySecondary,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_stats!.totalSessions == 0)
                      _EmptyState()
                    else ...[
                      // ── 2×2 stat grid ──────────────────────────────────
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: 'Avg Score',
                                value:
                                    _stats!.averageScore?.toStringAsFixed(0) ??
                                    '—',
                                icon: FluentIcons.favorite_star_fill,
                                accent: _pink,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _StatCard(
                                label: 'Total Sessions',
                                value: '${_stats!.totalSessions}',
                                icon: FluentIcons.timer,
                                accent: _purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: 'Best Score',
                                value: _stats!.bestScore?.toString() ?? '—',
                                icon: FluentIcons.trophy2_solid,
                                accent: _amber,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _StatCard(
                                label: 'Most Practiced',
                                value: _stats!.mostPracticedMovement ?? '—',
                                icon: FluentIcons.crown_solid,
                                accent: _cyan,
                                smallValue: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // ── Score trend ─────────────────────────────────────
                      if (_chronological.length >= 2) ...[
                        const _SectionHeader(
                          icon: FluentIcons.line_chart,
                          title: 'Score Trend',
                          accent: _pink,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _PanelCard(
                          accent: _pink,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: SizedBox(
                            height: 200,
                            child: _ScoreTrendChart(sessions: _chronological),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],

                      // ── Difficulty breakdown ────────────────────────────
                      const _SectionHeader(
                        icon: FluentIcons.chart_template,
                        title: 'Difficulty Breakdown',
                        accent: _amber,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PanelCard(
                        accent: _amber,
                        child: _DifficultyBreakdown(
                          data: _difficultyBreakdown,
                          total: _stats!.totalSessions,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // ── Chart section ───────────────────────────────────
                      const _SectionHeader(
                        icon: FluentIcons.bar_chart_vertical,
                        title: 'Sessions by Movement',
                        accent: _purple,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PanelCard(
                        accent: _purple,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: SizedBox(
                          height: 250,
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

// ── Panel card (dashboard-style glowing panel) ───────────────────────────────

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.accent = _purple,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.glow = false,
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: glow ? 0.55 : 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: glow ? 0.22 : 0.07),
            blurRadius: glow ? 24 : 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTheme.headingMedium),
      ],
    );
  }
}

// ── Stat card (hover-interactive) ────────────────────────────────────────────

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.smallValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool smallValue;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _PanelCard(
        accent: widget.accent,
        glow: _hovered,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: widget.accent, size: 15),
            ),
            const SizedBox(height: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.value,
                  style: TextStyle(
                    fontSize: widget.smallValue ? 16 : 24,
                    fontWeight: FontWeight.w800,
                    color: widget.accent,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _purple.withValues(alpha: 0.25),
                  _pink.withValues(alpha: 0.12),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              FluentIcons.bar_chart_vertical_fill,
              size: 40,
              color: _violet,
            ),
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

// ── Score trend line chart (interactive tooltip) ─────────────────────────────

class _ScoreTrendChart extends StatelessWidget {
  const _ScoreTrendChart({required this.sessions});

  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < sessions.length; i++)
        FlSpot(i.toDouble(), sessions[i].score.toDouble()),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.border.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 25,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _panelColor,
            tooltipBorder: const BorderSide(color: _pink),
            getTooltipItems: (touched) => touched.map((t) {
              final s = sessions[t.x.toInt()];
              final date = s.createdAt != null
                  ? DateFormat.MMMd().format(
                      DateTime.parse(s.createdAt!).toLocal(),
                    )
                  : '';
              return LineTooltipItem(
                '${s.score}\n',
                const TextStyle(
                  color: AppColors.primarySoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                children: [
                  TextSpan(
                    text: '${s.movementName}\n$date',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            gradient: const LinearGradient(colors: [_purple, _pink]),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: _pink,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _pink.withValues(alpha: 0.25),
                  _pink.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Difficulty breakdown (animated bars) ─────────────────────────────────────

class _DifficultyBreakdown extends StatelessWidget {
  const _DifficultyBreakdown({required this.data, required this.total});

  final Map<String, int> data;
  final int total;

  static const _colors = {
    'Easy': AppColors.success,
    'Medium': AppColors.warning,
    'Hard': AppColors.error,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in data.entries) ...[
          _DifficultyRow(
            label: entry.key,
            count: entry.value,
            fraction: total == 0 ? 0 : entry.value / total,
            color: _colors[entry.key] ?? AppColors.textSecondary,
          ),
          if (entry.key != data.keys.last)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int count;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.04)),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.6), color],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bar chart (interactive tooltip) ──────────────────────────────────────────

class _MovementChart extends StatefulWidget {
  const _MovementChart({required this.data});

  final Map<String, int> data;

  @override
  State<_MovementChart> createState() => _MovementChartState();
}

class _MovementChartState extends State<_MovementChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal + 2).toDouble(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _panelColor,
            tooltipBorder: const BorderSide(color: _purple),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${entries[group.x].key}\n',
              const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              children: [
                TextSpan(
                  text: '${rod.toY.toInt()} sessions',
                  style: const TextStyle(
                    color: AppColors.primarySoft,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          touchCallback: (event, response) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  response?.spot == null) {
                _touchedIndex = null;
                return;
              }
              _touchedIndex = response!.spot!.touchedBarGroupIndex;
            });
          },
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.border.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxVal > 8 ? (maxVal / 4).ceilToDouble() : 2,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                final name = entries[index].key;
                final short = name.length > 9
                    ? '${name.substring(0, 8)}…'
                    : name;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    short,
                    style: TextStyle(
                      fontSize: 11,
                      color: index == _touchedIndex
                          ? AppColors.primarySoft
                          : AppColors.textSecondary,
                      fontWeight: index == _touchedIndex
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
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
                  gradient: LinearGradient(
                    colors: i == _touchedIndex
                        ? const [_pink, _violet]
                        : const [_purple, _pink],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: i == _touchedIndex ? 22 : 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: (maxVal + 2).toDouble(),
                    color: AppColors.border.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
