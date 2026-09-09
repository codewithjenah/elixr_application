import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class RubricGuide extends StatelessWidget {
  const RubricGuide({super.key, this.compact = false});

  final bool compact;

  static const criteria = <(String, String)>[
    ('Form', 'Are your hands and body in the right position?'),
    ('Control', 'Is the bottle or shaker steady and under control?'),
    ('Finish', 'Did you complete the move?'),
    ('Position', 'Is the bottle or shaker in the right place?'),
  ];

  static const _criterionIcons = <IconData>[
    FluentIcons.hands_free,
    FluentIcons.processing_run,
    FluentIcons.completed,
    FluentIcons.move,
  ];

  static String scoreMeaning(int score) => switch (score) {
    0 => 'Not enough to score',
    1 => 'Shown briefly',
    2 => 'Partly shown',
    _ => 'Shown clearly and steadily',
  };

  // These labels are retained for existing callers. The guide presents simpler
  // trainee-facing labels without changing scoring thresholds or stored values.
  static String performanceBand(int total) => switch (total) {
    <= 3 => 'Beginning',
    <= 6 => 'Developing',
    <= 9 => 'Competent',
    <= 11 => 'Proficient',
    _ => 'Mastered',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      decoration: AppTheme.panelDecoration(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GuideHeader(compact: compact),
              const SizedBox(height: AppSpacing.md),
              const _VisibilityNote(),
              const SizedBox(height: AppSpacing.lg),
              if (compact) const _CriteriaSection() else const _GuideDetails(),
              if (!compact) ...[
                const SizedBox(height: AppSpacing.lg),
                const _TotalScoreSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 40 : 46,
          height: compact ? 40 : 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
          ),
          child: Icon(
            FluentIcons.trophy2,
            size: compact ? 18 : 21,
            color: AppColors.accentSoft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCORING GUIDE',
                style: AppTheme.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Scoring made simple',
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                  fontSize: compact ? 18 : 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                compact
                    ? 'ELIXR checks 4 things, worth up to 3 points each.'
                    : 'ELIXR checks 4 things. Each one is worth up to 3 points, for a total of 12.',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.35,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: AppSpacing.sm),
                const _TotalPointsBadge(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalPointsBadge extends StatelessWidget {
  const _TotalPointsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: const Text(
        '12 POINTS TOTAL',
        style: TextStyle(
          color: AppColors.primarySoft,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _VisibilityNote extends StatelessWidget {
  const _VisibilityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(FluentIcons.view, size: 16, color: AppColors.accentSoft),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: "Can't see you clearly? "),
                  TextSpan(
                    text: 'Scoring pauses. ',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(
                    text:
                        'Your score will not go down until ELIXR can see you and the bottle or shaker again.',
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

class _GuideDetails extends StatelessWidget {
  const _GuideDetails();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        if (stacked) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CriteriaSection(),
              SizedBox(height: AppSpacing.lg),
              _PointsSection(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _CriteriaSection()),
            SizedBox(width: AppSpacing.lg),
            Expanded(flex: 5, child: _PointsSection()),
          ],
        );
      },
    );
  }
}

class _CriteriaSection extends StatelessWidget {
  const _CriteriaSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'What ELIXR checks',
          subtitle: '4 things x 3 points = 12 total points',
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 380 ? 1 : 2;
            const gap = AppSpacing.sm;
            final itemWidth =
                (constraints.maxWidth - ((columns - 1) * gap)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (
                  var index = 0;
                  index < RubricGuide.criteria.length;
                  index++
                )
                  SizedBox(
                    width: itemWidth,
                    child: _CriterionTile(
                      icon: RubricGuide._criterionIcons[index],
                      title: RubricGuide.criteria[index].$1,
                      description: RubricGuide.criteria[index].$2,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.body.copyWith(
            color: context.elixTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _CriterionTile extends StatelessWidget {
  const _CriterionTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.accentSoft),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    height: 1.35,
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

class _PointsSection extends StatelessWidget {
  const _PointsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'How points work',
          subtitle: 'Each check earns from 0 to 3 points',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var score = 0; score <= 3; score++) ...[
          _ScoreStep(score: score, meaning: RubricGuide.scoreMeaning(score)),
          if (score < 3) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ScoreStep extends StatelessWidget {
  const _ScoreStep({required this.score, required this.meaning});

  final int score;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final color = switch (score) {
      0 => context.elixTextSecondary,
      1 => AppColors.warning,
      2 => AppColors.accentSoft,
      _ => AppColors.success,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Text(
            '$score',
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              meaning,
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextPrimary,
                fontWeight: score == 3 ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalScoreSection extends StatelessWidget {
  const _TotalScoreSection();

  static const bands = <(String, String, Color)>[
    ('0-3', 'Getting Started', AppColors.textSecondary),
    ('4-6', 'Learning', AppColors.warning),
    ('7-9', 'Good', AppColors.accentSoft),
    ('10-11', 'Great', AppColors.primarySoft),
    ('12', 'Mastered', AppColors.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your total score',
          style: AppTheme.body.copyWith(
            color: context.elixTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Your 4 scores are added together.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 620;
            if (stacked) {
              return Column(
                children: [
                  for (final band in bands) ...[
                    _BandSegment(band: band),
                    if (band != bands.last) const SizedBox(height: 6),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < bands.length; index++) ...[
                  Expanded(child: _BandSegment(band: bands[index])),
                  if (index < bands.length - 1) const SizedBox(width: 6),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BandSegment extends StatelessWidget {
  const _BandSegment({required this.band});

  final (String, String, Color) band;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: band.$3.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: band.$3.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            band.$1,
            style: TextStyle(
              color: band.$3,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            band.$2,
            style: AppTheme.caption.copyWith(
              color: context.elixTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
