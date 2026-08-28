import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

enum TrainingSessionPhase {
  ready,
  preparingCamera,

  /// Pre-practice readiness gate (Guided Practice only).
  readiness,

  getReady,
  inProgress,
  completed,
  cameraError,
}

(Color phaseAccent, String phaseLabel) trainingPhasePresentation(
  TrainingSessionPhase phase,
  BuildContext context,
) {
  return switch (phase) {
    TrainingSessionPhase.ready => (context.elixTextSecondary, 'Ready'),
    TrainingSessionPhase.preparingCamera => (AppColors.warning, 'Camera Setup'),
    TrainingSessionPhase.readiness => (AppColors.accent, 'Setup Check'),
    TrainingSessionPhase.getReady => (AppColors.primary, 'Get Ready'),
    TrainingSessionPhase.inProgress => (AppColors.success, 'In Progress'),
    TrainingSessionPhase.completed => (AppColors.success, 'Completed'),
    TrainingSessionPhase.cameraError => (AppColors.error, 'Camera Error'),
  };
}

String trainingStatusSectionTitle(TrainingSessionPhase phase) {
  return switch (phase) {
    TrainingSessionPhase.ready ||
    TrainingSessionPhase.preparingCamera ||
    TrainingSessionPhase.readiness ||
    TrainingSessionPhase.getReady ||
    TrainingSessionPhase.cameraError => 'Setup status',
    TrainingSessionPhase.inProgress ||
    TrainingSessionPhase.completed => 'Live status',
  };
}

/// Slot-based session panel shell with a premium training-dashboard layout.
class TrainingSessionPanel extends StatelessWidget {
  const TrainingSessionPanel({
    super.key,
    required this.phase,
    required this.metrics,
    required this.statusContent,
    required this.actionArea,
    this.rankBadge,
    this.supportingContent,
    this.notice,
    this.compactStatusNote,
    this.expandVertically = true,
  });

  final TrainingSessionPhase phase;
  final Widget metrics;
  final Widget statusContent;
  final Widget actionArea;
  final Widget? rankBadge;
  final Widget? supportingContent;
  final Widget? notice;
  final Widget? compactStatusNote;
  final bool expandVertically;

  @override
  Widget build(BuildContext context) {
    final (accent, phaseLabel) = trainingPhasePresentation(phase, context);
    final statusTitle = trainingStatusSectionTitle(phase);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionHeaderRow(
          phaseLabel: phaseLabel,
          accent: accent,
          rankBadge: rankBadge,
        ),
        const SizedBox(height: 12),
        metrics,
        const SizedBox(height: 12),
        _StatusSurface(
          key: const ValueKey('session-status-surface'),
          title: statusTitle,
          accent: accent,
          child: statusContent,
        ),
        if (notice != null) ...[const SizedBox(height: 12), notice!],
        if (supportingContent != null) ...[
          const SizedBox(height: 12),
          _SetupSurface(
            key: const ValueKey('session-setup-section'),
            child: supportingContent!,
          ),
        ],
        if (compactStatusNote != null) ...[
          const SizedBox(height: 12),
          compactStatusNote!,
        ],
      ],
    );

    final paddedContent = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: content,
    );

    // Desktop keeps the whole control deck visible without a nested scrollbar.
    // At unusually short window heights, scale the deck down as one unit rather
    // than hiding status or forcing the user to scroll beside the camera.
    final informationArea = expandVertically
        ? LayoutBuilder(
            key: const ValueKey('session-information-static'),
            builder: (context, constraints) {
              const horizontalPadding = 28.0;
              final contentWidth = (constraints.maxWidth - horizontalPadding)
                  .clamp(0.0, double.infinity);
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: contentWidth, child: content),
                ),
              );
            },
          )
        : SingleChildScrollView(
            key: const ValueKey('session-information-scrollable'),
            child: paddedContent,
          );

    return Container(
      key: const ValueKey('practice-session-panel'),
      decoration: AppTheme.practicePanelDecoration(context, accent: accent),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandVertically ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expandVertically)
            Expanded(child: informationArea)
          else
            Flexible(child: informationArea),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: context.elixBorder.withValues(alpha: 0.35),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, AppSpacing.sm + 2, 14, 14),
            child: actionArea,
          ),
        ],
      ),
    );
  }
}

class _SessionHeaderRow extends StatelessWidget {
  const _SessionHeaderRow({
    required this.phaseLabel,
    required this.accent,
    this.rankBadge,
  });

