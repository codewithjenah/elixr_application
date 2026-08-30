import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// Compact page-level back navigation for ELIXR desktop screens.
///
/// The optional [label] can identify the destination when that helps orient
/// the user. Modal close controls and navigation within split panes should use
/// controls that describe those local actions instead.
class ElixBackButton extends StatelessWidget {
  const ElixBackButton({
    super.key,
    required this.onPressed,
    this.label,
    this.tooltip = 'Back',
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final String? label;
  final String tooltip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final enabled = onPressed != null;
    final accessibilityLabel = semanticLabel ?? tooltip;

    final button = Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          EdgeInsets.symmetric(
            horizontal: label == null ? AppSpacing.sm : AppSpacing.sm + 2,
            vertical: AppSpacing.sm,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return highContrast ? colors.surfaceBase : Colors.transparent;
          }
          if (states.contains(WidgetState.pressed)) {
            return colors.interactivePressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.interactiveHover;
          }
          return highContrast ? colors.surfaceBase : Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return colors.disabledText;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return highContrast ? colors.textPrimary : colors.brandPrimary;
          }
          return colors.textPrimary;
        }),
        shape: WidgetStateProperty.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          final disabled = states.contains(WidgetState.disabled);
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: focused
                  ? colors.focusRing
                  : disabled && highContrast
                  ? colors.disabledBorder
                  : highContrast
                  ? colors.borderStrong
                  : Colors.transparent,
              width: focused
                  ? (highContrast
                        ? ElixFocus.ringWidthHighContrast
                        : ElixFocus.ringWidth)
                  : (highContrast ? ElixFocus.ringWidth : 1),
            ),
          );
        }),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.chrome_back, size: 16),
          if (label != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              label!,
              style: AppTheme.label(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: accessibilityLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            child: button,
          ),
        ),
      ),
    );
  }
}
