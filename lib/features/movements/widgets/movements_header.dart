import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../movements_presentation.dart';

class MovementsHeader extends StatelessWidget {
  const MovementsHeader({super.key, required this.summary});

  final MovementsSummary summary;

  @override
  Widget build(BuildContext context) {
    final progress = summary.totalMovements > 0
        ? summary.practicedCount / summary.totalMovements
        : 0.0;
    final averageLabel = summary.overallAverageRubric == null
        ? 'No rubric result yet'
        : '${summary.overallAverageRubric!.toStringAsFixed(1)} / 12';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final overview = _TrainingOverview(
          summary: summary,
          progress: progress,
        );
        return Semantics(
          container: true,
          label:
              'Training library. ${summary.practicedCount} of ${summary.totalMovements} movements practiced, ${(progress * 100).round()} percent. ${summary.totalSessions} sessions completed. Overall rubric average $averageLabel.',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  const _TitleBlock(),
                  const SizedBox(height: AppSpacing.lg),
                  overview,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(flex: 3, child: _TitleBlock()),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(flex: 2, child: overview),
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
                _StatsPanel(summary: summary, averageLabel: averageLabel),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    return ElixEditorialHeader(
      heading: 'Movements',
      eyebrow: 'TRAINING LIBRARY',
      subtitle:
          'Build your flair foundation, sharpen your control, and master every level.',
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(
            alpha: context.isDarkTheme ? 0.18 : 0.10,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.26)),
        ),
        child: const Icon(
          FluentIcons.more_sports,
          size: 20,
          color: AppColors.accentSoft,
        ),
      ),
    );
  }
}

class _TrainingOverview extends StatelessWidget {
  const _TrainingOverview({required this.summary, required this.progress});

  final MovementsSummary summary;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.panelDecoration(
        context,
        glow: AppColors.primary,
        highlighted: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRACTICED',
                      style: TextStyle(
                        color: context.elixTextSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${summary.practicedCount} / ${summary.totalMovements}',
                      style: TextStyle(
                        color: context.elixTextPrimary,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: AppColors.primarySoft,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: context.elixBorder),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.accent, AppColors.primary],
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
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.summary, required this.averageLabel});

  final MovementsSummary summary;
  final String averageLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 620;
        final tiles = [
          _SummaryStat(
            icon: FluentIcons.completed_solid,
            label: 'Practiced movements',
            value: '${summary.practicedCount} of ${summary.totalMovements}',
          ),
          _SummaryStat(
            icon: FluentIcons.history,
            label: 'Completed sessions',
            value: '${summary.totalSessions}',
          ),
          _SummaryStat(
            icon: FluentIcons.trophy2,
            label: 'Rubric average',
            value: averageLabel,
          ),
        ];
        if (stack) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                tiles[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[i]),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixCardSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.elixBorder,
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accentSoft),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.elixTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
