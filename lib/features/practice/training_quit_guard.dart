import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import 'just_dance/playground_session_controller.dart';
import 'practice_run_phase.dart';
import 'submission_recording_controller.dart';

/// Copy for the shared abandon-confirmation dialog.
class TrainingQuitCopy {
  const TrainingQuitCopy({
    required this.title,
    required this.body,
    required this.keepLabel,
    required this.quitLabel,
  });

  final String title;
  final String body;
  final String keepLabel;
  final String quitLabel;

  static const practice = TrainingQuitCopy(
    title: 'Quit training?',
    body:
        'Your current session will end and unsaved session progress will be lost.',
    keepLabel: 'Keep Training',
    quitLabel: 'Quit Session',
  );

  static const playground = TrainingQuitCopy(
    title: 'Quit Playground?',
    body:
        'Your current routine will end. This Playground run is not scored and '
        'will not be saved.',
    keepLabel: 'Keep Training',
    quitLabel: 'Quit Routine',
  );

  static const assignment = TrainingQuitCopy(
    title: 'Quit practice?',
    body:
        'Your current attempt will end and unsaved recording progress will be lost.',
    keepLabel: 'Keep Training',
    quitLabel: 'Quit Practice',
  );
}

/// True once camera preparation, readiness, countdown, an active session,
/// an in-progress Playground routine, or recording work has begun.
bool trainingShouldConfirmAbandon({
  required PracticeRunPhase runPhase,
  PlaygroundSessionPhase playgroundPhase = PlaygroundSessionPhase.idle,
  SubmissionRecordingPhase recordingPhase = SubmissionRecordingPhase.idle,
}) {
  if (_recordingHasWorkToLose(recordingPhase)) return true;
  if (_playgroundHasWorkToLose(playgroundPhase)) return true;
  return switch (runPhase) {
    PracticeRunPhase.preparingCamera ||
    PracticeRunPhase.readiness ||
    PracticeRunPhase.countdown ||
    PracticeRunPhase.active => true,
    PracticeRunPhase.idle ||
    PracticeRunPhase.completed ||
    PracticeRunPhase.error => false,
  };
}

bool _playgroundHasWorkToLose(PlaygroundSessionPhase phase) {
  return switch (phase) {
    PlaygroundSessionPhase.idle || PlaygroundSessionPhase.completed => false,
    PlaygroundSessionPhase.preparingMovement ||
    PlaygroundSessionPhase.getReady ||
    PlaygroundSessionPhase.assessing ||
    PlaygroundSessionPhase.success ||
    PlaygroundSessionPhase.missed ||
    PlaygroundSessionPhase.transitioning => true,
  };
}

bool _recordingHasWorkToLose(SubmissionRecordingPhase phase) {
  return switch (phase) {
    SubmissionRecordingPhase.idle ||
    SubmissionRecordingPhase.failed ||
    SubmissionRecordingPhase.attached ||
    SubmissionRecordingPhase.submitted => false,
    SubmissionRecordingPhase.consent ||
    SubmissionRecordingPhase.countdown ||
    SubmissionRecordingPhase.recording ||
    SubmissionRecordingPhase.preview ||
    SubmissionRecordingPhase.submitting => true,
  };
}

/// Premium Fluent confirmation. Returns true only when the user confirms quit.
Future<bool> showTrainingQuitDialog(
  BuildContext context, {
  required TrainingQuitCopy copy,
}) async {
  final confirmed = await ElixDialog.show<bool>(
    context,
    title: copy.title,
    icon: FluentIcons.warning,
    iconColor: AppColors.error,
    headerAccentColor: AppColors.error,
    barrierDismissible: true,
    maxWidth: 460,
    content: Text(
      copy.body,
      style: AppTheme.body.copyWith(
        fontSize: 14,
        color: context.elixTextSecondary,
        height: 1.45,
      ),
    ),
    actions: [_QuitConfirmActions(copy: copy)],
  );
  return confirmed == true;
}

class _QuitConfirmActions extends StatefulWidget {
  const _QuitConfirmActions({required this.copy});

  final TrainingQuitCopy copy;

  @override
  State<_QuitConfirmActions> createState() => _QuitConfirmActionsState();
}

class _QuitConfirmActionsState extends State<_QuitConfirmActions> {
  bool _busy = false;

  void _pop(bool value) {
    if (_busy) return;
    setState(() => _busy = true);
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('training-quit-dialog'),
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: Button(
              key: const ValueKey('training-quit-confirm'),
              onPressed: _busy ? null : () => _pop(true),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.isDisabled) {
                    return AppColors.error.withValues(alpha: 0.08);
                  }
                  if (states.isPressed) {
                    return AppColors.error.withValues(alpha: 0.22);
                  }
                  if (states.isHovered) {
                    return AppColors.error.withValues(alpha: 0.16);
                  }
                  return AppColors.error.withValues(alpha: 0.12);
                }),
                foregroundColor: WidgetStateProperty.all(AppColors.error),
              ),
              child: Text(widget.copy.quitLabel),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElixPrimaryButton(
              key: const ValueKey('training-quit-keep'),
              label: widget.copy.keepLabel,
              expanded: true,
              onPressed: _busy ? null : () => _pop(false),
            ),
          ),
        ),
      ],
    );
  }
}
