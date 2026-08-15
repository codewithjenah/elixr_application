import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/movement.dart';
import 'rubric_guide.dart';

const _kLearningContentMaxWidth = 1280.0;

class LearningCenterScreen extends StatelessWidget {
  const LearningCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final movements = movementCatalog
        .where((movement) => movement.enabled)
        .toList();

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 680
                ? AppSpacing.md
                : AppSpacing.xl;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.xl,
                horizontalPadding,
                AppSpacing.xxl,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kLearningContentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LearningHero(lessonCount: movements.length),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionHeading(
                          eyebrow: 'BEFORE YOU PRACTICE',
                          title: 'Start with the essentials',
                          subtitle:
                              'Set up your space and choose the right practice mode.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _QuickStartCards(),
                        const SizedBox(height: AppSpacing.lg),
                        const RubricGuide(),
                        const SizedBox(height: AppSpacing.xl),
                        _SectionHeading(
                          eyebrow: 'MOVEMENT LIBRARY',
                          title: 'Choose a lesson',
                          subtitle:
                              '${movements.length} guided lessons from foundational grips to advanced stalls.',
                          trailing: _CountBadge(count: movements.length),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _LessonGrid(movements: movements),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LearningHero extends StatelessWidget {
  const _LearningHero({required this.lessonCount});

  final int lessonCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppTheme.panelDecoration(
        context,
        glow: AppColors.accent,
        highlighted: true,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final intro = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  FluentIcons.education,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LEARNING CENTER',
                      style: AppTheme.caption.copyWith(
                        color: AppColors.primarySoft,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Help & Tutorials',
                      style: AppTheme.brandTitle(
                        fontSize: compact ? 28 : 34,
                        color: context.elixTextPrimary,
                      ).copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Learn the flow, understand your score, and build every movement with confidence.',
                      style: AppTheme.bodySecondary.copyWith(
                        color: context.elixTextSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final overview = _HeroOverview(lessonCount: lessonCount);

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                intro,
                const SizedBox(height: AppSpacing.lg),
                overview,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: intro),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 3, child: overview),
            ],
          );
        },
      ),
    );
  }
}

class _HeroOverview extends StatelessWidget {
  const _HeroOverview({required this.lessonCount});

  final int lessonCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeroMetric(
              icon: FluentIcons.library,
              value: '$lessonCount',
              label: 'Lessons',
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: context.elixBorder.withValues(alpha: 0.7),
          ),
          const Expanded(
            child: _HeroMetric(
              icon: FluentIcons.completed_solid,
              value: '4',
              label: 'Score criteria',
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.accentSoft),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: context.elixTextPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: AppTheme.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: AppTheme.headingLarge.copyWith(
                  color: context.elixTextPrimary,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class _QuickStartCards extends StatelessWidget {
  const _QuickStartCards();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        const camera = _GuideCard(
          icon: FluentIcons.video,
          accent: AppColors.primary,
          step: '01',
          title: 'Get camera-ready',
          description:
              'Keep your camera, prop, hands, and required body parts clearly visible before the countdown begins.',
          note:
              'Having trouble? Check the selected camera in Settings and close other apps using it.',
        );
        const practice = _PracticeModesCard();

        if (stacked) {
          return const Column(
            children: [
              camera,
              SizedBox(height: AppSpacing.md),
              practice,
            ],
          );
        }
        return const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: camera),
              SizedBox(width: AppSpacing.md),
              Expanded(child: practice),
            ],
          ),
        );
      },
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.accent,
    required this.step,
    required this.title,
    required this.description,
    required this.note,
  });

  final IconData icon;
  final Color accent;
  final String step;
  final String title;
  final String description;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AccentIcon(icon: icon, color: accent),
              const Spacer(),
              _StepBadge(value: step, color: accent),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.info, size: 14, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    note,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.4,
                    ),
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

class _PracticeModesCard extends StatelessWidget {
  const _PracticeModesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _AccentIcon(
                icon: FluentIcons.processing_run,
                color: AppColors.accentSoft,
              ),
              Spacer(),
              _StepBadge(value: '02', color: AppColors.accentSoft),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Choose your practice mode',
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _ModeRow(
            icon: FluentIcons.trophy2,
            color: AppColors.primary,
            title: 'Guided Practice',
            description: 'Follow a lesson and record a scored session.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ModeRow(
            icon: FluentIcons.freezing,
            color: AppColors.accentSoft,
            title: 'Live Practice',
            description: 'Train freely without scoring after learning a move.',
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
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
                const SizedBox(height: 2),
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

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: TextStyle(
        color: color.withValues(alpha: 0.8),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$count lessons',
        style: const TextStyle(
          color: AppColors.accentSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LessonGrid extends StatelessWidget {
  const _LessonGrid({required this.movements});

  final List<Movement> movements;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const gap = AppSpacing.md;
        final cardWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final movement in movements)
              SizedBox(
                width: cardWidth,
                child: _LessonCard(movement: movement),
              ),
          ],
        );
      },
    );
  }
}

class _LessonCard extends StatefulWidget {
  const _LessonCard({required this.movement});

  final Movement movement;

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _hovered = false;

  void _openLesson() {
    final movement = widget.movement;
    context.go(
      '/learn/movement/${Uri.encodeComponent(movement.name)}?difficulty=${movement.difficulty}&prop=${movement.supportedProps.first.protocolValue}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final movement = widget.movement;
    final difficultyColor = switch (movement.difficulty) {
      'Easy' => AppColors.success,
      'Medium' => AppColors.warning,
      _ => AppColors.primary,
    };

    return Semantics(
      button: true,
      label: 'Open ${movement.name} lesson',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _openLesson,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 156,
            decoration: AppTheme.panelDecoration(
              context,
              glow: AppColors.accent,
              highlighted: _hovered,
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 116,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        difficultyColor.withValues(
                          alpha: _hovered ? 0.22 : 0.14,
                        ),
                        AppColors.accent.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: difficultyColor.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: _hovered ? 1.06 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: MovementImage(
                        movementName: movement.name,
                        size: 106,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DifficultyBadge(
                          difficulty: movement.difficulty,
                          color: difficultyColor,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          movement.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body.copyWith(
                            color: context.elixTextPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            movement.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'View lesson',
                              style: AppTheme.caption.copyWith(
                                color: _hovered
                                    ? AppColors.primarySoft
                                    : context.elixTextSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              FluentIcons.chevron_right,
                              size: 10,
                              color: _hovered
                                  ? AppColors.primarySoft
                                  : context.elixTextSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.difficulty, required this.color});

  final String difficulty;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        difficulty.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
