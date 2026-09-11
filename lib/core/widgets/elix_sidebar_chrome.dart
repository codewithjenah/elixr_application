import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
import 'elix_app_logo.dart';
import 'message_unread_badge.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;

/// Shared Trainee/Teacher sidebar geometry. Keep both shells aligned.
abstract final class ElixSidebarMetrics {
  static const expandedWidth = 272.0;
  static const collapsedWidth = 84.0;

  /// Right-side dock radius. Left corners stay square so the pane reads as
  /// shell chrome rather than a floating card.
  static const paneRadius = 28.0;

  static const paneBorderRadius = BorderRadius.only(
    topRight: Radius.circular(paneRadius),
    bottomRight: Radius.circular(paneRadius),
  );

  /// Docked flush to the window on the left, top, and bottom. Destination
  /// pages keep their own content inset (dashboard uses [AppSpacing.lg]).
  static const paneInset = EdgeInsets.zero;

  static const paneMotion = Duration(milliseconds: 220);
  static const hoverMotion = Duration(milliseconds: 160);

  static const navOuterPadding = AppSpacing.sm + 4; // 12
  static const navInnerPadding = AppSpacing.sm; // 8
  static const navIndicatorWidth = 3.0;
  static const navIndicatorGap = 5.0;
  static const navIndicatorSlot = navIndicatorWidth + navIndicatorGap;
  static const navIconSlot = 32.0;
  static const navIconSize = 18.0;
  static const navIconLabelGap = 10.0;
  static const navItemHeight = 40.0;
  static const navItemRadius = 12.0;
  static const navHoverShift = 2.0;
  static const navHoverIconScale = 1.05;
  static const navPressedScale = 0.985;
  static const navLabelSlide = 0.06;
  static const identityCardRadius = 14.0;
  static const collapseButtonSize = 34.0;

  /// Left edge of destination labels; group titles use the same origin.
  static const navGroupLabelLeft =
      navOuterPadding +
      navInnerPadding +
      navIndicatorSlot +
      navIconSlot +
      navIconLabelGap;

  static Duration paneDuration(BuildContext context) =>
      ElixMotion.duration(context, paneMotion);

  static Duration hoverDuration(BuildContext context) =>
      ElixMotion.duration(context, hoverMotion);

  static bool reducedMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

BoxDecoration elixSidebarSurfaceDecoration(BuildContext context) {
  final isDark = context.isDarkTheme;
  final highContrast = context.isHighContrast;
  final colors = context.elixColors;
  final glowScale = context.elixWorkspaceVisuals.ambientGlowScale;
  final sidebarBase = isDark
      ? const Color(0xFF0E0A16)
      : context.elixCardSurface;

  return BoxDecoration(
    color: highContrast ? context.elixBackground : sidebarBase,
    borderRadius: ElixSidebarMetrics.paneBorderRadius,
    gradient: highContrast
        ? null
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                _pink.withValues(alpha: isDark ? 0.10 : 0.04),
                sidebarBase,
              ),
              Color.alphaBlend(
                _purple.withValues(alpha: isDark ? 0.05 : 0.02),
                sidebarBase,
              ),
              sidebarBase,
              Color.alphaBlend(
                _pink.withValues(alpha: isDark ? 0.03 : 0.015),
                sidebarBase,
              ),
            ],
            stops: const [0, 0.24, 0.68, 1],
          ),
    border: highContrast
        ? Border.all(color: colors.borderStrong, width: 2)
        : null,
    boxShadow: highContrast
        ? const []
        : [
            BoxShadow(
              color: colors.shadow.withValues(alpha: isDark ? 0.20 : 0.07),
              blurRadius: 16,
              offset: const Offset(6, 0),
            ),
            BoxShadow(
              color: _purple.withValues(
                alpha: (isDark ? 0.05 : 0.025) * glowScale,
              ),
              blurRadius: 14,
              offset: const Offset(4, 0),
            ),
          ],
  );
}

