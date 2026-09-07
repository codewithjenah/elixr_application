import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/teacher/activity_center/teacher_activity_controller.dart';
import '../../features/profile/profile_menu.dart';
import '../../services/auth_service.dart';
import '../../services/message_unread_service.dart';
import '../constants/app_spacing.dart';
import '../router/app_route_paths.dart';
import '../theme/app_theme.dart';
import '../utils/user_name.dart';
import '../widgets/elix_sidebar_chrome.dart';
import '../widgets/profile_avatar.dart';

/// The primary list is ordered by the work a Teacher does every day. The
/// legacy [classroom] and [insights] values remain for source compatibility
/// with consumers that classify sidebar items, but are no longer used by the
/// Teacher shell.
enum TeacherSidebarGroup { primary, utility, classroom, insights }

class TeacherSidebarItem {
  const TeacherSidebarItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.group,
  });

  final String label;
  final IconData icon;
  final String route;
  final TeacherSidebarGroup group;
}

const teacherSidebarItems = [
  TeacherSidebarItem(
    label: 'Dashboard',
    icon: FluentIcons.view_dashboard,
    route: AppRoutePaths.teacherDashboard,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Classrooms',
    icon: FluentIcons.people,
    route: AppRoutePaths.teacherGroups,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Review Work',
    icon: FluentIcons.review_request_solid,
    route: AppRoutePaths.teacherToReview,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Students',
    icon: FluentIcons.contact,
    route: AppRoutePaths.teacherStudents,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Calendar',
    icon: FluentIcons.calendar,
    route: AppRoutePaths.teacherCalendar,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Progress',
    icon: FluentIcons.analytics_view,
    route: AppRoutePaths.teacherProgress,
    group: TeacherSidebarGroup.primary,
  ),
  TeacherSidebarItem(
    label: 'Messages',
    icon: FluentIcons.chat,
    route: AppRoutePaths.teacherMessages,
    group: TeacherSidebarGroup.primary,
  ),
];

/// Destinations that remain one click away without competing with the
/// Teacher's daily classroom workflow.
const teacherSidebarUtilityItems = [
  TeacherSidebarItem(
    label: 'Notifications',
    icon: FluentIcons.activity_feed,
    route: AppRoutePaths.teacherActivityCenter,
    group: TeacherSidebarGroup.utility,
  ),
  TeacherSidebarItem(
    label: 'Teacher Access',
    icon: FluentIcons.add_friend,
    route: AppRoutePaths.teacherFaculties,
    group: TeacherSidebarGroup.utility,
  ),
];

@visibleForTesting
bool isTeacherSidebarRouteActive(String currentPath, String itemRoute) {
  return currentPath == itemRoute || currentPath.startsWith('$itemRoute/');
}

