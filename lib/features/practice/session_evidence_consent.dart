import 'package:fluent_ui/fluent_ui.dart';

import '../../core/widgets/elix_dialog.dart';

/// First-use consent for retaining one private confirmed-movement image.
///
/// Shared by official Guided Practice and personal Custom Movement practice
/// so both ask with the same copy and record the same account preference.
Future<bool> askSessionEvidenceConsent(BuildContext context) {
  return ElixDialog.confirm(
    context,
    title: 'Save your confirmed movement?',
    icon: FluentIcons.camera,
    maxWidth: 500,
    barrierDismissible: false,
    uniformActionSize: const Size(198, 56),
    cancelLabel: 'Save without image',
    confirmLabel: 'Enable & save image',
    message:
        'We captured one annotated image from the exact frame that '
        'confirmed your movement. It is private to your account, never '
        'shared to profiles or leaderboards, and can be deleted anytime '
        'in Settings → Privacy.',
  );
}