/// Docked shell pane used by both Trainee and Teacher sidebars.
class ElixSidebarPane extends StatelessWidget {
  const ElixSidebarPane({
    super.key,
    required this.isCollapsed,
    required this.child,
  });

  final bool isCollapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final contentWidth = isCollapsed
        ? ElixSidebarMetrics.collapsedWidth
        : ElixSidebarMetrics.expandedWidth;

    return AnimatedContainer(
      duration: ElixSidebarMetrics.paneDuration(context),
      curve: ElixMotion.standardCurve,
      width: contentWidth,
      decoration: elixSidebarSurfaceDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ElixSidebarAmbientGlow(),
          // The surface width animates, but target-state content must never
          // receive that intermediate width. In particular, the expanded
          // header, nav labels, badges, and identity card need 272px while
          // the pane is opening; the pane clips their still-hidden portion.
          OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: contentWidth,
            maxWidth: contentWidth,
            child: child,
          ),
          const ElixSidebarFacingHighlight(),
        ],
      ),
    );
  }
}

/// Static atmospheric light. Idle sidebar stays still.
class ElixSidebarAmbientGlow extends StatelessWidget {
  const ElixSidebarAmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast) return const SizedBox.shrink();
    final isDark = context.isDarkTheme;
    final scale = context.elixWorkspaceVisuals.ambientGlowScale;
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              left: -48,
              top: -64,
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _pink.withValues(alpha: (isDark ? 0.08 : 0.04) * scale),
                      _pink.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 196,
              child: Container(
                width: 112,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withValues(
                        alpha: (isDark ? 0.05 : 0.025) * scale,
                      ),
                      _purple.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1px content-facing separator. Flutter cannot mix a right-only border
/// with a rounded [BoxDecoration], so this stays a separate overlay.
class ElixSidebarFacingHighlight extends StatelessWidget {
  const ElixSidebarFacingHighlight({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast) return const SizedBox.shrink();
    final isDark = context.isDarkTheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: ElixSidebarMetrics.paneBorderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _pink.withValues(alpha: isDark ? 0.16 : 0.09),
                Color.lerp(
                  _purple,
                  Colors.white,
                  0.12,
                )!.withValues(alpha: isDark ? 0.18 : 0.10),
                _purple.withValues(alpha: isDark ? 0.08 : 0.05),
              ],
            ),
          ),
          child: const SizedBox(width: 1, height: double.infinity),
        ),
      ),
    );
  }
}

