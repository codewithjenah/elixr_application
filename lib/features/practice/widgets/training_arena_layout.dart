import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';

/// Shared desktop training geometry for Movement Practice and Playground.
abstract final class TrainingArenaLayout {
  static const cameraAspectWidth = 640.0;
  static const cameraAspectHeight = 480.0;
  static const cameraAspectRatio = cameraAspectWidth / cameraAspectHeight;

  static double panelWidthForContent(double contentWidth) {
    return math.min(
      AppSpacing.practicePanelMaxWidth,
      math.max(AppSpacing.practicePanelMinWidth, contentWidth * 0.28),
    );
  }

  static Size desktopCameraSize({
    required double contentWidth,
    required double workspaceHeight,
  }) {
    final panelWidth = panelWidthForContent(contentWidth);
    final availableCameraWidth =
        contentWidth - panelWidth - AppSpacing.practiceCameraPanelGap;
    final cameraWidth = math.min(
      availableCameraWidth,
      workspaceHeight * cameraAspectWidth / cameraAspectHeight,
    );
    final cameraHeight = cameraWidth * cameraAspectHeight / cameraAspectWidth;
    return Size(cameraWidth, cameraHeight);
  }

  static Size stackedCameraSize(double contentWidth) {
    return Size(
      contentWidth,
      contentWidth * cameraAspectHeight / cameraAspectWidth,
    );
  }
}

/// Camera + coach-panel composition used by scored practice and Playground.
class TrainingArenaWorkspace extends StatelessWidget {
  const TrainingArenaWorkspace({
    super.key,
    required this.desktop,
    required this.contentWidth,
    required this.workspaceHeight,
    required this.camera,
    required this.panel,
  });

  final bool desktop;
  final double contentWidth;
  final double workspaceHeight;
  final Widget camera;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    if (!desktop) {
      final cameraSize = TrainingArenaLayout.stackedCameraSize(contentWidth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: cameraSize.width,
            height: cameraSize.height,
            child: camera,
          ),
          const SizedBox(height: AppSpacing.practiceCameraPanelGap),
          panel,
        ],
      );
    }

    final panelWidth = TrainingArenaLayout.panelWidthForContent(contentWidth);
    final cameraSize = TrainingArenaLayout.desktopCameraSize(
      contentWidth: contentWidth,
      workspaceHeight: workspaceHeight,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cameraSize.width,
            height: cameraSize.height,
            child: camera,
          ),
          const SizedBox(width: AppSpacing.practiceCameraPanelGap),
          SizedBox(width: panelWidth, height: cameraSize.height, child: panel),
        ],
      ),
    );
  }
}
