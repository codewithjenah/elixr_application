import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
import 'elix_panel_card.dart';
import 'elix_primary_button.dart';

/// Shared loading / empty / error copy on an [ElixPanelCard] surface.
class ElixStatusPanel extends StatelessWidget {
  const ElixStatusPanel({
    super.key,
    required this.message,
    this.title,
    this.isError = false,
    this.isLoading = false,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final bool isError;
  final bool isLoading;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Semantics(
        liveRegion: isError || isLoading,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading) ...[
              const SizedBox(width: 20, height: 20, child: ProgressRing()),
              const SizedBox(height: AppSpacing.sm),
            ] else if (icon != null) ...[
              Icon(
                icon,
                color: isError
                    ? context.elixColors.error
                    : context.elixColors.brandPrimary,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (title != null) ...[
              Text(
                title!,
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              message,
              style: AppTheme.body.copyWith(
                color: isError
                    ? context.elixColors.error
                    : context.elixTextSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              ElixPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
                variant: isError
                    ? ElixButtonVariant.outline
                    : ElixButtonVariant.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact in-dialog error copy that never relies on colour alone.
class ElixInlineError extends StatelessWidget {
  const ElixInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = context.elixColors.error;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ElixToneCues.icon(ElixTone.error), size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: AppTheme.body.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
