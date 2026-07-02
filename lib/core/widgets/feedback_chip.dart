import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

class FeedbackChip extends StatefulWidget {
  const FeedbackChip({
    super.key,
    required this.message,
    required this.feedbackType,
  });

  final String message;
  final String feedbackType;

  @override
  State<FeedbackChip> createState() => _FeedbackChipState();
}

class _FeedbackChipState extends State<FeedbackChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  Color get _color {
    switch (widget.feedbackType) {
      case 'positive':
        return AppColors.success;
      case 'warning':
        return AppColors.warning;
      case 'error':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get _icon {
    switch (widget.feedbackType) {
      case 'positive':
        return FluentIcons.status_circle_checkmark;
      case 'warning':
        return FluentIcons.warning;
      case 'error':
        return FluentIcons.status_circle_error_x;
      default:
        return FluentIcons.info_solid;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_fade),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(_icon, color: _color, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.message,
                  style: AppTheme.body.copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
