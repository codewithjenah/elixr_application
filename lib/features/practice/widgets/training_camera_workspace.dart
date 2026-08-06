import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
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
    this.frameBytes,
    this.frameListenable,
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
    this.accentBorder = false,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
    this.overlays,
    this.statusItems = const [],
  });

  /// Static frame for tests / simple callers. Ignored when [frameListenable] is set.
  final Uint8List? frameBytes;

  /// High-frequency JPEG updates. Only the camera image rebuilds on changes.
  final ValueListenable<Uint8List?>? frameListenable;
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
  final bool accentBorder;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;
  final Widget? overlays;
  final List<TrainingCameraStatusItem> statusItems;

  static const _viewportColor = Color(0xFF0A0A0C);
  static const _frameAspectRatio = 640 / 480;
  static const _radius = AppSpacing.practiceSurfaceRadius;

  bool get _hasFatalOrConnectionError =>
      sessionError != null || connectionState == WebSocketConnectionState.error;

  Border? _viewportBorder() {
    if (_hasFatalOrConnectionError) {
      return Border.all(
        color: AppColors.error.withValues(alpha: 0.55),
        width: 1.5,
      );
    }
    if (isSessionActive) {
      return Border.all(
        color: AppColors.primary.withValues(alpha: 0.5),
        width: 1.5,
      );
    }
    if (accentBorder || isPreparingCamera) {
      return Border.all(
        color: AppColors.accent.withValues(alpha: 0.45),
        width: 1.5,
      );
    }
    return Border.all(
      color: const Color(0xFF2A2A32).withValues(alpha: 0.65),
      width: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Camera workspace',
      child: Container(
        key: const ValueKey('practice-camera-workspace'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              border: _viewportBorder(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius - 1),
              child: ColoredBox(
                color: _viewportColor,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildBody(context),
                    const _ViewportVignette(),
                    const _CornerGuides(),
                    ?overlays,
                    if (statusItems.isNotEmpty && !_hasFatalOrConnectionError)
                      Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: _StatusStrip(
                          items: statusItems.take(3).toList(),
                        ),
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
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (connecting || connectionState == WebSocketConnectionState.connecting) {
      return _CenteredMessage(
        child: _LoadingState(title: 'Connecting to camera'),
      );
    }

    if (connectionState == WebSocketConnectionState.disconnected) {
      return _CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.video_solid,
              size: 36,
              color: AppColors.textSecondary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Camera disconnected',
              style: AppTheme.bodySecondary.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final listenable = frameListenable;
    if (listenable != null) {
      return _CameraFeedSurface(
        frameListenable: listenable,
        mirrored: mirrored,
        overlayFeedback: isSessionActive ? overlayFeedback : null,
        showFeedbackMessage: showFeedbackMessage,
        aspectRatio: _frameAspectRatio,
        placeholder: _buildWaitingOrIdlePlaceholder(),
      );
    }

    return _buildFrameOrPlaceholder(frameBytes);
  }

  Widget _buildWaitingOrIdlePlaceholder() {
    if (isPreparingCamera) {
      return _CenteredMessage(child: _LoadingState(title: 'Preparing camera'));
    }

    if (isSessionActive) {
      return _CenteredMessage(
        child: Text(
          'Waiting for camera frames…',
          style: AppTheme.bodySecondary.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    if (connectionState == WebSocketConnectionState.connected) {
      return _CenteredMessage(child: _IdlePreviewState());
    }

    return const SizedBox.shrink();
  }

  Widget _buildFrameOrPlaceholder(Uint8List? bytes) {
    if (bytes != null) {
      return _MirroredCameraFeed(
        frameBytes: bytes,
        mirrored: mirrored,
        overlayFeedback: isSessionActive ? overlayFeedback : null,
        showFeedbackMessage: showFeedbackMessage,
        aspectRatio: _frameAspectRatio,
      );
    }

    return _buildWaitingOrIdlePlaceholder();
  }

  Widget _buildErrorSurface(BuildContext context) {
    final isFatal = sessionError != null;
    return ColoredBox(
      color: AppColors.background.withValues(alpha: 0.88),
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

class _IdlePreviewState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.18),
                AppColors.accent.withValues(alpha: 0.14),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.22),
            ),
          ),
          child: Icon(
            FluentIcons.video_solid,
            size: 28,
            color: AppColors.primarySoft.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Camera preview',
          style: AppTheme.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Begin calibration to activate the live feed.',
          style: AppTheme.bodySecondary.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Keep your upper body, hands, and bottle visible.',
          style: AppTheme.caption.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.85),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: ProgressRing(strokeWidth: 3, activeColor: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTheme.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This may take a moment…',
          style: AppTheme.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ViewportVignette extends StatelessWidget {
  const _ViewportVignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [
              const Color(0x00000000),
              const Color(0xFF000000).withValues(alpha: 0.18),
            ],
            stops: const [0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _CornerGuides extends StatelessWidget {
  const _CornerGuides();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: 10, left: 10, child: _bracket(Alignment.topLeft)),
          Positioned(top: 10, right: 10, child: _bracket(Alignment.topRight)),
          Positioned(
            bottom: 10,
            left: 10,
            child: _bracket(Alignment.bottomLeft),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: _bracket(Alignment.bottomRight),
          ),
        ],
      ),
    );
  }

  Widget _bracket(Alignment alignment) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _CornerBracketPainter(isTop: isTop, isLeft: isLeft),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({required this.isTop, required this.isLeft});

  final bool isTop;
  final bool isLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primarySoft.withValues(alpha: 0.28)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD9101018),
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

class _CameraFeedSurface extends StatelessWidget {
  const _CameraFeedSurface({
    required this.frameListenable,
    required this.mirrored,
    required this.aspectRatio,
    required this.placeholder,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
  });

  final ValueListenable<Uint8List?> frameListenable;
  final bool mirrored;
  final double aspectRatio;
  final Widget placeholder;
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
            ValueListenableBuilder<Uint8List?>(
              valueListenable: frameListenable,
              builder: (context, bytes, _) {
                if (bytes == null) {
                  return placeholder;
                }
                return Transform.flip(
                  key: const ValueKey('camera-frame-transform'),
                  flipX: mirrored,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                );
              },
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
        color: const Color(0xCC101018),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          feedback.movement,
                          style: AppTheme.body.copyWith(
                            fontSize: 14,
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
                        fontSize: 14,
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
