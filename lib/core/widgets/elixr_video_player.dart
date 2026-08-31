import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player_win/video_player_win.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

/// Awaitable native-player release so Windows can delete the MP4 afterward.
class ElixrPlaybackSession {
  Future<void> Function()? _release;

  void attach(Future<void> Function() release) {
    _release = release;
  }

  Future<void> release() async {
    final release = _release;
    _release = null;
    if (release != null) {
      await release();
    }
  }
}

/// Windows in-app playback using Media Foundation via `video_player_win`.
///
/// Submission review playback must pass a local `file:` URI. Do not feed a
/// Firebase download URL into this widget.
class ElixrVideoPlayer extends StatefulWidget {
  const ElixrVideoPlayer({
    super.key,
    required this.source,
    this.autoPlay = false,
    this.mirrored = true,
    this.session,
  });

  final Uri source;
  final bool autoPlay;

  /// Submission clips are captured from the raw camera frame, while the live
  /// training feed is shown like a mirror. Keep review playback consistent
  /// with the trainee's live view by default.
  final bool mirrored;
  final ElixrPlaybackSession? session;

  @override
  State<ElixrVideoPlayer> createState() => _ElixrVideoPlayerState();
}

class _ElixrVideoPlayerState extends State<ElixrVideoPlayer> {
  WinVideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.session?.attach(_releaseNative);
    _open(widget.source);
  }

  @override
  void didUpdateWidget(ElixrVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.attach(() async {});
      widget.session?.attach(_releaseNative);
    }
    if (oldWidget.source != widget.source) {
      _open(widget.source);
    }
  }

  Future<void> _releaseNative() async {
    final controller = _controller;
    _controller = null;
    _ready = false;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _open(Uri source) async {
    await _releaseNative();
    _error = null;
    if (mounted) setState(() {});
    final next = source.isScheme('file') || source.scheme.isEmpty
        ? WinVideoPlayerController.file(File(source.toFilePath()))
        : WinVideoPlayerController.networkUrl(source);
    try {
      await next.initialize();
      if (widget.autoPlay) {
        await next.play();
      }
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _ready = true;
      });
    } catch (_) {
      await next.dispose();
      if (!mounted) return;
      setState(() {
        _error = 'This clip could not be played in-app.';
      });
    }
  }

  void _showFullscreen() {
    final controller = _controller;
    if (!mounted || controller == null) return;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black,
        builder: (dialogContext) => _FullscreenElixrVideoPlayer(
          controller: controller,
          mirrored: widget.mirrored,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.session?.attach(() async {});
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: AppColors.error),
        ),
      );
    }
    final controller = _controller;
    if (!_ready || controller == null) {
      return const Center(child: ProgressRing());
    }
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: Center(
              child: Transform.flip(
                key: const Key('elixr_video_inline_mirror'),
                flipX: widget.mirrored,
                child: WinVideoPlayer(controller),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ElixrVideoControls(
          controller: controller,
          onFullscreen: _showFullscreen,
        ),
      ],
    );
  }
}

class _ElixrVideoControls extends StatefulWidget {
  const _ElixrVideoControls({
    required this.controller,
    this.onFullscreen,
    this.isFullscreen = false,
  });

  final WinVideoPlayerController controller;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  @override
  State<_ElixrVideoControls> createState() => _ElixrVideoControlsState();
}

class _ElixrVideoControlsState extends State<_ElixrVideoControls> {
  int? _scrubPositionMs;
  bool _commandInFlight = false;

  @override
  void didUpdateWidget(covariant _ElixrVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _scrubPositionMs = null;
    }
  }

  Future<void> _togglePlayPause() async {
    if (_commandInFlight) return;
    _commandInFlight = true;
    try {
      final controller = widget.controller;
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.isCompleted) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } catch (_) {
      // The parent owns controller initialization and native disposal. A
      // stale click during teardown should not produce an unhandled future.
    } finally {
      if (mounted) {
        setState(() => _commandInFlight = false);
      } else {
        _commandInFlight = false;
      }
    }
  }

  Future<void> _seekTo(int milliseconds, int durationMs) async {
    final targetMs = milliseconds.clamp(0, durationMs).toInt();
    try {
      await widget.controller.seekTo(Duration(milliseconds: targetMs));
    } catch (_) {
      // The controller may be released while the user is scrubbing.
    } finally {
      if (mounted) setState(() => _scrubPositionMs = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WinVideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final maxMs = durationMs > 0 ? durationMs : 1;
        final positionMs = (_scrubPositionMs ?? value.position.inMilliseconds)
            .clamp(0, durationMs > 0 ? durationMs : 0)
            .toInt();
        final foreground = widget.isFullscreen
            ? Colors.white
            : context.elixTextPrimary;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              key: const Key('elixr_video_progress'),
              value: positionMs.toDouble(),
              min: 0,
              max: maxMs.toDouble(),
              label: _formatVideoDuration(Duration(milliseconds: positionMs)),
              onChanged: durationMs <= 0
                  ? null
                  : (next) {
                      setState(() => _scrubPositionMs = next.round());
                    },
              onChangeEnd: durationMs <= 0
                  ? null
                  : (next) => unawaited(_seekTo(next.round(), durationMs)),
            ),
            Row(
              children: [
                Tooltip(
                  message: value.isPlaying ? 'Pause' : 'Play',
                  child: IconButton(
                    key: const Key('elixr_video_play_pause'),
                    icon: Icon(
                      value.isPlaying ? FluentIcons.pause : FluentIcons.play,
                      color: foreground,
                    ),
                    onPressed: _commandInFlight
                        ? null
                        : () => unawaited(_togglePlayPause()),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${_formatVideoDuration(Duration(milliseconds: positionMs))} / '
                    '${_formatVideoDuration(value.duration)}',
                    style: AppTheme.caption.copyWith(color: foreground),
                  ),
                ),
                if (widget.onFullscreen != null)
                  Tooltip(
                    message: widget.isFullscreen
                        ? 'Exit fullscreen'
                        : 'Enlarge video',
                    child: IconButton(
                      key: Key(
                        widget.isFullscreen
                            ? 'elixr_video_exit_fullscreen'
                            : 'elixr_video_fullscreen',
                      ),
                      icon: Icon(
                        widget.isFullscreen
                            ? FluentIcons.back_to_window
                            : FluentIcons.full_screen,
                        color: foreground,
                      ),
                      onPressed: widget.onFullscreen,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FullscreenElixrVideoPlayer extends StatelessWidget {
  const _FullscreenElixrVideoPlayer({
    required this.controller,
    required this.mirrored,
    required this.onClose,
  });

  final WinVideoPlayerController controller;
  final bool mirrored;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Transform.flip(
                  key: const Key('elixr_video_fullscreen_mirror'),
                  flipX: mirrored,
                  child: WinVideoPlayer(controller),
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Tooltip(
                  message: 'Close fullscreen',
                  child: IconButton(
                    key: const Key('elixr_video_close_fullscreen'),
                    icon: const Icon(
                      FluentIcons.chrome_close,
                      color: Colors.white,
                    ),
                    style: const ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        Color(0x66000000),
                      ),
                    ),
                    onPressed: onClose,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: const Color(0xCC000000),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.xs,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: _ElixrVideoControls(
                      controller: controller,
                      isFullscreen: true,
                      onFullscreen: onClose,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatVideoDuration(Duration value) {
  final seconds = value.inSeconds;
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
