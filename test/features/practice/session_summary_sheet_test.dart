import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
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
    movement: 'Hand Stall',
    score: score,
    feedback: message,
    feedbackType: feedbackType,
    postureStatus: 'ok',
    sessionState: 'active',
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
    code: 'prop_not_upright',
  );
}

SessionAssessment _assessment({
  required int score,
  List<SessionImprovement> improvements = const [],
  List<SessionStrength> strengths = const [],
  SessionRecommendation? recommendation,
  bool heldSteady = false,
  PracticeFeedback? latestFeedback,
  bool includeEmptyCoaching = false,
  String? cleanSessionMessage,
}) {
  final coaching = includeEmptyCoaching
      ? const SessionCoachingSummary.empty()
      : SessionCoachingSummary(
          strengths: strengths,
          improvements: improvements,
          recommendation: recommendation,
          cleanSessionMessage: cleanSessionMessage,
        );
  return SessionAssessment(
    finalScore: score,
    heldSteady: heldSteady,
    totalApplicableSamples: 20,
    positiveSampleCount: 16,
    positiveRatio: 0.8,
    improvements: improvements,
    latestFeedback: latestFeedback,
    coaching: coaching,
  );
}

Future<void> _openSummary(
  WidgetTester tester, {
  required SessionAssessment assessment,
  required Future<String> Function(String? existingSessionId) onSave,
  Size size = const Size(1366, 768),
  String movement = 'Hand Stall',
}) async {
  tester.view.physicalSize = size;
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
                  movement: movement,
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
  // Leave exceptions for callers to assert; do not swallow overflows.
}

Finder get _saveButton => find.byType(GameActionButton);

