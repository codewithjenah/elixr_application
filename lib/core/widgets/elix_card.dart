import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// A shared ELIXR content surface.
///
/// Supplying [onTap] makes the card a keyboard-accessible button. Decorative
/// cards intentionally stay out of the focus order.
class ElixCard extends StatefulWidget {
  const ElixCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<ElixCard> createState() => _ElixCardState();
}

class _ElixCardState extends State<ElixCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _interactive => widget.onTap != null;
  bool get _enabled => _interactive && widget.enabled;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final decoration = AppTheme.cardDecoration(context);
    final borderColor = _focused
        ? context.elixColors.focusRing
        : (_hovered && _enabled && !highContrast
              ? context.elixColors.borderStrong
              : context.elixBorder);
    final card = AnimatedContainer(
      duration: ElixMotion.duration(context, ElixMotion.micro),
      curve: ElixMotion.microCurve,
      width: double.infinity,
      padding: widget.padding,
      decoration: decoration.copyWith(
        color: _hovered && _enabled && !highContrast
            ? context.elixColors.interactiveHover
            : decoration.color,
        border: Border.all(
          color: borderColor,
          width: _focused ? (highContrast ? 4 : 2) : (highContrast ? 2 : 1),
        ),
      ),
      child: widget.child,
    );

    if (!_interactive) return card;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: _enabled ? widget.onTap : null,
      child: Focus(
        canRequestFocus: _enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (!_enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? widget.onTap : null,
            child: card,
          ),
        ),
      ),
    );
  }
}
