import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../movements/movements_presentation.dart';
import '../training_recommendation.dart';

const _panelColor = AppColors.panelSurface;

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
        const _SectionHeader(
          icon: FluentIcons.medal,
          title: 'Movement Mastery',
          accent: AppColors.primarySoft,
        ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTheme.headingMedium),
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
        color: _panelColor,
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
    final progress = mastery.recentAverageScore ?? 0;
    final recentLabel = mastery.recentAverageScore != null
        ? mastery.recentAverageScore!.round().toString()
        : '—';
    final bestLabel = mastery.bestScore?.toString() ?? '—';
    final statusLabel = masteryStatusLabel(mastery.status);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mastery.movement.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Best $bestLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${mastery.completedSessions} sessions',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        );

        final progressBar = _MasteryProgressBar(
          value: progress / 100,
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

class _MasteryProgressBar extends StatelessWidget {
  const _MasteryProgressBar({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.04)),
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
          width: 32,
          child: Text(
            '${(value * 100).round()}',
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
