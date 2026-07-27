import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

const _amber = AppColors.warning;

class LeaderboardHeader extends StatelessWidget {
  const LeaderboardHeader({
    super.key,
    required this.onRefresh,
    this.refreshEnabled = true,
  });

  final VoidCallback onRefresh;
  final bool refreshEnabled;

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
            FluentIcons.trophy2_solid,
            size: 20,
            color: AppColors.accentSoft,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Leaderboard',
                    style: AppTheme.headingLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _amber.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'All Time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _amber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'All-time rankings by total XP.',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        _RefreshButton(enabled: refreshEnabled, onPressed: onRefresh),
      ],
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh leaderboard',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: FocusableActionDetector(
          child: GestureDetector(
            onTap: widget.enabled ? widget.onPressed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered && widget.enabled
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : context.elixBorder,
                ),
              ),
              child: Icon(
                FluentIcons.refresh,
                size: 16,
                color: widget.enabled
                    ? AppColors.accentSoft
                    : context.elixTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
