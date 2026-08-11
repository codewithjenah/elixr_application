import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/session.dart';
import '../models/calendar_day_summary.dart';
import '../utils/calendar_metrics.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;
const _cyan = AppColors.primarySoft;

class SelectedDayPanel extends StatelessWidget {
  const SelectedDayPanel({super.key, required this.summary});

  final CalendarDaySummary summary;

  @override
  Widget build(BuildContext context) {
    final sessions = List<Session>.from(summary.sessions)
      ..sort((a, b) {
        final aAt = a.createdAt;
        final bAt = b.createdAt;
        if (aAt == null && bAt == null) return 0;
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        return bAt.compareTo(aAt);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMMEEEEd().format(summary.date),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Sessions', value: '${summary.sessionCount}'),
              _MetricChip(
                label: 'Average',
                value: summary.averageScore == null
                    ? '—'
                    : summary.averageScore!.toStringAsFixed(0),
              ),
              _MetricChip(
                label: 'Best',
                value: summary.bestScore?.toString() ?? '—',
              ),
              _MetricChip(
                label: 'Duration',
                value: formatCalendarDuration(summary.totalDurationSeconds),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (sessions.isEmpty)
            _EmptySelectedDay(onStartPractice: () => context.go('/movements'))
          else
            Column(
              children: [
                for (var i = 0; i < sessions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _SessionRow(session: sessions[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySelectedDay extends StatelessWidget {
  const _EmptySelectedDay({required this.onStartPractice});

  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No practice recorded',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Complete a guided practice session to add activity to this date.',
            style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onStartPractice,
            child: const Text('Start Practice'),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Session session;

  Color _difficultyColor(BuildContext context, String difficulty) {
    switch (difficulty) {
      case 'Easy':
        return _cyan;
      case 'Medium':
        return _purple;
      case 'Hard':
        return _pink;
      default:
        return context.elixTextSecondary;
    }
  }

  String? _localTime() {
    final raw = session.createdAt;
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateFormat.jm().format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final time = _localTime();
    final diffColor = _difficultyColor(context, session.difficulty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.movementName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: diffColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: diffColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        session.difficulty,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: diffColor,
                        ),
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${session.score}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentSoft,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatCalendarDuration(session.durationSeconds),
                style: TextStyle(
                  fontSize: 11,
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
