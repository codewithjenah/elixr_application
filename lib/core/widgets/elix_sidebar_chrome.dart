import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'message_unread_badge.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;

/// Shared Trainee/Teacher sidebar geometry. Keep both shells aligned.
abstract final class ElixSidebarMetrics {
  static const expandedWidth = 256.0;
  static const collapsedWidth = 80.0;
  static const navOuterPadding = AppSpacing.sm + 4; // 12
  static const navInnerPadding = AppSpacing.sm; // 8
  static const navIndicatorWidth = 3.0;
  static const navIndicatorGap = 5.0;
  static const navIconSlot = 28.0;
  static const navIconSize = 18.0;
  static const navIconLabelGap = 10.0;
  static const navItemHeight = 36.0;
  static const navGroupLabelLeft =
      navOuterPadding + navInnerPadding + navIndicatorWidth + navIndicatorGap;
  static const layoutCollapseThreshold = 168.0;
}

BoxDecoration elixSidebarSurfaceDecoration(BuildContext context) {
  final isDark = context.isDarkTheme;
  final highContrast = context.isHighContrast;
  final sidebarBase = isDark
      ? const Color(0xFF120D1C)
      : context.elixCardSurface;
  return BoxDecoration(
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
}

class ElixBrandMark extends StatelessWidget {
  const ElixBrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
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
}

class ElixBrandWordmark extends StatelessWidget {
  const ElixBrandWordmark({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
          subtitle,
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
}

class ElixSidebarBrandDivider extends StatelessWidget {
  const ElixSidebarBrandDivider({super.key, required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
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
    );
  }
}

class ElixSidebarCollapseButton extends StatefulWidget {
  const ElixSidebarCollapseButton({
    super.key,
    required this.isCollapsed,
    required this.onTap,
  });

  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  State<ElixSidebarCollapseButton> createState() =>
      _ElixSidebarCollapseButtonState();
}

class _ElixSidebarCollapseButtonState extends State<ElixSidebarCollapseButton> {
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

class ElixSidebarHeader extends StatelessWidget {
  const ElixSidebarHeader({
    super.key,
    required this.showCollapsedLayout,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.subtitle,
  });

  final bool showCollapsedLayout;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    if (showCollapsedLayout) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        child: Column(
          children: [
            const Center(child: ElixBrandMark(size: 40)),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: ElixSidebarCollapseButton(
                isCollapsed: isCollapsed,
                onTap: onToggleCollapse,
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
          const ElixBrandMark(size: 34),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: ElixBrandWordmark(subtitle: subtitle)),
          const SizedBox(width: AppSpacing.xs),
          ElixSidebarCollapseButton(
            isCollapsed: isCollapsed,
            onTap: onToggleCollapse,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

class ElixSidebarGroupLabel extends StatelessWidget {
  const ElixSidebarGroupLabel({
    super.key,
    required this.title,
    required this.isCollapsed,
  });

  final String title;
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    if (isCollapsed) {
      return const SizedBox(height: AppSpacing.sm);
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: ElixSidebarMetrics.navGroupLabelLeft,
        right: ElixSidebarMetrics.navOuterPadding,
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
    );
  }
}

class ElixSidebarNavTile extends StatefulWidget {
  const ElixSidebarNavTile({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
    this.unreadCount = 0,
    this.comingSoon = false,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool isCollapsed;
  final int unreadCount;
  final bool comingSoon;
  final VoidCallback onTap;

  @override
  State<ElixSidebarNavTile> createState() => _ElixSidebarNavTileState();
}

class _ElixSidebarNavTileState extends State<ElixSidebarNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final soon = widget.comingSoon;
    final highlight = (widget.isActive || _hovered) && !soon;

    final iconColor = widget.isActive
        ? _pink
        : highlight
        ? context.elixTextPrimary
        : context.elixTextSecondary.withValues(alpha: soon ? 0.5 : 1);

    final tile = Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ElixSidebarMetrics.navOuterPadding,
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
              height: ElixSidebarMetrics.navItemHeight,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCollapsed
                    ? 0
                    : ElixSidebarMetrics.navInnerPadding,
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
                              width: ElixSidebarMetrics.navIndicatorWidth,
                              decoration: BoxDecoration(
                                color: _pink,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                widget.icon,
                                size: ElixSidebarMetrics.navIconSize,
                                color: iconColor,
                              ),
                              if (widget.unreadCount > 0)
                                Positioned(
                                  top: -8,
                                  right: -12,
                                  child: MessageUnreadBadge(
                                    count: widget.unreadCount,
                                    compact: true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width:
                              ElixSidebarMetrics.navIndicatorWidth +
                              ElixSidebarMetrics.navIndicatorGap,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: widget.isActive
                                ? Container(
                                    width: ElixSidebarMetrics.navIndicatorWidth,
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
                          width: ElixSidebarMetrics.navIconSlot,
                          height: ElixSidebarMetrics.navIconSlot,
                          child: Center(
                            child: Icon(
                              widget.icon,
                              size: ElixSidebarMetrics.navIconSize,
                              color: iconColor,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: ElixSidebarMetrics.navIconLabelGap,
                        ),
                        Expanded(
                          child: Text(
                            widget.label,
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
                        if (!soon && widget.unreadCount > 0)
                          MessageUnreadBadge(count: widget.unreadCount),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    if (widget.isCollapsed) {
      return Tooltip(
        message: soon ? '${widget.label} (coming soon)' : widget.label,
        displayHorizontally: true,
        useMousePosition: false,
        style: const TooltipThemeData(preferBelow: false),
        child: tile,
      );
    }
    return tile;
  }
}
