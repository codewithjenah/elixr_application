import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/locked_movement_mark.dart';
import 'package:elixr_application/features/profile/widgets/completed_movements_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _completedNames = [
  'Normal Grip',
  "Bartender's Grip",
  'Reverse Grip',
  'Hand Stall',
];

Future<void> _pumpSection(
  WidgetTester tester, {
  required CompletedMovementsIdentityPolicy identityPolicy,
  int? viewerLevel,
  List<String> movementNames = _completedNames,
}) async {
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: CompletedMovementsSection(
          movementNames: movementNames,
          identityPolicy: identityPolicy,
          viewerLevel: viewerLevel,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'shows current completed movements and hides retired movement names',
    (tester) async {
      await _pumpSection(
        tester,
        identityPolicy: CompletedMovementsIdentityPolicy.authorizedFull,
        movementNames: const [
          'Tap',
          'Clip',
          'Arm Stall',
          'Hand Stall',
          'Hand Stall',
        ],
      );

      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('Tap'), findsNothing);
      expect(find.text('Clip'), findsNothing);
      expect(find.text('Arm Stall'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('No completed movements yet.'), findsNothing);
    },
  );

  testWidgets(
    'viewer sees only personally revealed completed movement identities',
    (tester) async {
      await _pumpSection(
        tester,
        identityPolicy: CompletedMovementsIdentityPolicy.viewerRelative,
        viewerLevel: 1,
      );

      expect(find.text('Normal Grip'), findsOneWidget);
      expect(find.text("Bartender's Grip"), findsNothing);
      expect(find.text('Reverse Grip'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.bySemanticsLabel('Movement image: Hand Stall'), findsNothing);
      expect(find.text('3 locked movements'), findsOneWidget);
      expect(find.byType(LockedMovementMark), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    },
  );

  testWidgets(
    'owner level cannot bypass viewer censoring on the completed list',
    (tester) async {
      await _pumpSection(
        tester,
        identityPolicy: CompletedMovementsIdentityPolicy.viewerRelative,
        viewerLevel: 1,
      );

      expect(find.text('Hand Stall'), findsNothing);
      expect(find.text('Unlocks at Level 5'), findsNothing);
    },
  );

  testWidgets(
    'teacher administrative rendering still shows authorized completed names',
    (tester) async {
      await _pumpSection(
        tester,
        identityPolicy: CompletedMovementsIdentityPolicy.authorizedFull,
        viewerLevel: 1,
      );

      expect(find.text('Normal Grip'), findsOneWidget);
      expect(find.text("Bartender's Grip"), findsOneWidget);
      expect(find.text('Reverse Grip'), findsOneWidget);
      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('3 locked movements'), findsNothing);
    },
  );

  testWidgets(
    'loading viewer progression cannot leak completed movement identities',
    (tester) async {
      await _pumpSection(
        tester,
        identityPolicy: CompletedMovementsIdentityPolicy.viewerRelative,
      );

      expect(find.text('Normal Grip'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.text('3 locked movements'), findsNothing);
      expect(find.text('Checking completed movements…'), findsOneWidget);
    },
  );

  testWidgets('higher viewer level reveals more completed identities', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      identityPolicy: CompletedMovementsIdentityPolicy.viewerRelative,
      viewerLevel: 3,
    );

    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text("Bartender's Grip"), findsOneWidget);
    expect(find.text('Reverse Grip'), findsOneWidget);
    expect(find.text('Hand Stall'), findsNothing);
    expect(find.text('1 locked movement'), findsOneWidget);
  });
}
