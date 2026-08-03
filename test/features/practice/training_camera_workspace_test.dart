import 'dart:convert';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/widgets/training_camera_workspace.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _frameTransformKey = ValueKey<String>('camera-frame-transform');
const _propLabelKey = ValueKey<String>('frame-prop-label');
const _sidePanelKey = ValueKey<String>('practice-side-panel');

final _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

final _tinyPngAlt = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8BQDwAEhQGAhKmM'
    'IwAAAABJRU5ErkJggg==',
  ),
);

PracticeFeedback _feedback(TrainingProp prop, {String text = 'Good'}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    score: 80,
    feedback: text,
    feedbackType: 'positive',
    postureStatus: 'stable',
    propType: prop,
  );
}

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: child),
  );
}

Widget _workspace({
  required TrainingProp prop,
  required bool mirrored,
  Uint8List? frameBytes,
  ValueListenable<Uint8List?>? frameListenable,
  double width = 640,
  double height = 480,
  bool countdownActive = false,
  PracticeFeedback? overlayFeedback,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: TrainingCameraWorkspace(
      frameBytes: frameBytes,
      frameListenable: frameListenable,
      mirrored: mirrored,
      connectionState: WebSocketConnectionState.connected,
      connecting: false,
      isSessionActive: true,
      onRetry: () {},
      onCountdownComplete: () {},
      countdownActive: countdownActive,
      overlayFeedback: overlayFeedback ?? _feedback(prop),
    ),
  );
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required TrainingProp prop,
  required bool mirrored,
  double width = 640,
  double height = 480,
}) async {
  await tester.pumpWidget(
    _wrap(
      _workspace(
        prop: prop,
        mirrored: mirrored,
        width: width,
        height: height,
        frameBytes: _tinyPng,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RebuildProbe extends StatelessWidget {
  const _RebuildProbe({required this.label});

  final String label;

  static int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Text(label, key: _sidePanelKey);
  }
}

void main() {
  group('TrainingCameraWorkspace prop label', () {
    testWidgets('mirrored shaker label stays outside the flipped image', (
      tester,
    ) async {
      await _pumpWorkspace(tester, prop: TrainingProp.shaker, mirrored: true);

      expect(find.text('Cocktail Shaker'), findsOneWidget);
      final transformFinder = find.byKey(_frameTransformKey);
      expect(transformFinder, findsOneWidget);
      expect(
        find.descendant(of: transformFinder, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: transformFinder,
          matching: find.byKey(_propLabelKey),
        ),
        findsNothing,
      );

      final transform = tester.widget<Transform>(transformFinder);
      expect(transform.transform.storage[0], -1);
    });

    testWidgets('mirrored bottle label remains readable', (tester) async {
      await _pumpWorkspace(tester, prop: TrainingProp.bottle, mirrored: true);

      expect(find.text('Bottle'), findsOneWidget);
      expect(find.byKey(_propLabelKey), findsOneWidget);
    });

    testWidgets('unmirrored feed shows the same readable label', (
      tester,
    ) async {
      await _pumpWorkspace(tester, prop: TrainingProp.shaker, mirrored: false);

      expect(find.text('Cocktail Shaker'), findsOneWidget);
      final transform = tester.widget<Transform>(
        find.byKey(_frameTransformKey),
      );
      expect(transform.transform.storage[0], 1);
    });

    testWidgets('narrow viewport does not overflow the HUD', (tester) async {
      await tester.binding.setSurfaceSize(const Size(180, 180));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await _pumpWorkspace(
        tester,
        prop: TrainingProp.shaker,
        mirrored: true,
        width: 160,
        height: 120,
      );

      expect(find.text('Cocktail Shaker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('TrainingCameraWorkspace frame isolation', () {
    testWidgets('frame listenable updates the camera image', (tester) async {
      final frames = ValueNotifier<Uint8List?>(_tinyPng);
      addTearDown(frames.dispose);

      await tester.pumpWidget(
        _wrap(
          _workspace(
            prop: TrainingProp.bottle,
            mirrored: true,
            frameListenable: frames,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      frames.value = _tinyPngAlt;
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(_frameTransformKey), findsOneWidget);
    });

    testWidgets('frame-only updates do not rebuild side panel content', (
      tester,
    ) async {
      final frames = ValueNotifier<Uint8List?>(_tinyPng);
      addTearDown(frames.dispose);
      _RebuildProbe.buildCount = 0;

      await tester.pumpWidget(
        _wrap(
          Row(
            children: [
              Expanded(
                child: _workspace(
                  prop: TrainingProp.bottle,
                  mirrored: false,
                  frameListenable: frames,
                ),
              ),
              const SizedBox(
                width: 120,
                child: _RebuildProbe(label: 'Side panel'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final buildsAfterMount = _RebuildProbe.buildCount;
      expect(buildsAfterMount, greaterThan(0));

      frames.value = _tinyPngAlt;
      await tester.pump();
      frames.value = _tinyPng;
      await tester.pump();

      expect(_RebuildProbe.buildCount, buildsAfterMount);
      expect(find.byKey(_sidePanelKey), findsOneWidget);
    });

    testWidgets('countdown overlay remains visible over live frames', (
      tester,
    ) async {
      final frames = ValueNotifier<Uint8List?>(_tinyPng);
      addTearDown(frames.dispose);

      await tester.pumpWidget(
        _wrap(
          _workspace(
            prop: TrainingProp.bottle,
            mirrored: true,
            frameListenable: frames,
            countdownActive: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      // Countdown paints a large overlay numeral / progress surface.
      expect(find.byType(TrainingCameraWorkspace), findsOneWidget);
      frames.value = _tinyPngAlt;
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('feedback overlay text remains visible with mirroring', (
      tester,
    ) async {
      final frames = ValueNotifier<Uint8List?>(_tinyPng);
      addTearDown(frames.dispose);

      await tester.pumpWidget(
        _wrap(
          _workspace(
            prop: TrainingProp.shaker,
            mirrored: true,
            frameListenable: frames,
            overlayFeedback: _feedback(
              TrainingProp.shaker,
              text: 'Keep the shaker upright',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Keep the shaker upright'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsOneWidget);
      final transform = tester.widget<Transform>(
        find.byKey(_frameTransformKey),
      );
      expect(transform.transform.storage[0], -1);
    });
  });
}
