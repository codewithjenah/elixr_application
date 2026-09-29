import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../practice/practice_game_widgets.dart';
import '../practice/session_summary_sheet.dart';

/// Immutable view of the backend's authoritative custom assessment.
///
/// Custom movements are scored by their own contract (component scores and a
/// 0..100 percentage). This is deliberately not a four-criterion
/// `RubricAssessment`.
@immutable
class CustomAssessmentSnapshot {
  const CustomAssessmentSnapshot({
    required this.scorePercent,
    required this.componentScores,
    required this.feedback,
    this.total,
    this.rawTotal,
    this.rawTotalMalformed = false,
    this.maxTotal,
    this.performanceLevel,
  });

  /// User-facing overall percentage (70..100 for validated completions).
  final double scorePercent;

  /// Persistence total (0..12). For validated completions this is the
  /// percentage-derived grade, not the raw rubric; classroom persistence and
  /// [performanceLevel] use it.
  final int? total;

  /// Backend-authoritative raw rubric total; sent only for validated
  /// completions (`raw_total`).
  final int? rawTotal;

  /// `raw_total` was sent but unusable, so [total] must not stand in for it.
  final bool rawTotalMalformed;
  final int? maxTotal;
  final String? performanceLevel;

  /// Backend component scores on the 0..3 scale; null means not assessed.
  final Map<String, int?> componentScores;
  final List<String> feedback;

  static const componentMax = 3;

  static CustomAssessmentSnapshot? tryFrom(Map<String, dynamic> raw) {
    final percent = raw['score_percent'];
    if (percent is! num || !percent.isFinite || percent < 0 || percent > 100) {
      return null;
    }
    final components = <String, int?>{};
    final rawComponents = raw['component_scores'];
    if (rawComponents is Map) {
      for (final entry in rawComponents.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String) continue;
        if (value == null) {
          components[key] = null;
        } else if (value is num && value.isFinite) {
          components[key] = value.round();
        }
      }
    }
    final total = raw['total'];
    final maxTotal = raw['max_total'];
    final level = raw['performance_level'];
    final max = maxTotal is num && maxTotal > 0 ? maxTotal.toInt() : null;
    final rawTotal = raw['raw_total'];
    final validRawTotal =
        rawTotal is num &&
            rawTotal.isFinite &&
            rawTotal == rawTotal.roundToDouble() &&
            max != null &&
            rawTotal >= 0 &&
            rawTotal <= max
        ? rawTotal.toInt()
        : null;
    return CustomAssessmentSnapshot(
      scorePercent: percent.toDouble(),
      total: total is num ? total.toInt() : null,
      rawTotal: validRawTotal,
      rawTotalMalformed: raw.containsKey('raw_total') && validRawTotal == null,
      maxTotal: max,
      performanceLevel: level is String && level.trim().isNotEmpty
          ? level.trim()
          : null,
      componentScores: Map.unmodifiable(components),
      feedback: List.unmodifiable(
        raw['feedback'] is List
            ? (raw['feedback'] as List).whereType<String>()
            : const <String>[],
      ),
    );
  }

  int get roundedPercent => scorePercent.round();

  /// Rubric total to display: `raw_total` when sent, else (legacy and
  /// incomplete payloads, where `total` is the rubric) `total`. Null when
  /// `raw_total` is malformed or the total is out of range.
  int? get rubricTotal {
    if (rawTotal != null) return rawTotal;
    final fallback = total;
    final max = maxTotal;
    if (rawTotalMalformed || fallback == null || max == null) return null;
    return fallback >= 0 && fallback <= max ? fallback : null;
  }

  /// Numeric component scores for persistence.
  Map<String, double> get persistedComponentScores => {
    for (final entry in componentScores.entries)
      if (entry.value != null) entry.key: entry.value!.toDouble(),
  };

  String? get performanceLevelLabel {
    final level = performanceLevel;
    if (level == null) return null;
    return level
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}

/// Modal result for Custom Movement practice (personal and classroom),
/// patterned after the official [SessionSummarySheet]. It only observes
/// [saveController]; the practice flow starts the one persistence operation
/// before showing it.
class CustomMovementResultDialog extends StatelessWidget {
  const CustomMovementResultDialog({
    super.key,
    required this.movementName,
    required this.durationSeconds,
    required this.assessment,
    required this.saveState,
    required this.onPrimaryAction,
    required this.onBack,
    required this.onPracticeAgain,
    this.saveError,
    this.evidenceJpegBytes,
    this.contextLabel = personalContextLabel,
    this.backLabel = personalBackLabel,
    this.showPracticeAgain = true,
    this.allowSaveRetry = true,
  });

