import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player_win/video_player_win.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

/// Windows in-app playback using Media Foundation via `video_player_win`.
class ElixrVideoPlayer extends StatefulWidget {
  const ElixrVideoPlayer({
    super.key,
    required this.source,
    this.autoPlay = false,
  });

  final Uri source;
  final bool autoPlay;

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
    _open(widget.source);
  }

  @override
  void didUpdateWidget(ElixrVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _open(widget.source);
    }
  }

  Future<void> _open(Uri source) async {
    await _controller?.dispose();
    _controller = null;
    _ready = false;
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

  @override
  void dispose() {
    _controller?.dispose();
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
            child: Center(child: WinVideoPlayer(controller)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            IconButton(
              icon: Icon(
                controller.value.isPlaying
                    ? FluentIcons.pause
                    : FluentIcons.play,
              ),
              onPressed: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
                setState(() {});
              },
            ),
            Expanded(
              child: Text(
                _format(controller.value.position),
                style: AppTheme.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _format(Duration value) {
    final seconds = value.inSeconds;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
