import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/features/student_progress/student_progress_session_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PublicProfileSession legacy() => PublicProfileSession(
  sessionId: 'v1',
  userId: 'trainee',
  movementName: 'Hand Stall',
  difficulty: 'Easy',
  legacyScore: 80,
  durationSeconds: 60,
  propType: TrainingProp.bottle,
);
PublicProfileSession rubric() => PublicProfileSession(
  sessionId: 'v2',
  userId: 'trainee',
  movementName: 'Claw Grip',
  difficulty: 'Hard',
  rubric: RubricAssessment(
    technique: 3,
    stability: 2,
    completion: 1,
    propPositioning: 0,
  ),
  assessmentVersion: 2,
  durationSeconds: 120,
  propType: TrainingProp.shaker,
);

void main() {
  Future<void> pump(WidgetTester tester, PublicProfileSession value) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StudentProgressSessionCard(session: value)),
        ),
      );
  testWidgets('V1 shows legacy output and no fabricated rubric details', (
    tester,
  ) async {
    await pump(tester, legacy());
    expect(find.textContaining('Assessment V1 · Legacy · 80%'), findsOneWidget);
    expect(find.textContaining('Date unavailable'), findsOneWidget);
    await tester.tap(find.text('View details'));
    await tester.pump();
    expect(find.text('Hide details'), findsOneWidget);
    expect(
      find.textContaining('Criterion-level rubric scores are unavailable'),
      findsOneWidget,
    );
    for (final criterion in RubricCriterion.values) {
      expect(find.textContaining(criterion.label), findsNothing);
    }
  });
  testWidgets('V2 uses shared rubric labels and derived total', (tester) async {
    final value = rubric();
    await pump(tester, value);
    expect(
      find.textContaining(
        'Assessment V2 · 6/${RubricAssessment.maxTotalScore}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Legacy'), findsNothing);
    await tester.tap(find.text('View details'));
    await tester.pump();
    for (final criterion in RubricCriterion.values) {
      expect(
        find.text(
          '${criterion.label}: ${value.rubric!.scoreFor(criterion)}/${RubricAssessment.maxCriterionScore}',
        ),
        findsOneWidget,
      );
    }
  });
}
