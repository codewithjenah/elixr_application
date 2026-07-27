import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/practice_feedback.dart';
import 'practice_game_widgets.dart';

enum SessionSummaryResult { saved, discarded, tryAgain }

class SessionSummarySheet extends StatelessWidget {
  const SessionSummarySheet({
    super.key,
    required this.movement,
    required this.score,
    required this.durationSeconds,
    required this.feedbacks,
    required this.onSave,
    required this.onDiscard,
    required this.onTryAgain,
    this.saving = false,
    this.heldSteady = false,
  });

  final String movement;
  final int score;
  final int durationSeconds;
  final List<PracticeFeedback> feedbacks;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onTryAgain;
  final bool saving;
  final bool heldSteady;

  static Future<SessionSummaryResult?> show(
    BuildContext context, {
    required String movement,
    required int score,
    required int durationSeconds,
    required List<PracticeFeedback> feedbacks,
    required Future<void> Function() onSave,
    bool heldSteady = false,
  }) {
    return showDialog<SessionSummaryResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      useRootNavigator: true,
      builder: (ctx) {
        var saving = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                if (score >= 60)
                  const Positioned.fill(child: ConfettiOverlay()),
                Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: _AnimatedEntrance(
                      child: SessionSummarySheet(
                        movement: movement,
                        score: score,
                        durationSeconds: durationSeconds,
                        feedbacks: feedbacks,
                        saving: saving,
                        heldSteady: heldSteady,
                        onDiscard: () => Navigator.of(
                          ctx,
                          rootNavigator: true,
                        ).pop(SessionSummaryResult.discarded),
                        onTryAgain: () => Navigator.of(
                          ctx,
                          rootNavigator: true,
                        ).pop(SessionSummaryResult.tryAgain),
                        onSave: () async {
                          setState(() => saving = true);
                          await onSave();
                          if (ctx.mounted) {
                            Navigator.of(
                              ctx,
                              rootNavigator: true,
                            ).pop(SessionSummaryResult.saved);
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

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  /// Counts warning-type feedback messages across the session and returns the
  /// top 3 most frequent ones as improvement suggestions.
  /// Detection-failure messages (environment issues) are excluded so only
  /// technique-related tips surface.
  static List<String> _deriveImprovements(List<PracticeFeedback> feedbacks) {
    const skipPhrases = [
      'not detected',
      'not visible',
      'Keep the bottle visible',
      'Step back',
      'Face the camera',
      'in frame',
      'Camera unavailable',
      'Model load failed',
      'Target body part',
    ];

    final counts = <String, int>{};
    for (final f in feedbacks) {
      if (f.feedbackType == 'positive') continue;
      if (skipPhrases.any((p) => f.feedback.contains(p))) continue;
      counts[f.feedback] = (counts[f.feedback] ?? 0) + 1;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => e.key).toList();
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

  static String _tierMessage(int score) {
    if (score >= 80) return 'Solid execution. Keep the consistency going.';
    if (score >= 60) return 'Good progress. A few things to fine-tune.';
    if (score >= 40) return 'Getting there. Focus on the tips below.';
    return 'Early stages — review the tips below and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final improvements = _deriveImprovements(feedbacks);
    final scoreClr = _scoreColor(score);
    final tier = _tier(score);

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
            _buildScoreSection(scoreClr, tier),
            _buildDurationRow(context),
            Flexible(child: _buildImprovements(context, improvements)),
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
              heldSteady
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
          RankBadge(score: score),
        ],
      ),
    );
  }

  Widget _buildScoreSection(
    Color scoreClr,
    ({String label, Color color}) tier,
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
            tween: Tween(begin: 0, end: score.toDouble()),
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
                  _tierMessage(score),
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

  Widget _buildImprovements(BuildContext context, List<String> improvements) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                improvements.isEmpty ? 'Performance' : 'What to Improve',
                style: AppTheme.headingMedium.copyWith(fontSize: 15),
              ),
              if (improvements.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${improvements.length} tip${improvements.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (improvements.isEmpty)
            _buildAllGoodCard()
          else
            Flexible(child: _TipsCard(tips: improvements)),
        ],
      ),
    );
  }

  Widget _buildAllGoodCard() {
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
          const Expanded(
            child: Text(
              'Great form — no corrections needed this session!',
              style: TextStyle(
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

/// Single beginner-friendly tips card (all tips in one place).
class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.tips});

  final List<String> tips;

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
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tips.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      tips[i],
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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
