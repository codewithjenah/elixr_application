import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

class PrivateProfileState extends StatelessWidget {
  const PrivateProfileState({super.key, this.ownerIsTeacher = false});

  final bool ownerIsTeacher;

  @override
  Widget build(BuildContext context) {
    final body = ownerIsTeacher
        ? 'This teacher has locked their detailed activity. '
              'Name and avatar remain visible.'
        : 'This player has locked their detailed activity. '
              'Basic leaderboard identity remains visible.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? AppColors.panelSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.lock,
            size: 40,
            color: AppColors.accent.withValues(alpha: 0.85),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This profile is locked',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Profile owners can see recent profile visitors.',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }
}