  static const personalContextLabel = 'Personal practice · No global XP';
  static const personalBackLabel = 'Back to My Movements';
  static const classroomContextLabel = 'Classroom assessment · No global XP';
  static const classroomBackLabel = 'Back to Assignment';

  final String movementName;
  final int durationSeconds;
  final CustomAssessmentSnapshot assessment;
  final SessionSaveState saveState;
  final String? saveError;
  final Uint8List? evidenceJpegBytes;
  final VoidCallback onPrimaryAction;
  final VoidCallback onBack;
  final VoidCallback onPracticeAgain;
  final String contextLabel;
  final String backLabel;
  final bool showPracticeAgain;

  /// False when the save operation is not idempotent: a failed save is then
  /// final for this dialog and the trainee may still leave.
  final bool allowSaveRetry;

  static Future<SessionSummaryResult?> show(
    BuildContext context, {
    required String movementName,
    required int durationSeconds,
    required CustomAssessmentSnapshot assessment,
    required SessionSummarySaveController saveController,
    Uint8List? evidenceJpegBytes,
    String contextLabel = personalContextLabel,
    String backLabel = personalBackLabel,
    bool showPracticeAgain = true,
    bool allowSaveRetry = true,
    String? saveFailureMessage,
  }) {
    return showDialog<SessionSummaryResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6080812),
      useRootNavigator: true,
      builder: (ctx) => AnimatedBuilder(
        animation: saveController,
        builder: (context, _) {
          final state = saveController.state;
          final saved =
              state == SessionSaveState.saved ||
              state == SessionSaveState.pendingSync;
          final settled =
              saved || (state == SessionSaveState.failed && !allowSaveRetry);
          void close(SessionSummaryResult result) {
            if (!settled) return;
            Navigator.of(ctx, rootNavigator: true).pop(result);
          }

          return SafeArea(
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: CustomMovementResultDialog(
                  movementName: movementName,
                  durationSeconds: durationSeconds,
                  assessment: assessment,
                  saveState: state,
                  saveError: state == SessionSaveState.failed
                      ? saveFailureMessage ?? saveController.error
                      : saveController.error,
                  evidenceJpegBytes: evidenceJpegBytes,
                  contextLabel: contextLabel,
                  backLabel: backLabel,
                  showPracticeAgain: showPracticeAgain,
                  allowSaveRetry: allowSaveRetry,
                  onPrimaryAction: () {
                    if (state == SessionSaveState.failed && allowSaveRetry) {
                      unawaited(saveController.retry());
                      return;
                    }
                    close(SessionSummaryResult.saved);
                  },
                  onBack: () => close(SessionSummaryResult.discarded),
                  onPracticeAgain: () => close(SessionSummaryResult.tryAgain),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math
            .min(720.0, constraints.maxWidth - 48)
            .clamp(320.0, 720.0);
        return ConstrainedBox(
          key: const Key('custom-result-dialog'),
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: constraints.maxHeight,
          ),
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
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    movementName: movementName,
                    contextLabel: contextLabel,
                    evidenceJpegBytes: evidenceJpegBytes,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ScoreCard(
                            assessment: assessment,
                            duration: _formatDuration(durationSeconds),
                          ),
                          if (assessment.feedback.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _FeedbackCard(feedback: assessment.feedback),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _Actions(
                    saveState: saveState,
                    saveError: saveError,
                    onPrimaryAction: onPrimaryAction,
                    onBack: onBack,
                    onPracticeAgain: onPracticeAgain,
                    backLabel: backLabel,
                    showPracticeAgain: showPracticeAgain,
                    allowSaveRetry: allowSaveRetry,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.movementName,
    required this.contextLabel,
    this.evidenceJpegBytes,
  });

  final String movementName;
  final String contextLabel;
  final Uint8List? evidenceJpegBytes;

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.isHighContrast
                ? context.elixBorder
                : AppColors.primary.withValues(alpha: 0.16),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(FluentIcons.completed_solid, color: accent, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session Complete · Custom Assessment',
                  style: AppTheme.eyebrow(
                    color: context.elixTextSecondary,
                  ).copyWith(letterSpacing: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  movementName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  contextLabel,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (evidenceJpegBytes != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _EvidenceThumbnail(bytes: evidenceJpegBytes!),
          ],
        ],
      ),
    );
  }
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.bytes});

