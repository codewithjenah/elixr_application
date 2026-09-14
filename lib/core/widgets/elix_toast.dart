import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../services/notification_audio_service.dart';
import '../theme/app_theme.dart';

/// A single acknowledgement channel. ELIXR dismisses the active toast before
/// showing the next one instead of relying on replacement implementation.
abstract final class ElixToast {
  static final Expando<_ShadToastPresenter> _shadPresenters =
      Expando<_ShadToastPresenter>();

  static void showSuccess(BuildContext context, {required String message}) {
    _show(
      context,
      title: 'Success',
      message: message,
      severity: InfoBarSeverity.success,
    );
  }

  static void showError(BuildContext context, {required String message}) {
    _show(
      context,
      title: 'Something went wrong',
      message: message,
      severity: InfoBarSeverity.error,
    );
  }

  static void showInfo(BuildContext context, {required String message}) {
    _show(
      context,
      title: 'Update',
      message: message,
      severity: InfoBarSeverity.info,
    );
  }

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required InfoBarSeverity severity,
  }) {
    NotificationAudioScope.maybeOf(context)?.playNotification();
    final toaster = shad.ShadToaster.maybeOf(context);
    if (toaster == null) {
      // The Fluent fallback also changes overlay state, so do not perform it
      // from a ChangeNotifier callback while Flutter is building a frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        displayInfoBar(
          context,
          builder: (_, _) => KeyedSubtree(
            key: const Key('elix_toast'),
            child: InfoBar(
              title: Text(title),
              content: Text(message),
              severity: severity,
            ),
          ),
        );
      });
      return;
    }
    final presenter = _shadPresenters[toaster] ?? _ShadToastPresenter();
    _shadPresenters[toaster] = presenter;
    presenter.request(
      toaster,
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
    );
  }
}

/// Defers toaster mutation until Flutter has completed the current frame.
/// A newer request invalidates both queued work and an older hide completion,
/// so rapid notifications always leave the most recent acknowledgement shown.
class _ShadToastPresenter {
  int _generation = 0;
  bool _frameCallbackScheduled = false;
  shad.ShadToast? _pendingToast;

  void request(shad.ShadToasterState toaster, shad.ShadToast toast) {
    _generation++;
    _pendingToast = toast;
    if (_frameCallbackScheduled) return;

    _frameCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameCallbackScheduled = false;
      final toastToPresent = _pendingToast;
      _pendingToast = null;
      if (toastToPresent == null || !toaster.mounted) return;

      final generation = _generation;
      toaster.hide(animate: false).whenComplete(() {
        if (!toaster.mounted || generation != _generation) return;
        toaster.show(toastToPresent);
      });
    });
  }
}
