import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import 'teacher_analytics_controller.dart';
import 'teacher_analytics_models.dart';

/// Compact, best-effort current-week summary for the Teacher dashboard.
///
/// It intentionally owns no dashboard state and never replaces the existing
/// roster content when analytics reads fail.
class TeacherAnalyticsSummary extends StatelessWidget {
  const TeacherAnalyticsSummary({super.key, required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return ElixPanelCard(
          accent: context.elixColors.brandSecondary,
          showAccentBar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryHeader(controller: controller),
              const SizedBox(height: AppSpacing.md),
              if ((controller.loading || controller.sessionLoading) &&
                  snapshot == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: ProgressBar(),
                )
              else if (controller.errorMessage != null && snapshot == null)
                Text(
                  'Analytics is temporarily unavailable. Your class data is still shown below.',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextSecondary,
                  ),
                )
              else
                _SummaryMetrics(snapshot: snapshot),
              if (controller.partialDataWarning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Some practice history could not be loaded, so some numbers may be incomplete.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixColors.warning,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.elixColors.brandSecondary.withValues(
                  alpha: context.isHighContrast ? 0 : 0.16,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                FluentIcons.chart,
                size: 16,
                color: context.elixColors.brandSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'This Week',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "A quick look at your class's practice.",
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Button(
          onPressed: controller.sessionLoading ? null : controller.refresh,
          child: const Text('Refresh'),
        ),
        FilledButton(
          onPressed: () => context.go(AppRoutePaths.teacherAnalytics),
          child: const Text('View Analytics'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.lg),
            Flexible(child: actions),
          ],
        );
      },
    );
  }
}

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.snapshot});

  final AnalyticsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final values = [
      _SummaryMetricData(
        label: 'Class average score',
        value: _score(snapshot?.averageScore),
        icon: FluentIcons.favorite_star,
        color: context.elixColors.milestone,
      ),
      _SummaryMetricData(
        label: 'Practice per student',
        value: snapshot?.averagePracticeSessions?.toStringAsFixed(1) ?? '—',
        icon: FluentIcons.repeat_all,
        color: context.elixColors.brandSecondary,
      ),
      _SummaryMetricData(
        label: 'Assignments completed',
        value: snapshot?.completionRate == null
            ? '—'
            : '${(snapshot!.completionRate! * 100).toStringAsFixed(0)}%',
        icon: FluentIcons.completed,
        color: context.elixColors.success,
      ),
      _SummaryMetricData(
        label: 'Change from last week',
        value: snapshot?.improvement == null ? '—' : _signed(snapshot!.improvement!),
        icon: FluentIcons.trending12,
        color: _changeColor(context, snapshot?.improvement),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final children = [
          for (final value in values) _SummaryMetric(data: value),
        ];
        if (wide) {
          return Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(child: children[index]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
                child: child,
              ),
          ],
        );
      },
    );
  }

  static String _score(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} / 12';
  static String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';

  static Color _changeColor(BuildContext context, double? value) {
    if (value == null) return context.elixTextSecondary;
    return value >= 0
        ? context.elixColors.success
        : context.elixColors.error;
  }
}

class _SummaryMetricData {
  const _SummaryMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.data});

  final _SummaryMetricData data;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Container(
      constraints: const BoxConstraints(minHeight: 102),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : context.elixCardSurface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, size: 16, color: data.color),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.value,
            style: AppTheme.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
