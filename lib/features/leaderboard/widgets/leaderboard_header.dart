import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

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
              alpha: context.isDarkTheme ? 0.18 : 0.10,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.26)),
          ),
          child: const Icon(
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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    'Leaderboard',
                    style: AppTheme.headingLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      'All Time',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: AppColors.warning.withValues(
                          alpha: context.isDarkTheme ? 0.92 : 0.85,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'All-time rankings by total XP.',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled;
    final accentBorder = _hovered || _focused;

    return Semantics(
      button: true,
      enabled: interactive,
      label: 'Refresh leaderboard',
      child: Tooltip(
        message: 'Refresh leaderboard',
        child: FocusableActionDetector(
          onShowFocusHighlight: (focused) {
            setState(() => _focused = focused);
          },
          onShowHoverHighlight: (hovered) {
            setState(() => _hovered = hovered);
          },
          mouseCursor: interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (interactive) widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: interactive ? widget.onPressed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !interactive
                      ? context.elixBorder.withValues(alpha: 0.5)
                      : accentBorder
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : context.elixBorder,
                  width: _focused ? 1.6 : 1,
                ),
              ),
              child: Icon(
                FluentIcons.refresh,
                size: 16,
                color: interactive
                    ? AppColors.accentSoft
                    : context.elixTextSecondary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
