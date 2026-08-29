import 'package:fluent_ui/fluent_ui.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_image.dart';
import 'profile_section_card.dart';

class CompletedMovementsSection extends StatelessWidget {
  const CompletedMovementsSection({super.key, required this.movementNames});

  final List<String> movementNames;

  @override
  Widget build(BuildContext context) {
    // Older session history is intentionally retained, but retired movement
    // names must not appear in the current profile completion summary.
    final visibleMovementNames = _currentMovementNames(movementNames);

    return ProfileSectionCard(
      title: 'Completed Movements',
      trailing: visibleMovementNames.isEmpty
          ? null
          : Text(
              '${visibleMovementNames.length}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
      child: visibleMovementNames.isEmpty
          ? Text(
              'No completed movements yet.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 520 ? 2 : 1;
                const gap = AppSpacing.sm;
                final tileWidth = (width - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final name in visibleMovementNames)
                      SizedBox(
                        width: tileWidth,
                        child: _MovementTile(name: name),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

List<String> _currentMovementNames(Iterable<String> names) {
  final unique = <String>{};
  final visible = <String>[];
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        !isRecognizedCoachingMovement(trimmed) ||
        !unique.add(trimmed)) {
      continue;
    }
    visible.add(trimmed);
  }
  visible.sort();
  return visible;
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : context.elixBorder.withValues(alpha: 0.4),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? context.elixCardSurface
                  : context.elixColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: MovementImage(
              movementName: name,
              size: 28,
              paddingFactor: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.elixTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
