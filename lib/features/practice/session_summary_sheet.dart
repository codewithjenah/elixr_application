import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../data/models/assessment_score_display.dart';
import '../../data/models/movement.dart';
import '../../data/models/rubric_assessment.dart';
import '../../data/models/training_prop.dart';
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
  static const performanceColumnWidth = 236.0;
  static const scoreRingSize = 108.0;
  static const scoreRingSizeCompact = 88.0;
  static const cardPadding = 12.0;
  static const sectionGap = 12.0;
  static const bodyPadding = 16.0;
  static const headerPaddingH = 18.0;
  static const headerPaddingV = 12.0;
  static const actionsPadding = 16.0;
  static const primaryActionWidth = 260.0;
  static const evidenceWidth = 96.0;
  static const evidenceHeight = 72.0;
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
    this.evidenceJpegBytes,
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
  final Uint8List? evidenceJpegBytes;

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
    TrainingProp? nextProp,
    Uint8List? evidenceJpegBytes,
  }) {
    return showDialog<SessionSummaryResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6080812),
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

            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            return Stack(
              children: [
                if (celebrates(assessment.performanceLevel) && !reduceMotion)
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
                          nextMovementName: nextMovement == null
                              ? null
                              : nextPracticeLabel(
                                  nextMovement,
                                  nextProp ?? nextMovement.supportedProps.first,
                                ),
                          evidenceJpegBytes: evidenceJpegBytes,
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
            ? 'Strong finish — review recurring form notes below.'
            : 'Solid execution. Keep the consistency going.',
      PerformanceLevel.competent =>
        hasImprovements
            ? 'Good progress. A few things to fine-tune below.'
            : 'Good effort. Keep practicing to build consistency.',
      PerformanceLevel.developing =>
        hasImprovements
            ? 'Getting there. Focus on the tips below.'
            : 'You are making progress. Keep practicing to raise your ELIXR '
                  'score.',
      PerformanceLevel.beginning =>
        hasImprovements
            ? 'Early stages — review the tips below and try again.'
            : 'Keep going — regular practice will help your ELIXR score '
                  'improve.',
    };
  }

  static String _performanceMessage(PerformanceLevel level) {
    if (celebrates(level)) {
      return 'No recurring form issue met the session threshold.';
    }
    return 'No recurring form issue was detected. '
        'Keep practicing to improve your ELIXR score.';
  }

  static ({String label, Color color}) _tier(PerformanceLevel level) => (
    label: AssessmentScoreDisplay.performanceLabel(level),
    color: performanceLevelColor(level),
  );

  @override
  Widget build(BuildContext context) {
    final levelColor = performanceLevelColor(_level);
    final tier = _tier(_level);
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final flatten =
        highContrast || context.elixWorkspaceVisuals.flattenDenseSurfaces;
    final glowScale = context.elixWorkspaceVisuals.ambientGlowScale;

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
              color: isDark ? colors.canvasDeep : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: highContrast
                    ? colors.borderStrong
                    : AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.22),
                width: highContrast ? 2 : 1,
              ),
              boxShadow: flatten
                  ? const []
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: (isDark ? 0.16 : 0.10) * glowScale,
                        ),
                        blurRadius: 48,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: colors.shadow.withValues(
                          alpha: isDark ? 0.7 : 0.22,
                        ),
                        blurRadius: 44,
                        offset: const Offset(0, 22),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ResultHero(
                    movement: movement,
                    heldSteady: _heldSteady,
                    level: _level,
                    completionMessage: _heldSteady
                        ? 'You held "$movement" steady. Well done!'
                        : _tierMessage(
                            _level,
                            hasImprovements: assessment.hasImprovements,
                          ),
                    evidenceJpegBytes: evidenceJpegBytes,
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: _SummaryBody(
                      rubric: _rubric,
                      levelColor: levelColor,
                      tier: tier,
                      durationSeconds: durationSeconds,
                      assessment: assessment,
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

class _ResultHero extends StatelessWidget {
  const _ResultHero({
    required this.movement,
    required this.heldSteady,
    required this.level,
    required this.completionMessage,
    this.evidenceJpegBytes,
  });

  final String movement;
  final bool heldSteady;
  final PerformanceLevel level;
  final String completionMessage;
  final Uint8List? evidenceJpegBytes;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final glowScale = context.elixWorkspaceVisuals.ambientGlowScale;
    final success = context.elixColors.success;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(
                    alpha: (isDark ? 0.14 : 0.06) * glowScale,
                  ),
                  AppColors.accent.withValues(
                    alpha: (isDark ? 0.07 : 0.035) * glowScale,
                  ),
                  Colors.transparent,
                ],
                stops: const [0, 0.42, 1],
              ),
        border: Border(
          bottom: BorderSide(
            color: highContrast
                ? context.elixBorder
                : AppColors.primary.withValues(alpha: 0.16),
          ),
        ),
      ),
      child: Stack(
        children: [
          if (!highContrast) ...[
            Positioned(
              left: -36,
              top: -48,
              child: IgnorePointer(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(
                          alpha: (isDark ? 0.20 : 0.08) * glowScale,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 120,
              top: -28,
              child: IgnorePointer(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(
                          alpha: (isDark ? 0.14 : 0.06) * glowScale,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _SummaryLayout.headerPaddingH,
              vertical: _SummaryLayout.headerPaddingV,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: success.withValues(alpha: highContrast ? 0 : 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: success.withValues(alpha: highContrast ? 1 : 0.4),
                    ),
                    boxShadow: highContrast
                        ? const []
                        : [
                            BoxShadow(
                              color: success.withValues(alpha: 0.22),
                              blurRadius: 16,
                            ),
                          ],
                  ),
                  child: Icon(
                    heldSteady
                        ? FluentIcons.trophy2_solid
                        : FluentIcons.completed_solid,
                    color: success,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session Complete',
                        style: AppTheme.eyebrow(
                          color: context.elixTextSecondary,
                        ).copyWith(letterSpacing: 1.6),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        movement,
                        style: AppTheme.headingMedium.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: context.elixTextPrimary,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        completionMessage,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: heldSteady
                              ? AppColors.primary
                              : context.elixTextSecondary,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (evidenceJpegBytes != null) ...[
                  _EvidenceThumbnail(bytes: evidenceJpegBytes!),
                  const SizedBox(width: AppSpacing.sm),
                ],
                RankBadge(level: level),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact affordance keeps the completion screen one-page while preserving
/// access to the complete, uncropped confirmation frame.
class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.bytes});

  final Uint8List bytes;

  void _openViewer(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 760),
        title: const Text('Confirmed movement frame'),
        content: AspectRatio(
          aspectRatio: 4 / 3,
          child: ColoredBox(
            color: Colors.black,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(FluentIcons.photo2, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        actions: [
          Button(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = context.isHighContrast;

    return Tooltip(
      message: 'View confirmed frame',
      child: HoverButton(
        onPressed: () => _openViewer(context),
        cursor: SystemMouseCursors.click,
        builder: (context, states) {
          final hovered = states.isHovered;
          final focused = states.isFocused;
          return Semantics(
            button: true,
            label: 'View confirmed movement frame',
            child: AnimatedContainer(
              key: const Key('session-summary-evidence'),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: _SummaryLayout.evidenceWidth,
              height: _SummaryLayout.evidenceHeight,
              transformAlignment: Alignment.center,
              transform: Matrix4.translationValues(
                0,
                hovered && !reduceMotion ? -1 : 0,
                0,
              ),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused
                      ? context.elixColors.focusRing
                      : AppColors.primary.withValues(
                          alpha: hovered || highContrast ? 0.75 : 0.38,
                        ),
                  width: focused || highContrast ? 2 : 1,
                ),
                boxShadow: highContrast
                    ? const []
                    : [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: hovered ? 0.28 : 0.14,
                          ),
                          blurRadius: hovered ? 16 : 10,
                        ),
                      ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(-1, 1, 1),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      FluentIcons.photo2,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
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
            AppSpacing.sm + 2,
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
                  emptyImprovementsMessage: emptyImprovementsMessage,
                  emptyStrengthsMessage: emptyStrengthsMessage,
                )
              : _CompactBody(
                  rubric: rubric,
                  levelColor: levelColor,
                  tier: tier,
                  durationSeconds: durationSeconds,
                  assessment: assessment,
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
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _SummaryLayout.performanceColumnWidth,
          child: _PerformanceDashboard(
            rubric: rubric,
            levelColor: levelColor,
            tier: tier,
            durationSeconds: durationSeconds,
            compact: false,
          ),
        ),
        const SizedBox(width: _SummaryLayout.sectionGap + 2),
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
    required this.emptyImprovementsMessage,
    required this.emptyStrengthsMessage,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final SessionAssessment assessment;
  final String emptyImprovementsMessage;
  final String emptyStrengthsMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PerformanceDashboard(
          rubric: rubric,
          levelColor: levelColor,
          tier: tier,
          durationSeconds: durationSeconds,
          compact: true,
        ),
        const SizedBox(height: _SummaryLayout.sectionGap),
        _CoachingColumn(
          assessment: assessment,
          emptyImprovementsMessage: emptyImprovementsMessage,
          emptyStrengthsMessage: emptyStrengthsMessage,
          preferSideBySideInsights: true,
        ),
      ],
    );
  }
}

class _PerformanceDashboard extends StatelessWidget {
  const _PerformanceDashboard({
    required this.rubric,
    required this.levelColor,
    required this.tier,
    required this.durationSeconds,
    required this.compact,
  });

  final RubricAssessment rubric;
  final Color levelColor;
  final ({String label, Color color}) tier;
  final int durationSeconds;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final gauge = _ScoreGauge(
      total: rubric.total,
      color: levelColor,
      size: compact
          ? _SummaryLayout.scoreRingSizeCompact
          : _SummaryLayout.scoreRingSize,
    );
    final tierBadge = _TierBadge(label: tier.label, color: tier.color);
    final durationChip = _MetaChip(
      icon: FluentIcons.clock,
      label: SessionSummarySheet._formatDuration(durationSeconds),
    );
    final criteria = _CriteriaCard(rubric: rubric, accent: levelColor);

    final summary = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              gauge,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [tierBadge, durationChip],
                    ),
                  ],
                ),
              ),
            ],
          )
        : Column(
            children: [
              gauge,
              const SizedBox(height: AppSpacing.sm),
              tierBadge,
              const SizedBox(height: AppSpacing.sm),
              durationChip,
            ],
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_SummaryLayout.cardPadding),
      decoration: BoxDecoration(
        color: highContrast
            ? colors.surfaceRaised
            : Color.alphaBlend(
                levelColor.withValues(alpha: isDark ? 0.08 : 0.05),
                isDark ? const Color(0xFF12101A) : colors.surfaceTinted,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : levelColor.withValues(alpha: isDark ? 0.28 : 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          summary,
          const SizedBox(height: AppSpacing.sm + 2),
          criteria,
        ],
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  const _ScoreGauge({
    required this.total,
    required this.color,
    required this.size,
  });

  final int total;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = context.isHighContrast;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 1100);

    return Semantics(
      label: AssessmentScoreDisplay.officialSemantics(total),
      child: TweenAnimationBuilder<double>(
        duration: duration,
        curve: Curves.easeOutCubic,
        tween: Tween(
          begin: reduceMotion ? total.toDouble() : 0,
          end: total.toDouble(),
        ),
        builder: (context, animatedTotal, _) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _ScoreRingPainter(
              progress: (animatedTotal / RubricScale.maxTotal).clamp(0.0, 1.0),
              color: color,
              glow: !highContrast,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${animatedTotal.round()}',
                    style: TextStyle(
                      fontSize: size >= 100 ? 30 : 24,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '/${RubricScale.maxTotal}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.elixTextSecondary,
                      fontWeight: FontWeight.w600,
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

/// Rubric total plus the four criterion scores for the completed session.
class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard({required this.rubric, required this.accent});

  final RubricAssessment rubric;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('session-summary-rubric'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ELIXR Score',
                style: AppTheme.caption.copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextSecondary,
                ),
              ),
            ),
            Text(
              AssessmentScoreDisplay.official(rubric.total),
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
          _RubricMetricRow(
            label: AssessmentScoreDisplay.criterionLabel(criterion),
            score: rubric.scoreFor(criterion),
          ),
      ],
    );
  }
}

class _RubricMetricRow extends StatelessWidget {
  const _RubricMetricRow({required this.label, required this.score});

  final String label;
  final int score;

  Color get _accent {
    if (score >= RubricScale.maxCriterion) return AppColors.success;
    if (score == 2) return AppColors.primarySoft;
    if (score == 1) return AppColors.warning;
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: context.elixTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 46,
            child: _SegmentMeter(
              value: score,
              max: RubricScale.maxCriterion,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 34,
            child: Text(
              '$score/${RubricScale.maxCriterion}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentMeter extends StatelessWidget {
  const _SegmentMeter({
    required this.value,
    required this.max,
    required this.color,
  });

  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < max; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i < value ? color : color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ],
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
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
      icon: FluentIcons.completed_solid,
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
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final surface = highContrast
        ? context.elixCardSurface
        : Color.alphaBlend(
            accent.withValues(alpha: isDark ? 0.08 : 0.05),
            isDark ? const Color(0xFF12101A) : context.elixPanelSurface,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_SummaryLayout.cardPadding),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : accent.withValues(alpha: isDark ? 0.28 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 13, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
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
                  SizedBox(
                    width: 16,
                    child: Padding(
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
                  ),
                  const SizedBox(width: 6),
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
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final glowScale = context.elixWorkspaceVisuals.ambientGlowScale;
    final surface = highContrast
        ? colors.surfaceRaised
        : Color.alphaBlend(
            AppColors.primary.withValues(alpha: isDark ? 0.09 : 0.05),
            isDark ? const Color(0xFF161122) : colors.surfaceTinted,
          );

    return Container(
      key: const Key('session-summary-recommendation'),
      width: double.infinity,
      padding: const EdgeInsets.all(_SummaryLayout.cardPadding),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? colors.borderStrong
              : AppColors.primary.withValues(alpha: isDark ? 0.34 : 0.24),
        ),
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: (isDark ? 0.10 : 0.05) * glowScale,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FluentIcons.forward,
                  size: 13,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        'NEXT UP',
                        style: AppTheme.eyebrow(
                          color: AppColors.primary,
                        ).copyWith(fontSize: 10, letterSpacing: 1.3),
                      ),
                    ),
                    Text(
                      'Recommended Next Session',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            'Practice ${recommendation.movementName} again',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.elixTextPrimary,
              height: 1.25,
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
          const SizedBox(height: AppSpacing.sm + 2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaChip(
                icon: FluentIcons.checkbox_composite,
                label: 'Target: ${recommendation.targetLabel}',
              ),
              _MetaChip(
                icon: FluentIcons.clock,
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
    final isDark = context.isDarkTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? context.elixColors.canvas.withValues(alpha: 0.55)
              : context.elixBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
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
        color: context.isHighContrast
            ? null
            : context.elixPanelSurface.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(
            color: context.isHighContrast
                ? context.elixBorder
                : AppColors.primary.withValues(alpha: 0.12),
          ),
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
                      style: TextStyle(
                        fontSize: 13,
                        color: context.elixTextPrimary,
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
                _TryAgainButton(
                  onPressed: saving ? null : onTryAgain,
                  expanded: false,
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
                      child: _TryAgainButton(
                        onPressed: saving ? null : onTryAgain,
                        expanded: true,
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

class _TryAgainButton extends StatelessWidget {
  const _TryAgainButton({required this.onPressed, required this.expanded});

  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          FluentIcons.refresh,
          size: 14,
          color: onPressed == null
              ? context.elixColors.disabledText
              : context.elixTextPrimary,
        ),
        const SizedBox(width: 6),
        Text(
          'Try Again',
          style: AppTheme.body.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );

    return Button(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return context.elixColors.disabledSurface;
          }
          if (states.contains(WidgetState.pressed)) {
            return context.elixColors.interactivePressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return context.elixColors.interactiveHover;
          }
          return context.elixBackground;
        }),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Quick fade and scale-in for the summary card.
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
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _scale = Tween(
      begin: 0.97,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  final double progress;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    const strokeWidth = 7.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;

    if (glow) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = strokeWidth + 5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    canvas.drawArc(
      rect,
      start,
      sweep,
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
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
