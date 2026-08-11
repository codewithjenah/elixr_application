import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/settings_service.dart';

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

  static const steps = <_OnboardingStep>[
    _OnboardingStep(
      title: 'Welcome to ELIXR',
      description:
          'Train flair bartending with real-time coaching that guides your form as you practice.',
      icon: FluentIcons.rocket,
    ),
    _OnboardingStep(
      title: 'Movements',
      description:
          'Browse the difficulty-tiered movement library — Easy, Medium, and Hard — and pick what to learn next.',
      icon: FluentIcons.exercise_tracker,
    ),
    _OnboardingStep(
      title: 'Live Practice',
      description:
          'Get real-time computer-vision feedback through your webcam during training sessions.',
      icon: FluentIcons.video,
    ),
    _OnboardingStep(
      title: 'Progress & Calendar',
      description:
          'Track movement mastery and daily practice consistency so you can see how far you have come.',
      icon: FluentIcons.calendar,
    ),
    _OnboardingStep(
      title: 'Leaderboard & Achievements',
      description:
          'Earn XP, unlock achievements, and compete with other flair bartenders.',
      icon: FluentIcons.trophy,
    ),
    _OnboardingStep(
      title: 'Settings',
      description:
          'Set up your camera and adjust appearance and accessibility options to fit how you train.',
      icon: FluentIcons.settings,
    ),
  ];

  /// Shows the onboarding dialog. Marks onboarding complete on Skip or Get Started.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
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
      final settings = context.read<SettingsService>();
      await settings.setHasSeenOnboarding(true);
      if (mounted) Navigator.of(context).pop();
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
            HyperlinkButton(
              onPressed: _closing ? null : _completeAndClose,
              child: Text(
                'Skip',
                style: TextStyle(color: context.elixTextSecondary),
              ),
            ),
            const Spacer(),
            Button(
              onPressed: (_stepIndex == 0 || _closing) ? null : _goBack,
              child: const Text('Back'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElixPrimaryButton(
              label: _isLastStep ? 'Get Started' : 'Next',
              expanded: false,
              onPressed: _closing ? null : _goNext,
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
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
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
