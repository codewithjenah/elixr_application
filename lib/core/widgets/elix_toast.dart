import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../theme/app_theme.dart';

/// A single acknowledgement channel. ELIXR dismisses the active toast before
/// showing the next one instead of relying on replacement implementation.
abstract final class ElixToast {
  static void showSuccess(BuildContext context, {required String message}) {
    _show(context, title: 'Success', message: message, isError: false);
  }

  static void showError(BuildContext context, {required String message}) {
    _show(
      context,
      title: 'Something went wrong',
      message: message,
      isError: true,
    );
  }

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required bool isError,
  }) {
    final toaster = shad.ShadToaster.maybeOf(context);
    if (toaster == null) {
      displayInfoBar(
        context,
        builder: (_, _) => KeyedSubtree(
          key: const Key('elix_toast'),
          child: InfoBar(
            title: Text(title),
            content: Text(message),
            severity: isError ? InfoBarSeverity.error : InfoBarSeverity.success,
          ),
        ),
      );
      return;
    }
    toaster
        .hide(animate: false)
        .whenComplete(
          () => toaster.show(
            shad.ShadToast(
              key: const Key('elix_toast'),
              duration: const Duration(milliseconds: 3600),
              title: Text(title),
              description: Semantics(
                liveRegion: true,
                label: '$title: $message',
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
          ),
        );
  }
}
