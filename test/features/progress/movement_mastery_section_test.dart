import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
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

void main() {
  testWidgets('shows the mapped icon for every movement mastery row', (
    tester,
  ) async {
    final masteries = [
      for (var i = 0; i < movementCatalog.length; i++)
        _unpracticedMastery(movementCatalog[i], i),
    ];

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: MovementMasterySection(masteries: masteries),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MovementImage), findsNWidgets(movementCatalog.length));
    for (final movement in movementCatalog) {
      expect(
        find.bySemanticsLabel('Movement image: ${movement.name}'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
