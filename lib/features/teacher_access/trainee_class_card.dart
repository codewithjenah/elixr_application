import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';

const _bannerColors = [
  AppColors.primary,
  AppColors.accent,
  Color(0xFF0F766E),
  Color(0xFF1D4ED8),
  Color(0xFFC2410C),
];

/// Stable Classroom-style header color for a class card or detail banner.
Color traineeClassBannerColor(String groupId) {
  var hash = 0;
  for (final code in groupId.codeUnits) {
    hash = (hash + code) & 0x7fffffff;
  }
  return _bannerColors[hash % _bannerColors.length];
}

/// Compact Google Classroom-style class card. Opens the class detail page.
class TraineeClassCard extends StatelessWidget {
  const TraineeClassCard({
    super.key,
    required this.groupId,
    required this.className,
    required this.teacherDisplayName,
    required this.onOpen,
  });

  final String groupId;
  final String className;
  final String teacherDisplayName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final banner = traineeClassBannerColor(groupId);
    return ElixHoverSurface(
      borderRadius: 16,
      onTap: onOpen,
      child: Container(
        key: Key('teacher_access_group_$groupId'),
        height: 196,
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: banner,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.headingMedium.copyWith(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          teacherDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Classmates and assignments',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ),
                    Icon(
                      FluentIcons.chevron_right,
                      size: 12,
                      color: context.elixTextSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
