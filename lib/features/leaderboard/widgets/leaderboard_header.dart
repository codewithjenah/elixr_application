import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../data/models/leaderboard_period.dart';
import '../leaderboard_presentation.dart';

class LeaderboardHeader extends StatelessWidget {
  const LeaderboardHeader({
    super.key,
    required this.onRefresh,
    this.period = LeaderboardPeriod.allTime,
    this.onPeriodChanged,
    this.refreshEnabled = true,
  });

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod>? onPeriodChanged;
  final VoidCallback onRefresh;
  final bool refreshEnabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = _LeaderboardTitle(period: period);
        final selector = LeaderboardPeriodSelector(
          period: period,
          onChanged: onPeriodChanged,
        );
        final refresh = _RefreshButton(
          enabled: refreshEnabled,
          onPressed: onRefresh,
        );

        if (constraints.maxWidth >= 880) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 392, child: selector),
              const SizedBox(width: AppSpacing.sm),
              refresh,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: selector),
                const SizedBox(width: AppSpacing.sm),
                refresh,
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LeaderboardTitle extends StatelessWidget {
  const _LeaderboardTitle({required this.period});

  final LeaderboardPeriod period;

  @override
  Widget build(BuildContext context) {
    return ElixEditorialHeader(
      heading: 'Leaderboard',
      eyebrow: 'COMMUNITY',
      subtitle: LeaderboardPresentation.periodSubtitle(period),
      leading: Container(
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
    );
  }
}

class LeaderboardPeriodSelector extends StatelessWidget {
  const LeaderboardPeriodSelector({
    super.key,
    required this.period,
    required this.onChanged,
  });

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Leaderboard period',
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.elixBorder),
        ),
        child: Row(
          children: [
            for (final value in LeaderboardPeriod.values)
              Expanded(
                child: _PeriodButton(
                  key: ValueKey('leaderboard-period-${value.name}'),
                  icon: _periodIcon(value),
                  label: LeaderboardPresentation.periodLabel(value),
                  selected: value == period,
                  onPressed: onChanged == null || value == period
                      ? null
                      : () => onChanged!(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _periodIcon(LeaderboardPeriod period) {
  return switch (period) {
    LeaderboardPeriod.today => FluentIcons.clock,
    LeaderboardPeriod.thisMonth => FluentIcons.calendar,
    LeaderboardPeriod.allTime => FluentIcons.globe,
  };
}

class _PeriodButton extends StatefulWidget {
  const _PeriodButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_PeriodButton> createState() => _PeriodButtonState();
}

class _PeriodButtonState extends State<_PeriodButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    final highlighted = widget.selected || _hovered || _focused;

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: interactive || widget.selected,
      label: '${widget.label} leaderboard',
      child: FocusableActionDetector(
        enabled: interactive,
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.primary.withValues(
                      alpha: context.isDarkTheme ? 0.18 : 0.12,
                    )
                  : _hovered
                  ? AppColors.accent.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focused
                    ? AppColors.primary.withValues(alpha: 0.85)
                    : widget.selected
                    ? AppColors.primary.withValues(alpha: 0.36)
                    : Colors.transparent,
                width: _focused ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    widget.icon,
                    size: 12,
                    color: widget.selected
                        ? AppColors.primarySoft
                        : context.elixTextSecondary,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: highlighted
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: widget.selected
                          ? AppColors.primarySoft
                          : context.elixTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          enabled: interactive,
          onShowFocusHighlight: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onShowHoverHighlight: (hovered) {
            if (_hovered != hovered) setState(() => _hovered = hovered);
          },
          mouseCursor: interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
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
              duration: const Duration(milliseconds: 120),
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !interactive
                      ? context.elixBorder.withValues(alpha: 0.5)
                      : accentBorder
                      ? AppColors.accent.withValues(alpha: 0.60)
                      : context.elixBorder,
                  width: _focused ? 1.5 : 1,
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
