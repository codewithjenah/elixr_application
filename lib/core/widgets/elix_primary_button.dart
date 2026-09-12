import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

/// The shared primary action. Normal themes render a real [shad.ShadButton].
class ElixPrimaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    final child = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: ProgressRing(strokeWidth: 2),
          )
        : Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          );
    final effectivePadding =
        padding ??
        EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: dense ? AppSpacing.sm : AppSpacing.md,
        );
    Widget button;
    if (context.isHighContrast) {
      button = FilledButton(
        onPressed: disabled ? null : onPressed,
        style: ButtonStyle(padding: WidgetStatePropertyAll(effectivePadding)),
        child: child,
      );
    } else {
      button = shad.ShadButton(
        key: const ValueKey('elix-primary-shad-button'),
        onPressed: disabled ? null : onPressed,
        enabled: !disabled,
        expands: expanded,
        padding: effectivePadding,
        leading: icon == null ? null : Icon(icon, size: 16),
        child: child,
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
