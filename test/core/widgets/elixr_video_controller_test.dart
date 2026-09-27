import 'dart:async';
import 'dart:io';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elixr_video_controller.dart';
import 'package:elixr_application/core/widgets/elixr_video_player.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Stands in for the macOS AVFoundation implementation of `video_player`.
class _FakeAvFoundationPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  int created = 0;
  int playCalls = 0;
  Duration? lastSeek;
  Duration position = Duration.zero;
  String? lastUri;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    lastUri = dataSource.uri;
    return _newPlayer();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    lastUri = options.dataSource.uri;
    return _newPlayer();
  }

  int _newPlayer() {
    final id = ++created;
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    controller.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 13),
        size: const Size(16, 9),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> play(int playerId) async => playCalls++;

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    lastSeek = position;
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Widget buildView(int playerId) => SizedBox(key: ValueKey('av-$playerId'));

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      buildView(options.playerId);

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await _events.remove(playerId)?.close();
  }
}

File _testClip() {
  final directory = Directory.systemTemp.createTempSync('elixr_av_test_');
  final file = File('${directory.path}${Platform.pathSeparator}clip.mp4');
  file.writeAsBytesSync([0]);
  addTearDown(() => directory.deleteSync(recursive: true));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform initialPlatform;
  late _FakeAvFoundationPlatform fake;

  setUp(() {
    initialPlatform = VideoPlayerPlatform.instance;
    fake = _FakeAvFoundationPlatform();
    VideoPlayerPlatform.instance = fake;
    ElixrVideoController.debugBackendOverride = ElixrVideoBackend.videoPlayer;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = initialPlatform;
    ElixrVideoController.debugBackendOverride = null;
  });

  test('macOS adapter reports duration for MP4 upload validation', () async {
    final controller = ElixrVideoController.file(_testClip());
    try {
      await controller.initialize();
      expect(controller.value.isInitialized, isTrue);
      expect(controller.value.duration, const Duration(seconds: 13));
      expect(controller.value.size, const Size(16, 9));
    } finally {
      await controller.dispose();
    }
    expect(fake.disposed, [1]);
  });

  testWidgets('ElixrVideoPlayer keeps its controls on the macOS player', (
    tester,
  ) async {
    final clip = _testClip();
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: SizedBox(height: 280, child: ElixrVideoPlayer(source: clip.uri)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(fake.lastUri, startsWith('file:'));
    expect(find.byKey(const ValueKey('av-1')), findsOneWidget);
    expect(find.byKey(const Key('elixr_video_play_pause')), findsOneWidget);
    expect(find.byKey(const Key('elixr_video_progress')), findsOneWidget);
    expect(find.byKey(const Key('elixr_video_fullscreen')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    // Native release is asynchronous; let the dispose chain complete.
    for (var i = 0; i < 5 && fake.disposed.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(fake.disposed, [1]);
  });
}
