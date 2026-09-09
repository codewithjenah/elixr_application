import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/coaching_verdict_style.dart';
import '../../../data/models/practice_feedback.dart';
import '../../../data/models/rubric_assessment.dart';
import '../practice_feedback_controller.dart';
import '../practice_game_widgets.dart';
import 'training_performance.dart';

/// Perimeter HUD for scored Movement Practice. Rebuilds from listenables
/// rather than the camera JPEG stream.
class TrainingLiveHud extends StatelessWidget {
  const TrainingLiveHud({
    super.key,
    required this.elapsedDisplay,
    required this.assessmentListenable,
    required this.holdListenable,
    required this.comboListenable,
    required this.scorePopupListenable,
    required this.calloutListenable,
    this.coaching,
  });

  final String elapsedDisplay;
  final ValueListenable<RubricAssessment?> assessmentListenable;
  final ValueListenable<double> holdListenable;
  final ValueListenable<ComboState> comboListenable;
  final ValueListenable<ScorePopupState> scorePopupListenable;
  final ValueListenable<PerformanceCalloutState> calloutListenable;
  final PracticeFeedback? coaching;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            child: _HudChip(
              label: 'TIME',
              value: elapsedDisplay,
              accent: AppColors.textPrimary,
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            right: AppSpacing.md,
            child: ValueListenableBuilder<RubricAssessment?>(
              valueListenable: assessmentListenable,
              builder: (context, assessment, _) {
                final level = assessment?.performanceLevel;
                return _HudChip(
                  label: 'RUBRIC',
                  value: assessment == null
                      ? '—'
                      : '${assessment.total} / ${RubricScale.maxTotal}',
                  supporting: level?.label,
                  accent: performanceLevelColor(level),
                );
              },
            ),
          ),
          if (coaching != null)
            Positioned(
              top: 62,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: Align(
                alignment: Alignment.topCenter,
                child: _CoachingChip(feedback: coaching!),
              ),
            ),
          Positioned(
            left: AppSpacing.md,
            bottom: AppSpacing.md,
            child: ValueListenableBuilder<RubricAssessment?>(
              valueListenable: assessmentListenable,
              builder: (context, assessment, _) =>
                  _CriteriaStrip(assessment: assessment),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.md,
            child: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: holdListenable,
                builder: (context, holdProgress, _) {
                  if (holdProgress <= 0 || holdProgress >= 1) {
                    return const SizedBox.shrink();
                  }
                  return _HoldChip(progress: holdProgress);
                },
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: ValueListenableBuilder<ComboState>(
              valueListenable: comboListenable,
              builder: (context, comboState, _) =>
                  ComboBadge(combo: comboState.combo),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<PerformanceCalloutState>(
                    valueListenable: calloutListenable,
                    builder: (context, callout, _) => PerformanceCallout(
                      trigger: callout.trigger,
                      level: callout.level,
                      total: callout.total,
                    ),
                  ),
                  ValueListenableBuilder<ScorePopupState>(
                    valueListenable: scorePopupListenable,
                    builder: (context, popup, _) =>
                        ScorePopup(trigger: popup.trigger, delta: popup.delta),
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

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.value,
    required this.accent,
    this.supporting,
  });

  final String label;
  final String value;
  final String? supporting;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: supporting == null ? '$label $value' : '$label $value $supporting',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xE6101018),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.caption.copyWith(
                fontSize: 9,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: AppTheme.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.6,
              ),
            ),
            if (supporting != null)
              Text(
                supporting!,
                style: AppTheme.caption.copyWith(
                  color: accent.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoachingChip extends StatelessWidget {
  const _CoachingChip({required this.feedback});

  final PracticeFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final accent = coachingVerdictColor(
      feedback.coachingVerdict,
      feedbackType: feedback.feedbackType,
    );
    final text = feedback.feedback.length > 72
        ? '${feedback.feedback.substring(0, 72)}…'
        : feedback.feedback;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xE6101018),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _CriteriaStrip extends StatelessWidget {
  const _CriteriaStrip({required this.assessment});

  final RubricAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6101018),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final criterion in RubricCriterion.values) ...[
            if (criterion != RubricCriterion.values.first)
              const SizedBox(width: 8),
            _CriterionDot(
              label: criterion.shortHudLabel,
              score: assessment?.scoreFor(criterion),
            ),
          ],
        ],
      ),
    );
  }
}

class _CriterionDot extends StatelessWidget {
  const _CriterionDot({required this.label, required this.score});

  final String label;
  final int? score;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          score == null ? '—' : '$score',
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: score == null ? AppColors.textSecondary : AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _HoldChip extends StatelessWidget {
  const _HoldChip({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE6101018),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: ProgressRing(
              value: progress * 100,
              strokeWidth: 3,
              activeColor: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Hold steady…',
            style: AppTheme.body.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

extension on RubricCriterion {
  String get shortHudLabel => switch (this) {
    RubricCriterion.technique => 'TECH',
    RubricCriterion.stability => 'STAB',
    RubricCriterion.completion => 'HOLD',
    RubricCriterion.propPositioning => 'PROP',
  };
}
