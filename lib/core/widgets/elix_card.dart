import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

enum ElixCardVariant { neutral, interactive, highlighted, metric }

/// Shared ELIXR surface backed by [shad.ShadCard] outside high contrast.
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
  ElixCardVariant get resolvedVariant =>
      variant ??
      (onTap == null ? ElixCardVariant.neutral : ElixCardVariant.interactive);
  @override
  State<ElixCard> createState() => _ElixCardState();
}

class _ElixCardState extends State<ElixCard> {
  bool _focused = false;
  bool get _interactive => widget.onTap != null;
  bool get _enabled => _interactive && widget.enabled;
  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final body = widget.selected
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: ElixCard.selectedMarkKey,
                width: 3,
                color: colors.brandPrimary,
              ),
              Expanded(child: widget.child),
            ],
          )
        : widget.child;
    final card = context.isHighContrast
        ? Container(
            width: double.infinity,
            padding: widget.padding,
            decoration: AppTheme.cardDecoration(context).copyWith(
              color: _interactive && !_enabled
                  ? colors.disabledSurface
                  : context.elixCardSurface,
              border: Border.all(
                color: _focused ? colors.focusRing : context.elixBorder,
                width: _focused ? ElixFocus.ringWidthHighContrast : 2,
              ),
            ),
            child: body,
          )
        : shad.ShadCard(
            key: const ValueKey('elix-shad-card'),
            width: double.infinity,
            padding: widget.padding,
            backgroundColor: widget.selected
                ? colors.interactiveSelected
                : null,
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
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (_, event) {
          if (_enabled &&
              event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? widget.onTap : null,
          child: card,
        ),
      ),
    );
  }
}
