import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/progression/practice_variant.dart';
import '../../core/progression/progression_access.dart';
import '../../core/progression/progression_catalog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_stat_card.dart';
import '../../core/widgets/locked_movement_mark.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import '../../services/trainee_progression_service.dart';
import '../../services/tutorial_progress_service.dart';
import 'rubric_guide.dart';

const _kLearningContentMaxWidth = 1280.0;

const _learningMediumMovementDisplayOrder = <String>[
  'Hand Stall',
  'Forearm Stall',
  'Elbow Stall',
  'Wrist Stall',
  'One Finger Stall',
];

/// Presentation-only ordering for the trainee lesson library.
///
/// The shared catalog order remains unchanged because it also drives practice
/// progression. Only Medium lessons need a different pedagogical order here.
List<PracticeCatalogStep> _learningPracticeSteps() {
  final steps = enabledPracticeSteps();
  final mediumSteps = steps
      .where((step) => step.movement.difficulty == 'Medium')
      .toList();
  mediumSteps.sort((a, b) {
    final aIndex = _learningMediumMovementDisplayOrder.indexOf(a.movement.name);
    final bIndex = _learningMediumMovementDisplayOrder.indexOf(b.movement.name);
    if (aIndex == bIndex) {
      return _learningPropOrder(a.prop).compareTo(_learningPropOrder(b.prop));
    }
    if (aIndex < 0) return 1;
    if (bIndex < 0) return -1;
    return aIndex.compareTo(bIndex);
  });

  final ordered = <PracticeCatalogStep>[];
  var insertedMedium = false;
  for (final step in steps) {
    if (step.movement.difficulty != 'Medium') {
      ordered.add(step);
    } else if (!insertedMedium) {
      ordered.addAll(mediumSteps);
      insertedMedium = true;
    }
  }
  return ordered;
}

int _learningPropOrder(TrainingProp prop) => switch (prop) {
  TrainingProp.bottle => 0,
  TrainingProp.shaker => 1,
  TrainingProp.bottleAndShaker => 2,
};

class LearningCenterScreen extends StatelessWidget {
  const LearningCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lessons = _learningPracticeSteps();

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
                AppSpacing.pageTopInset,
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
                        _LearningHero(lessonCount: lessons.length),
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
                              '${lessons.length} guided lessons from foundational grips to advanced stalls.',
                          trailing: _CountBadge(count: lessons.length),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _LessonGrid(lessons: lessons),
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
    final highContrast = context.isHighContrast;
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
          final stacked = constraints.maxWidth < 760;
          final intro = ElixEditorialHeader(
            heading: 'Help & Tutorials',
            eyebrow: 'LEARNING CENTER',
            subtitle:
                'Learn the flow, understand your score, and build every movement with confidence.',
            leading: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highContrast ? context.elixColors.brandPrimary : null,
                gradient: highContrast
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.accent],
                      ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: highContrast
                    ? const []
                    : [
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
          );
          final overview = _HeroOverview(lessonCount: lessonCount);

