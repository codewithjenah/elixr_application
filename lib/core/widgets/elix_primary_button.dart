import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

class ElixPrimaryButton extends StatefulWidget {
  const ElixPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.expanded = true,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expanded;
  final bool dense;

  @override
  State<ElixPrimaryButton> createState() => _ElixPrimaryButtonState();
}

class _ElixPrimaryButtonState extends State<ElixPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.isLoading || widget.onPressed == null;

    Widget button = Listener(
      onPointerDown: (_) {
        if (!isDisabled) setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: MouseRegion(
        onEnter: (_) {
          if (!isDisabled) setState(() => _hovered = true);
        },
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _pressed && !isDisabled ? 0.977 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: _hovered && !isDisabled
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppColors.primary.withValues(alpha: 0.5);
                  }
                  if (states.contains(WidgetState.pressed) ||
                      (_pressed && !isDisabled)) {
                    return AppColors.primary.withValues(alpha: 0.85);
                  }
                  if (states.contains(WidgetState.hovered) ||
                      (_hovered && !isDisabled)) {
                    return AppColors.primarySoft;
                  }
                  return AppColors.primary;
                }),
                padding: WidgetStateProperty.all(
                  EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: widget.dense ? AppSpacing.sm : AppSpacing.md,
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
                  : Text(
                      widget.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    if (!widget.expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
