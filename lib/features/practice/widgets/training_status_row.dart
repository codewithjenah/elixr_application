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
    case 'unknown':
      return "Can't determine";
    default:
      return null;
  }
}

class TrainingStatusRow extends StatelessWidget {
  const TrainingStatusRow({
    super.key,
    required this.detection,
    this.propLabel = 'Bottle',
    this.postureLabel,
  });

  final TrainingDetectionStatus detection;
  final String propLabel;
  final String? postureLabel;

  @override
  Widget build(BuildContext context) {
    final objectLabel = propLabel.trim().isEmpty ? 'Prop' : propLabel;
    final (label, supporting, color, icon) = switch (detection) {
      TrainingDetectionStatus.detected => (
        '$objectLabel detected',
        'Tracking is active for this session.',
        AppColors.success,
        FluentIcons.status_circle_checkmark,
      ),
      TrainingDetectionStatus.searching => (
        'Searching for ${objectLabel.toLowerCase()}',
        'Keep the prop visible in frame.',
        AppColors.warning,
        FluentIcons.search,
      ),
      TrainingDetectionStatus.inactive => (
        'Detection inactive',
        'Detection begins once practice is active.',
        context.elixTextSecondary,
        FluentIcons.circle_ring,
      ),
    };

    return Semantics(
      label: label,
      child: _StatusCallout(
        icon: icon,
        label: label,
        supporting: supporting,
        color: color,
        pulse: detection == TrainingDetectionStatus.searching,
        postureLabel: postureLabel,
      ),
    );
  }
}

class _StatusCallout extends StatefulWidget {
  const _StatusCallout({
    required this.icon,
    required this.label,
    required this.supporting,
    required this.color,
    required this.pulse,
    this.postureLabel,
  });

  final IconData icon;
  final String label;
  final String supporting;
  final Color color;
  final bool pulse;
  final String? postureLabel;

  @override
  State<_StatusCallout> createState() => _StatusCalloutState();
}

class _StatusCalloutState extends State<_StatusCallout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncPulse(widget.pulse);
  }

  @override
  void didUpdateWidget(_StatusCallout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse) {
      _syncPulse(widget.pulse);
    }
  }

  void _syncPulse(bool enabled) {
    if (enabled) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSurface = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.color.withValues(alpha: 0.28)),
      ),
      child: Icon(widget.icon, size: 18, color: widget.color),
    );

    final animatedIcon = widget.pulse
        ? FadeTransition(opacity: _pulseAnimation, child: iconSurface)
        : iconSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            animatedIcon,
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: AppTheme.body.copyWith(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.supporting,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.postureLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                FluentIcons.contact,
                size: 16,
                color: context.elixTextSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.postureLabel!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