          if (stacked) {
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
    return Row(
      children: [
        Expanded(
          child: ElixStatCard(
            label: 'Lessons',
            value: '$lessonCount',
            icon: FluentIcons.library,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: ElixStatCard(
            label: 'Score criteria',
            value: '4',
            icon: FluentIcons.completed_solid,
          ),
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
    return ElixEditorialHeader(
      heading: title,
      eyebrow: eyebrow,
      subtitle: subtitle,
      variant: ElixEditorialHeaderVariant.compact,
      actions: trailing == null ? const [] : [trailing!],
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
  const _LessonGrid({required this.lessons});

  final List<PracticeCatalogStep> lessons;

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
            for (final lesson in lessons)
              SizedBox(
                width: cardWidth,
                child: _LessonCard(
                  movement: lesson.movement,
                  prop: lesson.prop,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LessonCard extends StatefulWidget {
  const _LessonCard({required this.movement, required this.prop});

  final Movement movement;
  final TrainingProp prop;

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _hovered = false;

  void _openLesson() {
    final movement = widget.movement;
    final prop = widget.prop;
    context.go(
      '/learn/movement/${Uri.encodeComponent(movement.name)}'
      '?difficulty=${movement.difficulty}&prop=${prop.protocolValue}',
    );
  }

  ProgressionAccessResult? _access() {
    final progression = Provider.of<TraineeProgressionService?>(
      context,
      listen: true,
    );
    final tutorials = Provider.of<TutorialProgressService?>(
      context,
      listen: true,
    );
    if (progression == null || tutorials == null) return null;
    return evaluatePersonal(
      variant: PracticeVariant(
        movementName: widget.movement.name,
        trainingProp: widget.prop,
      ),
      currentLevel: progression.currentLevelOrNull,
      tutorialCompleted: tutorials.isInitialized
          ? tutorials.hasCompletedLesson(widget.movement.name, widget.prop)
          : null,
    );
  }

  String _statusFor(ProgressionAccessResult? access) {
    if (access == null) return 'View lesson';
    switch (access) {
      case ProgressionAccessResult.personalReady:
        return 'Ready';
      case ProgressionAccessResult.personalLearn:
        return 'Learn';
      case ProgressionAccessResult.personalLocked:
        final level =
            requiredLevelFor(
              PracticeVariant(
                movementName: widget.movement.name,
                trainingProp: widget.prop,
              ),
            ) ??
            '?';
        return 'Locked · Level $level';
      case ProgressionAccessResult.personalLoading:
        return 'Checking…';
      case ProgressionAccessResult.invalid:
        return 'Unavailable';
      case ProgressionAccessResult.assignmentLoading:
      case ProgressionAccessResult.assignmentLearn:
      case ProgressionAccessResult.assignmentReady:
        return 'Unavailable';
    }
  }

  bool _canOpen(ProgressionAccessResult? access) {
    if (access == null) return true;
    return access == ProgressionAccessResult.personalLearn ||
        access == ProgressionAccessResult.personalReady;
  }

  @override
  Widget build(BuildContext context) {
    final movement = widget.movement;
    final progression = Provider.of<TraineeProgressionService?>(
      context,
      listen: true,
    );
    final traineeLevel = progression?.currentLevelOrNull;
    if (traineeLevel == null) {
      return _LessonCardSkeleton(difficulty: movement.difficulty);
    }
    if (!isMovementIdentityRevealed(movement.name, traineeLevel)) {
      return _LockedLessonCard(
        difficulty: movement.difficulty,
        unlockLevel: earliestRequiredLevelForMovement(movement.name),
      );
    }
    return _buildRevealedCard(context, movement, widget.prop);
  }

  Widget _buildRevealedCard(
    BuildContext context,
    Movement movement,
    TrainingProp prop,
  ) {
    final difficultyColor = switch (movement.difficulty) {
      'Easy' => AppColors.success,
      'Medium' => AppColors.warning,
      _ => AppColors.primary,
    };
    final access = _access();
    final openable = _canOpen(access);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: openable,
      enabled: openable,
      label:
          'Open ${movement.name} ${prop.displayLabel} lesson. ${_statusFor(access)}',
      child: MouseRegion(
        cursor: openable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: openable ? _openLesson : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 156),
            decoration: AppTheme.panelDecoration(
              context,
              glow: AppColors.accent,
              highlighted: _hovered && openable,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 116,
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
                          prop: prop,
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
                          Text(
                            prop.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(
                              color: difficultyColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            movement.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Text(
                                _statusFor(access),
                                style: AppTheme.caption.copyWith(
                                  color: _hovered && openable
                                      ? AppColors.primarySoft
                                      : context.elixTextSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (openable) ...[
                                const SizedBox(width: 5),
                                Icon(
                                  FluentIcons.chevron_right,
                                  size: 10,
                                  color: _hovered
                                      ? AppColors.primarySoft
                                      : context.elixTextSecondary,
                                ),
                              ],
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
      ),
    );
  }
}

class _LessonCardSkeleton extends StatelessWidget {
  const _LessonCardSkeleton({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final difficultyColor = switch (difficulty) {
      'Easy' => AppColors.success,
      'Medium' => AppColors.warning,
      _ => AppColors.primary,
    };
    final fill = context.isHighContrast
        ? context.elixBorder
        : difficultyColor.withValues(alpha: context.isDarkTheme ? 0.16 : 0.10);
    return Semantics(
      label: 'Loading movement lesson',
      child: Container(
        constraints: const BoxConstraints(minHeight: 156),
        decoration: AppTheme.panelDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 116, color: fill),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DifficultyBadge(
                        difficulty: difficulty,
                        color: difficultyColor,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        height: 14,
                        width: 140,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 200,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedLessonCard extends StatelessWidget {
  const _LockedLessonCard({
    required this.difficulty,
    required this.unlockLevel,
  });

  final String difficulty;
  final int? unlockLevel;

  @override
  Widget build(BuildContext context) {
    final difficultyColor = switch (difficulty) {
      'Easy' => AppColors.success,
      'Medium' => AppColors.warning,
      _ => AppColors.primary,
    };
    final requiredLevel = unlockLevel;
    return Semantics(
      container: true,
      button: false,
      label: MovementSpoilerCopy.semanticsLabel(unlockLevel: requiredLevel),
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 156),
          decoration: AppTheme.panelDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 116,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        difficultyColor.withValues(alpha: 0.14),
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
                    child: LockedMovementMark(
                      size: 72,
                      accent: difficultyColor,
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
                          difficulty: difficulty,
                          color: difficultyColor,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          MovementSpoilerCopy.lockedMovement,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body.copyWith(
                            color: context.elixTextPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (requiredLevel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            MovementSpoilerCopy.unlocksAtLevel(requiredLevel),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
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
