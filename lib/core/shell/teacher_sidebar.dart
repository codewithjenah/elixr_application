import 'package:elixr_core/utils/user_name.dart';
import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../router/app_route_paths.dart';
import '../theme/app_theme.dart';

class TeacherSidebarItem {
  const TeacherSidebarItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

const teacherSidebarItems = [
  TeacherSidebarItem(
    label: 'Dashboard',
    icon: FluentIcons.view_dashboard,
    route: AppRoutePaths.teacherDashboard,
  ),
  TeacherSidebarItem(
    label: 'Groups',
    icon: FluentIcons.people,
    route: AppRoutePaths.teacherGroups,
  ),
  TeacherSidebarItem(
    label: 'Students',
    icon: FluentIcons.contact,
    route: AppRoutePaths.teacherStudents,
  ),
  TeacherSidebarItem(
    label: 'Leaderboard',
    icon: FluentIcons.trophy2_solid,
    route: AppRoutePaths.teacherLeaderboard,
  ),
  TeacherSidebarItem(
    label: 'Movements',
    icon: FluentIcons.more_sports,
    route: AppRoutePaths.teacherMovements,
  ),
  TeacherSidebarItem(
    label: 'Settings',
    icon: FluentIcons.settings,
    route: AppRoutePaths.teacherSettings,
  ),
];

@visibleForTesting
bool isTeacherSidebarRouteActive(String currentPath, String itemRoute) {
  return currentPath == itemRoute || currentPath.startsWith('$itemRoute/');
}

const _expandedWidth = 256.0;
const _collapsedWidth = 80.0;

class TeacherSidebar extends StatelessWidget {
  const TeacherSidebar({
    super.key,
    required this.currentRoute,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onLogout,
  });

  final String currentRoute;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final width = isCollapsed ? _collapsedWidth : _expandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        border: Border(right: BorderSide(color: context.elixBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TeacherSidebarHeader(isCollapsed: isCollapsed),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              children: [
                for (final item in teacherSidebarItems)
                  _TeacherNavItem(
                    item: item,
                    isActive: isTeacherSidebarRouteActive(
                      currentRoute,
                      item.route,
                    ),
                    isCollapsed: isCollapsed,
                    onTap: () => context.go(item.route),
                  ),
              ],
            ),
          ),
          if (user != null)
            _TeacherIdentityFooter(
              user: user,
              isCollapsed: isCollapsed,
              onLogout: onLogout,
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: IconButton(
              icon: Icon(
                isCollapsed
                    ? FluentIcons.chevron_right
                    : FluentIcons.chevron_left,
              ),
              onPressed: onToggleCollapse,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherSidebarHeader extends StatelessWidget {
  const _TeacherSidebarHeader({required this.isCollapsed});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              FluentIcons.education,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: AppTheme.headingMedium.copyWith(
                      color: context.elixTextPrimary,
                    ),
                  ),
                  Text(
                    'Teacher',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeacherNavItem extends StatelessWidget {
  const _TeacherNavItem({
    required this.item,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  final TeacherSidebarItem item;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    final textColor = isActive
        ? activeColor
        : context.elixTextPrimary.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: HoverButton(
        onPressed: onTap,
        builder: (context, states) {
          final hovered = states.isHovered;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.12)
                  : hovered
                  ? context.elixBorder.withValues(alpha: 0.35)
                  : null,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: activeColor.withValues(alpha: 0.35))
                  : null,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: textColor),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item.label,
                      style: AppTheme.body.copyWith(
                        color: textColor,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TeacherIdentityFooter extends StatelessWidget {
  const _TeacherIdentityFooter({
    required this.user,
    required this.isCollapsed,
    required this.onLogout,
  });

  final User user;
  final bool isCollapsed;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final initials = userInitials(user.fullName);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initials,
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user.email,
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Button(
            onPressed: onLogout,
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const Icon(FluentIcons.sign_out, size: 16),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Log out'),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