void main() {
  testWidgets('populated coaching summary renders all three sections', (
    tester,
  ) async {
    final improvements = [
      _improvement('Keep the bottle upright on your palm.'),
    ];
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 78,
        heldSteady: true,
        improvements: improvements,
        strengths: const [
          SessionStrength(
            code: 'hold_confirmed',
            message: 'Hold confirmed',
            sampleCount: 1,
            sampleRatio: 1,
            evidenceKind: 'holdConfirmed',
          ),
        ],
        recommendation: const SessionRecommendation(
          movementName: 'Hand Stall',
          reason: 'Focus: Keep the bottle upright',
          targetLabel: 'Complete one confirmed hold (2.5 seconds)',
          targetUsesHoldMs: true,
          recommendedDurationSeconds: 180,
        ),
      ),
      onSave: (_) async => 'session-coaching',
    );

    expect(find.text('What Went Well'), findsOneWidget);
    expect(find.text('Needs Improvement'), findsOneWidget);
    expect(find.text('Recommended Next Session'), findsOneWidget);
    expect(find.text('Hold confirmed'), findsOneWidget);
    expect(find.text('Keep the bottle upright on your palm.'), findsOneWidget);
    expect(find.textContaining('Practice Hand Stall again'), findsOneWidget);
    expect(find.textContaining('mistakes'), findsNothing);
    expect(find.textContaining(' times'), findsNothing);
  });

  testWidgets('empty legacy coaching does not fabricate a recommendation', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(score: 70, includeEmptyCoaching: true),
      onSave: (_) async => 'session-legacy',
    );

    expect(find.text('Recommended Next Session'), findsNothing);
    expect(find.textContaining('Practice Hand Stall again'), findsNothing);
    expect(find.text('What Went Well'), findsOneWidget);
    expect(find.text('Needs Improvement'), findsOneWidget);
  });

  testWidgets('confirmed strength and recurring improvement can coexist', (
    tester,
  ) async {
    final improvements = [
      _improvement('Keep the bottle upright on your palm.'),
    ];
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 100,
        heldSteady: true,
        improvements: improvements,
        strengths: const [
          SessionStrength(
            code: 'hold_confirmed',
            message: 'Hold confirmed',
            sampleCount: 1,
            sampleRatio: 1,
            evidenceKind: 'holdConfirmed',
          ),
        ],
        recommendation: const SessionRecommendation(
          movementName: 'Hand Stall',
          reason: 'Focus: Keep the bottle upright',
          targetLabel: 'Complete one confirmed hold',
          targetUsesHoldMs: false,
          recommendedDurationSeconds: 180,
        ),
      ),
      onSave: (_) async => 'session-coexist',
    );

    expect(find.text('Hold confirmed'), findsOneWidget);
    expect(find.text('Keep the bottle upright on your palm.'), findsOneWidget);
  });

  testWidgets('score 100 with no improvements shows threshold message', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        score: 100,
        heldSteady: true,
        cleanSessionMessage: cleanSessionMessageFor('Hand Stall'),
        latestFeedback: _practiceFeedback(
          'Great grip!',
          feedbackType: 'positive',
          score: 100,
        ),
      ),
      onSave: (_) async => 'session-perfect',
    );

    expect(find.text('Needs Improvement'), findsOneWidget);
    expect(find.text(cleanSessionMessageFor('Hand Stall')), findsOneWidget);
  });

  testWidgets(
    'legacy coaching without cleanSessionMessage uses neutral fallback',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(
          score: 100,
          heldSteady: true,
          includeEmptyCoaching: false,
          latestFeedback: _practiceFeedback(
            'Great grip!',
            feedbackType: 'positive',
            score: 100,
          ),
        ),
        onSave: (_) async => 'session-legacy-clean',
      );

      expect(
        find.text('No recurring technique issue met the session threshold.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'score below 80 with no improvements shows neutral needs-improvement message',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(score: 55),
        onSave: (_) async => 'session-low',
      );

      expect(
        find.textContaining('No recurring technique issue was detected'),
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
      find.text('You held "Hand Stall" steady. Well done!'),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.trophy2_solid), findsOneWidget);
  });

  testWidgets('long coaching content keeps actions reachable at 1366x768', (
    tester,
  ) async {
    final improvements = [
      _improvement(
        'Keep the bottle upright on your palm while maintaining open fingers '
        'and centering the base carefully over the palm center.',
      ),
      _improvement(
        'Hold the bottle steady on your open palm without horizontal drift '
        'or sudden vertical bounce during the confirmation window.',
      ),
      _improvement(
        'Place the bottle base directly on your open palm and avoid letting '
        'the bottom drop clearly below the tracked palm landmark.',
      ),
    ];
    await _openSummary(
      tester,
      size: const Size(1366, 768),
      assessment: _assessment(
        score: 64,
        improvements: improvements,
        strengths: const [
          SessionStrength(
            code: 'hold_partial_progress',
            message: 'Best hold reached 82% of the target',
            sampleCount: 1,
            sampleRatio: 0.82,
            evidenceKind: 'holdPartialProgress',
          ),
          SessionStrength(
            code: 'hand_stall_locked',
            message: 'Correct Hand Stall form detected',
            sampleCount: 12,
            sampleRatio: 0.4,
            evidenceKind: 'positiveCode',
          ),
        ],
        recommendation: const SessionRecommendation(
          movementName: 'Hand Stall',
          reason:
              'Focus: Keep the bottle upright on your palm while refining '
              'steady balance through the full confirmation window',
          targetLabel: 'Complete one confirmed hold (2.5 seconds)',
          targetUsesHoldMs: true,
          recommendedDurationSeconds: 180,
        ),
      ),
      onSave: (_) async => 'session-long',
    );

    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Discard without saving'), findsOneWidget);
    await tester.ensureVisible(_saveButton);
    expect(_saveButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Phase C layout hardening', () {
    SessionAssessment denseCoachingAssessment({
      required bool heldSteady,
      required String movementName,
      String focus =
          'Focus: Keep refining an especially long recommendation focus '
          'sentence that remains readable without overlapping pinned actions',
    }) {
      return _assessment(
        score: heldSteady ? 92 : 58,
        heldSteady: heldSteady,
        strengths: const [
          SessionStrength(
            code: 'hold_confirmed',
            message: 'Hold confirmed — best hold lasted longer than expected',
            sampleCount: 1,
            sampleRatio: 1,
            evidenceKind: 'holdConfirmed',
          ),
          SessionStrength(
            code: 'hand_stall_locked',
            message:
                'Correct Hand Stall form detected across a long supportive '
                'strength sentence for layout stress testing',
            sampleCount: 12,
            sampleRatio: 0.4,
            evidenceKind: 'positiveCode',
          ),
          SessionStrength(
            code: 'extra_strength',
            message: 'Additional form evidence remained consistent',
            sampleCount: 8,
            sampleRatio: 0.25,
            evidenceKind: 'positiveCode',
          ),
        ],
        improvements: [
          _improvement(
            'Keep the bottle upright on your palm while maintaining open '
            'fingers and centering carefully over a long feedback message.',
          ),
          _improvement(
            'Hold the bottle steady without horizontal drift or sudden bounce '
            'during the confirmation window on a longer improvement line.',
          ),
          _improvement(
            'Place the bottle base directly on your open palm and avoid '
            'letting the bottom drop below the tracked palm landmark.',
          ),
        ],
        recommendation: SessionRecommendation(
          movementName: movementName,
          reason: focus,
          targetLabel: 'Complete one confirmed hold (2.5 seconds)',
          targetUsesHoldMs: true,
          recommendedDurationSeconds: 180,
        ),
      );
    }

    Future<void> assertLayoutHealthy(
      WidgetTester tester, {
      required Size size,
      required SessionAssessment assessment,
      String movement = 'Hand Stall',
    }) async {
      await _openSummary(
        tester,
        size: size,
        movement: movement,
        assessment: assessment,
        onSave: (_) async => 'session-layout',
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Discard without saving'), findsOneWidget);
      await tester.ensureVisible(_saveButton);
      expect(_saveButton, findsOneWidget);
      expect(find.text('What Went Well'), findsOneWidget);
      expect(find.text('Needs Improvement'), findsOneWidget);
    }

    testWidgets('dense coaching remains usable at 1366x768', (tester) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(1366, 768),
        assessment: denseCoachingAssessment(
          heldSteady: true,
          movementName:
              'Reverse Forearm Stall With An Unusually Long Movement Label',
        ),
        movement: 'Reverse Forearm Stall With An Unusually Long Movement Label',
      );
      expect(find.text('Recommended Next Session'), findsOneWidget);
    });

    testWidgets('dense coaching remains usable at 1280x720', (tester) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(1280, 720),
        assessment: denseCoachingAssessment(
          heldSteady: false,
          movementName: 'Hand Stall',
        ),
      );
    });

    testWidgets('dense coaching remains usable at 1024x768', (tester) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(1024, 768),
        assessment: denseCoachingAssessment(
          heldSteady: true,
          movementName: 'Bottle in a tin',
        ),
      );
    });

    testWidgets('dense coaching remains usable at narrow 900x600', (
      tester,
    ) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(900, 600),
        assessment: denseCoachingAssessment(
          heldSteady: false,
          movementName: 'Double Hand Stall',
        ),
      );
    });

    testWidgets('unconfirmed low-data coaching keeps actions pinned', (
      tester,
    ) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(1280, 720),
        assessment: _assessment(
          score: 40,
          heldSteady: false,
          includeEmptyCoaching: false,
        ),
      );
      expect(find.text('Recommended Next Session'), findsNothing);
    });

    testWidgets('legacy empty coaching does not invent recommendation', (
      tester,
    ) async {
      await _openSummary(
        tester,
        size: const Size(1024, 768),
        assessment: _assessment(score: 70, includeEmptyCoaching: true),
        onSave: (_) async => 'session-legacy-layout',
      );
      expect(find.text('Recommended Next Session'), findsNothing);
      expect(find.textContaining('Practice Hand Stall again'), findsNothing);
      expect(find.text('Try Again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('save failure message remains visible with pinned actions', (
      tester,
    ) async {
      await _openSummary(
        tester,
        size: const Size(900, 600),
        assessment: denseCoachingAssessment(
          heldSteady: true,
          movementName: 'Shoulder Stall',
        ),
        onSave: (_) async {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        },
      );

      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();

      expect(
        find.textContaining('Could not save your session'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Discard without saving'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
                    movement: 'Hand Stall',
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
