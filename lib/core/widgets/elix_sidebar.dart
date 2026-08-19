import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/gamification_rules.dart';
import '../theme/app_theme.dart';
import '../utils/user_name.dart';
import 'profile_avatar.dart';
import '../../features/profile/profile_menu.dart';

// Neon accents matching the dashboard.
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
    label: 'Leaderboard',
    icon: FluentIcons.trophy2_solid,
    route: '/leaderboard',
    group: SidebarGroup.overview,
  ),
  SidebarItem(
    label: 'Training',
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
    label: 'Live Practice',
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
    label: 'Coaching',
    icon: FluentIcons.chat,
    route: '/coaching',
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

const _expandedWidth = 256.0;
const _collapsedWidth = 80.0;

// Shared nav-item geometry so icons, labels, and group headers stay aligned.
const _navOuterPadding = AppSpacing.sm + 4; // 12
const _navInnerPadding = AppSpacing.sm; // 8
const _navIndicatorWidth = 3.0;
const _navIndicatorGap = 5.0;
const _navIconSlot = 28.0;
const _navIconSize = 18.0;
const _navIconLabelGap = 10.0;
// The sidebar is a one-screen navigation surface. Compact rows keep every
// destination and the profile card visible at normal desktop heights.
const _navItemHeight = 36.0;
const _navGroupLabelLeft =
    _navOuterPadding + _navInnerPadding + _navIndicatorWidth + _navIndicatorGap;
// Switch to collapsed chrome before expanded rows need more than ~168px.
const _layoutCollapseThreshold = 168.0;

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
    final initials = (user?.fullName.isNotEmpty == true)
        ? userInitials(user!.fullName)
        : '?';
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final sidebarBase = isDark
        ? const Color(0xFF120D1C)
        : context.elixCardSurface;
    final sidebarDecoration = BoxDecoration(
      color: highContrast ? context.elixBackground : null,
      gradient: highContrast
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  AppColors.primary.withValues(alpha: isDark ? 0.10 : 0.045),
                  sidebarBase,
                ),
                sidebarBase,
                Color.alphaBlend(
                  AppColors.accent.withValues(alpha: isDark ? 0.09 : 0.035),
                  sidebarBase,
                ),
              ],
              stops: const [0, 0.48, 1],
            ),
      border: Border(
        right: BorderSide(
          color: highContrast
              ? context.elixBorder
              : (isDark
                    ? _purple.withValues(alpha: 0.24)
                    : context.elixBorder.withValues(alpha: 0.9)),
        ),
      ),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                blurRadius: 16,
                offset: const Offset(4, 0),
              ),
            ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: widget.isCollapsed ? _collapsedWidth : _expandedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: sidebarDecoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showCollapsedLayout =
              widget.isCollapsed ||
              constraints.maxWidth < _layoutCollapseThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, showCollapsedLayout),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showCollapsedLayout
                      ? AppSpacing.sm
                      : AppSpacing.md,
                ),
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _pink.withValues(alpha: 0.55),
                        _purple.withValues(alpha: 0.35),
                        context.elixBorder.withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                ),
              ),
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
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildProfileSection(
                context,
                user,
                initials,
                showCollapsedLayout,
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
  ) {
    final List<Widget> children = [];

    void addGroup(SidebarGroup group, String title) {
      final items = elixSidebarItems.where((i) => i.group == group).toList();
      if (items.isEmpty) return;

      if (!showCollapsedLayout) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              left: _navGroupLabelLeft,
              right: _navOuterPadding,
              top: AppSpacing.sm,
              bottom: 2,
            ),
            child: Text(
              title.toUpperCase(),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                fontSize: 10,
              ),
            ),
          ),
        );
      } else {
        children.add(const SizedBox(height: AppSpacing.sm));
      }

      for (final item in items) {
        children.add(
          _SidebarTile(
            item: item,
            isActive: isElixSidebarRouteActive(widget.currentRoute, item.route),
            isCollapsed: showCollapsedLayout,
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

  Widget _logoMark(double size) {
    final radius = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: _pink.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_pink, _purple],
          ),
          borderRadius: radius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            'E',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.48,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandWordmark(BuildContext context) {
    final titleStyle = AppTheme.headingMedium.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
      height: 1.1,
      color: Colors.white,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_pink, _purple],
          ).createShader(bounds),
          child: Text(
            AppConstants.appName,
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 28,
          height: 1.5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: const LinearGradient(colors: [_pink, _purple]),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Flair Training',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontSize: 10.5,
            letterSpacing: 0.4,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool showCollapsedLayout) {
    if (showCollapsedLayout) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Center(child: _logoMark(40)),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: _CollapseButton(
                isCollapsed: widget.isCollapsed,
                onTap: widget.onToggleCollapse,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _logoMark(34),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _brandWordmark(context)),
          const SizedBox(width: AppSpacing.xs),
          _CollapseButton(
            isCollapsed: widget.isCollapsed,
            onTap: widget.onToggleCollapse,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
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

class _CollapseButton extends StatefulWidget {
  const _CollapseButton({required this.isCollapsed, required this.onTap});

  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  State<_CollapseButton> createState() => _CollapseButtonState();
}

class _CollapseButtonState extends State<_CollapseButton> {
  bool _hovered = false;

  static const _buttonSize = 40.0;
  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: Tooltip(
        message: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _buttonSize,
              height: _buttonSize,
              decoration: BoxDecoration(
                color: _hovered
                    ? context.elixCardSurface.withValues(alpha: 0.9)
                    : context.elixCardSurface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hovered
                      ? _pink.withValues(alpha: 0.55)
                      : context.elixBorder.withValues(alpha: 0.7),
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    // Action icon: expanded → collapse (arrow left), collapsed → expand.
                    widget.isCollapsed
                        ? FluentIcons.open_pane_mirrored
                        : FluentIcons.close_pane_mirrored,
                    key: ValueKey(widget.isCollapsed),
                    size: _iconSize,
                    color: _hovered ? _pink : context.elixTextPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  final SidebarItem item;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final soon = widget.item.comingSoon;
    final highlight = (widget.isActive || _hovered) && !soon;

    final iconColor = widget.isActive
        ? _pink
        : highlight
        ? context.elixTextPrimary
        : context.elixTextSecondary.withValues(alpha: soon ? 0.5 : 1);

    final tile = Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _navOuterPadding,
          vertical: 1,
        ),
        child: MouseRegion(
          cursor: soon ? SystemMouseCursors.basic : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: _navItemHeight,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCollapsed ? 0 : _navInnerPadding,
              ),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? _pink.withValues(alpha: 0.1)
                    : (_hovered && !soon)
                    ? context.elixBorder.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: widget.isCollapsed
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (widget.isActive)
                          Positioned(
                            left: 0,
                            top: 8,
                            bottom: 8,
                            child: Container(
                              width: _navIndicatorWidth,
                              decoration: BoxDecoration(
                                color: _pink,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        Center(
                          child: Icon(
                            widget.item.icon,
                            size: _navIconSize,
                            color: iconColor,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: _navIndicatorWidth + _navIndicatorGap,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: widget.isActive
                                ? Container(
                                    width: _navIndicatorWidth,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: _pink,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        SizedBox(
                          width: _navIconSlot,
                          height: _navIconSlot,
                          child: Center(
                            child: Icon(
                              widget.item.icon,
                              size: _navIconSize,
                              color: iconColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: _navIconLabelGap),
                        Expanded(
                          child: Text(
                            widget.item.label,
                            style: AppTheme.bodySecondary.copyWith(
                              color: widget.isActive
                                  ? _pink
                                  : highlight
                                  ? context.elixTextPrimary
                                  : context.elixTextSecondary.withValues(
                                      alpha: soon ? 0.5 : 1,
                                    ),
                              fontWeight: widget.isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (soon)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Soon',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: _purple.withValues(alpha: 0.9),
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
        message: soon
            ? '${widget.item.label} (coming soon)'
            : widget.item.label,
        displayHorizontally: true,
        useMousePosition: false,
        style: const TooltipThemeData(preferBelow: false),
        child: tile,
      );
    }
    return tile;
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
