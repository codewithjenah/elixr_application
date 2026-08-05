import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/widgets/readiness_checklist_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: SizedBox(width: 360, child: child)),
  );
}

const _waiting = ReadinessItemView(
  code: 'camera_frame',
  status: 'waiting',
  message: 'Waiting for camera frame',
);

const _ready = ReadinessItemView(
  code: 'bottle_detected',
  status: 'ready',
  message: 'Bottle detected',
);

const _error = ReadinessItemView(
  code: 'grip_landmarks_visible',
  status: 'error',
  message: 'Grip landmarks not visible',
);

void main() {
  group('ReadinessChecklistPanel', () {
    testWidgets('pumps with empty items', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(items: [], progress: 0, stable: false),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Readiness Check'), findsOneWidget);
    });

    testWidgets('shows resolved title for known code', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_waiting],
            progress: 0.3,
            stable: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // 'Camera Frame' is the resolved title for 'camera_frame'.
      expect(find.text('Camera Frame'), findsOneWidget);
    });

    testWidgets('shows three items with mixed statuses', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_waiting, _ready, _error],
            progress: 0.5,
            stable: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Camera Frame'), findsOneWidget);
      expect(find.text('Bottle Detected'), findsOneWidget);
      expect(find.text('Grip Landmarks'), findsOneWidget);
    });

    testWidgets('stable=true shows Ready badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_ready],
            progress: 1.0,
            stable: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets('frozen=true dims content and shows starting message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_ready],
            progress: 1.0,
            stable: true,
            frozen: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ready — starting…'), findsOneWidget);
    });

    testWidgets('unknown code falls back to backend message as title', (
      tester,
    ) async {
      const unknownItem = ReadinessItemView(
        code: 'custom_xyz_check',
        status: 'waiting',
        message: 'Custom check in progress',
      );
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [unknownItem],
            progress: 0,
            stable: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Unknown code: title and instruction fall back to the backend message.
      expect(find.text('Custom check in progress'), findsWidgets);
    });
  });
}
