import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../data/models/practice_feedback.dart';
import '../../../services/websocket_service.dart';
import '../practice_game_widgets.dart';

class TrainingCameraStatusItem {
  const TrainingCameraStatusItem({required this.label, this.color});

  final String label;
  final Color? color;
}

/// Shared camera surface for scored and Free Practice sessions.
class TrainingCameraWorkspace extends StatelessWidget {
  const TrainingCameraWorkspace({
    super.key,
    required this.frameBytes,
    required this.mirrored,
    required this.connectionState,
    required this.connecting,
    required this.isSessionActive,
    required this.onRetry,
    required this.onCountdownComplete,
    this.errorMessage,
    this.sessionError,
    this.countdownActive = false,
    this.isPreparingCamera = false,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
    this.overlays,
    this.statusItems = const [],
  });

  final Uint8List? frameBytes;
  final bool mirrored;
  final WebSocketConnectionState connectionState;
  final bool connecting;
  final bool isSessionActive;
  final VoidCallback onRetry;
  final VoidCallback onCountdownComplete;
  final String? errorMessage;
  final String? sessionError;
  final bool countdownActive;
  final bool isPreparingCamera;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;
  final Widget? overlays;
  final List<TrainingCameraStatusItem> statusItems;

  static const _viewportColor = Color(0xFF0A0A0C);
  static const _frameAspectRatio = 640 / 480;

  bool get _hasFatalOrConnectionError =>
      sessionError != null || connectionState == WebSocketConnectionState.error;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isSessionActive
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  width: 1.5,
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: _viewportColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBody(context),
                ?overlays,
                if (statusItems.isNotEmpty && !_hasFatalOrConnectionError)
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: _StatusStrip(items: statusItems.take(3).toList()),
                  ),
                if (countdownActive)
                  Positioned.fill(
                    child: GameCountdownOverlay(
                      onComplete: onCountdownComplete,
                    ),
                  ),
                if (_hasFatalOrConnectionError) _buildErrorSurface(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Precedence: fatal/connection error handled as overlay; then connecting,
    // disconnected, running/waiting, idle.
    if (connecting || connectionState == WebSocketConnectionState.connecting) {
      return _CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: ProgressRing(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Connecting to camera…', style: AppTheme.bodySecondary),
          ],
        ),
      );
    }

    if (connectionState == WebSocketConnectionState.disconnected) {
      return _CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.video_solid,
              size: 40,
              color: AppColors.textSecondary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Camera disconnected', style: AppTheme.bodySecondary),
          ],
        ),
      );
    }

    if (frameBytes != null) {
      return _MirroredCameraFeed(
        frameBytes: frameBytes!,
        mirrored: mirrored,
        overlayFeedback: isSessionActive ? overlayFeedback : null,
        showFeedbackMessage: showFeedbackMessage,
        aspectRatio: _frameAspectRatio,
      );
    }

    if (isPreparingCamera || isSessionActive) {
      return _CenteredMessage(
        child: Text(
          isPreparingCamera
              ? 'Preparing camera…'
              : 'Waiting for camera frames…',
          style: AppTheme.bodySecondary,
        ),
      );
    }

    if (connectionState == WebSocketConnectionState.connected) {
      return _CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardSurface.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.video_solid,
                size: 40,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Camera preview will appear here.',
              style: AppTheme.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Keep your upper body, hands, and bottle visible.',
              style: AppTheme.caption.copyWith(
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorSurface(BuildContext context) {
    final isFatal = sessionError != null;
    return ColoredBox(
      color: AppColors.background.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFatal ? FluentIcons.error : FluentIcons.warning,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isFatal ? 'Session error' : 'Connection error',
              style: AppTheme.headingMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              sessionError ?? errorMessage ?? 'Connection error',
              style: AppTheme.body,
              textAlign: TextAlign.center,
            ),
            if (connectionState == WebSocketConnectionState.error) ...[
              const SizedBox(height: AppSpacing.lg),
              ElixPrimaryButton(
                label: 'Retry',
                onPressed: connecting ? null : onRetry,
                isLoading: connecting,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(child: child);
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.items});

  final List<TrainingCameraStatusItem> items;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC101018),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (item.color ?? AppColors.textSecondary).withValues(
                      alpha: 0.35,
                    ),
                  ),
                ),
                child: Text(
                  item.label,
                  style: AppTheme.caption.copyWith(
                    color: item.color ?? AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MirroredCameraFeed extends StatelessWidget {
  const _MirroredCameraFeed({
    required this.frameBytes,
    required this.mirrored,
    required this.aspectRatio,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
  });

  final Uint8List frameBytes;
  final bool mirrored;
  final double aspectRatio;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.flip(
              key: const ValueKey('camera-frame-transform'),
              flipX: mirrored,
              child: Image.memory(
                frameBytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            if (overlayFeedback != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _FrameHudOverlay(
                  feedback: overlayFeedback!,
                  showFeedbackMessage: showFeedbackMessage,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FrameHudOverlay extends StatelessWidget {
  const _FrameHudOverlay({
    required this.feedback,
    this.showFeedbackMessage = true,
  });

  final PracticeFeedback feedback;
  final bool showFeedbackMessage;

  Color _feedbackColor() {
    switch (feedback.feedbackType) {
      case 'positive':
        return AppColors.success;
      case 'warning':
        return AppColors.warning;
      case 'error':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackText = feedback.feedback.length > 80
        ? '${feedback.feedback.substring(0, 80)}…'
        : feedback.feedback;
    final accent = _feedbackColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6101018), Color(0xCC0A0A0F)],
        ),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          feedback.movement,
                          style: AppTheme.body.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Container(
                          key: const ValueKey('frame-prop-label'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x33101018),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            feedback.propType.displayLabel,
                            style: AppTheme.caption.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showFeedbackMessage) ...[
                    const SizedBox(height: 4),
                    Text(
                      feedbackText,
                      style: AppTheme.body.copyWith(
                        fontSize: 15,
                        height: 1.3,
                        color: accent,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
