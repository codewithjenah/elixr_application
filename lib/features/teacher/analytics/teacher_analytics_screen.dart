import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/manila_day.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import 'teacher_analytics_controller.dart';
import 'teacher_analytics_models.dart';

class TeacherAnalyticsScreen extends StatefulWidget {
  const TeacherAnalyticsScreen({super.key, this.controller});

  final TeacherAnalyticsController? controller;

  @override
  State<TeacherAnalyticsScreen> createState() => _TeacherAnalyticsScreenState();
}

class _TeacherAnalyticsScreenState extends State<TeacherAnalyticsScreen> {
  TeacherAnalyticsController? _controller;
  late final bool _ownsController;
  String? _dependencyError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || !_ownsController) return;
    final teacherId = context.read<AuthService>().currentUser?.id;
    final groups = _tryRead<GroupRepository>(context);
    final assignments = _tryRead<ClassroomAssignmentRepository>(context);
    final progress = _tryRead<TeacherProgressRepository>(context);
    if (teacherId == null ||
        groups == null ||
        assignments == null ||
        progress == null) {
      _dependencyError = 'Analytics is not available right now.';
      return;
    }
    _controller = TeacherAnalyticsController(
      groupRepository: groups,
      assignmentRepository: assignments,
      progressRepository: progress,
      teacherId: teacherId,
    )..start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return TeacherScaffoldPage(
        header: const ElixEditorialPageHeader(
          heading: 'Analytics',
          eyebrow: 'TEACHER WORKSPACE',
          subtitle: 'See how your class is practicing.',
        ),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ElixStatusPanel(
              isError: _dependencyError != null,
              message: _dependencyError ?? 'Loading analytics…',
              icon: _dependencyError == null ? null : FluentIcons.error,
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: 'Analytics',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'See how your class is practicing and completing work.',
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  key: const Key('teacher_analytics_refresh'),
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('Refresh'),
                  onPressed: controller.sessionLoading
                      ? null
                      : controller.refresh,
                ),
              ],
            ),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalyticsFilters(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              if (controller.filterError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: InfoBar(
                    severity: InfoBarSeverity.warning,
                    title: const Text('Choose another date range'),
                    content: Text(controller.filterError!),
                  ),
                ),
              if (controller.hasStreamError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: InfoBar(
                    severity: InfoBarSeverity.warning,
                    title: const Text('Some class data could not be loaded'),
                    content: const Text(
                      'Some numbers may be incomplete. Try refreshing.',
                    ),
                    action: Button(
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              if (controller.loading && controller.snapshot == null)
                const SizedBox(
                  height: 280,
                  child: Center(child: ProgressRing()),
                )
              else if (controller.errorMessage != null &&
                  controller.snapshot == null)
                _AnalyticsMessage(
                  message: controller.errorMessage!,
                  actionLabel: 'Retry',
                  onAction: controller.retry,
                )
              else if (controller.filterError != null)
                const _AnalyticsMessage(
                  message: 'Choose a valid date range to see your class data.',
                )
              else
                _AnalyticsBody(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsFilters extends StatelessWidget {
  const _AnalyticsFilters({required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    final activeGroups = controller.groups
        .where(
          (group) => group.isActive && group.teacherId == controller.teacherId,
        )
        .toList(growable: false);
    return ElixPanelCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterField(
                label: 'Class',
                tooltip: 'Choose a class or view all classes together.',
                child: ComboBox<String>(
                  value: controller.selectedGroupId ?? _allClassesValue,
                  items: [
                    const ComboBoxItem(
                      value: _allClassesValue,
                      child: Text('All Classes'),
                    ),
                    for (final group in activeGroups)
                      ComboBoxItem(value: group.id, child: Text(group.name)),
                  ],
                  onChanged: (value) => controller.setSelectedGroupId(
                    value == _allClassesValue ? null : value,
                  ),
                ),
              ),
              _FilterField(
                label: 'Time period',
                tooltip: 'Choose which dates to view.',
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final value in AnalyticsPeriod.values)
                      ToggleButton(
                        checked: controller.period == value,
                        onChanged: (_) {
                          if (value == AnalyticsPeriod.custom) {
                            _showCustomRangePicker(context, controller);
                          } else {
                            controller.setPeriod(value);
                          }
                        },
                        child: Text(value.label),
                      ),
                  ],
                ),
              ),
              if (controller.period == AnalyticsPeriod.custom)
                _FilterField(
                  label: 'Date range',
                  tooltip: 'Choose dates from the last 90 days.',
                  child: Button(
                    onPressed: () =>
                        _showCustomRangePicker(context, controller),
                    child: Text(_customRangeLabel(controller)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static const _allClassesValue = '__all_classes__';

  static String _customRangeLabel(TeacherAnalyticsController controller) {
    final start = controller.customStartDate;
    final end = controller.customEndDate;
    if (start == null || end == null) return 'Choose dates';
    return '${DateFormat('MMM d, yyyy').format(start)} – '
        '${DateFormat('MMM d, yyyy').format(end)}';
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.tooltip,
    required this.child,
  });

  final String label;
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              const Icon(FluentIcons.info, size: 12),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    if (snapshot == null) {
      return const _AnalyticsMessage(
        message:
            'Add approved students to an active class to start seeing class data.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.sessionLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: ProgressBar(),
          ),
        if (controller.partialDataWarning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InfoBar(
              severity: InfoBarSeverity.warning,
              title: const Text('Some data is missing'),
              content: Text(controller.partialDataWarning!),
            ),
          ),
        _MetricGrid(snapshot: snapshot),
        const SizedBox(height: AppSpacing.xl),
        _TrendPanel(snapshot: snapshot),
        const SizedBox(height: AppSpacing.xl),
        _MovementInsights(snapshot: snapshot),
        const SizedBox(height: AppSpacing.xl),
        _GroupComparisonSection(snapshot: snapshot),
        if (controller.lastUpdated != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Last updated ${DateFormat('MMM d, yyyy h:mm a').format(controller.lastUpdated!.toLocal())}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final improvement = snapshot.improvement;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final cards = [
          _MetricCard(
            icon: FluentIcons.calculator,
            label: 'Average class score',
            value: _score(snapshot.averageScore),
            tooltip:
                "Average of each student's practice score. Each student counts equally.",
          ),
          _MetricCard(
            icon: FluentIcons.repeat_all,
            label: 'Practice sessions per student',
            value: snapshot.averagePracticeSessions?.toStringAsFixed(1) ?? '—',
            tooltip: 'Average number of practice sessions for each student.',
          ),
          _MetricCard(
            icon: FluentIcons.completed,
            label: 'Assignments completed',
            value: snapshot.completionRate == null
                ? '—'
                : '${(snapshot.completionRate! * 100).toStringAsFixed(0)}%',
            tooltip:
                'Percentage of due assignments that students turned in. Future assignments are not included.',
          ),
          _MetricCard(
            icon: FluentIcons.trending12,
            label: _improvementLabel(snapshot.periodWindow.period),
            value: improvement == null
                ? 'Not enough data yet'
                : _signedScore(improvement),
            tooltip:
                'Compares scores only for students who have a score in both time periods.',
            smallValue: improvement == null,
            valueColor: improvement == null
                ? null
                : improvement >= 0
                ? AppColors.success
                : AppColors.error,
          ),
        ];
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < cards.length; index++) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[index]),
                ],
              ],
            ),
          );
        }
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final card in cards)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
                child: card,
              ),
          ],
        );
      },
    );
  }

  static String _score(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} / 12';

  static String _signedScore(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} / 12';
  }

  static String _improvementLabel(AnalyticsPeriod period) => switch (period) {
    AnalyticsPeriod.thisWeek => 'Change from last week',
    AnalyticsPeriod.thisMonth => 'Change from last month',
    AnalyticsPeriod.custom => 'Change from previous period',
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tooltip,
    this.smallValue = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String tooltip;
  final bool smallValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ElixPanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.elixColors.brandPrimary, size: 22),
            const SizedBox(height: AppSpacing.md),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: smallValue
                  ? AppTheme.cardTitle(
                      color: valueColor ?? context.elixTextPrimary,
                    )
                  : AppTheme.metric(
                      context,
                      color: valueColor ?? context.elixTextPrimary,
                    ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTheme.supporting(color: context.elixTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasScores = snapshot.trendBuckets.any(
      (bucket) => bucket.averageScore != null,
    );
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Score progress over time',
            tooltip:
                "Shows your class's average score for each day or week in the selected time range.",
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasScores)
            Text(
              'No practice sessions with scores in this time range yet.',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            )
          else
            SizedBox(
              height: 250,
              child: _TrendChart(buckets: snapshot.trendBuckets),
            ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.buckets});

  final List<AnalyticsTrendBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var index = 0; index < buckets.length; index++) {
      final score = buckets[index].averageScore;
      if (score != null) spots.add(FlSpot(index.toDouble(), score));
    }
    final interval = buckets.length > 8
        ? (buckets.length / 5).ceilToDouble()
        : 1.0;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 12,
        minX: 0,
        maxX: buckets.length <= 1 ? 1 : (buckets.length - 1).toDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.elixBorder.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.elixPanelSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${buckets[spot.x.toInt()].label}\n${spot.y.toStringAsFixed(1)} / 12',
                  TextStyle(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
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
              reservedSize: 32,
              interval: 3,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: context.elixTextSecondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: interval,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox.shrink();
                }
                final label = buckets[index].label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label.length > 8 ? label.substring(4, 8) : label,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.elixTextSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.accent,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementInsights extends StatelessWidget {
  const _MovementInsights({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Movement highlights',
          tooltip:
              'Most practiced shows what students practiced most. Hardest shows the movement with the lowest average score.',
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _InsightCard(
                title: 'Most practiced',
                icon: FluentIcons.favorite_star,
                insight: snapshot.mostPracticed,
                emptyCopy: 'No practice sessions yet.',
                details: (value) =>
                    '${value.sessionCount} sessions · ${value.distinctStudentCount} students',
              ),
              _InsightCard(
                title: 'Hardest',
                icon: FluentIcons.warning,
                insight: snapshot.hardest,
                emptyCopy:
                    'Not enough practice yet (need 3 sessions from 2 students).',
                details: (value) =>
                    '${value.averageScore?.toStringAsFixed(1) ?? '—'} / 12 · '
                    '${value.sessionCount} sessions · ${value.distinctStudentCount} students',
              ),
            ];
            if (constraints.maxWidth >= 800) {
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[1]),
                ],
              );
            }
            return Column(
              children: [
                cards[0],
                const SizedBox(height: AppSpacing.md),
                cards[1],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.icon,
    required this.insight,
    required this.emptyCopy,
    required this.details,
  });

  final String title;
  final IconData icon;
  final MovementInsight? insight;
  final String emptyCopy;
  final String Function(MovementInsight) details;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      child: Row(
        children: [
          Icon(icon, color: context.elixColors.brandPrimary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (insight == null)
                  Text(
                    emptyCopy,
                    style: AppTheme.body.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  )
                else ...[
                  Text(
                    insight!.movementName,
                    style: AppTheme.headingMedium.copyWith(
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details(insight!),
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupComparisonSection extends StatefulWidget {
  const _GroupComparisonSection({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  State<_GroupComparisonSection> createState() =>
      _GroupComparisonSectionState();
}

class _GroupComparisonSectionState extends State<_GroupComparisonSection> {
  _GroupSort _sort = _GroupSort.average;
  bool _ascending = false;

  @override
  Widget build(BuildContext context) {
    final comparisons = [...widget.snapshot.groupComparisons]..sort(_compare);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Class comparison',
          tooltip:
              "See each class's scores, practice, completed assignments, and change.",
        ),
        const SizedBox(height: AppSpacing.md),
        if (comparisons.isEmpty)
          Text(
            'No active classes yet.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          )
        else ...[
          ElixPanelCard(
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 760
                  ? Column(
                      children: [
                        for (final comparison in comparisons)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _NarrowGroupComparison(
                              comparison: comparison,
                            ),
                          ),
                      ],
                    )
                  : _WideGroupComparison(
                      comparisons: comparisons,
                      sort: _sort,
                      ascending: _ascending,
                      onSort: _onSort,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _GroupComparisonChart(comparisons: comparisons),
        ],
      ],
    );
  }

  int _compare(GroupComparison a, GroupComparison b) {
    int result;
    switch (_sort) {
      case _GroupSort.group:
        result = a.group.name.toLowerCase().compareTo(
          b.group.name.toLowerCase(),
        );
      case _GroupSort.average:
        result = _compareNullable(a.averageScore, b.averageScore);
      case _GroupSort.sessions:
        result = _compareNullable(
          a.averagePracticeSessions,
          b.averagePracticeSessions,
        );
      case _GroupSort.completion:
        result = _compareNullable(a.completionRate, b.completionRate);
      case _GroupSort.improvement:
        result = _compareNullable(a.improvement, b.improvement);
    }
    return _ascending ? result : -result;
  }

  void _onSort(_GroupSort value) {
    setState(() {
      if (_sort == value) {
        _ascending = !_ascending;
      } else {
        _sort = value;
        _ascending = value == _GroupSort.group;
      }
    });
  }

  static int _compareNullable(double? a, double? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }
}

enum _GroupSort { group, average, sessions, completion, improvement }

class _WideGroupComparison extends StatelessWidget {
  const _WideGroupComparison({
    required this.comparisons,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final List<GroupComparison> comparisons;
  final _GroupSort sort;
  final bool ascending;
  final ValueChanged<_GroupSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GroupComparisonRow(
          isHeader: true,
          group: 'Class',
          average: 'Average score',
          sessions: 'Practice per student',
          completion: 'Assignments',
          improvement: 'Change',
          onSort: onSort,
          sort: sort,
          ascending: ascending,
        ),
        const Divider(),
        for (final comparison in comparisons)
          _GroupComparisonRow(
            group: comparison.group.name,
            average: _score(comparison.averageScore),
            sessions:
                comparison.averagePracticeSessions?.toStringAsFixed(1) ?? '—',
            completion: comparison.completionRate == null
                ? '—'
                : '${(comparison.completionRate! * 100).toStringAsFixed(0)}%',
            improvement: comparison.improvement == null
                ? '—'
                : _signed(comparison.improvement!),
          ),
      ],
    );
  }

  static String _score(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} / 12';
  static String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';
}

class _GroupComparisonRow extends StatelessWidget {
  const _GroupComparisonRow({
    required this.group,
    required this.average,
    required this.sessions,
    required this.completion,
    required this.improvement,
    this.isHeader = false,
    this.onSort,
    this.sort,
    this.ascending = false,
  });

  final String group;
  final String average;
  final String sessions;
  final String completion;
  final String improvement;
  final bool isHeader;
  final ValueChanged<_GroupSort>? onSort;
  final _GroupSort? sort;
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: context.elixTextSecondary,
          )
        : AppTheme.body.copyWith(color: context.elixTextPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: _headerButton(context, group, _GroupSort.group, style),
          ),
          Expanded(
            child: _headerButton(context, average, _GroupSort.average, style),
          ),
          Expanded(
            child: _headerButton(context, sessions, _GroupSort.sessions, style),
          ),
          Expanded(
            child: _headerButton(
              context,
              completion,
              _GroupSort.completion,
              style,
            ),
          ),
          Expanded(
            child: _headerButton(
              context,
              improvement,
              _GroupSort.improvement,
              style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(
    BuildContext context,
    String value,
    _GroupSort column,
    TextStyle style,
  ) {
    if (!isHeader || onSort == null) {
      return Align(
        alignment: column == _GroupSort.group
            ? Alignment.centerLeft
            : Alignment.center,
        child: Text(value, style: style),
      );
    }
    final selected = sort == column;
    return Align(
      alignment: column == _GroupSort.group
          ? Alignment.centerLeft
          : Alignment.center,
      child: Button(
        onPressed: () => onSort!(column),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(
                  ascending ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                  size: 10,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NarrowGroupComparison extends StatelessWidget {
  const _NarrowGroupComparison({required this.comparison});

  final GroupComparison comparison;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comparison.group.name,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _MiniMetric(
                label: 'Average score',
                value: _score(comparison.averageScore),
              ),
              _MiniMetric(
                label: 'Practice per student',
                value:
                    comparison.averagePracticeSessions?.toStringAsFixed(1) ??
                    '—',
              ),
              _MiniMetric(
                label: 'Assignments',
                value: comparison.completionRate == null
                    ? '—'
                    : '${(comparison.completionRate! * 100).toStringAsFixed(0)}%',
              ),
              _MiniMetric(
                label: 'Change',
                value: comparison.improvement == null
                    ? '—'
                    : _signed(comparison.improvement!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _score(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} / 12';
  static String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: AppTheme.body.copyWith(
          color: context.elixTextPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        label,
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      ),
    ],
  );
}

class _GroupComparisonChart extends StatelessWidget {
  const _GroupComparisonChart({required this.comparisons});

  final List<GroupComparison> comparisons;

  @override
  Widget build(BuildContext context) {
    final values = comparisons
        .map((comparison) => comparison.averageScore)
        .toList();
    if (!values.any((value) => value != null)) return const SizedBox.shrink();
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Average score by class',
            tooltip: 'Class averages use the same 0–12 score scale.',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 230,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: 12,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: context.elixBorder.withValues(alpha: 0.45),
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
                      reservedSize: 32,
                      interval: 3,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index < 0 || index >= comparisons.length) {
                          return const SizedBox.shrink();
                        }
                        final name = comparisons[index].group.name;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            name.length > 10
                                ? '${name.substring(0, 9)}…'
                                : name,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.elixTextSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < comparisons.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: values[index] ?? 0,
                          color: values[index] == null
                              ? context.elixBorder
                              : AppColors.accent,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 12,
                            color: context.elixBorder.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.tooltip});

  final String title;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(FluentIcons.info, size: 13),
      ],
    ),
  );
}

class _AnalyticsMessage extends StatelessWidget {
  const _AnalyticsMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ElixStatusPanel(
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    ),
  );
}

class _CustomDateSelection {
  const _CustomDateSelection(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

Future<void> _showCustomRangePicker(
  BuildContext context,
  TeacherAnalyticsController controller,
) async {
  final now = DateTime.now();
  final today = ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(now.toUtc()));
  var start =
      controller.customStartDate ?? today.subtract(const Duration(days: 6));
  var end = controller.customEndDate ?? today;
  if (start.isAfter(end)) start = end;
  final selection = await showDialog<_CustomDateSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => ContentDialog(
        title: const Text('Choose a Manila date range'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Up to 90 days. Future dates are not available.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Start date',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
              ),
              DatePicker(
                selected: start,
                endDate: today,
                onChanged: (value) => setState(() => start = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'End date',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
              ),
              DatePicker(
                selected: end,
                endDate: today,
                onChanged: (value) => setState(() => end = value),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _CustomDateSelection(start, end)),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
  if (selection != null && context.mounted) {
    await controller.setCustomRange(
      startDate: selection.start,
      endDate: selection.end,
    );
  }
}

T? _tryRead<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
