import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/teacher_theme.dart';
import 'roster_controller.dart';

/// Teacher-owned invite surface. The historical filename is retained to avoid
/// a noisy file move; Teachers no longer enter Trainee codes here.
class AddStudentSheet extends StatelessWidget {
  const AddStudentSheet({super.key, required this.controller});

  final RosterController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final invite = controller.invite;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Invite students',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'Students enter this durable roster code or open the join '
                  'link. You approve each incoming request.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TeacherColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (invite == null)
                  FilledButton.icon(
                    key: const Key('roster_generate_invite'),
                    onPressed: controller.busy
                        ? null
                        : controller.generateOrRotateInvite,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Generate roster code'),
                  )
                else ...[
                  Center(
                    child: QrImageView(
                      key: const Key('roster_invite_qr'),
                      data: invite.joinUri.toString(),
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    invite.displayCode,
                    key: const Key('roster_invite_code'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    invite.joinUri.toString(),
                    key: const Key('roster_invite_uri'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('roster_copy_code'),
                        onPressed: () => _copy(
                          context,
                          invite.displayCode,
                          'Roster code copied',
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy code'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('roster_copy_uri'),
                        onPressed: () => _copy(
                          context,
                          invite.joinUri.toString(),
                          'Join link copied',
                        ),
                        icon: const Icon(Icons.link),
                        label: const Text('Copy link'),
                      ),
                      OutlinedButton(
                        key: const Key('roster_rotate_invite'),
                        onPressed: controller.busy
                            ? null
                            : () => _confirmRotate(context),
                        child: const Text('Rotate'),
                      ),
                      TextButton(
                        key: const Key('roster_revoke_invite'),
                        onPressed: controller.busy
                            ? null
                            : controller.revokeInvite,
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmRotate(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rotate roster code?'),
        content: const Text(
          'Rotation immediately invalidates the previous code and QR link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.generateOrRotateInvite();
  }
}
