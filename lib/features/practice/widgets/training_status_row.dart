import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

enum TrainingDetectionStatus { inactive, searching, detected }

TrainingDetectionStatus resolveDetectionStatus({
  required bool sessionActive,
  bool? bottleDetected,
}) {
  if (!sessionActive) return TrainingDetectionStatus.inactive;
  if (bottleDetected == true) return TrainingDetectionStatus.detected;
  // Active but not detected, or feedback temporarily unavailable → searching
  return TrainingDetectionStatus.searching;
}

String? postureDisplayLabel(String? postureStatus) {
  switch (postureStatus) {
    case 'stable':
      return 'Posture stable';
    case 'unstable':
      return 'Posture unstable';
    default:
      return null;
  }
}

class TrainingStatusRow extends StatelessWidget {
  const TrainingStatusRow({
    super.key,
    required this.detection,
    this.postureLabel,
  });

  final TrainingDetectionStatus detection;
  final String? postureLabel;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (detection) {
      TrainingDetectionStatus.detected => (
        'Bottle detected',
        AppColors.success,
        FluentIcons.status_circle_checkmark,
      ),
      TrainingDetectionStatus.searching => (
        'Searching for bottle',
        AppColors.warning,
        FluentIcons.search,
      ),
      TrainingDetectionStatus.inactive => (
        'Detection inactive',
        context.elixTextSecondary,
        FluentIcons.circle_ring,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusLine(icon: icon, label: label, color: color),
        if (postureLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _StatusLine(
            icon: FluentIcons.contact,
            label: postureLabel!,
            color: context.elixTextSecondary,
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTheme.body.copyWith(color: color, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
