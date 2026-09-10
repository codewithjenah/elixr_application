import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/coaching_verdict_style.dart';
import '../../../data/models/practice_feedback.dart';
import '../../../services/websocket_service.dart';
import '../camera_recovery_presentation.dart';
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
    this.onChooseCamera,
    this.onOpenSetupHelp,
    this.recoveryPresentation,
    this.errorMessage,
    this.sessionError,
    this.countdownActive = false,
    this.isPreparingCamera = false,
    this.accentBorder = false,
    this.readyAura = false,
    this.idleTitle = 'Training Arena',
    this.idleSubtitle =
        'Start from the session panel to activate the live feed.',
    this.idleCaption = 'Keep your upper body, hands, and bottle visible.',
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
  final VoidCallback? onChooseCamera;
  final VoidCallback? onOpenSetupHelp;
  final CameraRecoveryPresentation? recoveryPresentation;
  final String? errorMessage;
  final String? sessionError;
  final bool countdownActive;
  final bool isPreparingCamera;
  final bool accentBorder;
  final bool readyAura;
  final String idleTitle;
  final String idleSubtitle;
  final String idleCaption;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;
  final Widget? overlays;
  final List<TrainingCameraStatusItem> statusItems;

  static const _radius = AppSpacing.practiceSurfaceRadius;

  bool get _hasFatalOrConnectionError =>
      sessionError != null || connectionState == WebSocketConnectionState.error;

  Color _stageAccent(ElixSemanticColors colors) {
    if (_hasFatalOrConnectionError) return colors.error;
    if (readyAura) return colors.success;
    if (countdownActive || isSessionActive) return colors.brandPrimary;
    if (accentBorder || isPreparingCamera) return colors.brandSecondary;
    return colors.brandHover;
  }

  Border _viewportBorder(ElixSemanticColors colors) {
    final accent = _stageAccent(colors);
    if (_hasFatalOrConnectionError) {
      return Border.all(color: accent.withValues(alpha: 0.7), width: 1.5);
    }
    if (isSessionActive || readyAura || countdownActive) {
      return Border.all(color: accent.withValues(alpha: 0.55), width: 1.5);
    }
    if (accentBorder || isPreparingCamera) {
      return Border.all(color: accent.withValues(alpha: 0.45), width: 1.5);
    }
    return Border.all(
      color: colors.borderSubtle.withValues(alpha: 0.7),
      width: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final accent = _stageAccent(colors);
    final highContrast = context.isHighContrast;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Camera workspace',
      child: Container(
        key: const ValueKey('practice-camera-workspace'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: accent.withValues(
                      alpha: readyAura
                          ? 0.22
                          : (isSessionActive || countdownActive ? 0.16 : 0.1),
                    ),
                    blurRadius: readyAura ? 36 : 28,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.38),
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
              border: _viewportBorder(colors),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ArenaAmbientFill(accent: accent, highContrast: highContrast),
                  _buildBody(context),
                  const _ViewportVignette(),
                  _CornerGuides(color: accent),
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
              color: context.elixColors.textSecondary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Camera disconnected',
              style: ElixTypography.body(
                color: context.elixColors.textSecondary,
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
        placeholder: _buildWaitingOrIdlePlaceholder(context),
      );
    }

    return _buildFrameOrPlaceholder(context, frameBytes);
  }

  Widget _buildWaitingOrIdlePlaceholder(BuildContext context) {
    if (isPreparingCamera) {
      return _CenteredMessage(child: _LoadingState(title: 'Preparing camera'));
    }

    if (isSessionActive) {
      return _CenteredMessage(
        child: Text(
          'Waiting for camera frames…',
          style: ElixTypography.body(color: context.elixColors.textSecondary),
        ),
      );
    }

    if (connectionState == WebSocketConnectionState.connected) {
      return _CenteredMessage(
        child: _IdlePreviewState(
          title: idleTitle,
          subtitle: idleSubtitle,
          caption: idleCaption,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFrameOrPlaceholder(BuildContext context, Uint8List? bytes) {
    if (bytes != null) {
      return _MirroredCameraFeed(
        frameBytes: bytes,
        mirrored: mirrored,
        overlayFeedback: isSessionActive ? overlayFeedback : null,
        showFeedbackMessage: showFeedbackMessage,
      );
    }

    return _buildWaitingOrIdlePlaceholder(context);
  }

  Widget _buildErrorSurface(BuildContext context) {
    final recovery =
        recoveryPresentation ??
        CameraRecoveryPresentation.fromFailure(
          diagnosticMessage: sessionError ?? errorMessage,
          connectionFailed: connectionState == WebSocketConnectionState.error,
        );
    return ColoredBox(
      color: context.elixColors.canvasDeep.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.error, color: context.elixColors.error, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              recovery.title,
              style: ElixTypography.sectionTitle(
                context,
                color: context.elixColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              recovery.message,
              style: ElixTypography.body(
                color: context.elixColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (recovery.canRetry ||
                (recovery.canChooseCamera && onChooseCamera != null) ||
                (recovery.canOpenSetupHelp && onOpenSetupHelp != null)) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  if (recovery.canRetry)
                    ElixPrimaryButton(
                      label: 'Retry',
                      onPressed: connecting ? null : onRetry,
                      isLoading: connecting,
                      expanded: false,
                    ),
                  if (recovery.canChooseCamera && onChooseCamera != null)
                    Button(
                      onPressed: connecting ? null : onChooseCamera,
                      child: const Text('Choose camera'),
                    ),
                  if (recovery.canOpenSetupHelp && onOpenSetupHelp != null)
                    Button(
                      onPressed: onOpenSetupHelp,
                      child: const Text('Open setup help'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArenaAmbientFill extends StatelessWidget {
  const _ArenaAmbientFill({required this.accent, required this.highContrast});

  final Color accent;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    if (highContrast) {
      return ColoredBox(color: context.elixColors.canvasDeep);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 0.18),
          radius: 1.08,
          colors: [
            accent.withValues(alpha: 0.16),
            context.elixColors.glowSecondary.withValues(alpha: 0.08),
            context.elixColors.canvasDeep,
            context.elixColors.canvas,
          ],
          stops: const [0.0, 0.32, 0.7, 1.0],
        ),
      ),
    );
  }
}

class _IdlePreviewState extends StatelessWidget {
  const _IdlePreviewState({
    required this.title,
    required this.subtitle,
    required this.caption,
  });

  final String title;
  final String subtitle;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('training-arena-idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.elixColors.brandPrimary.withValues(alpha: 0.22),
                context.elixColors.brandSecondary.withValues(alpha: 0.16),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.elixColors.borderInteractive.withValues(
                alpha: 0.28,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: context.elixColors.glowPrimary.withValues(alpha: 0.18),
                blurRadius: 22,
              ),
            ],
          ),
          child: Icon(
            FluentIcons.video_solid,
            size: 30,
            color: context.elixColors.brandHover.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: ElixTypography.sectionTitle(
            context,
            color: context.elixColors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            subtitle,
            style: ElixTypography.body(
              color: context.elixColors.textPrimary.withValues(alpha: 0.9),
            ).copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            caption,
            style: ElixTypography.supporting(
              color: context.elixColors.textSecondary.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
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
        SizedBox(
          width: 32,
          height: 32,
          child: ProgressRing(
            strokeWidth: 3,
            activeColor: context.elixColors.brandPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: ElixTypography.body(
            color: context.elixColors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'This may take a moment…',
          style: ElixTypography.supporting(
            color: context.elixColors.textSecondary,
          ),
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
  const _CornerGuides({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: 12, left: 12, child: _bracket(Alignment.topLeft)),
          Positioned(top: 12, right: 12, child: _bracket(Alignment.topRight)),
          Positioned(
            bottom: 12,
            left: 12,
            child: _bracket(Alignment.bottomLeft),
          ),
          Positioned(
            bottom: 12,
            right: 12,
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
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _CornerBracketPainter(
          isTop: isTop,
          isLeft: isLeft,
          color: color,
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({
    required this.isTop,
    required this.isLeft,
    required this.color,
  });

  final bool isTop;
  final bool isLeft;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

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
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isTop != isTop ||
      oldDelegate.isLeft != isLeft;
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
                  color: context.elixColors.surfaceTinted.withValues(
                    alpha: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (item.color ?? context.elixColors.textSecondary)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  item.label,
                  style: ElixTypography.supporting(
                    color: item.color ?? context.elixColors.textSecondary,
                  ).copyWith(fontWeight: FontWeight.w600),
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
    required this.placeholder,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
  });

  final ValueListenable<Uint8List?> frameListenable;
  final bool mirrored;
  final Widget placeholder;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
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
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => placeholder,
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
    );
  }
}

class _MirroredCameraFeed extends StatelessWidget {
  const _MirroredCameraFeed({
    required this.frameBytes,
    required this.mirrored,
    this.overlayFeedback,
    this.showFeedbackMessage = true,
  });

  final Uint8List frameBytes;
  final bool mirrored;
  final PracticeFeedback? overlayFeedback;
  final bool showFeedbackMessage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Transform.flip(
          key: const ValueKey('camera-frame-transform'),
          flipX: mirrored,
          child: Image.memory(
            frameBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
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

  @override
  Widget build(BuildContext context) {
    final feedbackText = feedback.feedback.length > 80
        ? '${feedback.feedback.substring(0, 80)}…'
        : feedback.feedback;
    final presentation = CoachingVerdictPresentation.fromFeedback(feedback);
    final accent = presentation.tone(
      context,
      feedbackType: feedback.feedbackType,
    );

    return Semantics(
      label: presentation.semanticsLabel(feedbackText),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.isHighContrast
              ? presentation.surface(context)
              : context.elixColors.surfaceRaised.withValues(alpha: 0.9),
          border: Border(
            bottom: BorderSide(
              color: presentation.border(
                context,
                feedbackType: feedback.feedbackType,
              ),
              width: context.isHighContrast ? 2 : 1,
            ),
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
                            style:
                                ElixTypography.body(
                                  color: context.elixColors.brandPrimary,
                                ).copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
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
                              color: context.elixColors.surfaceInteractive
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: context.elixColors.borderInteractive
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              feedback.propType.displayLabel,
                              style: ElixTypography.supporting(
                                color: context.elixColors.textPrimary,
                              ).copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showFeedbackMessage) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(presentation.icon, size: 16, color: accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  presentation.label,
                                  style: ElixTypography.supporting(
                                    color: accent,
                                  ).copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (feedbackText.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    feedbackText,
                                    style:
                                        ElixTypography.supporting(
                                          color: context.elixTextPrimary,
                                        ).copyWith(
                                          height: 1.3,
                                          fontWeight: FontWeight.w500,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (presentation.observationTip != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    presentation.observationTip!,
                                    style: ElixTypography.supporting(
                                      color: context.elixTextSecondary,
                                    ).copyWith(height: 1.25),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
