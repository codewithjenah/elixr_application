import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:elixr_application/features/practice/session_summary_sheet.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _practiceFeedback(
  String message, {
  String feedbackType = 'warning',
  int score = 50,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Basic Flip',
    score: score,
    feedback: message,
    feedbackType: feedbackType,
    postureStatus: 'ok',
    sessionState: 'active',
  );
}

SessionAssessment _assessment({
  required int score,
  List<SessionImprovement> improvements = const [],
  bool heldSteady = false,
  PracticeFeedback? latestFeedback,
}) {
  return SessionAssessment(
    finalScore: score,
    heldSteady: heldSteady,
    totalApplicableSamples: 20,
    positiveSampleCount: 16,
    positiveRatio: 0.8,
    improvements: improvements,
    latestFeedback: latestFeedback,
  );
}

SessionImprovement _improvement(String message) {
  final frame = _practiceFeedback(message);
  return SessionImprovement(
    message: message,
    occurrenceCount: 4,
    occurrenceRatio: 0.2,
    feedbackType: frame.feedbackType,
    representativeFeedback: frame,
  );
}

Future<void> _openSummary(
  WidgetTester tester, {
  required SessionAssessment assessment,
  required Future<String> Function(String? existingSessionId) onSave,
}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (context) {
          return Center(
            child: FilledButton(
              onPressed: () async {
                await SessionSummarySheet.show(
                  context,
                  movement: 'Basic Flip',
                  durationSeconds: 45,
                  assessment: assessment,
                  onSave: onSave,
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  tester.takeException();
}

Finder get _saveButton => find.byType(GameActionButton);

void main() {
  testWidgets('score 100 with no improvements shows great-form message', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 100,
        heldSteady: true,
        latestFeedback: _practiceFeedback(
          'Great grip!',
          feedbackType: 'positive',
          score: 100,
        ),
      ),
      onSave: (_) async => 'session-perfect',
    );

    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('What to Improve'), findsNothing);
    expect(
      find.text('Great form — no corrections needed this session!'),
      findsOneWidget,
    );
  });

  testWidgets('perfect assessment does not show old warning messages', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 100,
        heldSteady: true,
        latestFeedback: _practiceFeedback(
          'Great grip!',
          feedbackType: 'positive',
          score: 100,
        ),
      ),
      onSave: (_) async => 'session-perfect',
    );

    expect(
      find.textContaining('Move your hand to the upper bottle neck'),
      findsNothing,
    );
  });

  testWidgets(
    'score below 80 with no improvements does not show no corrections needed',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(score: 55),
        onSave: (_) async => 'session-low',
      );

      expect(
        find.text('Great form — no corrections needed this session!'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'score below 80 with no improvements does not mention tips below',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(score: 55),
        onSave: (_) async => 'session-low',
      );

      expect(find.textContaining('tips below'), findsNothing);
      expect(find.textContaining('fine-tune'), findsNothing);
    },
  );

  testWidgets(
    'score below 80 with no improvements shows neutral performance message',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(score: 55),
        onSave: (_) async => 'session-low',
      );

      expect(find.text('Performance'), findsOneWidget);
      expect(
        find.textContaining('No recurring technique issue was detected'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Keep practicing to improve your overall score'),
        findsOneWidget,
      );
    },
  );

  testWidgets('assessment.heldSteady alone controls held-steady header', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(score: 85, heldSteady: true),
      onSave: (_) async => 'session-held',
    );

    expect(
      find.text('You held "Basic Flip" steady. Well done!'),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.trophy2_solid), findsOneWidget);
  });

  testWidgets('non-perfect assessment displays persistent improvements', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 72,
        improvements: [
          _improvement('Keep your wrist steady'),
          _improvement('Lower your elbow'),
        ],
      ),
      onSave: (_) async => 'session-improve',
    );

    expect(find.text('What to Improve'), findsOneWidget);
    expect(find.text('Performance'), findsNothing);
    expect(find.text('Keep your wrist steady'), findsOneWidget);
    expect(find.text('Lower your elbow'), findsOneWidget);
    expect(find.textContaining('2 tips'), findsOneWidget);
  });

  testWidgets('duplicate save clicks issue one persistence operation', (
    tester,
  ) async {
    var saveCalls = 0;

    await _openSummary(
      tester,
      assessment: _assessment(
        score: 50,
        improvements: [_improvement('Keep your wrist steady')],
      ),
      onSave: (existingSessionId) async {
        saveCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return existingSessionId ?? 'session-duplicate';
      },
    );

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    expect(saveCalls, 1);
    await tester.pump(const Duration(milliseconds: 200));
    tester.takeException();
  });

  testWidgets('failed save shows error and restores enabled actions', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 50,
        improvements: [_improvement('Keep your wrist steady')],
      ),
      onSave: (_) async {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      },
    );

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(find.textContaining('Could not save your session'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Discard without saving'), findsOneWidget);
    expect(_saveButton, findsOneWidget);
  });

  testWidgets('successful retry closes the dialog once', (tester) async {
    var saveCalls = 0;
    SessionSummaryResult? result;

    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () async {
                  result = await SessionSummarySheet.show(
                    context,
                    movement: 'Basic Flip',
                    durationSeconds: 45,
                    assessment: _assessment(
                      score: 50,
                      improvements: [_improvement('Keep your wrist steady')],
                    ),
                    onSave: (existingSessionId) async {
                      saveCalls++;
                      if (saveCalls == 1) {
                        throw FirebaseException(
                          plugin: 'cloud_firestore',
                          code: 'unavailable',
                        );
                      }
                      return existingSessionId ?? 'session-retry';
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    tester.takeException();

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
    expect(find.textContaining('Could not save your session'), findsOneWidget);

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(saveCalls, 2);
    expect(result, SessionSummaryResult.saved);
  });
}
