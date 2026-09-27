import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';

/// Native playback engine behind [ElixrVideoController].
enum ElixrVideoBackend {
  /// Media Foundation through `video_player_win` (the existing Windows path).
  windows,

  /// AVFoundation through the official `video_player` plugin (macOS).
  videoPlayer,
}

/// Platform-neutral playback state used by ELIXR's player UI.
@immutable
class ElixrVideoValue {
  const ElixrVideoValue({
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.size = Size.zero,
    this.isInitialized = false,
    this.isPlaying = false,
    this.isCompleted = false,
  });

  final Duration duration;
  final Duration position;
  final Size size;
  final bool isInitialized;
  final bool isPlaying;
  final bool isCompleted;
}

/// Application-owned adapter so screens never depend on a platform player.
///
/// Windows keeps `video_player_win` unchanged; every other host uses the
/// official `video_player` plugin, whose macOS implementation is AVFoundation.
abstract class ElixrVideoController
    implements ValueListenable<ElixrVideoValue> {
  factory ElixrVideoController.file(File file) {
    return switch (_backend()) {
      ElixrVideoBackend.windows => _WinElixrVideoController(
        WinVideoPlayerController.file(file),
      ),
      ElixrVideoBackend.videoPlayer => _PluginElixrVideoController(
        VideoPlayerController.file(file),
      ),
    };
  }

  factory ElixrVideoController.networkUrl(Uri uri) {
    return switch (_backend()) {
      ElixrVideoBackend.windows => _WinElixrVideoController(
        WinVideoPlayerController.networkUrl(uri),
      ),
      ElixrVideoBackend.videoPlayer => _PluginElixrVideoController(
        VideoPlayerController.networkUrl(uri),
      ),
    };
  }

  /// Forces a backend in tests; `null` selects by host platform.
  @visibleForTesting
  static ElixrVideoBackend? debugBackendOverride;

  static ElixrVideoBackend _backend() =>
      debugBackendOverride ??
      (Platform.isWindows
          ? ElixrVideoBackend.windows
          : ElixrVideoBackend.videoPlayer);

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// Releases the native player. Awaitable so callers can delete the file.
  Future<void> dispose();

  /// The texture-backed video surface for this controller.
  Widget buildSurface();
}

class _WinElixrVideoController implements ElixrVideoController {
  _WinElixrVideoController(this._inner);

  final WinVideoPlayerController _inner;

  @override
  ElixrVideoValue get value {
    final value = _inner.value;
    return ElixrVideoValue(
      duration: value.duration,
      position: value.position,
      size: value.size,
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isCompleted: value.isCompleted,
    );
  }

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Widget buildSurface() => WinVideoPlayer(_inner);
}

class _PluginElixrVideoController implements ElixrVideoController {
  _PluginElixrVideoController(this._inner);

  final VideoPlayerController _inner;

  @override
  ElixrVideoValue get value {
    final value = _inner.value;
    return ElixrVideoValue(
      duration: value.duration,
      position: value.position,
      size: value.size,
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isCompleted: value.isCompleted,
    );
  }

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Widget buildSurface() => VideoPlayer(_inner);
}
