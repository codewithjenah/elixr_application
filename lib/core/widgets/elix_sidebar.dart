import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../../features/profile/profile_menu.dart';
import '../../features/profile/profile_settings_screen.dart';

class SidebarItem {
  const SidebarItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

const _sidebarItems = [
  SidebarItem(
    label: 'Dashboard',
    icon: FluentIcons.view_dashboard,
    route: '/dashboard',
  ),
  SidebarItem(
    label: 'Movements',
    icon: FluentIcons.more_sports,
    route: '/movements',
  ),
  SidebarItem(
    label: 'History',
    icon: FluentIcons.clock,
    route: '/history',
  ),
  SidebarItem(
    label: 'Progress',
    icon: FluentIcons.bar_chart_vertical_fill,
    route: '/progress',
  ),
];

class ElixSidebar extends StatelessWidget {
  const ElixSidebar({
    super.key,
    required this.currentRoute,
    required this.onLogout,
  });

  final String currentRoute;
  final VoidCallback onLogout;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final initials = (user?.fullName.isNotEmpty == true)
        ? _initials(user!.fullName)
        : '?';

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: AppTheme.headingMedium.copyWith(
                    color: AppColors.primary,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Flair Training',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._sidebarItems.map((item) {
            final isActive = currentRoute.startsWith(item.route);
            return _SidebarTile(
              item: item,
              isActive: isActive,
              onTap: () => context.go(item.route),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Builder(
                builder: (profileContext) => GestureDetector(
                  onTap: () => ProfileMenu.show(
                    profileContext,
                    onLogout: onLogout,
                  ),
                  child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ProfileAvatarWidget(
                        imagePath: user?.profilePicturePath,
                        initials: initials,
                        radius: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'User',
                              style: AppTheme.body.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.role ?? 'Trainee',
                              style: AppTheme.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        FluentIcons.more,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final SidebarItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  item.label,
                  style: AppTheme.body.copyWith(
                    color: isActive ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
