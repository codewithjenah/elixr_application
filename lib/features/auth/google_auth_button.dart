import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';

class GoogleAuthButton extends StatelessWidget {
  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final enabled = onPressed != null && !isLoading;

    return HoverButton(
      onPressed: isLoading ? null : onPressed,
      semanticLabel: isLoading ? '$label, Loading' : label,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      builder: (context, states) {
        final hovered = states.isHovered && enabled;
        final pressed = states.isPressed && enabled;
        final focused = states.isFocused;
        return AnimatedContainer(
          duration: ElixMotion.duration(context, ElixMotion.micro),
          curve: ElixMotion.microCurve,
          width: double.infinity,
          height: dense ? 40 : 44,
          decoration: BoxDecoration(
            color: !enabled
                ? colors.disabledSurface
                : pressed
                ? colors.interactivePressed
                : hovered
                ? colors.interactiveHover
                : colors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? colors.focusRing
                  : !enabled
                  ? colors.disabledBorder
                  : highContrast
                  ? colors.borderStrong
                  : colors.borderSubtle,
              width: focused || highContrast ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: ProgressRing(strokeWidth: 2),
                )
              else
                const Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: AppTheme.body.copyWith(
                      color: enabled ? colors.textPrimary : colors.disabledText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, this.label = 'or'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Row(
      children: [
        Expanded(
          child: Divider(
            style: DividerThemeData(
              decoration: BoxDecoration(color: colors.borderSubtle),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: AppTheme.caption.copyWith(
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            style: DividerThemeData(
              decoration: BoxDecoration(color: colors.borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
