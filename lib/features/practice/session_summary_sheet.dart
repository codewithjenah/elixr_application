import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import 'practice_game_widgets.dart';
import 'session_assessment.dart';

enum SessionSummaryResult { saved, discarded, tryAgain }

class SessionSummarySheet extends StatelessWidget {
  const SessionSummarySheet({
    super.key,
    required this.movement,
    required this.durationSeconds,
    required this.assessment,
    required this.onSave,
    required this.onDiscard,
    required this.onTryAgain,
    this.saving = false,
    this.saveError,
  });

  final String movement;
  final int durationSeconds;
  final SessionAssessment assessment;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onTryAgain;
  final bool saving;
  final String? saveError;

  int get _score => assessment.finalScore;

  bool get _heldSteady => assessment.heldSteady;

  static Future<SessionSummaryResult?> show(
    BuildContext context, {
    required String movement,
    required int durationSeconds,
    required SessionAssessment assessment,
    required Future<String> Function(String? existingSessionId) onSave,
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
            return Stack(
              children: [
                if (assessment.finalScore >= 60)
                  const Positioned.fill(child: ConfettiOverlay()),
                Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: _AnimatedEntrance(
                      child: SessionSummarySheet(
                        movement: movement,
                        durationSeconds: durationSeconds,
                        assessment: assessment,
                        saving: saving,
                        saveError: saveError,
                        onDiscard: () => Navigator.of(
                          ctx,
                          rootNavigator: true,
                        ).pop(SessionSummaryResult.discarded),
                        onTryAgain: () => Navigator.of(
                          ctx,
                          rootNavigator: true,
                        ).pop(SessionSummaryResult.tryAgain),
                        onSave: () async {
                          if (saving) return;
                          setState(() {
                            saving = true;
                            saveError = null;
                          });
                          try {
                            pendingSessionId = await onSave(pendingSessionId);
                            if (ctx.mounted) {
                              Navigator.of(
                                ctx,
                                rootNavigator: true,
                              ).pop(SessionSummaryResult.saved);
                            }
                          } catch (error) {
                            if (ctx.mounted) {
                              setState(() {
                                saveError = _formatSaveError(error);
                              });
                            }
                          } finally {
                            if (ctx.mounted) {
                              setState(() => saving = false);
                            }
                          }
                        },
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

  static String _tierMessage(int score, {required bool hasImprovements}) {
    if (score >= 80) {
      return hasImprovements
          ? 'Strong finish — review recurring technique notes below.'
          : 'Solid execution. Keep the consistency going.';
    }
    if (score >= 60) {
      return hasImprovements
          ? 'Good progress. A few things to fine-tune below.'
          : 'Good effort. Keep practicing to build consistency.';
    }
    if (score >= 40) {
      return hasImprovements
          ? 'Getting there. Focus on the tips below.'
          : 'You are making progress. Keep practicing to raise your score.';
    }
    return hasImprovements
        ? 'Early stages — review the tips below and try again.'
        : 'Keep going — regular practice will help your score improve.';
  }

  static String _performanceMessage(int score) {
    if (score >= 80) {
      return 'No recurring technique issue met the session threshold.';
    }
    return 'No recurring technique issue was detected. '
        'Keep practicing to improve your overall score.';
  }

  static Color _scoreColor(int value) {
    if (value >= 80) return AppColors.success;
    if (value >= 50) return AppColors.warning;
    return AppColors.error;
  }

  static ({String label, Color color}) _tier(int score) {
    if (score >= 80) return (label: 'Excellent', color: AppColors.success);
    if (score >= 60) return (label: 'Good', color: AppColors.warning);
    if (score >= 40) return (label: 'Fair', color: AppColors.warning);
    return (label: 'Needs Practice', color: AppColors.error);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scoreClr = _scoreColor(_score);
    final tier = _tier(_score);

    return Container(
      width: (size.width * 0.9).clamp(320.0, 480.0),
      constraints: BoxConstraints(maxHeight: size.height * 0.85),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
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
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildScoreSection(scoreClr, tier, assessment.hasImprovements),
            _buildDurationRow(context),
            Flexible(child: _buildCoachingScroll(context)),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
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
              _heldSteady
                  ? FluentIcons.trophy2_solid
                  : FluentIcons.completed_solid,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Session Complete',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _heldSteady
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
          RankBadge(score: _score),
        ],
      ),
    );
  }

  Widget _buildScoreSection(
    Color scoreClr,
    ({String label, Color color}) tier,
    bool hasImprovements,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: _score.toDouble()),
            builder: (context, animatedScore, _) => SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: _ScoreRingPainter(
                  progress: (animatedScore / 100).clamp(0.0, 1.0),
                  color: scoreClr,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${animatedScore.round()}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: scoreClr,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Score',
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
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: tier.color.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    tier.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tier.color,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _tierMessage(_score, hasImprovements: hasImprovements),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: context.elixBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const Icon(FluentIcons.clock, size: 15, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            const Text(
              'Duration',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text(
              _formatDuration(durationSeconds),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachingScroll(BuildContext context) {
    final coaching = assessment.coaching;
    final strengths = coaching.strengths;
    final improvements = assessment.improvements;
    final recommendation = coaching.recommendation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, 0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCoachingSectionHeader(
              title: 'What Went Well',
              accent: AppColors.success,
              count: strengths.length,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (strengths.isEmpty)
              _buildEmptyCoachingCard(
                context,
                message: _heldSteady
                    ? 'Hold confirmed — keep reinforcing clean technique.'
                    : 'No standout technique strength met the session threshold.',
                accent: AppColors.success,
                icon: FluentIcons.emoji2,
              )
            else
              _BulletCard(
                accent: AppColors.success,
                items: strengths.map((s) => s.message).toList(growable: false),
              ),
            const SizedBox(height: AppSpacing.lg),
            _buildCoachingSectionHeader(
              title: 'Needs Improvement',
              accent: AppColors.warning,
              count: improvements.length,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (improvements.isEmpty)
              _buildPerformanceCard()
            else
              _BulletCard(
                accent: AppColors.warning,
                items: improvements
                    .map((i) => i.message)
                    .toList(growable: false),
              ),
            if (recommendation != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildCoachingSectionHeader(
                title: 'Recommended Next Session',
                accent: AppColors.primary,
                count: null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _RecommendationCard(recommendation: recommendation),
            ],
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachingSectionHeader({
    required String title,
    required Color accent,
    required int? count,
  }) {
    return Row(
      children: [
        Text(title, style: AppTheme.headingMedium.copyWith(fontSize: 15)),
        if (count != null && count > 0) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCoachingCard(
    BuildContext context, {
    required String message,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: context.elixTextSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              FluentIcons.emoji2,
              size: 18,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _performanceMessage(_score),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveError != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
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
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            children: [
              Expanded(
                child: Button(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (_) => context.elixBackground,
                    ),
                  ),
                  onPressed: saving ? null : onTryAgain,
                  child: Text(
                    'Try Again',
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: GameActionButton(
                  label: 'Save & Continue',
                  icon: FluentIcons.save,
                  onPressed: saving ? null : onSave,
                  isLoading: saving,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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

/// Compact bullet list for strengths or improvements (no nested scroll).
class _BulletCard extends StatelessWidget {
  const _BulletCard({required this.accent, required this.items});

  final Color accent;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      height: 1.45,
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
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Practice ${recommendation.movementName} again',
            style: TextStyle(
              fontSize: 14,
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Target: ${recommendation.targetLabel}',
            style: TextStyle(
              fontSize: 13,
              color: context.elixTextPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended duration: '
            '${_formatDuration(recommendation.recommendedDurationSeconds)}',
            style: TextStyle(
              fontSize: 13,
              color: context.elixTextPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
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
    final radius = size.width / 2 - 7;
    const strokeWidth = 7.0;

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
