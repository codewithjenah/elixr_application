import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

class HistoryHeader extends StatelessWidget {
  const HistoryHeader({
    super.key,
    required this.loading,
    required this.onRefresh,
  });

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(
              alpha: context.isDarkTheme ? 0.2 : 0.12,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
          ),
          child: Icon(
            FluentIcons.history,
            size: 20,
            color: AppColors.accentSoft,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'History',
                style: AppTheme.headingLarge.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 2),
              Text(
                'Review and compare your previous training sessions',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        _RefreshButton(loading: loading, onPressed: onRefresh),
      ],
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh sessions',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.loading
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: FocusableActionDetector(
          child: GestureDetector(
            onTap: widget.loading ? null : widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : context.elixBorder,
                ),
              ),
              child: AnimatedRotation(
                turns: widget.loading ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: Icon(
                  FluentIcons.refresh,
                  size: 16,
                  color: widget.loading
                      ? context.elixTextSecondary
                      : AppColors.accentSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
