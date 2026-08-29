import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import '../../services/tutorial_progress_service.dart';
import 'rubric_guide.dart';

class MovementLessonScreen extends StatelessWidget {
  const MovementLessonScreen({
    super.key,
    required this.movement,
    required this.difficulty,
    required this.prop,
    this.assignmentId,
  });
  final String movement;
  final String difficulty;
  final TrainingProp prop;
  final String? assignmentId;

  @override
  Widget build(BuildContext context) {
    final item = movementCatalog.where((m) => m.name == movement).firstOrNull;
    if (item == null) {
      return const ElixScaffoldPage(
        content: Center(child: Text('This movement is not available.')),
      );
    }
    final lesson = MovementLesson.forMovement(item);
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.pageTopInset,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 880;
                final hero = _Hero(item: item, lesson: lesson, prop: prop);
                final steps = _Panel(
                  eyebrow: 'TECHNIQUE',
                  title: 'Build the movement',
                  icon: FluentIcons.number_sequence,
                  child: Column(
                    children: [
                      for (var i = 0; i < lesson.steps.length; i++)
                        _Step(number: i + 1, text: lesson.steps[i]),
                    ],
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(movement: item.name, difficulty: item.difficulty),
                    const SizedBox(height: AppSpacing.md),
                    _Actions(
                      item: item,
                      difficulty: difficulty,
                      prop: prop,
                      assignmentId: assignmentId,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: hero),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(flex: 6, child: steps),
                        ],
                      )
                    else ...[
                      hero,
                      const SizedBox(height: AppSpacing.md),
                      steps,
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Panel(
                                eyebrow: 'SUCCESS TARGET',
                                title: 'What good looks like',
                                icon: FluentIcons.completed,
                                accent: AppColors.success,
                                child: Text(
                                  lesson.successTarget,
                                  style: AppTheme.body.copyWith(height: 1.4),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _Panel(
                                eyebrow: 'AVOID THIS',
                                title: 'Common mistake',
                                icon: FluentIcons.error_badge,
                                accent: AppColors.warning,
                                child: Text(
                                  lesson.commonMistake,
                                  style: AppTheme.body.copyWith(height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _Panel(
                        eyebrow: 'SUCCESS TARGET',
                        title: 'What good looks like',
                        icon: FluentIcons.completed,
                        accent: AppColors.success,
                        child: Text(
                          lesson.successTarget,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Panel(
                        eyebrow: 'AVOID THIS',
                        title: 'Common mistake',
                        icon: FluentIcons.error_badge,
                        accent: AppColors.warning,
                        child: Text(
                          lesson.commonMistake,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                    if (lesson.safetyNote != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Panel(
                        eyebrow: 'SAFETY',
                        title: 'Practice safely',
                        icon: FluentIcons.shield,
                        accent: AppColors.error,
                        child: Text(
                          lesson.safetyNote!,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const RubricGuide(compact: true),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.movement, required this.difficulty});
  final String movement, difficulty;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ElixEditorialHeader(
        heading: movement,
        eyebrow: 'MOVEMENT LESSON',
        variant: ElixEditorialHeaderVariant.compact,
      ),
      const SizedBox(height: AppSpacing.sm),
      _Pill(text: difficulty, color: AppColors.success),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.lesson, required this.prop});
  final Movement item;
  final MovementLesson lesson;
  final TrainingProp prop;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppTheme.panelDecoration(context, highlighted: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                FluentIcons.video,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CAMERA READY',
                    style: AppTheme.caption.copyWith(
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                  Text(
                    'Use: ${prop.displayLabel}',
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.elixBackground.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: MovementImage(movementName: item.name, size: 190),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          lesson.framing,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
  });
  final String eyebrow, title;
  final IconData icon;
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppTheme.panelDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: AppTheme.caption.copyWith(
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTheme.headingMedium.copyWith(fontSize: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final int number;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.difficulty,
    required this.prop,
    this.assignmentId,
  });
  final Movement item;
  final String difficulty;
  final TrainingProp prop;
  final String? assignmentId;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final stacked = c.maxWidth < 520;
      final assigned = assignmentId != null && assignmentId!.trim().isNotEmpty;
      final back = SizedBox(
        width: stacked ? double.infinity : 220,
        height: 52,
        child: Button(
          onPressed: () => context.go(
            assigned ? AppRoutePaths.assignedMovements : AppRoutePaths.learn,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.back, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  assigned ? 'Back to Assigned Movements' : 'Back to tutorials',
                ),
              ],
            ),
          ),
        ),
      );
      final start = SizedBox(
        width: stacked ? double.infinity : 260,
        height: 52,
        child: ElixPrimaryButton(
          label: 'Start guided practice',
          icon: FluentIcons.play_solid,
          expanded: false,
          dense: true,
          onPressed: () async {
            await context.read<TutorialProgressService>().completeLesson(
              item.name,
            );
            if (context.mounted) {
              context.go(
                assigned
                    ? AppRoutePaths.assignedPractice(assignmentId!.trim())
                    : '/practice?movement=${Uri.encodeComponent(item.name)}&difficulty=$difficulty&prop=${prop.protocolValue}',
              );
            }
          },
        ),
      );
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                back,
                const SizedBox(height: AppSpacing.sm),
                start,
              ],
            )
          : Row(children: [back, const Spacer(), start]);
    },
  );
}

class MovementLesson {
  const MovementLesson({
    required this.objective,
    required this.framing,
    required this.steps,
    required this.successTarget,
    required this.commonMistake,
    this.safetyNote,
  });
  final String objective, framing, successTarget, commonMistake;
  final List<String> steps;
  final String? safetyNote;
  factory MovementLesson.forMovement(Movement movement) {
    final balance =
        movement.name.contains('Stall') || movement.name == 'Bottle in a tin';
    return MovementLesson(
      objective:
          'Learn a controlled ${movement.name} before you open the camera.',
      framing:
          'Place the camera so your hands, prop, and upper body are clearly visible.',
      steps: balance
          ? [
              'Prepare a clear space and a safe practice prop.',
              'Start from a steady position.',
              'Move the prop to the named support point.',
              'Hold still while keeping the prop controlled.',
            ]
          : [
              'Prepare a clear space and a safe practice prop.',
              'Hold the prop in a relaxed starting position.',
              'Place your hand in the ${movement.name} position.',
              'Keep the prop controlled and hold the position.',
            ],
      successTarget: balance
          ? 'Hold the prop steadily at the correct support point.'
          : 'Show the grip clearly and keep it steady long enough for ELIXR to observe.',
      commonMistake: balance
          ? 'Rushing into the balance. Reset, lower the prop, and hold steady.'
          : 'Covering the grip with your hand. Turn the prop so the camera can see your fingers.',
      safetyNote: balance
          ? 'Use a safe practice prop and keep people and breakable items out of your practice area.'
          : null,
    );
  }
}
