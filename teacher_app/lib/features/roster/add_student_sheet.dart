import 'package:flutter/material.dart';

import '../../core/theme/teacher_theme.dart';
import 'roster_controller.dart';

class AddStudentSheet extends StatelessWidget {
  const AddStudentSheet({super.key, required this.controller});

  final RosterController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  controller.addStudentStep == AddStudentStep.enterCode
                      ? 'Add student'
                      : 'Confirm request',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (controller.addStudentStep == AddStudentStep.enterCode)
                  _CodeStep(controller: controller)
                else
                  _ConfirmStep(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CodeStep extends StatelessWidget {
  const _CodeStep({required this.controller});

  final RosterController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the coach code shared by the Trainee.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: TeacherColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('add_student_code_field'),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Coach code'),
          onChanged: controller.setCodeInput,
        ),
        if (controller.addStudentError != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.addStudentError!,
            key: const Key('add_student_error'),
            style: const TextStyle(color: TeacherColors.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('add_student_continue'),
          onPressed: controller.busy ? null : controller.resolveEnteredCode,
          child: controller.busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.controller});

  final RosterController controller;

  @override
  Widget build(BuildContext context) {
    final invite = controller.resolvedInvite;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Send a link request to this Trainee? They must approve before '
          'appearing on your roster. Training data is not shared yet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: TeacherColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          invite?.traineeDisplayName ?? '',
          key: const Key('add_student_confirm_name'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (controller.addStudentError != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.addStudentError!,
            key: const Key('add_student_error'),
            style: const TextStyle(color: TeacherColors.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('add_student_confirm'),
          onPressed: controller.busy
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final ok = await controller.confirmRequest();
                  if (ok && navigator.mounted) navigator.pop();
                },
          child: const Text('Send request'),
        ),
        TextButton(
          onPressed: controller.resetAddStudent,
          child: const Text('Use a different code'),
        ),
      ],
    );
  }
}
