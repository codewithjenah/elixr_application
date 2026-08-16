import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../../data/models/coaching_verdict.dart';
import 'coaching_verdict_style.dart';

class FeedbackChip extends StatefulWidget {
  const FeedbackChip({
    super.key,
    required this.message,
    required this.verdict,
    this.feedbackType = 'warning',
  });

  final String message;
  final CoachingVerdict verdict;
  final String feedbackType;

  @override
  State<FeedbackChip> createState() => _FeedbackChipState();
}

class _FeedbackChipState extends State<FeedbackChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  Color get _color =>
      coachingVerdictColor(widget.verdict, feedbackType: widget.feedbackType);

  IconData get _icon => coachingVerdictIcon(widget.verdict);

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
