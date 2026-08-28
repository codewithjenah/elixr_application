import 'package:fluent_ui/fluent_ui.dart';

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
    final isDisabled = widget.isLoading || widget.onPressed == null;
    final highContrast = context.isHighContrast;
    final decorativeMotionEnabled =
        !MediaQuery.disableAnimationsOf(context) && !highContrast;
    final colors = context.elixColors;

    Widget button = Listener(
      onPointerDown: (_) {
        if (!isDisabled) setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: MouseRegion(
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        onEnter: (_) {
          if (!isDisabled) setState(() => _hovered = true);
        },
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _pressed && !isDisabled && decorativeMotionEnabled
              ? 0.977
              : 1.0,
          duration: ElixMotion.duration(context, ElixMotion.micro),
          curve: ElixMotion.microCurve,
          child: AnimatedContainer(
            key: const ValueKey('elix-primary-button-surface'),
            duration: ElixMotion.duration(context, ElixMotion.standard),
            curve: ElixMotion.standardCurve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: _hovered && !isDisabled && decorativeMotionEnabled
                  ? [
                      BoxShadow(
                        color: colors.brandPrimary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Builder(
              builder: (context) {
                Widget innerButton = FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return colors.disabledSurface;
                      }
                      if (states.contains(WidgetState.pressed) ||
                          (_pressed && !isDisabled)) {
                        return highContrast
                            ? colors.brandPrimary
                            : colors.brandPressed;
                      }
                      if (states.contains(WidgetState.hovered) ||
                          (_hovered && !isDisabled)) {
                        return highContrast
                            ? colors.brandPrimary
                            : colors.brandHover;
                      }
                      return colors.brandPrimary;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return colors.disabledText;
                      }
                      return colors.onBrand;
                    }),
                    shape: WidgetStateProperty.resolveWith((states) {
                      final BorderSide side;
                      if (states.contains(WidgetState.focused)) {
                        side = BorderSide(
                          color: highContrast
                              ? colors.onBrand
                              : colors.focusRing,
                          width: 2,
                        );
                      } else if (states.contains(WidgetState.disabled)) {
                        side = BorderSide(
                          color: colors.disabledBorder,
                          width: highContrast ? 2 : 1,
                        );
                      } else {
                        side = BorderSide(
                          color: highContrast
                              ? colors.borderStrong
                              : colors.brandPrimary,
                          width: highContrast ? 2 : 1,
                        );
                      }
                      return RoundedRectangleBorder(
                        side: side,
                        borderRadius: BorderRadius.circular(4),
                      );
                    }),
                    padding: WidgetStateProperty.all(
                      widget.padding ??
                          EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: widget.dense
                                ? AppSpacing.sm
                                : AppSpacing.md,
                          ),
                    ),
                  ),
                  onPressed: widget.isLoading ? null : widget.onPressed,
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  size: 16,
                                  color: isDisabled
                                      ? colors.disabledText
                                      : colors.onBrand,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                              ],
                              Text(
                                widget.label,
                                style: TextStyle(
                                  color: isDisabled
                                      ? colors.disabledText
                                      : colors.onBrand,
                                  fontFamily: ElixTypography.fontFamily,
                                  fontFamilyFallback:
                                      ElixTypography.fontFallbacks,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                );
                if (!decorativeMotionEnabled) {
                  final theme = FluentTheme.of(context);
                  innerButton = FluentTheme(
                    data: theme.copyWith(
                      fasterAnimationDuration: Duration.zero,
                      fastAnimationDuration: Duration.zero,
                    ),
                    child: innerButton,
                  );
                }
                if (widget.isLoading) {
                  innerButton = Semantics(
                    container: true,
                    button: true,
                    enabled: false,
                    liveRegion: true,
                    label: widget.label,
                    value: 'Loading',
                    child: ExcludeSemantics(child: innerButton),
                  );
                }
                return innerButton;
              },
            ),
          ),
        ),
      ),
    );

    if (!widget.expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
