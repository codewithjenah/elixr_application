import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/practice_feedback.dart';
import '../readiness_display.dart';

/// Compact readiness-gate checklist shown in the session panel during the
/// pre-practice readiness phase.
///
/// Accepts [items] from [PracticeReadinessState.displayItems], [progress]
/// (0–1) toward stable-readiness, and optional [streamStale] / [frozen] flags.
///
/// When [frozen] is true, the header transitions to a locked-ready state
/// without dimming the item list — the user can still see which checks passed.
///
/// The stability bar is shown only when [complete] is true and [progress] > 0
/// (i.e. accumulating the stable hold). Before all items are ready, a compact
/// "N of M ready" summary is shown instead.
class ReadinessChecklistPanel extends StatelessWidget {
  const ReadinessChecklistPanel({
    super.key,
    required this.items,
    required this.progress,
    required this.stable,
    this.complete = false,
    this.frozen = false,
    this.streamStale = false,
    this.recoverableMessage,
    this.readyCount,
  });

  /// Current readiness check items (live or frozen snapshot).
  final List<ReadinessItemView> items;

  /// Stable-readiness confirmation progress (0.0–1.0).
  final double progress;

  /// Whether all checks have been stable long enough to proceed.
  final bool stable;

  /// Whether all checks have passed at least once.
  final bool complete;

  /// When true, the header shows a locked-ready indicator.
  final bool frozen;

  /// When true, the backend stream has stalled; shown as a warning.
  final bool streamStale;

  /// Inline recoverable message (e.g. "readiness_not_stable" rejection).
  final String? recoverableMessage;

  /// Pre-computed ready count for the "N of M" summary line. If null,
  /// computed locally from [items].
  final int? readyCount;

  @override
  Widget build(BuildContext context) {
    final ready =
        readyCount ??
        items.where((i) => i.status == ReadinessItemStatus.ready).length;
    final total = items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, ready: ready, total: total),
        if (streamStale) ...[
          const SizedBox(height: AppSpacing.xs),
          _StaleWarning(),
        ] else if (recoverableMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _RecoverableNote(message: recoverableMessage!),
        ],
        if (!complete && total > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          _ReadyCountSummary(readyCount: ready, total: total),
        ],
        if (complete && progress > 0 && !frozen) ...[
          const SizedBox(height: AppSpacing.sm),
          _StabilityBar(progress: progress),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(
                items.map((i) => '${i.code}:${i.status.wireValue}').join(),
              ),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items.map((item) => _ReadinessRow(item: item)).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required int ready,
    required int total,
  }) {
    if (frozen) {
      return Row(
        children: [
          Icon(FluentIcons.lock, size: 14, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Setup Check — Ready',
            style: AppTheme.bodySecondary.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Semantics(
          label: 'Readiness Check',
          child: Text(
            'Setup Check',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
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
    );
  }
}

class _ReadyCountSummary extends StatelessWidget {
  const _ReadyCountSummary({required this.readyCount, required this.total});

  final int readyCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$readyCount of $total ready',
      style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
    );
  }
}

class _StabilityBar extends StatelessWidget {
  const _StabilityBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.clamp(0.0, 1.0);
    return Semantics(
      label: 'Stability progress ${(fraction * 100).round()} percent',
      child: Container(
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
              color: AppColors.success,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaleWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(FluentIcons.warning, size: 12, color: AppColors.warning),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Waiting for a fresh camera reading\u2026',
            style: AppTheme.caption.copyWith(color: AppColors.warning),
          ),
        ),
      ],
    );
  }
}

class _RecoverableNote extends StatelessWidget {
  const _RecoverableNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTheme.caption.copyWith(color: AppColors.warning),
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
      ReadinessItemStatus.ready => (FluentIcons.check_mark, AppColors.success),
      ReadinessItemStatus.error => (FluentIcons.error_badge, AppColors.error),
      _ => (FluentIcons.progress_ring_dots, AppColors.warning),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        label:
            '${display.title}: ${display.instruction} — ${item.status.wireValue}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child:
                  item.status == ReadinessItemStatus.waiting ||
                      item.status == ReadinessItemStatus.unknown
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2, activeColor: color),
                    )
                  : Icon(icon, size: 14, color: color),
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
      ),
    );
  }
}
