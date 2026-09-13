import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
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
  Widget build(BuildContext context) => ElixDialog(
    title: movement.name,
    subtitle: movement.difficulty,
    icon: FluentIcons.reading_mode,
    maxWidth: 760,
    maxHeight: 720,
    scrollableContent: true,
    content: LayoutBuilder(
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
                  Expanded(child: _TutorialPanel.success(lesson.successTarget)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _TutorialPanel.mistake(lesson.commonMistake)),
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
                accent: context.elixColors.error,
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
    actions: [
      ElixPrimaryButton(
        label: 'Back to Training',
        expanded: false,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
  Widget build(BuildContext context) => ElixPanelCard(
    key: const ValueKey('tutorial-hero'),
    variant: ElixPanelVariant.hero,
    padding: const EdgeInsets.all(AppSpacing.md),
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
            borderRadius: BorderRadius.circular(ElixRadius.card),
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
    this.accent,
    this.accentTone,
  });
  factory _TutorialPanel.success(String text) => _TutorialPanel(
    eyebrow: 'SUCCESS TARGET',
    title: 'What good looks like',
    icon: FluentIcons.completed,
    accentTone: ElixTone.success,
    child: Text(text, style: AppTheme.body.copyWith(height: 1.4)),
  );
  factory _TutorialPanel.mistake(String text) => _TutorialPanel(
    eyebrow: 'AVOID THIS',
    title: 'Common mistake',
    icon: FluentIcons.error_badge,
    accentTone: ElixTone.warning,
    child: Text(text, style: AppTheme.body.copyWith(height: 1.4)),
  );
  final String eyebrow, title;
  final IconData icon;
  final Widget child;
  final Color? accent;
  final ElixTone? accentTone;

  @override
  Widget build(BuildContext context) {
    final tone = accentTone == null
        ? (accent ?? context.elixColors.brandPrimary)
        : ElixToneCues.color(context.elixColors, accentTone!);
    return ElixPanelCard(
      key: title == 'Build the movement'
          ? const ValueKey('tutorial-technique-panel')
          : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(ElixRadius.control),
                ),
                child: Icon(icon, size: 15, color: tone),
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
            color: context.elixColors.brandPrimary.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: context.elixColors.brandPrimary,
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

class _ActiveSessionNotice extends StatelessWidget {
  const _ActiveSessionNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: context.elixColors.brandPrimary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(ElixRadius.control),
      border: Border.all(
        color: context.elixColors.brandPrimary.withValues(alpha: .28),
      ),
    ),
    child: Row(
      children: [
        Icon(
          FluentIcons.info,
          size: 15,
          color: context.elixColors.brandPrimary,
        ),
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
