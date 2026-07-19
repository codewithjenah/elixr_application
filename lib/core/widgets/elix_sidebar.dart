import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../data/models/user.dart';
import '../../data/repositories/progress_repository.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../../features/profile/profile_menu.dart';
import '../../features/profile/profile_settings_screen.dart';

// Neon accents matching the dashboard.
const _pink = AppColors.primary;
const _purple = AppColors.accent;

class SidebarItem {
  const SidebarItem({
    required this.label,
    required this.icon,
    this.route,
    this.comingSoon = false,
  });

  final String label;
  final IconData icon;
  final String? route;
  final bool comingSoon;
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
    label: 'Live Practice',
    icon: FluentIcons.video,
    route: '/live-practice',
  ),
  SidebarItem(label: 'History', icon: FluentIcons.clock, route: '/history'),
  SidebarItem(
    label: 'Progress',
    icon: FluentIcons.bar_chart_vertical_fill,
    route: '/progress',
  ),
];

const _expandedWidth = 240.0;
const _collapsedWidth = 72.0;

// XP is derived from practice volume; purely cosmetic gamification.
const _xpPerSession = 25;
const _xpPerLevel = 250;

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
  final _progressRepo = ProgressRepository();
  bool _sidebarHovered = false;
  int _totalSessions = 0;
  String? _statsUserId;
  SessionService? _sessionService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SessionService>();
    if (service != _sessionService) {
      _sessionService?.removeListener(_loadStats);
      _sessionService = service..addListener(_loadStats);
    }
    final userId = context.watch<AuthService>().currentUser?.id;
    if (userId != _statsUserId) {
      _statsUserId = userId;
      _loadStats();
    }
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final userId = _statsUserId;
    if (userId == null) return;
    final stats = await _progressRepo.getStatsForUser(userId);
    if (mounted) setState(() => _totalSessions = stats.totalSessions);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  void _onItemTap(SidebarItem item) {
    if (item.comingSoon) return;
    if (item.route != null) context.go(item.route!);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final initials = (user?.fullName.isNotEmpty == true)
        ? _initials(user!.fullName)
        : '?';
    final isDark = context.isDarkTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _sidebarHovered = true),
      onExit: (_) => setState(() => _sidebarHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: widget.isCollapsed ? _collapsedWidth : _expandedWidth,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF120D1C) : context.elixCardSurface,
          border: Border(
            right: BorderSide(
              color: isDark
                  ? _purple.withValues(alpha: 0.18)
                  : context.elixBorder,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(4, 0),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isCollapsed
                        ? AppSpacing.sm
                        : AppSpacing.md,
                  ),
                  child: Container(
                    height: 1,
                    color: context.elixBorder.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final item in _sidebarItems)
                          _SidebarTile(
                            item: item,
                            isActive:
                                item.route != null &&
                                widget.currentRoute.startsWith(item.route!),
                            isCollapsed: widget.isCollapsed,
                            onTap: () => _onItemTap(item),
                          ),
                      ],
                    ),
                  ),
                ),
                _buildProfileSection(context, user, initials),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 8,
              child: Center(
                child: IgnorePointer(
                  ignoring: !_sidebarHovered,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _sidebarHovered ? 1 : 0,
                    child: _CollapseButton(
                      isCollapsed: widget.isCollapsed,
                      onTap: widget.onToggleCollapse,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoMark(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_pink, _purple],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(color: _pink.withValues(alpha: 0.45), blurRadius: 14),
        ],
      ),
      child: Center(
        child: Text(
          'E',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isCollapsed ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        widget.isCollapsed ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: widget.isCollapsed
          ? Center(child: _logoMark(40))
          : Row(
              children: [
                _logoMark(36),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: AppTheme.headingMedium.copyWith(
                          color: _pink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                      Text(
                        'Flair Training',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
    User? user,
    String initials,
  ) {
    final totalXp = _totalSessions * _xpPerSession;
    final level = totalXp ~/ _xpPerLevel + 1;
    final expInLevel = totalXp % _xpPerLevel;

    final profileTile = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Builder(
        builder: (profileContext) => GestureDetector(
          onTap: () =>
              ProfileMenu.show(profileContext, onLogout: widget.onLogout),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(
              horizontal: widget.isCollapsed ? AppSpacing.sm : AppSpacing.md,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isCollapsed ? AppSpacing.sm : AppSpacing.md,
              vertical: AppSpacing.sm + 4,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _pink.withValues(alpha: 0.10),
                  _purple.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _pink.withValues(alpha: 0.22)),
            ),
            child: widget.isCollapsed
                ? Center(
                    child: ProfileAvatarWidget(
                      imagePath: user?.profilePicturePath,
                      initials: initials,
                      radius: 18,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [_pink, _purple],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _pink.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: ProfileAvatarWidget(
                              imagePath: user?.profilePicturePath,
                              initials: initials,
                              radius: 17,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        user?.fullName.split(' ').first ??
                                            'User',
                                        style: AppTheme.body.copyWith(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: context.elixTextPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '👑',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                                Text(
                                  user?.role ?? 'Trainee',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 11,
                                    color: context.elixTextSecondary,
                                  ),
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
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Text(
                        'EXP $expInLevel / $_xpPerLevel',
                        style: AppTheme.caption.copyWith(
                          fontSize: 10,
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 5,
                          child: Stack(
                            children: [
                              Container(
                                color: context.elixBorder.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: (expInLevel / _xpPerLevel).clamp(
                                  0.0,
                                  1.0,
                                ),
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
    );

    if (widget.isCollapsed) {
      return Tooltip(message: user?.fullName ?? 'Profile', child: profileTile);
    }
    return profileTile;
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

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.elixCardSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hovered
                    ? context.elixBorder.withValues(alpha: 0.8)
                    : context.elixBorder.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: AnimatedRotation(
                turns: widget.isCollapsed ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  FluentIcons.chevron_left,
                  size: 14,
                  color: context.elixTextSecondary,
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
        ? Colors.white
        : highlight
        ? _pink
        : context.elixTextSecondary.withValues(alpha: soon ? 0.5 : 1);

    final tile = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isCollapsed ? AppSpacing.sm : AppSpacing.sm + 2,
        vertical: 3,
      ),
      child: MouseRegion(
        cursor: soon ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isCollapsed
                  ? AppSpacing.sm + 2
                  : AppSpacing.sm + 4,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              gradient: widget.isActive
                  ? LinearGradient(
                      colors: [
                        _pink.withValues(alpha: 0.22),
                        _purple.withValues(alpha: 0.10),
                      ],
                    )
                  : null,
              color: widget.isActive
                  ? null
                  : (_hovered && !soon)
                  ? context.elixBorder.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isActive
                    ? _pink.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: _pink.withValues(alpha: 0.18),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: widget.isCollapsed
                ? Center(
                    child: Icon(widget.item.icon, size: 20, color: iconColor),
                  )
                : Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: widget.isActive
                              ? const LinearGradient(colors: [_pink, _purple])
                              : null,
                          color: widget.isActive
                              ? null
                              : context.elixBorder.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: widget.isActive
                              ? [
                                  BoxShadow(
                                    color: _pink.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          widget.item.icon,
                          size: 16,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          widget.item.label,
                          style: AppTheme.body.copyWith(
                            color: widget.isActive
                                ? context.elixTextPrimary
                                : highlight
                                ? context.elixTextPrimary
                                : context.elixTextSecondary.withValues(
                                    alpha: soon ? 0.5 : 1,
                                  ),
                            fontWeight: widget.isActive
                                ? FontWeight.w700
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Soon',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _purple.withValues(alpha: 0.9),
                            ),
                          ),
                        )
                      else if (widget.isActive)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _pink,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _pink.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (widget.isCollapsed) {
      return Tooltip(
        message: soon ? '${widget.item.label} (coming soon)' : widget.item.label,
        child: tile,
      );
    }
    return tile;
  }
}
