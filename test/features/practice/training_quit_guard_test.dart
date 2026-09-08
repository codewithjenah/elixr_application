import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/practice/just_dance/playground_session_controller.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/features/practice/submission_recording_controller.dart';
import 'package:elixr_application/features/practice/training_quit_guard.dart';
import 'package:elixr_application/features/practice/widgets/training_action_area.dart';
import 'package:elixr_application/features/practice/widgets/training_arena_layout.dart';
import 'package:elixr_application/features/practice/widgets/training_camera_workspace.dart';
import 'package:elixr_application/features/practice/widgets/training_session_panel.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: child),
  );
}

void main() {
  test('abandon confirmation matches in-progress work, not idle/finish', () {
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.idle),
      isFalse,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.completed),
      isFalse,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.error),
      isFalse,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.preparingCamera),
      isTrue,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.readiness),
      isTrue,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.countdown),
      isTrue,
    );
    expect(
      trainingShouldConfirmAbandon(runPhase: PracticeRunPhase.active),
      isTrue,
    );
    expect(
      trainingShouldConfirmAbandon(
        runPhase: PracticeRunPhase.idle,
        playgroundPhase: PlaygroundSessionPhase.assessing,
      ),
      isTrue,
    );
    expect(
      trainingShouldConfirmAbandon(
        runPhase: PracticeRunPhase.idle,
        playgroundPhase: PlaygroundSessionPhase.completed,
      ),
      isFalse,
    );
    expect(
      trainingShouldConfirmAbandon(
        runPhase: PracticeRunPhase.idle,
        recordingPhase: SubmissionRecordingPhase.recording,
      ),
      isTrue,
    );
  });

  testWidgets('quit dialog keep and dismiss leave the session untouched', (
    tester,
  ) async {
    var confirmed = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Builder(
            builder: (context) {
              return Button(
                child: const Text('Open quit'),
                onPressed: () async {
                  confirmed = await showTrainingQuitDialog(
                    context,
                    copy: TrainingQuitCopy.practice,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open quit'));
    await tester.pumpAndSettle();
    expect(find.text('Quit training?'), findsOneWidget);
    expect(
      find.text(
        'Your current session will end and unsaved session progress will be lost.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('training-quit-keep')));
    await tester.pumpAndSettle();
    expect(find.text('Quit training?'), findsNothing);
    expect(confirmed, isFalse);
  });

  testWidgets('quit confirm returns true once', (tester) async {
    var confirmedCount = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Builder(
            builder: (context) {
              return Button(
                child: const Text('Open quit'),
                onPressed: () async {
                  if (await showTrainingQuitDialog(
                    context,
                    copy: TrainingQuitCopy.practice,
                  )) {
                    confirmedCount += 1;
                  }
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open quit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('training-quit-confirm')));
    await tester.pumpAndSettle();
    expect(confirmedCount, 1);
    expect(find.text('Quit training?'), findsNothing);
  });

  testWidgets('Finish Session is not the quit dialog', (tester) async {
    var finishCalls = 0;
    await tester.pumpWidget(
      _wrap(
        TrainingActionArea(
          kind: TrainingActionKind.finish,
          startLabel: 'Start Camera Setup',
          onPressed: () => finishCalls += 1,
        ),
      ),
    );
    await tester.tap(find.text('Finish Session'));
    await tester.pump();
    expect(finishCalls, 1);
    expect(find.text('Quit training?'), findsNothing);
  });

  testWidgets('1366 and 1920 arena layouts preserve 4:3 and do not overflow', (
    tester,
  ) async {
    Future<void> pumpAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: size.width,
            height: size.height,
            child: TrainingArenaWorkspace(
              desktop: size.width >= AppSpacing.practiceDesktopBreakpoint,
              contentWidth: size.width,
              workspaceHeight: size.height - 80,
              camera: TrainingCameraWorkspace(
                mirrored: false,
                connectionState: WebSocketConnectionState.connected,
                connecting: false,
                isSessionActive: false,
                onRetry: () {},
                onCountdownComplete: () {},
              ),
              panel: TrainingSessionPanel(
                phase: TrainingSessionPhase.ready,
                expandVertically: false,
                metrics: const TrainingReadyBrief(
                  title: 'Ready to train',
                  body: 'Start Camera Setup to begin.',
                ),
                statusContent: const SizedBox.shrink(),
                actionArea: TrainingActionArea(
                  kind: TrainingActionKind.start,
                  startLabel: 'Start Camera Setup',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
      await pumpAt(size);
      expect(tester.takeException(), isNull);
      final camera = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('practice-camera-workspace')),
      );
      expect(
        camera.size.aspectRatio,
        closeTo(TrainingArenaLayout.cameraAspectRatio, 0.02),
      );
      expect(find.text('Training Arena'), findsOneWidget);
      expect(find.text('Start Camera Setup'), findsOneWidget);
    }
  });

  testWidgets(
    'stacked arena below desktop breakpoint shrink-wraps without flex overflow',
    (tester) async {
      const size = Size(1024, 768);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: size.width,
            height: size.height,
            child: SingleChildScrollView(
              child: TrainingArenaWorkspace(
                desktop: false,
                contentWidth: size.width,
                workspaceHeight: size.height - 80,
                camera: TrainingCameraWorkspace(
                  mirrored: false,
                  connectionState: WebSocketConnectionState.connected,
                  connecting: false,
                  isSessionActive: false,
                  onRetry: () {},
                  onCountdownComplete: () {},
                ),
                panel: TrainingSessionPanel(
                  phase: TrainingSessionPhase.ready,
                  expandVertically: false,
                  metrics: const TrainingReadyBrief(
                    title: 'Ready to train',
                    body: 'Start Camera Setup to begin.',
                  ),
                  statusContent: const SizedBox.shrink(),
                  actionArea: TrainingActionArea(
                    kind: TrainingActionKind.start,
                    startLabel: 'Start Camera Setup',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Training Arena'), findsOneWidget);
      expect(find.text('Start Camera Setup'), findsOneWidget);
    },
  );
}
