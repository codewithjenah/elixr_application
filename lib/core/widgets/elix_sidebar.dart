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
    label: 'Notifications',
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

    return ElixSidebarPane(
      isCollapsed: widget.isCollapsed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElixSidebarHeader(
            showCollapsedLayout: widget.isCollapsed,
            isCollapsed: widget.isCollapsed,
            onToggleCollapse: widget.onToggleCollapse,
            subtitle: 'Trainee Workspace',
          ),
          const SizedBox(height: AppSpacing.sm),
          ElixSidebarBrandDivider(collapsed: widget.isCollapsed),
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
                      widget.isCollapsed,
                      unreadCount,
                      activityUnreadCount,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildProfileSection(user, initials, widget.isCollapsed),
          const SizedBox(height: AppSpacing.md),
        ],
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
              'Notifications' => activityUnreadCount,
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

class _ProfileSectionWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sidebarFirstName = normalizeNamePart(user?.firstName ?? '');
    final level = GamificationRules.levelForXp(totalXp);
    final expInLevel = GamificationRules.xpIntoLevel(totalXp);

    return ElixSidebarIdentityCard(
      isCollapsed: isCollapsed,
      onOpen: (profileContext) =>
          ProfileMenu.show(profileContext, onLogout: onLogout),
      avatar: ProfileAvatarWidget(
        networkImageUrl: user?.profilePictureUrl,
        legacyLocalPath: user?.profilePicturePath,
        initials: initials,
        radius: 18,
        equippedBorderId: equippedBorderId,
        animateBorder: true,
      ),
      name: sidebarFirstName.isNotEmpty ? sidebarFirstName : 'User',
      roleLabel: user?.role ?? 'Trainee',
      tooltip: user?.fullName ?? 'Profile',
      nameSuffix: user?.role == 'Admin'
          ? const Text('👑', style: TextStyle(fontSize: 10))
          : null,
      trailing: Text(
        'Lv. $level',
        style: AppTheme.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _pink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      footer: ElixSidebarXpTrack(
        progress: expInLevel / GamificationRules.xpPerLevel,
        caption: 'EXP',
        valueLabel: '$expInLevel / ${GamificationRules.xpPerLevel}',
      ),
    );
  }
}
