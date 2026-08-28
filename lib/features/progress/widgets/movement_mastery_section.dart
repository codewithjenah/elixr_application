import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../movements/movements_presentation.dart';
import '../training_recommendation.dart';

/// Displays per-movement mastery rows grouped by difficulty.
class MovementMasterySection extends StatelessWidget {
  const MovementMasterySection({super.key, required this.masteries});

  final List<MovementMastery> masteries;

  static const _difficultyGroups = ['Easy', 'Medium', 'Hard'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ElixSectionHeader(heading: 'Movement Mastery'),
        const SizedBox(height: AppSpacing.md),
        for (final difficulty in _difficultyGroups) ...[
          _DifficultyGroup(
            difficulty: difficulty,
            masteries: masteries
                .where((m) => m.movement.difficulty == difficulty)
                .toList(),
          ),
          if (difficulty != _difficultyGroups.last)
            const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _DifficultyGroup extends StatelessWidget {
  const _DifficultyGroup({required this.difficulty, required this.masteries});

  final String difficulty;
  final List<MovementMastery> masteries;

  @override
  Widget build(BuildContext context) {
    if (masteries.isEmpty) return const SizedBox.shrink();

    final accent = difficultyAccentColor(difficulty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            difficulty,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < masteries.length; i++) ...[
            _MasteryRow(mastery: masteries[i]),
            if (i < masteries.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.mastery});

  final MovementMastery mastery;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(mastery.movement.difficulty);
    final recentAverage = mastery.recentAverageRubric;
    final recentLabel = recentAverage != null
        ? '${recentAverage.round()} / 12'
        : '—';
    final bestLabel = mastery.bestRubricTotal != null
        ? '${mastery.bestRubricTotal} / 12'
        : '—';
    final statusLabel = masteryStatusLabel(mastery.status);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mastery.movement.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                Text(
                  'Recent $recentLabel',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.elixTextSecondary,
                  ),
                ),
                Text(
                  'Best $bestLabel',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.elixTextSecondary,
                  ),
                ),
                Text(
                  '${mastery.completedSessions} sessions',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ],
        );

        final progressBar = _MasteryProgressBar(
          rubricAverage: recentAverage,
          accent: accent,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleBlock, const SizedBox(height: 8), progressBar],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 3, child: titleBlock),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: progressBar),
          ],
        );
      },
    );
  }
}

/// Rubric progress on the 0..12 scale.
class _MasteryProgressBar extends StatelessWidget {
  const _MasteryProgressBar({
    required this.rubricAverage,
    required this.accent,
  });

  final double? rubricAverage;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final value = (rubricAverage ?? 0) / 12;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    color: context.isDarkTheme
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accent.withValues(alpha: 0.55), accent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 44,
          child: Text(
            rubricAverage == null ? '—' : '${rubricAverage!.round()}/12',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}
