import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../data/models/assessment_score_display.dart';
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
    final averageLabel = 'Average Score';
    final averageValue = _hasRubricData
        ? (averageRubricTotal == null
              ? '—'
              : rubricAverageLabel(averageRubricTotal!))
        : (averageLegacyScore == null
              ? '—'
              : averageLegacyScore!.toStringAsFixed(0));
    final bestLabel = 'Best Score';
    final bestValue = _hasRubricData
        ? (bestRubricTotal == null ? '—' : rubricTotalLabel(bestRubricTotal!))
        : (bestLegacyScore?.toString() ?? '—');

    final averageDetail = _hasRubricData
        ? 'from $rubricSessionCount ${rubricSessionCount == 1 ? 'session' : 'sessions'}'
        : (legacySessionCount > 0
              ? 'from $legacySessionCount ${legacySessionCount == 1 ? 'session' : 'sessions'}'
              : null);
    final bestDetail = _hasRubricData && bestRubricTotal != null
        ? AssessmentScoreDisplay.performanceLabel(
            PerformanceLevel.fromTotal(bestRubricTotal!),
          )
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
          _SummaryCard(
            icon: FluentIcons.history,
            label: 'Total Sessions',
            value: '$totalSessions',
            detail: totalDetail,
            accent: AppColors.accentSoft,
          ),
          _SummaryCard(
            icon: FluentIcons.chart_template,
            label: averageLabel,
            value: averageValue,
            detail: averageDetail,
            accent: AppColors.primary,
            infoTooltip: legacyExplanation,
          ),
          _SummaryCard(
            icon: FluentIcons.trophy2_solid,
            label: bestLabel,
            value: bestValue,
            detail: bestDetail,
            accent: AppColors.warning,
          ),
          _SummaryCard(
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

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.detail,
    this.infoTooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color accent;
  final String? infoTooltip;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final accent = widget.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: ElixMotion.duration(context, ElixMotion.micro),
        curve: ElixMotion.microCurve,
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered && !highContrast
                ? accent.withValues(alpha: 0.45)
                : context.elixBorder,
          ),
          gradient: highContrast
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(
                      alpha: context.isDarkTheme
                          ? (_hovered ? 0.14 : 0.08)
                          : 0.06,
                    ),
                    context.elixCardSurface,
                  ],
                ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: accent.withValues(
                      alpha: context.isDarkTheme
                          ? (_hovered ? 0.14 : 0.08)
                          : 0.05,
                    ),
                    blurRadius: 16,
                    spreadRadius: -8,
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: context.isDarkTheme ? 0.18 : 0.12,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon, size: 14, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontFamily: ElixTypography.fontFamily,
                      fontFamilyFallback: ElixTypography.fontFallbacks,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: context.elixTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.detail!,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.infoTooltip != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  key: const Key('history-legacy-info'),
                  message: widget.infoTooltip!,
                  child: Semantics(
                    label: widget.infoTooltip,
                    button: false,
                    child: Icon(
                      FluentIcons.info,
                      size: 13,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
