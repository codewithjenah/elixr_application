import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import 'movement_lesson_content.dart';

/// A focused, in-context presentation of canonical [MovementLesson] content.
/// This has no progress, routing, camera, or session dependencies.
class MovementTutorialDialog extends StatelessWidget {
  const MovementTutorialDialog({
    super.key,
    required this.movement,
    required this.prop,
    required this.lesson,
    this.sessionActive = false,
  });

  final Movement movement;
  final TrainingProp prop;
  final MovementLesson lesson;
  final bool sessionActive;

  @override
  Widget build(BuildContext context) => ContentDialog(
    constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
    title: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
          ),
          child: const Icon(FluentIcons.reading_mode, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(movement.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              _DifficultyBadge(label: movement.difficulty),
            ],
          ),
        ),
      ],
    ),
    content: SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final hero = _TutorialHero(
            movement: movement,
            prop: prop,
            lesson: lesson,
          );
          final technique = _TutorialPanel(
            eyebrow: 'HOW TO PERFORM',
            title: 'Build the movement',
            icon: FluentIcons.number_sequence,
            child: Column(
              children: [
                for (var i = 0; i < lesson.steps.length; i++)
                  _TutorialStep(number: i + 1, text: lesson.steps[i]),
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessionActive) ...[
                const _ActiveSessionNotice(),
                const SizedBox(height: AppSpacing.md),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: hero),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 6, child: technique),
                  ],
                )
              else ...[
                hero,
                const SizedBox(height: AppSpacing.md),
                technique,
              ],
              const SizedBox(height: AppSpacing.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TutorialPanel.success(lesson.successTarget),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _TutorialPanel.mistake(lesson.commonMistake),
                    ),
                  ],
                )
              else ...[
                _TutorialPanel.success(lesson.successTarget),
                const SizedBox(height: AppSpacing.md),
                _TutorialPanel.mistake(lesson.commonMistake),
              ],
              if (lesson.safetyNote != null) ...[
                const SizedBox(height: AppSpacing.md),
                _TutorialPanel(
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
            ],
          );
        },
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        child: const Text('Back to Training'),
      ),
    ],
  );
}

class _TutorialHero extends StatelessWidget {
  const _TutorialHero({
    required this.movement,
    required this.prop,
    required this.lesson,
  });
  final Movement movement;
  final TrainingProp prop;
  final MovementLesson lesson;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('tutorial-hero'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppTheme.panelDecoration(context, highlighted: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REQUIRED PROP',
          style: AppTheme.caption.copyWith(
            letterSpacing: .8,
            fontWeight: FontWeight.w700,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          prop.displayLabel,
          style: AppTheme.body.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 170,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.elixBackground.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: MovementImage(movementName: movement.name, size: 145),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          lesson.framing,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

class _TutorialPanel extends StatelessWidget {
  const _TutorialPanel({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
  });
  factory _TutorialPanel.success(String text) => _TutorialPanel(
    eyebrow: 'SUCCESS TARGET',
    title: 'What good looks like',
    icon: FluentIcons.completed,
    accent: AppColors.success,
    child: Text(text, style: AppTheme.body.copyWith(height: 1.4)),
  );
  factory _TutorialPanel.mistake(String text) => _TutorialPanel(
    eyebrow: 'AVOID THIS',
    title: 'Common mistake',
    icon: FluentIcons.error_badge,
    accent: AppColors.warning,
    child: Text(text, style: AppTheme.body.copyWith(height: 1.4)),
  );
  final String eyebrow, title;
  final IconData icon;
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    key: title == 'Build the movement'
        ? const ValueKey('tutorial-technique-panel')
        : null,
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

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({required this.number, required this.text});
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

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.success.withValues(alpha: .3)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.success,
      ),
    ),
  );
}

class _ActiveSessionNotice extends StatelessWidget {
  const _ActiveSessionNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.primary.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        const Icon(FluentIcons.info, size: 15, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Your training session remains active while this guide is open.',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
