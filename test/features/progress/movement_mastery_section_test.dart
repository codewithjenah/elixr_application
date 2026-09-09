import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/locked_movement_mark.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:elixr_application/features/progress/widgets/movement_mastery_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

MovementMastery _unpracticedMastery(Movement movement, int index) {
  return MovementMastery(
    movement: movement,
    completedSessions: 0,
    rubricSessionCount: 0,
    lifetimeAverageRubric: null,
    bestRubricTotal: null,
    recentAverageRubric: null,
    previousRecentAverageRubric: null,
    scoreTrend: ScoreTrend.unknown,
    lastPracticedAt: null,
    status: MovementMasteryStatus.notPracticed,
    catalogIndex: index,
  );
}

MovementMastery _practicedMastery(Movement movement, int index) {
  return MovementMastery(
    movement: movement,
    completedSessions: 4,
    rubricSessionCount: 3,
    lifetimeAverageRubric: 9,
    bestRubricTotal: 11,
    recentAverageRubric: 9,
    previousRecentAverageRubric: 7,
    scoreTrend: ScoreTrend.improving,
    lastPracticedAt: DateTime.utc(2026, 3, 1),
    status: MovementMasteryStatus.improving,
    catalogIndex: index,
  );
}

List<MovementMastery> _allUnpracticed() {
  return [
    for (var i = 0; i < movementCatalog.length; i++)
      _unpracticedMastery(movementCatalog[i], i),
  ];
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<MovementMastery> masteries,
  required int? traineeLevel,
}) async {
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: SingleChildScrollView(
          child: MovementMasterySection(
            masteries: masteries,
            traineeLevel: traineeLevel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final masteries = _allUnpracticed();

  testWidgets('level 1 shows Normal Grip and hides future movement identity', (
    tester,
  ) async {
    await _pumpSection(tester, masteries: masteries, traineeLevel: 1);

    expect(find.text('Normal Grip'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Movement image: Normal Grip'),
      findsOneWidget,
    );
    expect(find.text('Not practiced'), findsOneWidget);

    for (final movement in movementCatalog.skip(1)) {
      expect(find.text(movement.name), findsNothing);
      expect(
        find.bySemanticsLabel('Movement image: ${movement.name}'),
        findsNothing,
      );
    }
    expect(find.text('Locked Movement'), findsWidgets);
    expect(find.text('Unlocks at Level 5'), findsOneWidget);
    expect(find.text('Recent —'), findsOneWidget);
    expect(find.textContaining('Hand Stall'), findsNothing);
  });

  testWidgets('future mastery stats stay hidden until the reveal level', (
    tester,
  ) async {
    final withStats = [
      for (var i = 0; i < movementCatalog.length; i++)
        movementCatalog[i].name == 'Hand Stall'
            ? _practicedMastery(movementCatalog[i], i)
            : _unpracticedMastery(movementCatalog[i], i),
    ];
    await _pumpSection(tester, masteries: withStats, traineeLevel: 4);

    expect(find.text('Hand Stall'), findsNothing);
    expect(find.text('Improving'), findsNothing);
    expect(find.text('4 sessions'), findsNothing);
    expect(find.text('Best 11/12'), findsNothing);
    expect(find.byType(LockedMovementMark), findsWidgets);
  });

  testWidgets('movement identity becomes visible at the required level', (
    tester,
  ) async {
    await _pumpSection(tester, masteries: masteries, traineeLevel: 5);

    expect(find.text('Hand Stall'), findsOneWidget);
    expect(find.bySemanticsLabel('Movement image: Hand Stall'), findsOneWidget);
    expect(find.text('Unlocks at Level 5'), findsNothing);
    expect(find.text('One Finger Stall'), findsNothing);
  });

  testWidgets('loading state does not reveal movement names or images', (
    tester,
  ) async {
    await _pumpSection(tester, masteries: masteries, traineeLevel: null);

    for (final movement in movementCatalog) {
      expect(find.text(movement.name), findsNothing);
      expect(
        find.bySemanticsLabel('Movement image: ${movement.name}'),
        findsNothing,
      );
    }
    expect(find.byType(MovementImage), findsNothing);
    expect(find.text('Locked Movement'), findsNothing);
    expect(find.text('Easy'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Hard'), findsOneWidget);
  });

  testWidgets('revealed mastery still shows status, recent, best, sessions', (
    tester,
  ) async {
    final practiced = [
      for (var i = 0; i < movementCatalog.length; i++)
        movementCatalog[i].name == 'Normal Grip'
            ? _practicedMastery(movementCatalog[i], i)
            : _unpracticedMastery(movementCatalog[i], i),
    ];
    await _pumpSection(tester, masteries: practiced, traineeLevel: 1);

    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Improving'), findsOneWidget);
    expect(find.text('Recent 9/12'), findsOneWidget);
    expect(find.text('Best 11/12'), findsOneWidget);
    expect(find.text('4 sessions'), findsOneWidget);
  });
}
