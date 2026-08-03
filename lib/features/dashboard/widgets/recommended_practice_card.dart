import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../movements/movements_presentation.dart';
import '../../../features/progress/training_recommendation.dart';

const _purple = AppColors.accent;
const _cyan = AppColors.primarySoft;
const _panelColor = AppColors.panelSurface;

/// Dashboard card showing the rule-based next-practice recommendation.
class RecommendedPracticeCard extends StatefulWidget {
  const RecommendedPracticeCard({
    super.key,
    required this.recommendation,
    required this.loading,
  });

  final TrainingRecommendation? recommendation;
  final bool loading;

  @override
  State<RecommendedPracticeCard> createState() =>
      _RecommendedPracticeCardState();
}

class _RecommendedPracticeCardState extends State<RecommendedPracticeCard> {
  bool _hovered = false;
  bool _ctaHovered = false;

  void _practiceNow(MovementMastery mastery) {
    final encoded = Uri.encodeComponent(mastery.movement.name);
    context.go(
      '/practice?movement=$encoded&difficulty=${mastery.movement.difficulty}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _panel(
        child: const SizedBox(
          height: 120,
          child: Center(child: ProgressRing()),
        ),
      );
    }

    final recommendation = widget.recommendation;
    if (recommendation == null) {
      return _panel(
        child: const Text(
          'Sign in to see your personalized practice recommendation.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }

    final mastery = recommendation.recommended;
    final movement = mastery.movement;
    final accent = difficultyAccentColor(movement.difficulty);
    final statusLabel = masteryStatusLabel(mastery.status);
    final recentLabel = mastery.recentAverageScore != null
        ? mastery.recentAverageScore!.round().toString()
        : 'Not practiced';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: _hovered ? 0.45 : 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _hovered ? 0.14 : 0.07),
              blurRadius: _hovered ? 22 : 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(FluentIcons.lightbulb, size: 14, color: _cyan),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Recommended Next Practice',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InfoChip(label: movement.difficulty, color: accent),
                        _InfoChip(label: statusLabel, color: _purple),
                        _InfoChip(
                          label: 'Recent: $recentLabel',
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      recommendation.reason,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                );

                final cta = _PracticeNowButton(
                  hovered: _ctaHovered,
                  onHover: (value) => setState(() => _ctaHovered = value),
                  onPressed: () => _practiceNow(mastery),
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      const SizedBox(height: AppSpacing.md),
                      Align(alignment: Alignment.centerLeft, child: cta),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: AppSpacing.md),
                    cta,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color.lerp(color, Colors.white, 0.2),
        ),
      ),
    );
  }
}

class _PracticeNowButton extends StatelessWidget {
  const _PracticeNowButton({
    required this.hovered,
    required this.onHover,
    required this.onPressed,
  });

  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: hovered
                  ? const [AppColors.primarySoft, AppColors.accentSoft]
                  : const [AppColors.primary, AppColors.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: hovered ? 0.45 : 0.3,
                ),
                blurRadius: hovered ? 18 : 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(FluentIcons.play_solid, size: 12, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Practice Now',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