@visibleForTesting
bool isTeacherSidebarItemActive(String currentPath, TeacherSidebarItem item) {
  if (isTeacherSidebarRouteActive(currentPath, item.route)) return true;
  // Analytics and Rankings are one Progress destination in the primary
  // hierarchy while their original routes remain valid deep links.
  if (item.route != AppRoutePaths.teacherProgress) return false;
  return isTeacherSidebarRouteActive(
        currentPath,
        AppRoutePaths.teacherAnalytics,
      ) ||
      isTeacherSidebarRouteActive(
        currentPath,
        AppRoutePaths.teacherLeaderboard,
      );
}

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
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final unreadCount =
        context.watch<MessageUnreadService?>()?.unreadCount ?? 0;
    final activity = context.watch<TeacherActivityController?>();
    final activityUnreadCount = activity?.unreadCount ?? 0;
    final pendingReviewCount = activity?.pendingReviewCount ?? 0;
    final pendingJoinCount = activity?.pendingJoinCount ?? 0;
    final initials = (user?.fullName.isNotEmpty == true)
        ? userInitials(user!.fullName)
        : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: isCollapsed
          ? ElixSidebarMetrics.collapsedWidth
          : ElixSidebarMetrics.expandedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: elixSidebarSurfaceDecoration(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showCollapsedLayout =
              isCollapsed ||
              constraints.maxWidth < ElixSidebarMetrics.layoutCollapseThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElixSidebarHeader(
                showCollapsedLayout: showCollapsedLayout,
                isCollapsed: isCollapsed,
                onToggleCollapse: onToggleCollapse,
                subtitle: 'Teacher',
              ),
              const SizedBox(height: AppSpacing.sm),
              ElixSidebarBrandDivider(collapsed: showCollapsedLayout),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, navConstraints) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: navConstraints.maxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildGroupedItems(
                          context,
                          showCollapsedLayout,
                          unreadCount,
                          activityUnreadCount,
                          pendingReviewCount,
                          pendingJoinCount,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _TeacherIdentityFooter(
                user: user,
                initials: initials,
                isCollapsed: showCollapsedLayout,
                onLogout: onLogout,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildGroupedItems(
    BuildContext context,
    bool showCollapsedLayout,
    int unreadCount,
    int activityUnreadCount,
    int pendingReviewCount,
    int pendingJoinCount,
  ) {
    final children = <Widget>[];

    void addGroup(List<TeacherSidebarItem> items, String title) {
      if (items.isEmpty) return;

      children.add(
        ElixSidebarGroupLabel(title: title, isCollapsed: showCollapsedLayout),
      );

      for (final item in items) {
        children.add(
          ElixSidebarNavTile(
            label: item.label,
            icon: item.icon,
            isActive: isTeacherSidebarItemActive(currentRoute, item),
            isCollapsed: showCollapsedLayout,
            unreadCount: switch (item.route) {
              AppRoutePaths.teacherMessages => unreadCount,
              AppRoutePaths.teacherActivityCenter => activityUnreadCount,
              AppRoutePaths.teacherToReview => pendingReviewCount,
              AppRoutePaths.teacherGroups => pendingJoinCount,
              _ => 0,
            },
            onTap: () => context.go(item.route),
          ),
        );
      }
    }

    addGroup(teacherSidebarItems, 'Workspace');
    addGroup(teacherSidebarUtilityItems, 'Utilities');

    return children;
  }
}

/// Identity card that opens [ProfileMenu]. No XP / level / EXP bar.
class _TeacherIdentityFooter extends StatefulWidget {
  const _TeacherIdentityFooter({
    required this.user,
    required this.initials,
    required this.isCollapsed,
    required this.onLogout,
  });

  final User? user;
  final String initials;
  final bool isCollapsed;
  final VoidCallback onLogout;

  @override
  State<_TeacherIdentityFooter> createState() => _TeacherIdentityFooterState();
}

class _TeacherIdentityFooterState extends State<_TeacherIdentityFooter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sidebarFirstName = normalizeNamePart(widget.user?.firstName ?? '');

    final profileTile = Semantics(
      button: true,
      label: 'Profile menu',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Builder(
          builder: (profileContext) => GestureDetector(
            onTap: () =>
                ProfileMenu.show(profileContext, onLogout: widget.onLogout),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.symmetric(
                horizontal: widget.isCollapsed ? AppSpacing.sm : AppSpacing.md,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCollapsed ? 0 : AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: _hovered
                    ? context.elixBorder.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _hovered
                      ? context.elixBorder.withValues(alpha: 0.4)
                      : context.elixBorder.withValues(alpha: 0.2),
                ),
              ),
              child: widget.isCollapsed
                  ? Center(
                      child: ProfileAvatarWidget(
                        key: const Key('teacher_sidebar_avatar'),
                        networkImageUrl: widget.user?.profilePictureUrl,
                        legacyLocalPath: widget.user?.profilePicturePath,
                        initials: widget.initials,
                        radius: 18,
                        equippedBorderId: widget.user?.profileBorderId,
                        animateBorder: true,
                      ),
                    )
                  : Row(
                      children: [
                        ProfileAvatarWidget(
                          key: const Key('teacher_sidebar_avatar'),
                          networkImageUrl: widget.user?.profilePictureUrl,
                          legacyLocalPath: widget.user?.profilePicturePath,
                          initials: widget.initials,
                          radius: 18,
                          equippedBorderId: widget.user?.profileBorderId,
                          animateBorder: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sidebarFirstName.isNotEmpty
                                    ? sidebarFirstName
                                    : 'User',
                                style: AppTheme.bodySecondary.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.elixTextPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Teacher',
                                style: AppTheme.caption.copyWith(
                                  fontSize: 11,
                                  color: context.elixTextSecondary,
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
          ),
        ),
      ),
    );

    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.user?.fullName ?? 'Profile',
        displayHorizontally: true,
        useMousePosition: false,
        style: const TooltipThemeData(preferBelow: false),
        child: profileTile,
      );
    }
    return profileTile;
  }
}
