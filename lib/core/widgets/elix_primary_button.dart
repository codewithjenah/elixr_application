import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

class ElixPrimaryButton extends StatefulWidget {
  const ElixPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.dense = false,
    this.padding,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final bool dense;
  final EdgeInsetsGeometry? padding;
  @override
  State<ElixPrimaryButton> createState() => _ElixPrimaryButtonState();
}

class _ElixPrimaryButtonState extends State<ElixPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading || widget.onPressed == null;
    final highContrast = context.isHighContrast;
    final reducedMotion =
        MediaQuery.disableAnimationsOf(context) || highContrast;
    final colors = context.elixColors;
    Widget button = Listener(
      onPointerDown: disabled ? null : (_) => setState(() => _pressed = true),
      onPointerUp: disabled ? null : (_) => setState(() => _pressed = false),
      onPointerCancel: disabled
          ? null
          : (_) => setState(() => _pressed = false),
      child: MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        onEnter: disabled ? null : (_) => setState(() => _hovered = true),
        onExit: disabled
            ? null
            : (_) => setState(() {
                _hovered = false;
                _pressed = false;
              }),
        child: AnimatedContainer(
          key: const ValueKey('elix-primary-button-surface'),
          duration: reducedMotion ? Duration.zero : ElixMotion.standard,
          curve: ElixMotion.standardCurve,
          decoration: BoxDecoration(
            color: disabled
                ? colors.disabledSurface
                : (highContrast ? colors.brandPrimary : null),
            gradient: disabled || highContrast
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _pressed
                        ? [colors.brandPressed, colors.brandSecondary]
                        : _hovered
                        ? [colors.brandHover, colors.brandSecondary]
                        : [colors.brandPrimary, colors.brandSecondary],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled
                  ? colors.disabledBorder
                  : (highContrast
                        ? colors.borderStrong
                        : colors.borderInteractive),
              width: highContrast ? 2 : 1,
            ),
            boxShadow: disabled || highContrast
                ? const []
                : [
                    BoxShadow(
                      color: colors.glowPrimary.withValues(
                        alpha: _hovered ? .32 : .2,
                      ),
                      blurRadius: _hovered ? 16 : 11,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              final activation =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space;
              if (!activation || disabled) return KeyEventResult.ignored;
              if (event is KeyDownEvent) {
                setState(() => _pressed = true);
              } else if (event is KeyUpEvent) {
                setState(() => _pressed = false);
              }
              return KeyEventResult.ignored;
            },
            child: FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(
                  disabled ? colors.disabledText : colors.onBrand,
                ),
                padding: WidgetStateProperty.all(
                  widget.padding ??
                      EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: widget.dense ? AppSpacing.sm : AppSpacing.md,
                      ),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              onPressed: disabled ? null : widget.onPressed,
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 16),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontFamily: ElixTypography.fontFamily,
                            fontFamilyFallback: ElixTypography.fontFallbacks,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    if (reducedMotion) {
      final theme = FluentTheme.of(context);
      button = FluentTheme(
        data: theme.copyWith(
          fasterAnimationDuration: Duration.zero,
          fastAnimationDuration: Duration.zero,
        ),
        child: button,
      );
    }
    if (widget.expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return Semantics(
      button: true,
      enabled: !disabled,
      liveRegion: widget.isLoading,
      label: widget.label,
      value: widget.isLoading ? 'Loading' : null,
      child: button,
    );
  }
}
