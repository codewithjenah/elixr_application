import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../movements_presentation.dart';
import 'movement_card.dart';

class MovementDifficultySection extends StatelessWidget {
  const MovementDifficultySection({
    super.key,
    required this.difficulty,
    required this.movements,
    required this.stats,
  });

  final String difficulty;
  final List<Movement> movements;
  final Map<String, MovementStats> stats;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(difficulty);
    final practiced = movements
        .where((m) => (stats[m.name]?.count ?? 0) > 0)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                difficultySectionTitle(difficulty),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            Text(
              '$practiced of ${movements.length} practiced',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.elixTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Divider(
          style: DividerThemeData(
            decoration: BoxDecoration(
              color: context.elixBorder.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = movementsGridColumns(constraints.maxWidth);
            const spacing = AppSpacing.md;
            // Keep a small buffer above practiced-card content so font
            // metrics cannot trigger sub-pixel RenderFlex overflows.
            const targetHeight = 248.0;
            final totalSpacing = spacing * (columns - 1);
            final cardWidth = (constraints.maxWidth - totalSpacing) / columns;
            final aspectRatio = cardWidth / targetHeight;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: movements.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) {
                final movement = movements[index];
                final entry = stats[movement.name];
                return MovementCard(
                  movement: movement,
                  sessionCount: entry?.count ?? 0,
                  avgScore: entry?.avgScore ?? 0,
                );
              },
            );
          },
        ),
      ],
    );
  }
}