  final String phaseLabel;
  final Color accent;
  final Widget? rankBadge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Icon(FluentIcons.processing, size: 15, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRAINING SESSION',
                style: AppTheme.caption.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: 3),
              _PhaseChip(label: phaseLabel, accent: accent),
            ],
          ),
        ),
        if (rankBadge != null) ...[
          const SizedBox(width: AppSpacing.sm),
          rankBadge!,
        ],
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: AppTheme.caption.copyWith(
            fontSize: 10,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatusSurface extends StatelessWidget {
  const _StatusSurface({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
  });

  final String title;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: AppTheme.practiceSectionSurface(context, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(label: title, color: accent),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

class _SetupSurface extends StatelessWidget {
  const _SetupSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: AppTheme.practiceSectionSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            label: 'Session setup',
            color: context.elixTextSecondary,
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

/// Elapsed clock for Live / Free Practice. Callers own when the display
/// advances; this widget only applies the metric type scale.
class LivePracticeElapsedMetric extends StatelessWidget {
  const LivePracticeElapsedMetric({super.key, required this.elapsedDisplay});

  final String elapsedDisplay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('ELAPSED', style: AppTheme.eyebrow(color: AppColors.primarySoft)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          elapsedDisplay,
          style: AppTheme.metric(
            context,
            color: context.elixTextPrimary,
          ).copyWith(letterSpacing: 2),
        ),
      ],
    );
  }
}

/// Compact elapsed / rubric metric tiles for the session panel.
class SessionMetricTiles extends StatelessWidget {
  const SessionMetricTiles({
    super.key,
    required this.elapsedDisplay,
    required this.rubricChild,
    this.performanceBar,
    this.rubricBreakdown,
  });

  final String elapsedDisplay;
  final Widget rubricChild;
  final Widget? performanceBar;

  /// Per-criterion rubric breakdown shown below the performance bar.
  final Widget? rubricBreakdown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                key: const ValueKey('session-elapsed-metric'),
                icon: FluentIcons.clock,
                label: 'ELAPSED',
                accent: context.elixTextSecondary,
                child: Text(
                  elapsedDisplay,
                  style: AppTheme.sectionTitle(
                    context,
                    color: context.elixTextPrimary,
                  ).copyWith(letterSpacing: 0.8),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                key: const ValueKey('session-score-metric'),
                icon: FluentIcons.trophy,
                label: 'RUBRIC',
                accent: AppColors.primary,
                emphasized: true,
                child: rubricChild,
              ),
            ),
          ],
        ),
        if (performanceBar != null) ...[
          const SizedBox(height: AppSpacing.md),
          performanceBar!,
        ],
        if (rubricBreakdown != null) ...[
          const SizedBox(height: AppSpacing.md),
          rubricBreakdown!,
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.child,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 7,
      ),
      decoration: AppTheme.practiceMetricTileDecoration(context).copyWith(
        border: emphasized
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.22))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTheme.caption.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: emphasized
                      ? AppColors.primarySoft
                      : context.elixTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Compact setup row with icon for session panel.
class SessionSetupRow extends StatelessWidget {
  const SessionSetupRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.elixTextSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: AppTheme.body.copyWith(
                fontWeight: FontWeight.w600,
                color: context.elixTextPrimary,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stage indicator for calibration phases.
class TrainingStageIndicator extends StatelessWidget {
  const TrainingStageIndicator({
    super.key,
    required this.cameraActive,
    required this.cameraDone,
    required this.setupActive,
    required this.setupDone,
    required this.practiceActive,
  });

  final bool cameraActive;
  final bool cameraDone;
  final bool setupActive;
  final bool setupDone;
  final bool practiceActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: AppTheme.practiceMetricTileDecoration(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StageStep(label: 'Camera', active: cameraActive, done: cameraDone),
          _StageDivider(),
          _StageStep(
            label: 'Setup Check',
            active: setupActive,
            done: setupDone,
          ),
          _StageDivider(),
          _StageStep(label: 'Practice', active: practiceActive, done: false),
        ],
      ),
    );
  }
}

class _StageStep extends StatelessWidget {
  const _StageStep({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : active
        ? AppColors.primary
        : context.elixTextSecondary;
    return Text(
      label,
      style: AppTheme.caption.copyWith(
        color: color,
        fontWeight: (active || done) ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _StageDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '›',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      ),
    );
  }
}
