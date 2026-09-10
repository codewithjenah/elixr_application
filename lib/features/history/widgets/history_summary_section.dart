import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/elix_summary_stat_card.dart';
import '../../../data/models/rubric_assessment.dart';
import '../history_format.dart';

class HistorySummarySection extends StatelessWidget {
  const HistorySummarySection({
    super.key,
    required this.totalSessions,
    required this.rubricSessionCount,
    required this.averageRubricTotal,
    required this.bestRubricTotal,
    required this.legacySessionCount,
    required this.averageLegacyScore,
    required this.bestLegacyScore,
    required this.totalDurationSeconds,
    this.matchingCount,
  });

  final int totalSessions;

  /// Assessment V2 cohort (rubric totals 0..12).
  final int rubricSessionCount;
  final double? averageRubricTotal;
  final int? bestRubricTotal;

  /// Legacy Assessment V1 cohort (percentages 0..100).
  final int legacySessionCount;
  final double? averageLegacyScore;
  final int? bestLegacyScore;

  final int totalDurationSeconds;

  /// When non-null, a filter/search is active and this is the result size.
  final int? matchingCount;

  bool get _hasRubricData => rubricSessionCount > 0;

  @override
  Widget build(BuildContext context) {
    final averageLabel = _hasRubricData ? 'Average Rubric' : 'Average Score';
    final averageValue = _hasRubricData
        ? (averageRubricTotal == null
              ? '—'
              : rubricAverageLabel(averageRubricTotal!))
        : (averageLegacyScore == null
              ? '—'
              : averageLegacyScore!.toStringAsFixed(0));
    final bestLabel = _hasRubricData ? 'Best Rubric' : 'Best Score';
    final bestValue = _hasRubricData
        ? (bestRubricTotal == null ? '—' : rubricTotalLabel(bestRubricTotal!))
        : (bestLegacyScore?.toString() ?? '—');

    final averageDetail = _hasRubricData
        ? 'from $rubricSessionCount ${rubricSessionCount == 1 ? 'session' : 'sessions'}'
        : (legacySessionCount > 0
              ? 'from $legacySessionCount ${legacySessionCount == 1 ? 'session' : 'sessions'}'
              : null);
    final bestDetail = _hasRubricData && bestRubricTotal != null
        ? PerformanceLevel.fromTotal(bestRubricTotal!).label
        : null;
    final timeDetail = totalSessions > 0
        ? 'across $totalSessions ${totalSessions == 1 ? 'session' : 'sessions'}'
        : null;
    final totalDetail = matchingCount == null
        ? null
        : '$matchingCount matching';
    final legacyExplanation = _hasRubricData
        ? historyLegacyCohortExplanation(
            legacySessionCount: legacySessionCount,
            averageLegacyScore: averageLegacyScore,
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 4
            : width >= 560
            ? 2
            : 1;
        final cards = <Widget>[
          ElixSummaryStatCard(
            icon: FluentIcons.history,
            label: 'Total Sessions',
            value: '$totalSessions',
            detail: totalDetail,
            accent: AppColors.accentSoft,
          ),
          ElixSummaryStatCard(
            icon: FluentIcons.chart_template,
            label: averageLabel,
            value: averageValue,
            detail: averageDetail,
            accent: AppColors.primary,
            infoTooltip: legacyExplanation,
            infoTooltipKey: legacyExplanation == null
                ? null
                : const Key('history-legacy-info'),
          ),
          ElixSummaryStatCard(
            icon: FluentIcons.trophy2_solid,
            label: bestLabel,
            value: bestValue,
            detail: bestDetail,
            accent: AppColors.warning,
          ),
          ElixSummaryStatCard(
            icon: FluentIcons.clock,
            label: 'Total Training Time',
            value: formatTrainingDuration(totalDurationSeconds),
            detail: timeDetail,
            accent: AppColors.success,
          ),
        ];
        return _SummaryGrid(columns: columns, cards: cards);
      },
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.columns, required this.cards});

  final int columns;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    const gap = AppSpacing.sm;
    if (columns == 1) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            cards[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      final end = (i + columns).clamp(0, cards.length);
      final slice = cards.sublist(i, end);
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < slice.length; j++) ...[
                if (j > 0) const SizedBox(width: gap),
                Expanded(child: slice[j]),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}
