import 'dart:convert';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/widgets/training_camera_workspace.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _frameTransformKey = ValueKey<String>('camera-frame-transform');
const _propLabelKey = ValueKey<String>('frame-prop-label');

final _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

PracticeFeedback _feedback(TrainingProp prop) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    score: 80,
    feedback: 'Good',
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
  double width = 640,
  double height = 480,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: TrainingCameraWorkspace(
      frameBytes: _tinyPng,
      mirrored: mirrored,
      connectionState: WebSocketConnectionState.connected,
      connecting: false,
      isSessionActive: true,
      onRetry: () {},
      onCountdownComplete: () {},
      overlayFeedback: _feedback(prop),
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
      _workspace(prop: prop, mirrored: mirrored, width: width, height: height),
    ),
  );
  await tester.pumpAndSettle();
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
}
