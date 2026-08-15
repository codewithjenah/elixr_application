import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class RubricGuide extends StatelessWidget {
  const RubricGuide({super.key, this.compact = false});

  final bool compact;

  static const criteria = <(String, String)>[
    (
      'Technique',
      'Whether the movement-specific body and hand form is correct.',
    ),
    ('Stability', 'Whether the prop remains controlled and steady.'),
    ('Completion', 'Progress toward and completion of the confirmed hold.'),
    (
      'Prop Positioning',
      'Whether the prop is aligned with the correct grip or stall point.',
    ),
  ];

  static const _criterionIcons = <IconData>[
    FluentIcons.hands_free,
    FluentIcons.processing_run,
    FluentIcons.completed,
    FluentIcons.move,
  ];

  static String scoreMeaning(int score) => switch (score) {
    0 => 'Not demonstrated or not enough valid evidence.',
    1 => 'Demonstrated briefly.',
    2 => 'Demonstrated partially or inconsistently.',
    _ => 'Demonstrated consistently with enough observation.',
  };

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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppTheme.panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  FluentIcons.trophy2,
                  size: 19,
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
                      'How your performance is measured',
                      style: AppTheme.headingMedium.copyWith(
                        color: context.elixTextPrimary,
                        fontSize: compact ? 18 : 21,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: const Text(
                  '12 MAX',
                  style: TextStyle(
                    color: AppColors.primarySoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.17),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  FluentIcons.view,
                  size: 15,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Visibility problems do not lower scores. They pause valid evidence collection until ELIXR can clearly see you and the prop.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              const gap = AppSpacing.sm;
              final itemWidth =
                  (constraints.maxWidth - ((columns - 1) * gap)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var index = 0; index < criteria.length; index++)
                    SizedBox(
                      width: itemWidth,
                      child: _CriterionTile(
                        icon: _criterionIcons[index],
                        title: criteria[index].$1,
                        description: criteria[index].$2,
                      ),
                    ),
                ],
              );
            },
          ),
          if (!compact) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Score scale',
              style: AppTheme.body.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 4 : 2;
                const gap = AppSpacing.sm;
                final itemWidth =
                    (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var score = 0; score <= 3; score++)
                      SizedBox(
                        width: itemWidth,
                        child: _ScoreTile(
                          score: score,
                          meaning: scoreMeaning(score),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            const _PerformanceBands(),
          ],
        ],
      ),
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
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.accentSoft),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.score, required this.meaning});

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
      height: 66,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.17)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$score',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              meaning,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceBands extends StatelessWidget {
  const _PerformanceBands();

  static const bands = <(String, String, Color)>[
    ('0–3', 'Beginning', AppColors.textSecondary),
    ('4–6', 'Developing', AppColors.warning),
    ('7–9', 'Competent', AppColors.accentSoft),
    ('10–11', 'Proficient', AppColors.primarySoft),
    ('12', 'Mastered', AppColors.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.75)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          for (final band in bands)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: band.$3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  band.$1,
                  style: TextStyle(
                    color: band.$3,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  band.$2,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