/// Fade plus a short horizontal travel for expanding labels.
///
/// Collapsing removes the child immediately so hidden labels, badges, and
/// their fixed spacing never participate in compact-row layout.
class ElixSidebarReveal extends StatefulWidget {
  const ElixSidebarReveal({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<ElixSidebarReveal> createState() => _ElixSidebarRevealState();
}

class _ElixSidebarRevealState extends State<ElixSidebarReveal> {
  late bool _revealed = widget.visible;

  @override
  void didUpdateWidget(covariant ElixSidebarReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _revealed = false;
      return;
    }
    if (!oldWidget.visible) {
      _revealed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) {
          setState(() => _revealed = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ElixSidebarMetrics.reducedMotion(context);
    if (!widget.visible) {
      // An invisible label must not continue to reserve its fixed gap, badge,
      // or text row during the compact layout.
      return const SizedBox.shrink();
    }
    return AnimatedOpacity(
      opacity: _revealed || reduced ? 1 : 0,
      duration: ElixSidebarMetrics.paneDuration(context),
      curve: ElixMotion.standardCurve,
      child: AnimatedSlide(
        offset: _revealed || reduced
            ? Offset.zero
            : const Offset(-ElixSidebarMetrics.navLabelSlide, 0),
        duration: ElixSidebarMetrics.paneDuration(context),
        curve: ElixMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}

class ElixBrandMark extends StatelessWidget {
  const ElixBrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // The supplied mark already includes its own lighting and transparent
    // silhouette. Keep the sidebar treatment transparent, like the splash,
    // so a surrounding tile does not alter the artwork.
    return SizedBox(
      width: size,
      height: size,
      child: ElixAppLogo(size: size, borderRadius: size * 0.18),
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
      fontSize: 21,
      color: Colors.white,
    ).copyWith(letterSpacing: 3.0, height: 1.0);

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
          width: 48,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(colors: [_pink, _purple]),
            boxShadow: highContrast
                ? const []
                : [
                    BoxShadow(
                      color: _pink.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: AppTheme.eyebrow(
            color: Color.lerp(context.elixTextSecondary, _pink, 0.22),
          ).copyWith(fontSize: 10, letterSpacing: 1.8, height: 1.1),
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
          borderRadius: BorderRadius.circular(1),
          gradient: LinearGradient(
            colors: [
              _pink.withValues(alpha: 0.58),
              _purple.withValues(alpha: 0.32),
              context.elixBorder.withValues(alpha: 0.08),
            ],
          ),
          boxShadow: context.isHighContrast
              ? const []
              : [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.18),
                    blurRadius: 6,
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
  bool _focused = false;

  static const _iconSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Semantics(
      button: true,
      label: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: Tooltip(
        message: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: ElixSidebarMetrics.hoverDuration(context),
                width: ElixSidebarMetrics.collapseButtonSize,
                height: ElixSidebarMetrics.collapseButtonSize,
                decoration: BoxDecoration(
                  color: _hovered
                      ? _pink.withValues(alpha: highContrast ? 0 : 0.12)
                      : context.elixCardSurface.withValues(
                          alpha: highContrast ? 1 : 0.36,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _focused
                        ? context.elixColors.focusRing
                        : _hovered
                        ? _pink.withValues(alpha: 0.46)
                        : context.elixBorder.withValues(alpha: 0.42),
                    width: _focused
                        ? (highContrast
                              ? ElixFocus.ringWidthHighContrast
                              : ElixFocus.ringWidth)
                        : 1,
                  ),
                  boxShadow: _hovered && !highContrast
                      ? [
                          BoxShadow(
                            color: _pink.withValues(alpha: 0.14),
                            blurRadius: 12,
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: ElixSidebarMetrics.hoverDuration(context),
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
    return showCollapsedLayout
        ? Padding(
            key: const ValueKey('sidebar-header-collapsed'),
            padding: const EdgeInsets.only(
              top: AppSpacing.md + 6,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              children: [
                const Center(child: ElixBrandMark(size: 56)),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: ElixSidebarCollapseButton(
                    isCollapsed: isCollapsed,
                    onTap: onToggleCollapse,
                  ),
                ),
              ],
            ),
          )
        : Padding(
            key: const ValueKey('sidebar-header-expanded'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md + 6,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                const ElixBrandMark(size: 56),
                const SizedBox(width: 8),
                Expanded(child: ElixBrandWordmark(subtitle: subtitle)),
                const SizedBox(width: AppSpacing.xs),
                ElixSidebarCollapseButton(
                  isCollapsed: isCollapsed,
                  onTap: onToggleCollapse,
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
    final motion = ElixSidebarMetrics.paneDuration(context);
    return AnimatedSize(
      duration: motion,
      curve: ElixMotion.standardCurve,
      alignment: Alignment.topLeft,
      child: isCollapsed
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(
                left: ElixSidebarMetrics.navGroupLabelLeft,
                right: ElixSidebarMetrics.navOuterPadding,
                top: AppSpacing.sm,
                bottom: 2,
              ),
              child: Text(
                title.toUpperCase(),
                style: AppTheme.eyebrow(
                  color: context.elixTextSecondary.withValues(alpha: 0.64),
                ).copyWith(fontSize: 10, letterSpacing: 1.7),
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
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final soon = widget.comingSoon;
    final highlight = (widget.isActive || _hovered || _focused) && !soon;
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final glowScale = context.elixWorkspaceVisuals.persistentGlowScale;
    final reduced = ElixSidebarMetrics.reducedMotion(context);
    final collapsed = widget.isCollapsed;

    final iconColor = widget.isActive
        ? _pink
        : highlight
        ? context.elixTextPrimary
        : context.elixTextSecondary.withValues(alpha: soon ? 0.5 : 1);

    final hoverShift = !reduced && _hovered && !soon
        ? ElixSidebarMetrics.navHoverShift
        : 0.0;
    final pressScale = !reduced && _pressed && !soon
        ? ElixSidebarMetrics.navPressedScale
        : 1.0;

    final tile = Semantics(
      button: true,
      enabled: !soon,
      selected: widget.isActive,
      label: widget.label,
      onTap: soon ? null : widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ElixSidebarMetrics.navOuterPadding,
          vertical: 1,
        ),
        child: Focus(
          canRequestFocus: !soon,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (_, event) {
            if (soon || event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: soon ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              onTap: soon ? null : widget.onTap,
              onTapDown: soon ? null : (_) => setState(() => _pressed = true),
              onTapUp: soon ? null : (_) => setState(() => _pressed = false),
              onTapCancel: soon ? null : () => setState(() => _pressed = false),
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                duration: ElixSidebarMetrics.hoverDuration(context),
                curve: ElixMotion.microCurve,
                scale: pressScale,
                child: AnimatedContainer(
                  key: ValueKey('elix-sidebar-nav-surface-${widget.label}'),
                  duration: ElixSidebarMetrics.hoverDuration(context),
                  curve: ElixMotion.standardCurve,
                  height: ElixSidebarMetrics.navItemHeight,
                  transform: Matrix4.translationValues(hoverShift, 0, 0),
                  transformAlignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: highContrast
                        ? (widget.isActive
                              ? colors.surfaceSelected
                              : colors.surfaceBase)
                        : (widget.isActive ? null : Colors.transparent),
                    gradient: highContrast
                        ? null
                        : widget.isActive
                        ? LinearGradient(
                            colors: [
                              _pink.withValues(alpha: 0.20),
                              _purple.withValues(alpha: 0.10),
                            ],
                          )
                        : (_hovered && !soon)
                        ? LinearGradient(
                            colors: [
                              colors.surfaceInteractive.withValues(alpha: 0.72),
                              colors.surfaceInteractive.withValues(alpha: 0.28),
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(
                      ElixSidebarMetrics.navItemRadius,
                    ),
                    border: Border.all(
                      color: _focused
                          ? colors.focusRing
                          : widget.isActive
                          ? (highContrast
                                ? context.elixTextPrimary
                                : colors.borderInteractive.withValues(
                                    alpha: 0.72,
                                  ))
                          : (_hovered && !soon && !highContrast)
                          ? _pink.withValues(alpha: 0.18)
                          : Colors.transparent,
                      width: _focused
                          ? (highContrast
                                ? ElixFocus.ringWidthHighContrast
                                : ElixFocus.ringWidth)
                          : 1,
                    ),
                    boxShadow: highContrast
                        ? const []
                        : widget.isActive
                        ? [
                            BoxShadow(
                              color: colors.glowPrimary.withValues(
                                alpha: 0.28 * glowScale,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : (_hovered && !soon)
                        ? [
                            BoxShadow(
                              color: _pink.withValues(alpha: 0.08 * glowScale),
                              blurRadius: 10,
                            ),
                          ]
                        : const [],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final iconCenterPad =
                          ((constraints.maxWidth -
                                      ElixSidebarMetrics.navIconSlot) /
                                  2)
                              .clamp(0.0, 40.0);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              left: collapsed
                                  ? iconCenterPad
                                  : ElixSidebarMetrics.navInnerPadding,
                              right: collapsed
                                  ? 0
                                  : ElixSidebarMetrics.navInnerPadding,
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: ElixSidebarMetrics.paneDuration(
                                    context,
                                  ),
                                  curve: ElixMotion.standardCurve,
                                  width: collapsed
                                      ? 0
                                      : ElixSidebarMetrics.navIndicatorSlot,
                                ),
                                _buildNavIcon(context, iconColor),
                                Expanded(
                                  child: ElixSidebarReveal(
                                    visible: !collapsed,
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          const SizedBox(
                                            width: ElixSidebarMetrics
                                                .navIconLabelGap,
                                          ),
                                          Expanded(
                                            child: Text(
                                              widget.label,
                                              style: AppTheme.bodySecondary
                                                  .copyWith(
                                                    color: widget.isActive
                                                        ? _pink
                                                        : highlight
                                                        ? context
                                                              .elixTextPrimary
                                                        : context
                                                              .elixTextSecondary
                                                              .withValues(
                                                                alpha: soon
                                                                    ? 0.5
                                                                    : 1,
                                                              ),
                                                    fontWeight: widget.isActive
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                  ),
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (soon) const _SoonChip(),
                                          if (!soon && !collapsed)
                                            _UnreadBadgeSlot(
                                              count: widget.unreadCount,
                                              compact: false,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _NavActiveIndicator(
                            visible: widget.isActive && !soon,
                          ),
                          if (collapsed && widget.unreadCount > 0)
                            Positioned(
                              left: iconCenterPad + 22,
                              top: 2,
                              child: _UnreadBadgeSlot(
                                count: widget.unreadCount,
                                compact: true,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
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

  Widget _buildNavIcon(BuildContext context, Color iconColor) {
    final highContrast = context.isHighContrast;
    final reduced = ElixSidebarMetrics.reducedMotion(context);
    final scale = !reduced && _hovered && !widget.comingSoon
        ? ElixSidebarMetrics.navHoverIconScale
        : 1.0;
    return AnimatedScale(
      duration: ElixSidebarMetrics.hoverDuration(context),
      curve: ElixMotion.microCurve,
      scale: scale,
      child: AnimatedContainer(
        duration: ElixSidebarMetrics.hoverDuration(context),
        width: ElixSidebarMetrics.navIconSlot,
        height: ElixSidebarMetrics.navIconSlot,
        decoration: BoxDecoration(
          color: widget.isActive
              ? (highContrast
                    ? Colors.transparent
                    : _pink.withValues(alpha: 0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: widget.isActive && highContrast
              ? Border.all(color: context.elixTextPrimary)
              : null,
        ),
        child: Center(
          child: Icon(
            widget.icon,
            size: ElixSidebarMetrics.navIconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _NavActiveIndicator extends StatelessWidget {
  const _NavActiveIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AnimatedOpacity(
          duration: ElixSidebarMetrics.hoverDuration(context),
          opacity: visible ? 1 : 0,
          child: AnimatedContainer(
            duration: ElixSidebarMetrics.hoverDuration(context),
            curve: ElixMotion.standardCurve,
            width: visible ? ElixSidebarMetrics.navIndicatorWidth : 0,
            height: 22,
            decoration: BoxDecoration(
              gradient: highContrast
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_pink, _purple],
                    ),
              color: highContrast ? context.elixTextPrimary : null,
              borderRadius: BorderRadius.circular(3),
              boxShadow: highContrast || !visible
                  ? const []
                  : [
                      BoxShadow(
                        color: _pink.withValues(alpha: 0.42),
                        blurRadius: 8,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }
}

class _UnreadBadgeSlot extends StatelessWidget {
  const _UnreadBadgeSlot({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: ElixMotion.duration(context, ElixMotion.micro),
      switchInCurve: ElixMotion.microCurve,
      switchOutCurve: ElixMotion.microCurve,
      child: MessageUnreadBadge(
        key: ValueKey('unread-$count-$compact'),
        count: count,
        compact: compact,
      ),
    );
  }
}

class ElixSidebarXpTrack extends StatelessWidget {
  const ElixSidebarXpTrack({
    super.key,
    required this.progress,
    required this.caption,
    required this.valueLabel,
  });

  final double progress;
  final String caption;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              caption,
              style: AppTheme.caption.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: context.elixTextSecondary,
              ),
            ),
            Text(
              valueLabel,
              style: AppTheme.caption.copyWith(
                fontSize: 9,
                color: context.elixTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 5,
            child: Stack(
              children: [
                ColoredBox(
                  color: highContrast
                      ? context.elixBorder
                      : context.elixBorder.withValues(alpha: 0.55),
                  child: const SizedBox.expand(),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: highContrast
                          ? null
                          : const LinearGradient(colors: [_pink, _purple]),
                      color: highContrast ? context.elixTextPrimary : null,
                      boxShadow: highContrast
                          ? const []
                          : [
                              BoxShadow(
                                color: _pink.withValues(alpha: 0.35),
                                blurRadius: 6,
                              ),
                            ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared identity footer for Trainee and Teacher sidebars.
class ElixSidebarIdentityCard extends StatefulWidget {
  const ElixSidebarIdentityCard({
    super.key,
    required this.isCollapsed,
    required this.onOpen,
    required this.avatar,
    required this.name,
    required this.roleLabel,
    this.tooltip,
    this.nameSuffix,
    this.trailing,
    this.footer,
  });

  final bool isCollapsed;
  final ValueChanged<BuildContext> onOpen;
  final Widget avatar;
  final String name;
  final String roleLabel;
  final String? tooltip;
  final Widget? nameSuffix;
  final Widget? trailing;
  final Widget? footer;

  @override
  State<ElixSidebarIdentityCard> createState() =>
      _ElixSidebarIdentityCardState();
}

class _ElixSidebarIdentityCardState extends State<ElixSidebarIdentityCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.isCollapsed;
    final reduced = ElixSidebarMetrics.reducedMotion(context);
    final highContrast = context.isHighContrast;
    final hoverShift = !reduced && _hovered ? 1.0 : 0.0;

    final card = Semantics(
      button: true,
      label: 'Profile menu',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Builder(
          builder: (profileContext) => GestureDetector(
            onTap: () => widget.onOpen(profileContext),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: ElixSidebarMetrics.hoverDuration(context),
              curve: ElixMotion.standardCurve,
              transform: Matrix4.translationValues(hoverShift, 0, 0),
              transformAlignment: Alignment.center,
              margin: EdgeInsets.symmetric(
                horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: _hovered
                    ? (highContrast
                          ? context.elixCardSurface
                          : context.elixColors.surfaceInteractive.withValues(
                              alpha: 0.42,
                            ))
                    : (highContrast
                          ? Colors.transparent
                          : context.elixCardSurface.withValues(alpha: 0.14)),
                borderRadius: BorderRadius.circular(
                  ElixSidebarMetrics.identityCardRadius,
                ),
                border: Border.all(
                  color: _hovered
                      ? (highContrast
                            ? context.elixTextPrimary
                            : _pink.withValues(alpha: 0.22))
                      : context.elixBorder.withValues(
                          alpha: highContrast ? 1 : 0.16,
                        ),
                ),
                boxShadow: _hovered && !highContrast
                    ? [
                        BoxShadow(
                          color: _pink.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: collapsed
                  ? Center(child: widget.avatar)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            widget.avatar,
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
                                          widget.name,
                                          style: AppTheme.bodySecondary
                                              .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: context.elixTextPrimary,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (widget.nameSuffix != null) ...[
                                        const SizedBox(width: 4),
                                        widget.nameSuffix!,
                                      ],
                                    ],
                                  ),
                                  Text(
                                    widget.roleLabel,
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
                            if (widget.trailing != null) widget.trailing!,
                          ],
                        ),
                        if (widget.footer != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          widget.footer!,
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    if (collapsed) {
      return Tooltip(
        message: widget.tooltip ?? 'Profile',
        displayHorizontally: true,
        useMousePosition: false,
        style: const TooltipThemeData(preferBelow: false),
        child: card,
      );
    }
    return card;
  }
}
