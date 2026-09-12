import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

enum ElixPanelVariant { normal, elevated, hero }

/// Neutral panel surface used by Trainee dashboard and Teacher destinations.
///
/// Accent is optional and should be used for icons, hover, or a thin accent
/// bar — not for a persistent glowing border on every panel.
class ElixPanelCard extends StatelessWidget {
  const ElixPanelCard({
    super.key,
    required this.child,
    this.accent,
    this.padding,
    this.showAccentBar = false,
    this.expand = true,
    this.variant = ElixPanelVariant.normal,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool showAccentBar;
  final ElixPanelVariant variant;

  /// When true, the panel stretches to the parent's width. Set false inside
  /// a [Wrap] so the card can size to its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final surface = variant == ElixPanelVariant.normal
        ? colors.surfaceRaised
        : colors.surfaceTinted;
    final borderColor = highContrast
        ? colors.borderStrong
        : showAccentBar && accent != null
        ? accent!.withValues(alpha: 0.46)
        : colors.borderSubtle;
    final accentColor = accent;
    final highlighted = variant == ElixPanelVariant.hero;
    final workspaceVisuals = context.elixWorkspaceVisuals;
    final flattenSurface =
        workspaceVisuals.flattenDenseSurfaces &&
        variant == ElixPanelVariant.normal;
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    final panel = Container(
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: highContrast ? surface : null,
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: variant == ElixPanelVariant.normal
                    ? [surface, surface]
                    : [
                        colors.surfaceTinted,
                        Color.alphaBlend(
                          colors.brandSecondary.withValues(
                            alpha: highlighted ? 0.11 : 0.035,
                          ),
                          colors.surfaceRaised,
                        ),
                        colors.surfaceRaised,
                      ],
              ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: highContrast ? 2 : 1),
        boxShadow: highContrast || flattenSurface
            ? const []
            : [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.38),
                  blurRadius: variant == ElixPanelVariant.normal ? 12 : 22,
                  offset: Offset(
                    0,
                    variant == ElixPanelVariant.normal ? 4 : 10,
                  ),
                ),
                if (highlighted)
                  BoxShadow(
                    color: colors.glowPrimary.withValues(
                      alpha: 0.22 * workspaceVisuals.persistentGlowScale,
                    ),
                    blurRadius: 30,
                    spreadRadius: -9,
                  ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: showAccentBar && accentColor != null
            ? Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: content,
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(
                      color: highContrast ? colors.borderStrong : accentColor,
                    ),
                  ),
                ],
              )
            : content,
      ),
    );
    // Shad owns the normal panel surface; the legacy container remains only
    // for the explicit high-contrast treatment and the optional accent rail.
    if (highContrast) return panel;
    return shad.ShadCard(
      key: const ValueKey('elix-panel-shad-card'),
      width: expand ? double.infinity : null,
      padding: EdgeInsets.zero,
      shadows: const [],
      backgroundColor: colors.surfaceRaised,
      child: panel,
    );
  }
}

/// Small rounded accent pill (streak badges, status chips, etc.).
class ElixPill extends StatelessWidget {
  const ElixPill({
    super.key,
    required this.text,
    required this.color,
    this.compact = false,
  });

  final String text;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    if (!highContrast) {
      return shad.ShadBadge.outline(
        key: const ValueKey('elix-shad-badge'),
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: Color.lerp(color, context.elixTextPrimary, 0.25),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 5,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.elixBorder, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: context.elixTextPrimary,
        ),
      ),
    );
  }
}

/// Restrained desktop hover wrapper for clickable panel surfaces.
class ElixHoverSurface extends StatefulWidget {
  const ElixHoverSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 12,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<ElixHoverSurface> createState() => _ElixHoverSurfaceState();
}

class _ElixHoverSurfaceState extends State<ElixHoverSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? widget.onTap : null,
      child: Focus(
        canRequestFocus: enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
          onExit: (_) => setState(() => _hovered = false),
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: GestureDetector(
            onTap: enabled ? widget.onTap : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: ElixMotion.duration(context, ElixMotion.standard),
              curve: ElixMotion.standardCurve,
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixColors.surfaceBase
                    : (_hovered && enabled
                          ? context.elixColors.interactiveHover
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: _focused
                      ? context.elixColors.focusRing
                      : (_hovered && enabled
                            ? (highContrast
                                  ? context.elixBorder
                                  : context.elixColors.borderStrong)
                            : (highContrast
                                  ? context.elixBorder
                                  : Colors.transparent)),
                  width: _focused
                      ? (highContrast
                            ? ElixFocus.ringWidthHighContrast
                            : ElixFocus.ringWidth)
                      : (highContrast ? ElixFocus.ringWidth : 1),
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
