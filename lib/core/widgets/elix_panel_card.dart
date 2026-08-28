import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

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
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool showAccentBar;

  /// When true, the panel stretches to the parent's width. Set false inside
  /// a [Wrap] so the card can size to its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final surface = context.elixPanelSurface;
    final borderColor = context.elixColors.borderSubtle;
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    return Container(
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: highContrast ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: showAccentBar && accent != null
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: accent),
                    Expanded(child: content),
                  ],
                ),
              )
            : content,
      ),
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : color.withValues(alpha: 0.32),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: highContrast
              ? context.elixTextPrimary
              : Color.lerp(color, context.elixTextPrimary, 0.25),
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
                      ? (highContrast ? 4 : 2)
                      : (highContrast ? 2 : 1),
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
