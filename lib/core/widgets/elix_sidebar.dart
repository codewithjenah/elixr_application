import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/message_unread_service.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/gamification_rules.dart';
import '../theme/app_theme.dart';
import '../utils/user_name.dart';
import 'elix_sidebar_chrome.dart';
import 'profile_avatar.dart';
import '../../features/profile/profile_menu.dart';
import '../../features/trainee/activity_center/trainee_activity_controller.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;

enum SidebarGroup { overview, training, insights }

class SidebarItem {
  const SidebarItem({
    required this.label,
    required this.icon,
    this.route,
    this.comingSoon = false,
    required this.group,
  });

  final String label;
  final IconData icon;
  final String? route;
  final bool comingSoon;
  final SidebarGroup group;
}

const elixSidebarItems = [
  SidebarItem(
    label: 'Dashboard',
    icon: FluentIcons.view_dashboard,
    route: '/dashboard',
    group: SidebarGroup.overview,
  ),
  SidebarItem(
    label: 'Classroom',
    icon: FluentIcons.people,
    route: '/teacher-access',
    group: SidebarGroup.overview,
  ),
  SidebarItem(
    label: 'Leaderboard',
    icon: FluentIcons.trophy2_solid,
    route: '/leaderboard',
    group: SidebarGroup.overview,
  ),
  SidebarItem(
    label: 'Sessions',
    icon: FluentIcons.calendar_agenda,
    route: '/training',
    group: SidebarGroup.training,
  ),
  SidebarItem(
    label: 'Movements',
    icon: FluentIcons.more_sports,
    route: '/movements',
    group: SidebarGroup.training,
  ),
  SidebarItem(
    label: 'Playground',
    icon: FluentIcons.video,
    route: '/live-practice',
    group: SidebarGroup.training,
  ),
  SidebarItem(
    label: 'Help & Tutorials',
    icon: FluentIcons.education,
    route: '/learn',
    group: SidebarGroup.training,
  ),
  SidebarItem(
    label: 'Activity Center',
    icon: FluentIcons.activity_feed,
    route: '/activity-center',
    group: SidebarGroup.insights,
  ),
  SidebarItem(
    label: 'Messages',
    icon: FluentIcons.chat,
    route: '/messages',
    group: SidebarGroup.insights,
  ),
  SidebarItem(
    label: 'Progress',
    icon: FluentIcons.bar_chart_vertical_fill,
    route: '/progress',
    group: SidebarGroup.insights,
  ),
  SidebarItem(
    label: 'Achievements',
    icon: FluentIcons.medal,
    route: '/achievements',
    group: SidebarGroup.insights,
  ),
];

/// True when [currentPath] is this destination or a nested path under it.
///
/// Training stays selected for `/training` regardless of `view` query params
/// because [AppShell] passes path only.
@visibleForTesting
bool isElixSidebarRouteActive(String currentPath, String? itemRoute) {
  if (itemRoute == null) return false;
  return currentPath == itemRoute || currentPath.startsWith('$itemRoute/');
}

// The sidebar is a one-screen navigation surface. Compact rows keep every
// destination and the profile card visible at normal desktop heights.

