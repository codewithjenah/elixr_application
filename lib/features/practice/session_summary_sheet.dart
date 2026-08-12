import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/movement.dart';
import '../../data/models/rubric_assessment.dart';
import 'practice_game_widgets.dart';
import 'session_assessment.dart';
import 'widgets/training_performance.dart';

enum SessionSummaryResult { saved, discarded, tryAgain, next }

/// Centralized sizing for the session-complete dashboard.
abstract final class _SummaryLayout {
  static const dialogMaxWidth = 960.0;
  static const dialogMinWidth = 320.0;
  static const viewportMargin = 24.0;
  static const twoColumnBreakpoint = 720.0;
  static const actionsRegularBreakpoint = 780.0;
  static const insightSideBySideBreakpoint = 440.0;
  static const performanceColumnWidth = 220.0;
  static const scoreRingSize = 92.0;
  static const cardPadding = 16.0;
  static const sectionGap = 16.0;
  static const bodyPadding = 20.0;
  static const headerPaddingH = 20.0;
  static const headerPaddingV = 14.0;
  static const actionsPadding = 16.0;
  static const primaryActionWidth = 260.0;
}

class SessionSummarySheet extends StatelessWidget {
  const SessionSummarySheet({
    super.key,
    required this.movement,
    required this.durationSeconds,
    required this.assessment,
    required this.onPrimaryAction,
    required this.onDiscard,
    required this.onTryAgain,
    this.saving = false,
    this.saveError,
    this.nextMovementName,
  });

  final String movement;
  final int durationSeconds;
  final SessionAssessment assessment;
  final VoidCallback onPrimaryAction;
  final VoidCallback onDiscard;
  final VoidCallback onTryAgain;
  final bool saving;
  final String? saveError;
  final String? nextMovementName;

  RubricAssessment get _rubric => assessment.rubric;

  PerformanceLevel get _level => assessment.performanceLevel;

  bool get _heldSteady => assessment.heldSteady;

  /// Celebration threshold: Proficient (10) or better.
  static bool celebrates(PerformanceLevel level) =>
      level.index >= PerformanceLevel.proficient.index;

