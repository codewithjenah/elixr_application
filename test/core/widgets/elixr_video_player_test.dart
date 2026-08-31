import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elixr_video_player.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:video_player_win/video_player_win_platform_interface.dart';

class _FakeVideoPlayerPlatform extends VideoPlayerWinPlatform {
  final players = <int, WinVideoPlayerController>{};
  int playCalls = 0;
  int pauseCalls = 0;
  int? lastSeekMs;

  @override
  Future<WinVideoPlayerValue?> openVideo(
    WinVideoPlayerController player,
    int textureId,
    String path,
    Map<String, String> httpHeaders,
  ) async {
    const textureIdForTest = 1;
    final value = WinVideoPlayerValue(
      textureId: textureIdForTest,
      duration: const Duration(seconds: 13),
      size: const Size(16, 9),
      isInitialized: true,
    );
    players[textureIdForTest] = player;
    return value;
  }

  @override
  Future<void> play(int textureId) async {
    playCalls++;
    final player = players[textureId];
    if (player != null) {
      player.value = player.value.copyWith(isPlaying: true);
    }
  }

  @override
  Future<void> pause(int textureId) async {
    pauseCalls++;
    final player = players[textureId];
    if (player != null) {
      player.value = player.value.copyWith(isPlaying: false);
    }
  }

  @override
  Future<void> seekTo(int textureId, int ms) async {
    lastSeekMs = ms;
    final player = players[textureId];
    if (player != null) {
      player.value = player.value.copyWith(
        position: Duration(milliseconds: ms),
      );
    }
  }

  @override
  Future<int> getCurrentPosition(int textureId) async {
    return players[textureId]?.value.position.inMilliseconds ?? 0;
  }

  @override
  Future<int?> getDuration(int textureId) async {
    return players[textureId]?.value.duration.inMilliseconds;
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> dispose(int textureId) async {
    players.remove(textureId);
  }

  @override
  void unregisterPlayer(int textureId) {
    players.remove(textureId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('video controls support playback, seeking, and fullscreen', (
    tester,
  ) async {
    final initialPlatform = VideoPlayerWinPlatform.instance;
    final fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerWinPlatform.instance = fakePlatform;
    addTearDown(() => VideoPlayerWinPlatform.instance = initialPlatform);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: SizedBox(
          height: 280,
          child: ElixrVideoPlayer(
            source: Uri(scheme: 'file', path: 'clip'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('elixr_video_progress')), findsOneWidget);
    expect(find.byKey(const Key('elixr_video_play_pause')), findsOneWidget);
    expect(find.byKey(const Key('elixr_video_fullscreen')), findsOneWidget);
    final inlineMirror = tester.widget<Transform>(
      find.byKey(const Key('elixr_video_inline_mirror')),
    );
    expect(inlineMirror.transform.storage[0], -1);

    await tester.tap(find.byKey(const Key('elixr_video_play_pause')));
    await tester.pump();
    expect(fakePlatform.playCalls, 1);

    final progress = find.byKey(const Key('elixr_video_progress'));
    await tester.tapAt(tester.getTopLeft(progress) + const Offset(80, 8));
    await tester.pump();
    expect(fakePlatform.lastSeekMs, isNotNull);

    await tester.tap(find.byKey(const Key('elixr_video_fullscreen')));
    await tester.pump();
    expect(
      find.byKey(const Key('elixr_video_exit_fullscreen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('elixr_video_close_fullscreen')),
      findsOneWidget,
    );
    final fullscreenMirror = tester.widget<Transform>(
      find.byKey(const Key('elixr_video_fullscreen_mirror')),
    );
    expect(fullscreenMirror.transform.storage[0], -1);

    await tester.tap(find.byKey(const Key('elixr_video_exit_fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('elixr_video_exit_fullscreen')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
