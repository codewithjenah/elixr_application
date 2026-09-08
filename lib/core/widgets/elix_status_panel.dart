import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'elix_panel_card.dart';

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
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
