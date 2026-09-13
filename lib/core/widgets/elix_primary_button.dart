import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

/// Standard action treatments. Use a semantic treatment instead of supplying
/// ad-hoc button colours from a feature screen.
enum ElixButtonVariant { primary, secondary, outline, ghost, destructive }

/// The shared ELIXR action control. Normal themes render a Shadcn primitive;
/// high contrast retains Fluent's system-native focus and contrast behavior.
class ElixPrimaryButton extends StatelessWidget {
  const ElixPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.dense = false,
    this.autofocus = false,
    this.padding,
    this.variant = ElixButtonVariant.primary,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final bool dense;
  final bool autofocus;
  final EdgeInsetsGeometry? padding;
  final ElixButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    final labelChild = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.action(),
    );
    const loadingIndicator = SizedBox(
      width: 18,
      height: 18,
      child: ProgressRing(strokeWidth: 2),
    );
    final effectivePadding =
        padding ??
        EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          // ShadButton's regular height is 40px. The Geist action line box is
          // 20px, so the default Shad vertical inset must leave room for it.
          // The previous non-dense 16px inset produced a 52px child inside
          // that 40px constraint and clipped the label.
          vertical: AppSpacing.sm,
        );
    final fluentChild = isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loadingIndicator,
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: labelChild),
            ],
          )
        : icon == null
        ? labelChild
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: labelChild),
            ],
          );
    Widget button;
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      final style = switch (variant) {
        ElixButtonVariant.primary => ButtonStyle(
          padding: WidgetStatePropertyAll(effectivePadding),
        ),
        ElixButtonVariant.destructive => ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return context.elixColors.disabledSurface;
            }
            return context.elixColors.error;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return context.elixTextSecondary;
            }
            return context.elixColors.onBrand;
          }),
          padding: WidgetStatePropertyAll(effectivePadding),
        ),
        _ => ButtonStyle(padding: WidgetStatePropertyAll(effectivePadding)),
      };
      button = variant == ElixButtonVariant.outline
          ? Button(
              autofocus: autofocus,
              onPressed: disabled ? null : onPressed,
              style: style,
              child: isLoading ? loadingIndicator : fluentChild,
            )
          : FilledButton(
              autofocus: autofocus,
              onPressed: disabled ? null : onPressed,
              style: style,
              child: fluentChild,
            );
    } else {
      final resolvedPadding = effectivePadding.resolve(
        Directionality.of(context),
      );
      final scaledLineHeight = MediaQuery.textScalerOf(context).scale(20);
      button = shad.ShadButton.raw(
        key: const ValueKey('elix-primary-shad-button'),
        variant: switch (variant) {
          ElixButtonVariant.primary => shad.ShadButtonVariant.primary,
          ElixButtonVariant.secondary => shad.ShadButtonVariant.secondary,
          ElixButtonVariant.outline => shad.ShadButtonVariant.outline,
          ElixButtonVariant.ghost => shad.ShadButtonVariant.ghost,
          ElixButtonVariant.destructive => shad.ShadButtonVariant.destructive,
        },
        autofocus: autofocus,
        onPressed: disabled ? null : onPressed,
        enabled: !disabled,
        expands: expanded,
        // Keep the standard 40px Shad height at normal scaling, while making
        // room for the complete Geist line box at accessible text scales.
        height: (scaledLineHeight + resolvedPadding.vertical)
            .clamp(40, double.infinity)
            .toDouble(),
        padding: effectivePadding,
        // ShadButton expands its child to consume the remaining row width.
        // Keep loading feedback in its dedicated leading slot so the ring
        // retains its square constraints while an expanded label fills space.
        leading: isLoading
            ? loadingIndicator
            : (icon == null ? null : Icon(icon, size: 16)),
        child: expanded ? labelChild : Flexible(child: labelChild),
      );
    }
    if (expanded && context.isHighContrast) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return Semantics(
      button: true,
      enabled: !disabled,
      liveRegion: isLoading,
      label: label,
      value: isLoading ? 'Loading' : null,
      child: button,
    );
  }
}