class ElixSidebar extends StatefulWidget {
  const ElixSidebar({
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
  State<ElixSidebar> createState() => _ElixSidebarState();
}

class _ElixSidebarState extends State<ElixSidebar> {
  final _leaderboardRepo = LeaderboardRepository();
  int _totalXp = 0;
  String? _equippedBorderId;
  String? _statsUserId;
  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AuthService>().currentUser?.id;
    if (userId != _statsUserId) {
      _statsUserId = userId;
      _subscribeToLeaderboard(userId);
    }
  }

  @override
  void dispose() {
    _leaderboardSub?.cancel();
    super.dispose();
  }

  void _subscribeToLeaderboard(String? userId) {
    _leaderboardSub?.cancel();
    _leaderboardSub = null;
    if (userId == null) {
      setState(() {
        _totalXp = 0;
        _equippedBorderId = null;
      });
      return;
    }
    // Live subscription (not a one-shot fetch): session awards, quest claims,
    // and border equip writes all touch leaderboard/{userId}.
    _leaderboardSub = _leaderboardRepo.watchPlayer(userId).listen((entry) {
      if (!mounted) return;
      setState(() {
        _totalXp = entry?.totalXp ?? 0;
        _equippedBorderId = entry?.equippedBorderId;
      });
    });
  }

  void _onItemTap(SidebarItem item) {
    if (item.comingSoon) return;
    if (item.route != null) context.go(item.route!);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final unreadCount =
        context.watch<MessageUnreadService?>()?.unreadCount ?? 0;
    final activityUnreadCount =
        context.watch<TraineeActivityController?>()?.unreadCount ?? 0;
    final initials = (user?.fullName.isNotEmpty == true)
        ? userInitials(user!.fullName)
        : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: widget.isCollapsed
          ? ElixSidebarMetrics.collapsedWidth
          : ElixSidebarMetrics.expandedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: elixSidebarSurfaceDecoration(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showCollapsedLayout =
              widget.isCollapsed ||
              constraints.maxWidth < ElixSidebarMetrics.layoutCollapseThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElixSidebarHeader(
                showCollapsedLayout: showCollapsedLayout,
                isCollapsed: widget.isCollapsed,
                onToggleCollapse: widget.onToggleCollapse,
                subtitle: 'Trainee Workspace',
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
                          showCollapsedLayout,
                          unreadCount,
                          activityUnreadCount,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildProfileSection(user, initials, showCollapsedLayout),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildGroupedItems(
    bool showCollapsedLayout,
    int unreadCount,
    int activityUnreadCount,
  ) {
    final List<Widget> children = [];

    void addGroup(SidebarGroup group, String title) {
      final items = elixSidebarItems.where((i) => i.group == group).toList();
      if (items.isEmpty) return;

      children.add(
        ElixSidebarGroupLabel(title: title, isCollapsed: showCollapsedLayout),
      );

      for (final item in items) {
        children.add(
          ElixSidebarNavTile(
            label: item.label,
            icon: item.icon,
            isActive: isElixSidebarRouteActive(widget.currentRoute, item.route),
            isCollapsed: showCollapsedLayout,
            unreadCount: switch (item.label) {
              'Messages' => unreadCount,
              'Activity Center' => activityUnreadCount,
              _ => 0,
            },
            comingSoon: item.comingSoon,
            onTap: () => _onItemTap(item),
          ),
        );
      }
    }

    addGroup(SidebarGroup.overview, 'Overview');
    addGroup(SidebarGroup.training, 'Training');
    addGroup(SidebarGroup.insights, 'Insights');

    return children;
  }

  Widget _buildProfileSection(
    User? user,
    String initials,
    bool showCollapsedLayout,
  ) {
    return _ProfileSectionWidget(
      user: user,
      initials: initials,
      totalXp: _totalXp,
      equippedBorderId: _equippedBorderId,
      isCollapsed: showCollapsedLayout,
      onLogout: widget.onLogout,
    );
  }
}

class _ProfileSectionWidget extends StatefulWidget {
  const _ProfileSectionWidget({
    required this.user,
    required this.initials,
    required this.totalXp,
    required this.equippedBorderId,
    required this.isCollapsed,
    required this.onLogout,
  });

  final User? user;
  final String initials;
  final int totalXp;
  final String? equippedBorderId;
  final bool isCollapsed;
  final VoidCallback onLogout;

  @override
  State<_ProfileSectionWidget> createState() => _ProfileSectionWidgetState();
}

class _ProfileSectionWidgetState extends State<_ProfileSectionWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sidebarFirstName = normalizeNamePart(widget.user?.firstName ?? '');
    final level = GamificationRules.levelForXp(widget.totalXp);
    final expInLevel = GamificationRules.xpIntoLevel(widget.totalXp);

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
                        networkImageUrl: widget.user?.profilePictureUrl,
                        legacyLocalPath: widget.user?.profilePicturePath,
                        initials: widget.initials,
                        radius: 18,
                        equippedBorderId: widget.equippedBorderId,
                        animateBorder: true,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ProfileAvatarWidget(
                              networkImageUrl: widget.user?.profilePictureUrl,
                              legacyLocalPath: widget.user?.profilePicturePath,
                              initials: widget.initials,
                              radius: 18,
                              equippedBorderId: widget.equippedBorderId,
                              animateBorder: true,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          sidebarFirstName.isNotEmpty
                                              ? sidebarFirstName
                                              : 'User',
                                          style: AppTheme.bodySecondary
                                              .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: context.elixTextPrimary,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (widget.user?.role == 'Admin')
                                        const Text(
                                          '👑',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    widget.user?.role ?? 'Trainee',
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
                            Text(
                              'Lv. $level',
                              style: AppTheme.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _pink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'EXP',
                              style: AppTheme.caption.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: context.elixTextSecondary,
                              ),
                            ),
                            Text(
                              '$expInLevel / ${GamificationRules.xpPerLevel}',
                              style: AppTheme.caption.copyWith(
                                fontSize: 9,
                                color: context.elixTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 4,
                            child: Stack(
                              children: [
                                Container(
                                  color: context.elixBorder.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor:
                                      (expInLevel /
                                              GamificationRules.xpPerLevel)
                                          .clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [_pink, _purple],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