  final Uint8List bytes;

  Widget _image(BoxFit fit) => Transform(
    alignment: Alignment.center,
    transform: Matrix4.diagonal3Values(-1, 1, 1),
    child: Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(FluentIcons.photo2, color: Colors.white)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'View confirmed frame',
      child: Semantics(
        button: true,
        label: 'View confirmed movement frame',
        child: GestureDetector(
          onTap: () => ElixDialog.show<void>(
            context,
            title: 'Confirmed movement frame',
            maxWidth: 760,
            scrollableContent: true,
            content: AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(
                color: Colors.black,
                child: _image(BoxFit.contain),
              ),
            ),
            actions: [
              ElixPrimaryButton(
                label: 'Close',
                expanded: false,
                variant: ElixButtonVariant.secondary,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          ),
          child: Container(
            key: const Key('custom-result-evidence'),
            width: 96,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.38),
              ),
            ),
            child: _image(BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.assessment, required this.duration});

  final CustomAssessmentSnapshot assessment;
  final String duration;

  @override
  Widget build(BuildContext context) {
    // The large percentage and this 0..12 rubric are different measures;
    // the percentage-derived persistence total is never shown as the rubric.
    final rubric = assessment.rubricTotal;
    final maxTotal = assessment.maxTotal;
    final level = assessment.performanceLevelLabel;
    return Container(
      key: const Key('custom-result-score'),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.practiceSectionSurface(
        context,
        accent: AppColors.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${assessment.roundedPercent}%',
                style: AppTheme.metric(context, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  children: [
                    if (rubric != null && maxTotal != null)
                      _Chip(label: 'Rubric $rubric / $maxTotal'),
                    if (level != null) _Chip(label: level),
                    _Chip(label: duration),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Custom Score',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in assessment.componentScores.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
                  Text(
                    entry.value == null
                        ? 'Not assessed'
                        : '${entry.value} / ${CustomAssessmentSnapshot.componentMax}',
                    style: AppTheme.caption.copyWith(
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: context.elixTextPrimary,
      ),
    ),
  );
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

  final List<String> feedback;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: AppTheme.practiceSectionSurface(
      context,
      accent: AppColors.warning,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Feedback',
          style: AppTheme.headingMedium.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final message in feedback)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '•  $message',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.elixTextPrimary,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.saveState,
    required this.saveError,
    required this.onPrimaryAction,
    required this.onBack,
    required this.onPracticeAgain,
    required this.backLabel,
    required this.showPracticeAgain,
    required this.allowSaveRetry,
  });

  final SessionSaveState saveState;
  final String? saveError;
  final VoidCallback onPrimaryAction;
  final VoidCallback onBack;
  final VoidCallback onPracticeAgain;
  final String backLabel;
  final bool showPracticeAgain;
  final bool allowSaveRetry;

  @override
  Widget build(BuildContext context) {
    final saving = saveState == SessionSaveState.saving;
    final failed = saveState == SessionSaveState.failed;
    final saved =
        saveState == SessionSaveState.saved ||
        saveState == SessionSaveState.pendingSync;
    final retry = failed && allowSaveRetry;
    final settled = saved || (failed && !allowSaveRetry);
    final buttons = [
      GameActionButton(
        key: const ValueKey('custom-result-back'),
        label: backLabel,
        icon: FluentIcons.chrome_back,
        onPressed: settled ? onBack : null,
        variant: GameActionButtonVariant.secondary,
      ),
      if (showPracticeAgain)
        GameActionButton(
          key: const ValueKey('custom-result-practice-again'),
          label: 'Practice Again',
          icon: FluentIcons.refresh,
          onPressed: settled ? onPracticeAgain : null,
          variant: GameActionButtonVariant.secondary,
        ),
      GameActionButton(
        key: const ValueKey('custom-result-primary-action'),
        label: retry ? 'Retry Save' : 'Done',
        icon: retry ? FluentIcons.sync : FluentIcons.check_mark,
        onPressed: saving ? null : onPrimaryAction,
        isLoading: saving,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, AppSpacing.sm, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.isHighContrast
                ? context.elixBorder
                : AppColors.primary.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SessionSaveStatusBanner(state: saveState, error: saveError),
              const SizedBox(height: AppSpacing.sm),
              if (wide)
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      buttons[i],
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
