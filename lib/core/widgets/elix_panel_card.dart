import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

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
    final isDark = context.isDarkTheme;
    final surface = isDark ? AppColors.panelSurface : context.elixCardSurface;
    final borderColor = context.elixBorder.withValues(alpha: isDark ? 0.55 : 1);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    return Container(
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: Color.lerp(color, context.elixTextPrimary, 0.25),
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
  });

  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final bool enabled;

  @override
  State<ElixHoverSurface> createState() => _ElixHoverSurfaceState();
}

class _ElixHoverSurfaceState extends State<ElixHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final isDark = context.isDarkTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _hovered
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _hovered
                  ? context.elixBorder.withValues(alpha: isDark ? 0.75 : 1)
                  : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
