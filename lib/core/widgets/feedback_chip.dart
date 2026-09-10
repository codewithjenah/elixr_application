import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: ElixMotion.intro);
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
    final presentation = CoachingVerdictPresentation.forVerdict(widget.verdict);
    final color = presentation.tone(context, feedbackType: widget.feedbackType);
    final child = Semantics(
      label: presentation.semanticsLabel(widget.message),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.isHighContrast
              ? presentation.surface(context)
              : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: presentation.border(
              context,
              feedbackType: widget.feedbackType,
            ),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(presentation.icon, color: color, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.label,
                    style: AppTheme.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.message,
                    style: AppTheme.body.copyWith(
                      fontSize: 14,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  if (presentation.observationTip != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      presentation.observationTip!,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_fade),
        child: child,
      ),
    );
  }
}
