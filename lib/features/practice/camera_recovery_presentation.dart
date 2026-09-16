import 'package:fluent_ui/fluent_ui.dart';

import '../../core/widgets/elix_dialog.dart';
import '../../data/models/ws_protocol.dart';

/// One-time trainee copy derived only from an accepted prepare acknowledgement.
String? cameraFallbackWarningMessage(CommandAck ack) {
  if (!ack.accepted ||
      ack.action != 'prepare' ||
      !ack.selectedCameraFallbackUsed) {
    return null;
  }

  final activeName = ack.activeCameraDisplayName?.trim();
  final displayName = activeName == null || activeName.isEmpty
      ? 'another available camera'
      : activeName;
  return 'Selected camera is unavailable. Using $displayName for this session.';
}

class CameraFallbackWarningTracker {
  String? _shownRequestId;

  String? takeMessage(CommandAck ack) {
    final message = cameraFallbackWarningMessage(ack);
    if (message == null || _shownRequestId == ack.requestId) return null;
    _shownRequestId = ack.requestId;
    return message;
  }
}

/// Trainee-facing copy and actions for an interrupted camera attempt.
///
/// Keep protocol diagnostics out of the viewport. Callers retain the raw code
/// in their existing debug paths and provide it here only for classification.
class CameraRecoveryPresentation {
  const CameraRecoveryPresentation({
    required this.title,
    required this.message,
    this.canRetry = true,
    this.canChooseCamera = false,
    this.canOpenSetupHelp = true,
  });

  final String title;
  final String message;
  final bool canRetry;
  final bool canChooseCamera;
  final bool canOpenSetupHelp;

  factory CameraRecoveryPresentation.fromFailure({
    String? errorCode,
    String? diagnosticMessage,
    required bool connectionFailed,
  }) {
    switch (errorCode) {
      case 'selected_camera_unavailable':
        return const CameraRecoveryPresentation(
          title: 'Selected camera unavailable',
          message:
              "ELIXR can't find the camera you selected. Reconnect it, then try again, or choose another camera.",
          canChooseCamera: true,
        );
      case 'camera_unavailable':
        return const CameraRecoveryPresentation(
          title: 'No usable camera',
          message:
              "ELIXR couldn't start a usable camera. Check the camera connection, then try again or choose another camera.",
          canChooseCamera: true,
        );
      case 'prepare_timeout':
        return const CameraRecoveryPresentation(
          title: 'Camera preparation timed out',
          message:
              "The camera took too long to start. Check that another app isn't using it, then try again.",
        );
      case 'readiness_not_stable':
      case 'readiness_stale':
        return const CameraRecoveryPresentation(
          title: 'Camera setup needs attention',
          message:
              'ELIXR could not finish camera setup. Keep your upper body, hands, and bottle visible, then try again.',
        );
    }
    if (connectionFailed) {
      return const CameraRecoveryPresentation(
        title: 'Camera service unavailable',
        message:
            "ELIXR couldn't start the camera service. Retry the connection before starting practice.",
        canOpenSetupHelp: false,
      );
    }
    return const CameraRecoveryPresentation(
      title: 'Camera session interrupted',
      message:
          'ELIXR could not continue this camera session. Try again to start a fresh practice attempt.',
    );
  }
}

Future<void> showCameraRecoverySetupHelp(BuildContext context) {
  return ElixDialog.alert(
    context,
    title: 'Camera setup help',
    message:
        'Reconnect the camera, make sure Windows allows camera access, and close any other app using it. Then confirm the intended camera in Settings and retry.',
    icon: FluentIcons.camera,
    actionLabel: 'Close',
  );
}
