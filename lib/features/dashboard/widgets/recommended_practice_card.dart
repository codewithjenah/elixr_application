import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/progression/practice_variant.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
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
  void _practiceNow(PracticeVariant variant, String difficulty) {
    final encoded = Uri.encodeComponent(variant.movementName);
    context.go(
      '/practice?movement=$encoded&difficulty=$difficulty&prop=${variant.trainingProp.protocolValue}',
    );
  }

  void _openMovements() {
    context.go('/movements');
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
    final runnable =
        recommendation.hasRunnablePractice &&
        recommendation.recommendedVariant != null;
    final movement = mastery.movement;
    final accent = difficultyAccentColor(movement.difficulty);
    final statusLabel = masteryStatusLabel(mastery.status);
    final recentAverage = mastery.recentAverageRubric;
    final recentLabel = recentAverage != null
        ? '${recentAverage.round()} / 12'
        : 'Not practiced';

    return DashboardPanelCard(
      accent: accent,
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ElixEyebrow(label: "COACH'S FOCUS"),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final recommendationCopy = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.26),
                      ),
                    ),
                    child: const Icon(
                      FluentIcons.bullseye_target,
                      size: 21,
                      color: AppColors.primarySoft,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          runnable ? movement.name : 'No ready practice yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.elixTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        if (runnable)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _InfoChip(
                                label: movement.difficulty,
                                color: accent,
                              ),
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
                        if (runnable) const SizedBox(height: 7),
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
                ],
              );
              final action = Button(
                onPressed: runnable
                    ? () => _practiceNow(
                        recommendation.recommendedVariant!,
                        movement.difficulty,
                      )
                    : _openMovements,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.isHovered) {
                      return AppColors.primary.withValues(alpha: 0.20);
                    }
                    return AppColors.primary.withValues(alpha: 0.10);
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.72),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(runnable ? 'Practice this' : 'Open Movements'),
                    const SizedBox(width: 8),
                    const Icon(FluentIcons.chevron_right, size: 11),
                  ],
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    recommendationCopy,
                    const SizedBox(height: 12),
                    action,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: recommendationCopy),
                  const SizedBox(width: AppSpacing.md),
                  if (constraints.maxWidth >= 760) ...[
                    Container(
                      width: 1,
                      height: 72,
                      color: context.elixBorder.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: 236,
                      child: Text(
                        '“Small steps create big progress.”',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.supporting(
                          color: context.elixTextSecondary,
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  action,
                ],
              );
            },
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
