import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'profile_section_card.dart';

class CompletedMovementsSection extends StatelessWidget {
  const CompletedMovementsSection({super.key, required this.movementNames});

  final List<String> movementNames;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      title: 'Completed Movements',
      trailing: movementNames.isEmpty
          ? null
          : Text(
              '${movementNames.length}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
      child: movementNames.isEmpty
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
                    for (final name in movementNames)
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
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              FluentIcons.check_mark,
              size: 12,
              color: AppColors.success,
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
