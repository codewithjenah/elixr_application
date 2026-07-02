import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../data/models/movement.dart';
import '../../services/settings_service.dart';
import '../profile/profile_settings_screen.dart';

class MovementsScreen extends StatelessWidget {
  const MovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottleDetectionEnabled =
        context.watch<SettingsService>().bottleDetectionEnabled;

    return ScaffoldPage(
      content: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Movements', style: AppTheme.headingLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Practice Easy, Medium, and Hard movements.',
                style: AppTheme.bodySecondary,
              ),
              if (!bottleDetectionEnabled) ...[
                const SizedBox(height: AppSpacing.md),
                ElixCard(
                  child: Row(
                    children: [
                      const Icon(
                        FluentIcons.info,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Bottle detection is off. Movement scoring uses posture only.',
                          style: AppTheme.bodySecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      HyperlinkButton(
                        child: const Text('Preferences'),
                        onPressed: () => ProfileSettingsScreen.show(
                          context,
                          initialSection: ProfileSettingsSection.preferences,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _DifficultySection(
                title: 'Easy',
                color: AppColors.success,
                movements: movementsByDifficulty('Easy'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _DifficultySection(
                title: 'Medium',
                color: AppColors.warning,
                movements: movementsByDifficulty('Medium'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _DifficultySection(
                title: 'Hard',
                color: AppColors.error,
                movements: movementsByDifficulty('Hard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultySection extends StatelessWidget {
  const _DifficultySection({
    required this.title,
    required this.color,
    required this.movements,
    this.badge,
  });

  final String title;
  final Color color;
  final List<Movement> movements;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTheme.headingMedium),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge!, style: AppTheme.caption),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...movements.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _MovementTile(movement: m),
            )),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final Movement movement;

  @override
  Widget build(BuildContext context) {
    final enabled = movement.enabled;

    return ElixCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: enabled
          ? () {
              final encoded = Uri.encodeComponent(movement.name);
              context.go(
                '/practice?movement=$encoded&difficulty=${movement.difficulty}',
              );
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        movement.name,
                        style: AppTheme.headingMedium.copyWith(fontSize: 16),
                      ),
                      if (!enabled) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Coming soon',
                            style: AppTheme.caption.copyWith(fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(movement.description, style: AppTheme.bodySecondary),
                  if (movement.requiresHandsDetection) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Hands detection required',
                      style: AppTheme.caption.copyWith(
                        color: AppColors.primarySoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              enabled
                  ? FluentIcons.play_solid
                  : FluentIcons.lock_solid,
              color: enabled ? AppColors.primary : AppColors.textSecondary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