  static Future<SessionSummaryResult?> show(
    BuildContext context, {
    required String movement,
    required int durationSeconds,
    required SessionAssessment assessment,
    required Future<String> Function(String? existingSessionId) onSave,
    Movement? nextMovement,
  }) {
    return showDialog<SessionSummaryResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      useRootNavigator: true,
      builder: (ctx) {
        var saving = false;
        String? saveError;
        String? pendingSessionId;
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> handlePrimaryAction() async {
              if (saving) return;
              setState(() {
                saving = true;
                saveError = null;
              });
              try {
                pendingSessionId = await onSave(pendingSessionId);
              } catch (error) {
                if (ctx.mounted) {
                  setState(() {
                    saveError = _formatSaveError(error);
                    saving = false;
                  });
                }
                return;
              }
              // Pop on success only — do not setState after pop (navigator can
              // be locked / element deactivated, which leaves the spinner up).
              if (ctx.mounted) {
                Navigator.of(ctx, rootNavigator: true).pop(
                  nextMovement != null
                      ? SessionSummaryResult.next
                      : SessionSummaryResult.saved,
                );
              }
            }

            return Stack(
              children: [
                if (celebrates(assessment.performanceLevel))
                  const Positioned.fill(child: ConfettiOverlay()),
                SafeArea(
                  child: Center(
                    child: Material(
                      type: MaterialType.transparency,
                      child: _AnimatedEntrance(
                        child: SessionSummarySheet(
                          movement: movement,
                          durationSeconds: durationSeconds,
                          assessment: assessment,
                          saving: saving,
                          saveError: saveError,
                          nextMovementName: nextMovement?.name,
                          onDiscard: () {
                            if (saving) return;
                            Navigator.of(
                              ctx,
                              rootNavigator: true,
                            ).pop(SessionSummaryResult.discarded);
                          },
                          onTryAgain: () {
                            if (saving) return;
                            Navigator.of(
                              ctx,
                              rootNavigator: true,
                            ).pop(SessionSummaryResult.tryAgain);
                          },
                          onPrimaryAction: handlePrimaryAction,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatSaveError(Object error) {
    if (error is FirebaseException) {
      return 'Could not save your session (${error.code}). '
          'Check your connection and try again.';
    }
    return 'Could not save your session. Check your connection and try again.';
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  static String _tierMessage(
    PerformanceLevel level, {
    required bool hasImprovements,
  }) {
    return switch (level) {
      PerformanceLevel.mastered || PerformanceLevel.proficient =>
        hasImprovements
            ? 'Strong finish — review recurring technique notes below.'
            : 'Solid execution. Keep the consistency going.',
      PerformanceLevel.competent =>
        hasImprovements
            ? 'Good progress. A few things to fine-tune below.'
            : 'Good effort. Keep practicing to build consistency.',
      PerformanceLevel.developing =>
        hasImprovements
            ? 'Getting there. Focus on the tips below.'
            : 'You are making progress. Keep practicing to raise your rubric '
                  'score.',
      PerformanceLevel.beginning =>
        hasImprovements
            ? 'Early stages — review the tips below and try again.'
            : 'Keep going — regular practice will help your rubric score '
                  'improve.',
    };
  }

  static String _performanceMessage(PerformanceLevel level) {
    if (celebrates(level)) {
      return 'No recurring technique issue met the session threshold.';
    }
    return 'No recurring technique issue was detected. '
        'Keep practicing to improve your rubric score.';
  }

  static ({String label, Color color}) _tier(PerformanceLevel level) =>
      (label: level.label, color: performanceLevelColor(level));

  @override
  Widget build(BuildContext context) {
    final levelColor = performanceLevelColor(_level);
    final tier = _tier(_level);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math
            .min(
              _SummaryLayout.dialogMaxWidth,
              constraints.maxWidth - (_SummaryLayout.viewportMargin * 2),
            )
            .clamp(
              _SummaryLayout.dialogMinWidth,
              _SummaryLayout.dialogMaxWidth,
            );
        final maxHeight = constraints.maxHeight;

        return ConstrainedBox(
          key: const Key('session-summary-dialog'),
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Container(
            width: maxWidth,
            decoration: BoxDecoration(
              color: context.elixCardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 48,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryHeader(
                    movement: movement,
                    heldSteady: _heldSteady,
                    level: _level,
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: _SummaryBody(
                      rubric: _rubric,
                      levelColor: levelColor,
                      tier: tier,
                      durationSeconds: durationSeconds,
                      assessment: assessment,
                      performanceMessage: _tierMessage(
                        _level,
                        hasImprovements: assessment.hasImprovements,
                      ),
                      emptyImprovementsMessage:
                          assessment.coaching.cleanSessionMessage ??
                          _performanceMessage(_level),
                      emptyStrengthsMessage: _heldSteady
                          ? 'Hold confirmed — keep reinforcing clean technique.'
                          : 'No standout technique strength met the session '
                                'threshold.',
                    ),
                  ),
                  _SummaryActions(
                    saving: saving,
                    saveError: saveError,
                    nextMovementName: nextMovementName,
                    onPrimaryAction: onPrimaryAction,
                    onDiscard: onDiscard,
                    onTryAgain: onTryAgain,
                    regularLayout:
                        maxWidth >= _SummaryLayout.actionsRegularBreakpoint,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.movement,
    required this.heldSteady,
    required this.level,
  });

  final String movement;
  final bool heldSteady;
  final PerformanceLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _SummaryLayout.headerPaddingH,
        vertical: _SummaryLayout.headerPaddingV,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.success.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0.07),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              heldSteady
                  ? FluentIcons.trophy2_solid
                  : FluentIcons.completed_solid,
              color: AppColors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Session Complete',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  heldSteady
                      ? 'You held "$movement" steady. Well done!'
                      : movement,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          RankBadge(level: level),
        ],
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.rubric,
    required this.levelColor,
    required this.tier,
    required this.durationSeconds,
    required this.assessment,
    required this.performanceMessage,
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
  final String performanceMessage;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumn =
            constraints.maxWidth >= _SummaryLayout.twoColumnBreakpoint;

        return SingleChildScrollView(
          key: const Key('session-summary-scroll'),
          padding: const EdgeInsets.fromLTRB(
            _SummaryLayout.bodyPadding,
            AppSpacing.sm + 4,
            _SummaryLayout.bodyPadding,
            AppSpacing.sm,
          ),
          child: useTwoColumn
              ? _RegularBody(
                  rubric: rubric,
                  levelColor: levelColor,
                  tier: tier,
                  durationSeconds: durationSeconds,
                  assessment: assessment,
                  performanceMessage: performanceMessage,
                  emptyImprovementsMessage: emptyImprovementsMessage,
                  emptyStrengthsMessage: emptyStrengthsMessage,
                )
              : _CompactBody(
                  rubric: rubric,
                  levelColor: levelColor,
                  tier: tier,
                  durationSeconds: durationSeconds,
                  assessment: assessment,
                  performanceMessage: performanceMessage,
                  emptyImprovementsMessage: emptyImprovementsMessage,
                  emptyStrengthsMessage: emptyStrengthsMessage,
                ),
        );
      },
    );
  }
}

class _RegularBody extends StatelessWidget {
  const _RegularBody({
    required this.rubric,
    required this.levelColor,
    required this.tier,
    required this.durationSeconds,
    required this.assessment,
    required this.performanceMessage,
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
  final String performanceMessage;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _SummaryLayout.performanceColumnWidth,
          child: _PerformanceColumn(
            rubric: rubric,
            levelColor: levelColor,
            tier: tier,
            durationSeconds: durationSeconds,
            performanceMessage: performanceMessage,
            compact: false,
          ),
        ),
        const SizedBox(width: _SummaryLayout.sectionGap + 4),
        Expanded(
          child: _CoachingColumn(
            assessment: assessment,
            emptyImprovementsMessage: emptyImprovementsMessage,
            emptyStrengthsMessage: emptyStrengthsMessage,
            preferSideBySideInsights: true,
          ),
        ),
      ],
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.rubric,
    required this.levelColor,
    required this.tier,
    required this.durationSeconds,
    required this.assessment,
    required this.performanceMessage,
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
  final String performanceMessage;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PerformanceColumn(
          rubric: rubric,
          levelColor: levelColor,
          tier: tier,
          durationSeconds: durationSeconds,
          performanceMessage: performanceMessage,
          compact: true,
        ),
        const SizedBox(height: _SummaryLayout.sectionGap),
        _CoachingColumn(
          assessment: assessment,
          emptyImprovementsMessage: emptyImprovementsMessage,
          emptyStrengthsMessage: emptyStrengthsMessage,
          preferSideBySideInsights: false,
        ),
      ],
    );
  }
}

class _PerformanceColumn extends StatelessWidget {
  const _PerformanceColumn({
    required this.rubric,
    required this.levelColor,
    required this.tier,
    required this.durationSeconds,
    required this.performanceMessage,
    required this.compact,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final String performanceMessage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ring = _RubricRing(total: rubric.total, color: levelColor);
    final tierBadge = _TierBadge(label: tier.label, color: tier.color);
    final durationPill = _DurationPill(
      label: SessionSummarySheet._formatDuration(durationSeconds),
    );
    final criteria = _CriteriaCard(rubric: rubric, accent: levelColor);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [tierBadge, durationPill],
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),
                    Text(
                      performanceMessage,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          criteria,
        ],
      );
    }

    // Keep ring, tier, message, and duration on one centered axis so the
    // performance column reads as a single aligned stack (not mixed axes).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ring,
        const SizedBox(height: AppSpacing.sm + 2),
        tierBadge,
        const SizedBox(height: AppSpacing.sm),
        Text(
          performanceMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        durationPill,
        const SizedBox(height: AppSpacing.sm + 2),
        criteria,
      ],
    );
  }
}

class _RubricRing extends StatelessWidget {
  const _RubricRing({required this.total, required this.color});

  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = _SummaryLayout.scoreRingSize;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: total.toDouble()),
      builder: (context, animatedTotal, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ScoreRingPainter(
            progress: (animatedTotal / RubricScale.maxTotal).clamp(0.0, 1.0),
            color: color,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${animatedTotal.round()}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'of ${RubricScale.maxTotal}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
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

/// Rubric total plus the four criterion scores for the completed session.
class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard({required this.rubric, required this.accent});

  final RubricAssessment rubric;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('session-summary-rubric'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rubric Score',
                  style: AppTheme.caption.copyWith(
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
              Text(
                '${rubric.total} / ${RubricScale.maxTotal}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final criterion in RubricCriterion.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      criterion.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${rubric.scoreFor(criterion)} / '
                    '${RubricScale.maxCriterion}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
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

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.clock, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingColumn extends StatelessWidget {
  const _CoachingColumn({
    required this.assessment,
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
    required this.preferSideBySideInsights,
  });

  final SessionAssessment assessment;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;
  final bool preferSideBySideInsights;

  @override
  Widget build(BuildContext context) {
    final strengths = assessment.coaching.strengths;
    final improvements = assessment.improvements;
    final recommendation = assessment.coaching.recommendation;

    final strengthsCard = _InsightCard(
      title: 'What Went Well',
      accent: AppColors.success,
      icon: FluentIcons.emoji2,
      count: strengths.length,
      items: strengths.map((s) => s.message).toList(growable: false),
      emptyMessage: emptyStrengthsMessage,
    );
    final improvementsCard = _InsightCard(
      title: 'Needs Improvement',
      accent: AppColors.warning,
      icon: FluentIcons.lightbulb,
      count: improvements.length,
      items: improvements.map((i) => i.message).toList(growable: false),
      emptyMessage: emptyImprovementsMessage,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            preferSideBySideInsights &&
            constraints.maxWidth >= _SummaryLayout.insightSideBySideBreakpoint;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideBySide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: strengthsCard),
                    const SizedBox(width: _SummaryLayout.sectionGap),
                    Expanded(child: improvementsCard),
                  ],
                ),
              )
            else ...[
              strengthsCard,
              const SizedBox(height: _SummaryLayout.sectionGap),
              improvementsCard,
            ],
            if (recommendation != null) ...[
              const SizedBox(height: _SummaryLayout.sectionGap),
              _RecommendationCard(recommendation: recommendation),
            ],
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.accent,
    required this.icon,
    required this.count,
    required this.items,
    required this.emptyMessage,
  });

  final String title;
  final Color accent;
  final IconData icon;
  final int count;
  final List<String> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_SummaryLayout.cardPadding),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.headingMedium.copyWith(fontSize: 13.5),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          if (items.isEmpty)
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 13,
                color: context.elixTextSecondary,
                height: 1.4,
              ),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      items[i],
                      style: TextStyle(
                        fontSize: 13,
                        color: context.elixTextPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final SessionRecommendation recommendation;

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('session-summary-recommendation'),
      width: double.infinity,
      padding: const EdgeInsets.all(_SummaryLayout.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FluentIcons.completed,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Recommended Next Session',
                  style: AppTheme.headingMedium.copyWith(fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Practice ${recommendation.movementName} again',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            recommendation.reason,
            style: TextStyle(
              fontSize: 13,
              color: context.elixTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaChip(
                icon: FluentIcons.checkbox_composite,
                label: 'Target: ${recommendation.targetLabel}',
              ),
              _DurationPill(
                label:
                    'Duration: ${_formatDuration(recommendation.recommendedDurationSeconds)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryActions extends StatelessWidget {
  const _SummaryActions({
    required this.saving,
    required this.saveError,
    required this.onPrimaryAction,
    required this.onDiscard,
    required this.onTryAgain,
    required this.nextMovementName,
    required this.regularLayout,
  });

  final bool saving;
  final String? saveError;
  final VoidCallback onPrimaryAction;
  final VoidCallback onDiscard;
  final VoidCallback onTryAgain;
  final String? nextMovementName;
  final bool regularLayout;

  @override
  Widget build(BuildContext context) {
    final hasNext = nextMovementName != null;
    final primaryButton = GameActionButton(
      label: hasNext ? 'Next: $nextMovementName' : 'Finish',
      icon: hasNext ? FluentIcons.chevron_right : FluentIcons.completed,
      onPressed: saving ? null : onPrimaryAction,
      isLoading: saving,
    );

    return Container(
      key: const Key('session-summary-actions'),
      padding: const EdgeInsets.fromLTRB(
        _SummaryLayout.actionsPadding,
        AppSpacing.sm,
        _SummaryLayout.actionsPadding,
        _SummaryLayout.actionsPadding,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveError != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    FluentIcons.error,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      saveError!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (regularLayout)
            Row(
              children: [
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HyperlinkButton(
                      onPressed: saving ? null : onDiscard,
                      child: Text(
                        'Discard without saving',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Button(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm + 4,
                      ),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (_) => context.elixBackground,
                    ),
                  ),
                  onPressed: saving ? null : onTryAgain,
                  child: Text(
                    'Try Again',
                    style: AppTheme.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: _SummaryLayout.primaryActionWidth,
                  child: primaryButton,
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Button(
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm + 4,
                            ),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (_) => context.elixBackground,
                          ),
                        ),
                        onPressed: saving ? null : onTryAgain,
                        child: Text(
                          'Try Again',
                          style: AppTheme.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 2, child: primaryButton),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: HyperlinkButton(
                    onPressed: saving ? null : onDiscard,
                    child: Text(
                      'Discard without saving',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Elastic pop-in entrance for the summary card.
class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({required this.child});

  final Widget child;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scale = Tween(
      begin: 0.75,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.3, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 6.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
