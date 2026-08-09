import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../movements/movements_presentation.dart';
import '../../progress/training_recommendation.dart';
import 'dashboard_panel_card.dart';

/// Slim coach recommendation strip that supports the hero CTA.
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
  void _practiceNow(MovementMastery mastery) {
    final encoded = Uri.encodeComponent(mastery.movement.name);
    context.go(
      '/practice?movement=$encoded&difficulty=${mastery.movement.difficulty}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const DashboardPanelCard(
        child: SizedBox(height: 72, child: Center(child: ProgressRing())),
      );
    }

    final recommendation = widget.recommendation;
    if (recommendation == null) {
      return DashboardPanelCard(
        child: Text(
          'Sign in to see your personalized practice recommendation.',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
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

    return DashboardPanelCard(
      accent: accent,
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "COACH'S FOCUS",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.elixTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _InfoChip(label: movement.difficulty, color: accent),
                        _InfoChip(
                          label: statusLabel,
                          color: context.elixTextSecondary,
                        ),
                        _InfoChip(
                          label: 'Recent: $recentLabel',
                          color: context.elixTextSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      recommendation.reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.elixTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              HyperlinkButton(
                onPressed: () => _practiceNow(mastery),
                child: const Text('Practice this'),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color.lerp(color, context.elixTextPrimary, 0.2),
        ),
      ),
    );
  }
}
