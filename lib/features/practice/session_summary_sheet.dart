import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/feedback_chip.dart';
import '../../data/models/practice_feedback.dart';

class SessionSummarySheet extends StatelessWidget {
  const SessionSummarySheet({
    super.key,
    required this.movement,
    required this.score,
    required this.durationSeconds,
    required this.feedbacks,
    required this.onSave,
    required this.onDiscard,
    this.saving = false,
  });

  final String movement;
  final int score;
  final int durationSeconds;
  final List<PracticeFeedback> feedbacks;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final bool saving;

  static Future<bool?> show(
    BuildContext context, {
    required String movement,
    required int score,
    required int durationSeconds,
    required List<PracticeFeedback> feedbacks,
    required Future<void> Function() onSave,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      useRootNavigator: true,
      builder: (ctx) {
        var saving = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return Center(
              child: Material(
                type: MaterialType.transparency,
                child: SessionSummarySheet(
                  movement: movement,
                  score: score,
                  durationSeconds: durationSeconds,
                  feedbacks: feedbacks,
                  saving: saving,
                  onDiscard: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(false),
                  onSave: () async {
                    setState(() => saving = true);
                    await onSave();
                    if (ctx.mounted) {
                      Navigator.of(ctx, rootNavigator: true).pop(true);
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  static List<PracticeFeedback> _uniqueFeedbacks(List<PracticeFeedback> list) {
    final seen = <String>{};
    final result = <PracticeFeedback>[];
    for (final f in list) {
      final key = '${f.feedbackType}:${f.feedback}';
      if (seen.add(key)) result.add(f);
    }
    return result;
  }

  Color _scoreColor(int value) {
    if (value >= 80) return AppColors.success;
    if (value >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final uniqueFeedbacks = _uniqueFeedbacks(feedbacks);
    final scoreClr = _scoreColor(score);

    return Container(
      width: (size.width * 0.9).clamp(320.0, 520.0),
      constraints: BoxConstraints(maxHeight: size.height * 0.82),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 40,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.success.withValues(alpha: 0.1),
                    AppColors.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
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
                    child: const Icon(
                      FluentIcons.completed_solid,
                      color: AppColors.success,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Session Complete', style: AppTheme.headingLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text(movement, style: AppTheme.bodySecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Score',
                      value: '$score',
                      accent: scoreClr,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Stat(
                      label: 'Duration',
                      value: _formatDuration(durationSeconds),
                      accent: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: [
                  Text('Feedback', style: AppTheme.headingMedium),
                  const Spacer(),
                  if (uniqueFeedbacks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${uniqueFeedbacks.length}',
                        style: AppTheme.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: uniqueFeedbacks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              FluentIcons.emoji2,
                              size: 36,
                              color: AppColors.success.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Great form — no corrections needed!',
                              style: AppTheme.bodySecondary,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: uniqueFeedbacks.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: FeedbackChip(
                              message: uniqueFeedbacks[i].feedback,
                              feedbackType: uniqueFeedbacks[i].feedbackType,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Expanded(
                    child: Button(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => context.elixBackground,
                        ),
                      ),
                      onPressed: saving ? null : onDiscard,
                      child: Text(
                        'Discard',
                        style: AppTheme.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: ElixPrimaryButton(
                      label: 'Save & Continue',
                      onPressed: saving ? null : onSave,
                      isLoading: saving,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.headingLarge.copyWith(
              fontSize: 32,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTheme.bodySecondary),
        ],
      ),
    );
  }
}
