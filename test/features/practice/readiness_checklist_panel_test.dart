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
  status: ReadinessItemStatus.waiting,
  message: 'Waiting for camera frame',
);

const _ready = ReadinessItemView(
  code: 'bottle_detected',
  status: ReadinessItemStatus.ready,
  message: 'Bottle detected',
);

const _error = ReadinessItemView(
  code: 'grip_landmarks_visible',
  status: ReadinessItemStatus.error,
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
      expect(find.text('Setup Check'), findsOneWidget);
    });

    testWidgets('shows resolved title for camera_frame (Camera)', (
      tester,
    ) async {
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
      // 'Camera' is the resolved title for 'camera_frame'.
      expect(find.text('Camera'), findsOneWidget);
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
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Grip Hand'), findsOneWidget);
    });

    testWidgets('stable=true shows Ready badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_ready],
            progress: 1.0,
            stable: true,
            complete: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets('frozen=true shows locked header, no overlay dim', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_ready],
            progress: 1.0,
            stable: true,
            complete: true,
            frozen: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Setup Check — Ready'), findsOneWidget);
      // The item list should still be visible (no full-panel dim).
      expect(find.text('Bottle'), findsOneWidget);
    });

    testWidgets('streamStale=true shows stale warning', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_waiting],
            progress: 0,
            stable: false,
            streamStale: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('fresh camera reading'), findsOneWidget);
    });

    testWidgets('recoverableMessage is shown when not stale', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_waiting],
            progress: 0,
            stable: false,
            recoverableMessage: 'Readiness lost. Keep inputs visible.',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Readiness lost. Keep inputs visible.'), findsOneWidget);
    });

    testWidgets('stability bar hidden when not complete', (tester) async {
      // Not complete, progress > 0: bar should NOT appear.
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_waiting],
            progress: 0.5,
            stable: false,
            complete: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // The _StabilityBar is absent; N of M label appears instead.
      expect(find.text('0 of 1 ready'), findsOneWidget);
    });

    testWidgets('stability bar shown when complete and progress > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ReadinessChecklistPanel(
            items: [_ready],
            progress: 0.6,
            stable: false,
            complete: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // No "N of M ready" line when complete.
      expect(find.text('1 of 1 ready'), findsNothing);
    });

    testWidgets('unknown code falls back to humanized title', (tester) async {
      const unknownItem = ReadinessItemView(
        code: 'custom_xyz_check',
        status: ReadinessItemStatus.waiting,
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
      // Humanized title: 'Custom Xyz Check'
      expect(find.text('Custom Xyz Check'), findsOneWidget);
      // Instruction is the backend message (different from title).
      expect(find.text('Custom check in progress'), findsOneWidget);
    });
  });
}
