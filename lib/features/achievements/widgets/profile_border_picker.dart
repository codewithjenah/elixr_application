import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/profile_border.dart';

class ProfileBorderPicker extends StatelessWidget {
  const ProfileBorderPicker({
    super.key,
    required this.unlockedBorderIds,
    required this.equippedBorderId,
    required this.busyBorderId,
    required this.onEquip,
    required this.onUnequip,
  });

  final Set<String> unlockedBorderIds;
  final String? equippedBorderId;
  final String? busyBorderId;
  final ValueChanged<String> onEquip;
  final VoidCallback onUnequip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final crossAxisCount = wide ? 5 : (constraints.maxWidth >= 480 ? 3 : 2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: profileBorderCatalog.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: wide ? 0.92 : 0.85,
          ),
          itemBuilder: (context, index) {
            final border = profileBorderCatalog[index];
            final unlocked = unlockedBorderIds.contains(border.id);
            final equipped = equippedBorderId == border.id;
            final busy = busyBorderId == border.id;

            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: equipped
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : context.elixBorder.withValues(alpha: 0.65),
                ),
              ),
              child: Column(
                children: [
                  ProfileBorderFrame(
                    size: 48,
                    equippedBorderId: border.id,
                    child: Container(
                      color: unlocked
                          ? Color(
                              border.primaryColorValue,
                            ).withValues(alpha: 0.18)
                          : context.elixBorder.withValues(alpha: 0.35),
                      child: Icon(
                        unlocked ? FluentIcons.contact : FluentIcons.lock,
                        size: 18,
                        color: unlocked
                            ? Color(border.primaryColorValue)
                            : context.elixTextSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    border.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unlocked ? border.rarity.name : 'Locked',
                    style: AppTheme.caption.copyWith(
                      fontSize: 10,
                      color: unlocked
                          ? AppColors.accent
                          : context.elixTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (equipped)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Equipped',
                        style: AppTheme.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    )
                  else if (unlocked)
                    Button(
                      onPressed: busy ? null : () => onEquip(border.id),
                      child: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : const Text('Equip'),
                    )
                  else
                    Text(
                      'Locked',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class UnequipBorderButton extends StatelessWidget {
  const UnequipBorderButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: enabled && !busy ? onPressed : null,
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : const Text('Unequip border'),
    );
  }
}
