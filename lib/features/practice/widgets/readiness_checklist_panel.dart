import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/practice_feedback.dart';
import '../readiness_display.dart';

/// Compact readiness-gate checklist shown in the session panel during the
/// pre-practice readiness phase.
///
/// Displays each [ReadinessItemView] with a status icon, resolved title, and
/// instruction text. A linear progress bar reflects [progress] (0–1) toward
/// a stable-readiness confirmation.
///
/// When [frozen] is true, the panel dims and shows a "Ready — starting…"
/// overlay to indicate that the user has committed and the countdown is
/// about to begin.
class ReadinessChecklistPanel extends StatelessWidget {
  const ReadinessChecklistPanel({
    super.key,
    required this.items,
    required this.progress,
    required this.stable,
    this.frozen = false,
  });

  /// Current readiness check items from the backend.
  final List<ReadinessItemView> items;

  /// Stable-readiness confirmation progress (0.0–1.0).
  final double progress;

  /// Whether all checks have been stable long enough to proceed.
  final bool stable;

  /// When true, dim the panel and show a "Ready — starting…" message.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Readiness Check',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (stable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  'Ready',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        if (!stable) ...[
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final fraction = progress.clamp(0.0, 1.0);
              return Container(
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ...items.map((item) => _ReadinessRow(item: item)),
        ],
      ],
    );

    if (!frozen) return content;

    return Stack(
      children: [
        Opacity(opacity: 0.45, child: content),
        Positioned.fill(
          child: Center(
            child: Text(
              'Ready — starting…',
              style: AppTheme.bodySecondary.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.item});

  final ReadinessItemView item;

  @override
  Widget build(BuildContext context) {
    final display = resolveReadinessDisplay(
      item.code,
      backendMessage: item.message,
    );
    final (icon, color) = switch (item.status) {
      'ready' => (FluentIcons.check_mark, AppColors.success),
      'error' => (FluentIcons.error_badge, AppColors.error),
      _ => (FluentIcons.progress_ring_dots, AppColors.warning),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.title,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  display.instruction,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
