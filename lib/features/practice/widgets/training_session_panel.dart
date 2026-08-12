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
    TrainingSessionPhase.preparingCamera => (
      AppColors.warning,
      'Preparing Camera',
    ),
    TrainingSessionPhase.readiness => (AppColors.accent, 'Readiness Check'),
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

    final scrollable = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionHeaderRow(
            phaseLabel: phaseLabel,
            accent: accent,
            rankBadge: rankBadge,
          ),
          const SizedBox(height: AppSpacing.md),
          metrics,
          const SizedBox(height: AppSpacing.md),
          _StatusSurface(
            key: const ValueKey('session-status-surface'),
            title: statusTitle,
            accent: accent,
            child: statusContent,
          ),
          if (notice != null) ...[
            const SizedBox(height: AppSpacing.md),
            notice!,
          ],
          if (supportingContent != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SetupSurface(
              key: const ValueKey('session-setup-section'),
              child: supportingContent!,
            ),
          ],
          if (compactStatusNote != null) ...[
            const SizedBox(height: AppSpacing.md),
            compactStatusNote!,
          ],
        ],
      ),
    );

    return Container(
      key: const ValueKey('practice-session-panel'),
      decoration: AppTheme.practicePanelDecoration(context, accent: accent),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandVertically ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Rubric metrics can exceed the available height, so the scroll area
          // must never claim the space reserved for the pinned action area.
          if (expandVertically)
            Expanded(child: scrollable)
          else
            Flexible(child: scrollable),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: context.elixBorder.withValues(alpha: 0.35),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 2,
              AppSpacing.md,
              AppSpacing.md,
            ),
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
        Text(
          'Session',
          style: AppTheme.headingMedium.copyWith(
            fontSize: 18,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _PhaseChip(label: phaseLabel, accent: accent),
        const Spacer(),
        ?rankBadge,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
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
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: AppTheme.practiceSectionSurface(context, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTheme.caption.copyWith(
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: AppTheme.practiceSectionSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Session setup',
            style: AppTheme.caption.copyWith(
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
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
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 22,
                    letterSpacing: 0.8,
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
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
        vertical: AppSpacing.sm,
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
          const SizedBox(height: 6),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.elixTextSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const Spacer(),
          Flexible(
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
