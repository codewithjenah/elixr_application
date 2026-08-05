import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_card.dart';

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

/// Slot-based session panel shell. Owns action pin; content comes from slots.
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
  });

  final TrainingSessionPhase phase;
  final Widget metrics;
  final Widget statusContent;
  final Widget actionArea;
  final Widget? rankBadge;
  final Widget? supportingContent;
  final Widget? notice;
  final Widget? compactStatusNote;

  String get _phaseLabel => switch (phase) {
    TrainingSessionPhase.ready => 'Ready',
    TrainingSessionPhase.preparingCamera => 'Preparing Camera',
    TrainingSessionPhase.readiness => 'Readiness Check',
    TrainingSessionPhase.getReady => 'Get Ready',
    TrainingSessionPhase.inProgress => 'In Progress',
    TrainingSessionPhase.completed => 'Completed',
    TrainingSessionPhase.cameraError => 'Camera Error',
  };

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Session',
                        style: AppTheme.headingMedium.copyWith(
                          color: context.elixTextPrimary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _PhaseChip(label: _phaseLabel),
                      const Spacer(),
                      ?rankBadge,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  metrics,
                  const SizedBox(height: AppSpacing.md),
                  statusContent,
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    notice!,
                  ],
                  if (supportingContent != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      height: 1,
                      color: context.elixBorder.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    supportingContent!,
                  ],
                  if (compactStatusNote != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    compactStatusNote!,
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
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

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.elixBorder.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: context.elixTextSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
