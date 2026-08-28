import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/settings_service.dart';
import '../../services/tutorial_progress_service.dart';

class _OnboardingStep {
  const _OnboardingStep({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

/// First-launch tutorial carousel shown once after successful login/registration.
class OnboardingOverlay {
  const OnboardingOverlay._();

  static const stepDotsKey = ValueKey<String>('onboarding-step-dots');

  static const steps = <_OnboardingStep>[
    _OnboardingStep(
      title: 'Prepare your space',
      description:
          'Use a clear space and a safe practice prop. Keep people and breakable items out of the way.',
      icon: FluentIcons.shield,
    ),
    _OnboardingStep(
      title: 'Learn before the camera',
      description:
          'Choose a movement lesson first. It shows the prop, camera framing, steps, and common mistakes.',
      icon: FluentIcons.exercise_tracker,
    ),
    _OnboardingStep(
      title: 'Camera setup comes first',
      description:
          'ELIXR checks visibility only. Setup is not scored. After it is ready, a countdown leads into practice.',
      icon: FluentIcons.video,
    ),
    _OnboardingStep(
      title: 'Understand your score',
      description:
          'ELIXR scores Technique, Stability, Completion, and Prop Positioning from 0 to 3. A confirmed hold completes the movement.',
      icon: FluentIcons.trophy,
    ),
  ];

  /// Shows the onboarding dialog. Marks onboarding complete on Skip or Get Started.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      // Keep onboarding owned by the authenticated shell navigator. When the
      // shell is removed on logout, its modal route is removed with it instead
      // of lingering on the root navigator above the login page.
      useRootNavigator: false,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => const Center(child: _OnboardingOverlayBody()),
    );
  }
}

class _OnboardingOverlayBody extends StatefulWidget {
  const _OnboardingOverlayBody();

  @override
  State<_OnboardingOverlayBody> createState() => _OnboardingOverlayBodyState();
}

class _OnboardingOverlayBodyState extends State<_OnboardingOverlayBody> {
  int _stepIndex = 0;
  bool _closing = false;

  int get _stepCount => OnboardingOverlay.steps.length;
  bool get _isLastStep => _stepIndex >= _stepCount - 1;

  Future<void> _completeAndClose() async {
    if (_closing) return;
    _closing = true;
    try {
      final tutorial = context.read<TutorialProgressService>();
      final settings = context.read<SettingsService>();
      final navigator = Navigator.of(context);
      await tutorial.completeOnboarding();
      await settings.setHasSeenOnboarding(true);
      if (!mounted) return;
      navigator.pop();
    } finally {
      _closing = false;
    }
  }

  void _goBack() {
    if (_stepIndex <= 0 || _closing) return;
    setState(() => _stepIndex -= 1);
  }

  void _goNext() {
    if (_closing) return;
    if (_isLastStep) {
      _completeAndClose();
      return;
    }
    setState(() => _stepIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    final step = OnboardingOverlay.steps[_stepIndex];
    final progressLabel = '${_stepIndex + 1} of $_stepCount';
    // Keep secondary and primary actions visually balanced. The final label
    // needs more room, so both controls grow together on that step.
    final actionWidth = _isLastStep ? 180.0 : 112.0;

    return ElixDialog(
      title: step.title,
      subtitle: progressLabel,
      icon: step.icon,
      iconColor: AppColors.primary,
      maxWidth: 480,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.description,
            style: AppTheme.body.copyWith(
              fontSize: 14,
              color: context.elixTextSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _StepProgressDots(currentIndex: _stepIndex, count: _stepCount),
        ],
      ),
      actions: [
        Row(
          children: [
            const Spacer(),
            SizedBox(
              width: actionWidth,
              height: 56,
              child: Button(
                onPressed: (_stepIndex == 0 || _closing) ? null : _goBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: actionWidth,
              height: 56,
              child: ElixPrimaryButton(
                label: _isLastStep ? 'Go to Dashboard' : 'Next',
                expanded: false,
                onPressed: _closing ? null : _goNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepProgressDots extends StatelessWidget {
  const _StepProgressDots({required this.currentIndex, required this.count});

  final int currentIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: OnboardingOverlay.stepDotsKey,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
          AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.standard),
            curve: ElixMotion.standardCurve,
            width: i == currentIndex ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == currentIndex
                  ? AppColors.primary
                  : context.elixBorder.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    );
  }
}
