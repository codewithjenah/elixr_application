import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// Midnight Pour card treatments. Interaction is independent: supplying
/// [ElixCard.onTap] makes any variant keyboard-accessible.
enum ElixCardVariant { neutral, interactive, highlighted, metric }

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
    this.selected = false,
    this.variant,
    this.semanticLabel,
  });

  static const selectedMarkKey = ValueKey<String>('elix-card-selected-mark');

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final ElixCardVariant? variant;
  final String? semanticLabel;

  ElixCardVariant get resolvedVariant {
    if (variant != null) return variant!;
    return onTap != null
        ? ElixCardVariant.interactive
        : ElixCardVariant.neutral;
  }

  @override
  State<ElixCard> createState() => _ElixCardState();
}

class _ElixCardState extends State<ElixCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;
  bool get _enabled => _interactive && widget.enabled;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final variant = widget.resolvedVariant;
    final highlighted = variant == ElixCardVariant.highlighted;
    final decoration = AppTheme.cardDecoration(context);

    final Color fill;
    if (!_enabled && _interactive) {
      fill = colors.disabledSurface;
    } else if (_pressed && _enabled && !highContrast) {
      fill = colors.interactivePressed;
    } else if (_hovered && _enabled && !highContrast) {
      fill = colors.interactiveHover;
    } else if (widget.selected && !highContrast) {
      fill = colors.interactiveSelected;
    } else {
      fill = decoration.color ?? colors.surfaceRaised;
    }

    final borderColor = !_enabled && _interactive
        ? colors.disabledBorder
        : (_focused
              ? colors.focusRing
              : (_hovered && _enabled && !highContrast
                    ? colors.borderStrong
                    : (widget.selected || highlighted
                          ? colors.borderStrong
                          : context.elixBorder)));

    final focusedWidth = highContrast
        ? ElixFocus.ringWidthHighContrast
        : ElixFocus.ringWidth;
    final restingWidth = highContrast
        ? ElixFocus.ringWidth
        : (widget.selected || highlighted ? ElixFocus.ringWidth : 1.0);

    var shadows = decoration.boxShadow ?? const <BoxShadow>[];
    if (highlighted && !highContrast) {
      shadows = [
        ...shadows,
        BoxShadow(
          color: colors.brandPrimary.withValues(alpha: 0.22),
          blurRadius: 24,
          spreadRadius: -4,
        ),
      ];
    }

    final padded = Padding(padding: widget.padding, child: widget.child);
    final body = widget.selected
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: ElixCard.selectedMarkKey,
                  width: 3,
                  color: highContrast
                      ? colors.borderStrong
                      : colors.brandPrimary,
                ),
                Expanded(child: padded),
              ],
            ),
          )
        : padded;

    final card = AnimatedContainer(
      duration: ElixMotion.duration(context, ElixMotion.micro),
      curve: ElixMotion.microCurve,
      width: double.infinity,
      decoration: decoration.copyWith(
        color: fill,
        gradient: null,
        boxShadow: highContrast ? const <BoxShadow>[] : shadows,
        border: Border.all(
          color: borderColor,
          width: _focused ? focusedWidth : restingWidth,
        ),
      ),
      child: body,
    );

    if (!_interactive) return card;

    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
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
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? widget.onTap : null,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: card,
          ),
        ),
      ),
    );
  }
}
