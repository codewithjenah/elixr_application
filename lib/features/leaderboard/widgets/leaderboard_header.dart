import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

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
    this.period = LeaderboardPeriod.thisMonth,
    this.onPeriodChanged,
    this.refreshEnabled = true,
    this.nowUtc,
  });

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod>? onPeriodChanged;
  final VoidCallback onRefresh;
  final bool refreshEnabled;
  final DateTime? nowUtc;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = _LeaderboardTitle(period: period, nowUtc: nowUtc);
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
  const _LeaderboardTitle({required this.period, this.nowUtc});

  final LeaderboardPeriod period;
  final DateTime? nowUtc;

  @override
  Widget build(BuildContext context) {
    final clock = (nowUtc ?? DateTime.now()).toUtc();
    return ElixEditorialHeader(
      heading: 'Leaderboard',
      eyebrow: 'COMMUNITY',
      subtitle: LeaderboardPresentation.headerSubtitle(period, nowUtc: clock),
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
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return _FluentPeriodSelector(period: period, onChanged: onChanged);
    }
    return Semantics(
      label: 'Leaderboard period',
      child: Row(
        children: [
          for (final value in LeaderboardPeriod.values) ...[
            Expanded(
              child: shad.ShadButton.raw(
                key: ValueKey('leaderboard-period-${value.name}'),
                variant: value == period
                    ? shad.ShadButtonVariant.secondary
                    : shad.ShadButtonVariant.ghost,
                size: shad.ShadButtonSize.sm,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: onChanged == null || value == period
                    ? null
                    : () => onChanged!(value),
                child: Expanded(
                  child: Text(
                    LeaderboardPresentation.periodLabel(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            if (value != LeaderboardPeriod.allTime)
              const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _FluentPeriodSelector extends StatelessWidget {
  const _FluentPeriodSelector({required this.period, required this.onChanged});

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Leaderboard period',
      child: Row(
        children: [
          for (final value in LeaderboardPeriod.values) ...[
            Expanded(
              child: ToggleButton(
                checked: value == period,
                onChanged: onChanged == null || value == period
                    ? null
                    : (_) => onChanged!(value),
                child: Text(LeaderboardPresentation.periodLabel(value)),
              ),
            ),
            if (value != LeaderboardPeriod.allTime)
              const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final useShad =
        !context.isHighContrast && shad.ShadTheme.maybeOf(context) != null;
    final child = !useShad
        ? IconButton(
            icon: const Icon(FluentIcons.refresh),
            onPressed: enabled ? onPressed : null,
          )
        : shad.ShadIconButton.outline(
            icon: const Icon(FluentIcons.refresh),
            onPressed: enabled ? onPressed : null,
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Refresh leaderboard',
      child: !useShad
          ? Tooltip(message: 'Refresh leaderboard', child: child)
          : shad.ShadTooltip(
              builder: (context) => const Text('Refresh leaderboard'),
              child: child,
            ),
    );
  }
}
