import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'elix_app_logo.dart';
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
    final highContrast = context.isHighContrast;
    final radius = size * 0.3;
    final stroke = (size * 0.05).clamp(1.4, 2.2);
    final innerSize = size - stroke * 2;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(stroke),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: highContrast
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_pink, AppColors.primarySoft, _purple],
              ),
        border: highContrast
            ? Border.all(color: context.elixBorder, width: stroke)
            : null,
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: _pink.withValues(alpha: 0.42),
                  blurRadius: 16,
                  spreadRadius: 0.4,
                ),
                BoxShadow(
                  color: _purple.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: ElixAppLogo(size: innerSize, borderRadius: innerSize * 0.28),
    );
  }
}

class ElixBrandWordmark extends StatelessWidget {
  const ElixBrandWordmark({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final titleStyle = AppTheme.brandTitle(
      fontSize: 20,
      color: Colors.white,
    ).copyWith(letterSpacing: 2.6, height: 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            if (!highContrast)
              ExcludeSemantics(
                child: Text(
                  AppConstants.appName,
                  style: titleStyle.copyWith(
                    color: _pink.withValues(alpha: 0.5),
                    shadows: [
                      Shadow(
                        color: _pink.withValues(alpha: 0.75),
                        blurRadius: 16,
                      ),
                      Shadow(
                        color: _purple.withValues(alpha: 0.45),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: highContrast
                    ? [context.elixTextPrimary, context.elixTextPrimary]
                    : const [_pink, AppColors.primarySoft, _purple],
              ).createShader(bounds),
              child: Text(
                AppConstants.appName,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          width: 46,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(colors: [_pink, _purple]),
            boxShadow: highContrast
                ? const []
                : [
                    BoxShadow(
                      color: _pink.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: AppTheme.brandFontFamily,
            fontFamilyFallback: AppTheme.brandFontFallbacks,
            color: Color.lerp(context.elixTextSecondary, _pink, 0.22),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.7,
            height: 1.1,
            fontVariations: const [
              FontVariation('wght', 600),
              FontVariation('wdth', 90),
            ],
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
        height: 1.5,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          gradient: LinearGradient(
            colors: [
              _pink.withValues(alpha: 0.72),
              _purple.withValues(alpha: 0.42),
              context.elixBorder.withValues(alpha: 0.12),
            ],
          ),
          boxShadow: context.isHighContrast
              ? const []
              : [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.28),
                    blurRadius: 8,
                  ),
                ],
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
            const Center(child: ElixBrandMark(size: 44)),
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
        AppSpacing.md + 2,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!context.isHighContrast)
            Positioned(
              left: -10,
              top: -14,
              child: IgnorePointer(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _pink.withValues(alpha: 0.18),
                        _pink.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              const ElixBrandMark(size: 40),
              const SizedBox(width: 10),
              Expanded(child: ElixBrandWordmark(subtitle: subtitle)),
              const SizedBox(width: AppSpacing.xs),
              ElixSidebarCollapseButton(
                isCollapsed: isCollapsed,
                onTap: onToggleCollapse,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
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
