import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../models/calendar_day_summary.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _cyan = AppColors.primarySoft;
const _amber = AppColors.warning;

class CalendarSummaryCards extends StatelessWidget {
  const CalendarSummaryCards({
    super.key,
    required this.activeDays,
    required this.monthlySessions,
    required this.currentStreak,
    required this.bestDay,
  });

  final int activeDays;
  final int monthlySessions;
  final int currentStreak;
  final CalendarDaySummary? bestDay;

  @override
  Widget build(BuildContext context) {
    final bestLabel = bestDay == null
        ? '—'
        : DateFormat.MMMd().format(bestDay!.date);
    final bestSub = bestDay?.averageScore == null
        ? 'No activity'
        : 'Average ${bestDay!.averageScore!.toStringAsFixed(0)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final cards = [
          _SummaryCard(
            label: 'Active Days',
            value: '$activeDays',
            subLabel: 'Unique practiced dates',
            icon: FluentIcons.calendar_day,
            accent: _cyan,
          ),
          _SummaryCard(
            label: 'Monthly Sessions',
            value: '$monthlySessions',
            subLabel: 'Completed this month',
            icon: FluentIcons.timer,
            accent: _purple,
          ),
          _SummaryCard(
            label: 'Current Streak',
            value: '$currentStreak',
            subLabel: currentStreak == 1 ? 'Day' : 'Days',
            icon: FluentIcons.lightning_bolt,
            accent: _amber,
          ),
          _SummaryCard(
            label: 'Best Training Day',
            value: bestLabel,
            subLabel: bestSub,
            icon: FluentIcons.trophy2_solid,
            accent: _pink,
            smallValue: bestDay != null,
          ),
        ];

        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[1]),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[3]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.accent,
    this.smallValue = false,
  });

  final String label;
  final String value;
  final String subLabel;
  final IconData icon;
  final Color accent;
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: smallValue ? 18 : 26,
              fontWeight: FontWeight.w800,
              color: accent == _pink ? _violet : accent,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 11,
              color: context.elixTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
