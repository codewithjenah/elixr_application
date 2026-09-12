import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../theme/app_theme.dart';

/// A single acknowledgement channel. [ShadToaster.show] replaces the visible
/// toast, which preserves ELIXR's no-stack notification behaviour.
abstract final class ElixToast {
  static void showSuccess(BuildContext context, {required String message}) {
    final toaster = shad.ShadToaster.maybeOf(context);
    if (toaster == null) return;
    toaster.show(
      shad.ShadToast(
        key: const Key('elix_toast'),
        duration: const Duration(milliseconds: 3600),
        title: const Text('Success'),
        description: Semantics(
          liveRegion: true,
          label: 'Success: $message',
          child: Text(message, style: AppTheme.bodySecondary),
        ),
        closeIcon: Semantics(
          button: true,
          label: 'Dismiss notification',
          child: shad.ShadButton.ghost(
            key: const Key('elix_toast_close'),
            size: shad.ShadButtonSize.sm,
            onPressed: () => toaster.hide(),
            child: const Icon(FluentIcons.chrome_close, size: 14),
          ),
        ),
      ),
    );
  }
}
