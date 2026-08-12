import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:elixr_application/features/practice/session_summary_sheet.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spreads a 0..12 rubric total deterministically across the four criteria.
RubricAssessment _rubric(int total) {
  assert(total >= 0 && total <= 12);
  final scores = <int>[0, 0, 0, 0];
  var remaining = total;
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    scores[i] = remaining >= 3 ? 3 : remaining;
    remaining -= scores[i];
  }
  return RubricAssessment(
    technique: scores[0],
    stability: scores[1],
    completion: scores[2],
    propPositioning: scores[3],
  );
}

PracticeFeedback _practiceFeedback(
  String message, {
  String feedbackType = 'warning',
  int rubricTotal = 5,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    assessment: _rubric(rubricTotal),
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
  required int total,
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
    rubric: _rubric(total),
    heldSteady: heldSteady,
    totalApplicableSamples: 20,
    positiveSampleCount: 16,
    positiveRatio: 0.8,
    improvements: improvements,
    latestFeedback: latestFeedback,
    coaching: coaching,
  );
}

SessionAssessment _standardSummaryAssessment() {
  return _assessment(
    total: 10,
    heldSteady: true,
    improvements: [_improvement('Keep the bottle upright on your palm.')],
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
  );
}

SessionAssessment denseCoachingAssessment({
  required bool heldSteady,
  required String movementName,
  String focus =
      'Focus: Keep refining an especially long recommendation focus '
      'sentence that remains readable without overlapping pinned actions',
}) {
  return _assessment(
    total: heldSteady ? 12 : 8,
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

Future<void> _openSummary(
  WidgetTester tester, {
  required SessionAssessment assessment,
  required Future<String> Function(String? existingSessionId) onSave,
  Size size = const Size(1366, 768),
  String movement = 'Hand Stall',
  Movement? nextMovement,
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
                  nextMovement: nextMovement,
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
}

Finder get _primaryButton => find.byType(GameActionButton);

Finder get _scrollView => find.byKey(const Key('session-summary-scroll'));

Finder get _actions => find.byKey(const Key('session-summary-actions'));

Finder get _recommendation =>
    find.byKey(const Key('session-summary-recommendation'));

Finder _primaryButtonLabeled(String label) =>
    find.widgetWithText(GameActionButton, label);

const _nextMovementFixture = Movement(
  name: "Bartender's Grip",
  difficulty: 'Easy',
  description: 'Pinch the neck with thumb and index finger.',
  requiresHandsDetection: true,
  enabled: true,
);

double _maxScrollExtent(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: _scrollView, matching: find.byType(Scrollable)),
  );
  return scrollable.position.maxScrollExtent;
}

bool _isFullyVisible(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  return rect.top >= -0.5 &&
      rect.left >= -0.5 &&
      rect.bottom <= viewport.height + 0.5 &&
      rect.right <= viewport.width + 0.5;
}

void main() {
  testWidgets('populated coaching summary renders all three sections', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _standardSummaryAssessment(),
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

  testWidgets(
    'summary renders movement-specific unconfirmed reason without inventing copy',
    (tester) async {
      const reason =
          'Keep the overhand neck grip secure long enough to complete a confirmed hold.';
      await _openSummary(
        tester,
        movement: 'Normal Grip',
        assessment: _assessment(
          total: 6,
          heldSteady: false,
          recommendation: const SessionRecommendation(
            movementName: 'Normal Grip',
            reason: reason,
            targetLabel:
                'Maintain the overhand neck grip through one confirmed hold',
            targetUsesHoldMs: false,
            recommendedDurationSeconds: 120,
          ),
        ),
        onSave: (_) async => 'session-unconfirmed-copy',
      );

      expect(find.text('Recommended Next Session'), findsOneWidget);
      expect(find.textContaining('Practice Normal Grip again'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(
        find.textContaining(
          'Practice Normal Grip again and complete one confirmed hold.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('summary renders combined focus and unconfirmed hold guidance', (
    tester,
  ) async {
    const reason =
        'Focus: Rotate your wrist into an overhand grip. Then keep the '
        'overhand neck grip secure long enough to complete a confirmed hold.';
    await _openSummary(
      tester,
      movement: 'Normal Grip',
      assessment: _assessment(
        total: 8,
        heldSteady: false,
        improvements: [
          _improvement('Rotate your wrist into an overhand grip.'),
        ],
        recommendation: const SessionRecommendation(
          movementName: 'Normal Grip',
          reason: reason,
          targetLabel:
              'Maintain the overhand neck grip through one confirmed hold '
              '(2.5 seconds)',
          targetUsesHoldMs: true,
          recommendedDurationSeconds: 120,
        ),
      ),
      onSave: (_) async => 'session-combined-copy',
    );

    expect(find.text('Recommended Next Session'), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    expect(
      find.textContaining('Focus: Rotate your wrist into an overhand grip'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'keep the overhand neck grip secure long enough to complete a '
        'confirmed hold.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('(2.5 seconds)'), findsOneWidget);
  });

  testWidgets('empty legacy coaching does not fabricate a recommendation', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(total: 9, includeEmptyCoaching: true),
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
        total: 12,
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

  testWidgets('rubric 12/12 with no improvements shows threshold message', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(
        total: 12,
        heldSteady: true,
        cleanSessionMessage: cleanSessionMessageFor('Hand Stall'),
        latestFeedback: _practiceFeedback(
          'Great grip!',
          feedbackType: 'positive',
          rubricTotal: 12,
        ),
      ),
      onSave: (_) async => 'session-perfect',
    );

    expect(find.text('Needs Improvement'), findsOneWidget);
    expect(find.text(cleanSessionMessageFor('Hand Stall')), findsOneWidget);
  });

  testWidgets('summary presents rubric total, level, and four criteria', (
    tester,
  ) async {
    await _openSummary(
      tester,
      assessment: _assessment(total: 10, heldSteady: true),
      onSave: (_) async => 'session-rubric',
    );

    expect(find.byKey(const Key('session-summary-rubric')), findsOneWidget);
    expect(find.text('Rubric Score'), findsOneWidget);
    expect(find.text('10 / 12'), findsOneWidget);
    expect(find.text('Proficient'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    for (final criterion in RubricCriterion.values) {
      expect(find.text(criterion.label), findsOneWidget);
    }
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Score'), findsNothing);
  });

  testWidgets(
    'legacy coaching without cleanSessionMessage uses neutral fallback',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(
          total: 12,
          heldSteady: true,
          includeEmptyCoaching: false,
          latestFeedback: _practiceFeedback(
            'Great grip!',
            feedbackType: 'positive',
            rubricTotal: 12,
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
    'below proficient with no improvements shows neutral needs-improvement '
    'message',
    (tester) async {
      await _openSummary(
        tester,
        assessment: _assessment(total: 6),
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
      assessment: _assessment(total: 11, heldSteady: true),
      onSave: (_) async => 'session-held',
    );

    expect(
      find.text('You held "Hand Stall" steady. Well done!'),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.trophy2_solid), findsOneWidget);
  });

  group('responsive no-scroll-first layout', () {
    testWidgets('751x911 standard summary fits without scrolling', (
      tester,
    ) async {
      const size = Size(751, 911);
      await _openSummary(
        tester,
        size: size,
        assessment: _standardSummaryAssessment(),
        onSave: (_) async => 'session-751',
      );

      expect(tester.takeException(), isNull);
      expect(_maxScrollExtent(tester), 0);

      expect(find.text('Session Complete'), findsOneWidget);
      expect(find.text('What Went Well'), findsOneWidget);
      expect(find.text('Needs Improvement'), findsOneWidget);
      expect(find.text('Hold confirmed'), findsOneWidget);
      expect(
        find.text('Keep the bottle upright on your palm.'),
        findsOneWidget,
      );
      expect(_recommendation, findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Discard without saving'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Save & Continue'), findsNothing);
      expect(_primaryButton, findsOneWidget);

      expect(_isFullyVisible(tester, _recommendation, size), isTrue);
      expect(_isFullyVisible(tester, _actions, size), isTrue);
      expect(_isFullyVisible(tester, find.text('Try Again'), size), isTrue);
      expect(_isFullyVisible(tester, _primaryButton, size), isTrue);
    });

    testWidgets('1366x768 uses regular layout with zero scroll extent', (
      tester,
    ) async {
      const size = Size(1366, 768);
      await _openSummary(
        tester,
        size: size,
        assessment: _standardSummaryAssessment(),
        onSave: (_) async => 'session-1366',
      );

      expect(tester.takeException(), isNull);
      expect(_maxScrollExtent(tester), 0);

      final dialog = tester.getRect(
        find.byKey(const Key('session-summary-dialog')),
      );
      expect(dialog.width, greaterThanOrEqualTo(700));

      expect(
        _isFullyVisible(tester, find.text('What Went Well'), size),
        isTrue,
      );
      expect(
        _isFullyVisible(tester, find.text('Needs Improvement'), size),
        isTrue,
      );
      expect(_isFullyVisible(tester, _recommendation, size), isTrue);
      expect(_isFullyVisible(tester, _actions, size), isTrue);
      expect(_isFullyVisible(tester, find.text('Try Again'), size), isTrue);
      expect(
        _isFullyVisible(tester, find.text('Discard without saving'), size),
        isTrue,
      );
      expect(_isFullyVisible(tester, _primaryButton, size), isTrue);
    });

    testWidgets('1280x720 standard summary is fully visible without overflow', (
      tester,
    ) async {
      const size = Size(1280, 720);
      await _openSummary(
        tester,
        size: size,
        assessment: _standardSummaryAssessment(),
        onSave: (_) async => 'session-1280',
      );

      expect(tester.takeException(), isNull);
      expect(_maxScrollExtent(tester), 0);
      expect(_isFullyVisible(tester, _recommendation, size), isTrue);
      expect(_isFullyVisible(tester, _actions, size), isTrue);
    });

    testWidgets(
      'dense coaching at 900x600 allows fallback scroll with pinned actions',
      (tester) async {
        const size = Size(900, 600);
        await _openSummary(
          tester,
          size: size,
          assessment: denseCoachingAssessment(
            heldSteady: false,
            movementName: 'Double Hand Stall',
          ),
          onSave: (_) async => 'session-dense-900',
        );

        expect(tester.takeException(), isNull);
        expect(_maxScrollExtent(tester), greaterThan(0));
        expect(_isFullyVisible(tester, _actions, size), isTrue);
        expect(_isFullyVisible(tester, find.text('Try Again'), size), isTrue);
        expect(_isFullyVisible(tester, _primaryButton, size), isTrue);

        await tester.drag(_scrollView, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text('Recommended Next Session'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'long movement name keeps header and rank badge inside dialog',
      (tester) async {
        const movement =
            'Reverse Forearm Stall With An Unusually Long Movement Label';
        await _openSummary(
          tester,
          size: const Size(751, 911),
          movement: movement,
          assessment: _assessment(
            total: 11,
            heldSteady: true,
            strengths: const [
              SessionStrength(
                code: 'hold_confirmed',
                message: 'Hold confirmed',
                sampleCount: 1,
                sampleRatio: 1,
                evidenceKind: 'holdConfirmed',
              ),
            ],
          ),
          onSave: (_) async => 'session-long-name',
        );

        expect(tester.takeException(), isNull);
        final dialogRect = tester.getRect(
          find.byKey(const Key('session-summary-dialog')),
        );
        final badgeRect = tester.getRect(find.byType(RankBadge));
        expect(badgeRect.right, lessThanOrEqualTo(dialogRect.right + 0.5));
        expect(badgeRect.left, greaterThanOrEqualTo(dialogRect.left - 0.5));
        expect(find.textContaining(movement), findsOneWidget);
      },
    );
  });

  group('Phase C layout hardening', () {
    Future<void> assertLayoutHealthy(
      WidgetTester tester, {
      required Size size,
      required SessionAssessment assessment,
      String movement = 'Hand Stall',
      bool expectRecommendation = true,
    }) async {
      await _openSummary(
        tester,
        size: size,
        movement: movement,
        assessment: assessment,
        onSave: (_) async => 'session-layout',
      );

      expect(tester.takeException(), isNull);
      expect(_scrollView, findsOneWidget);
      expect(_actions, findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Discard without saving'), findsOneWidget);
      expect(_isFullyVisible(tester, _actions, size), isTrue);
      expect(_primaryButton, findsOneWidget);
      expect(find.text('What Went Well'), findsOneWidget);
      expect(find.text('Needs Improvement'), findsOneWidget);
      if (expectRecommendation) {
        expect(find.text('Recommended Next Session'), findsOneWidget);
      }
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
      expect(_maxScrollExtent(tester), greaterThan(0));
    });

    testWidgets('unconfirmed low-data coaching keeps actions pinned', (
      tester,
    ) async {
      await assertLayoutHealthy(
        tester,
        size: const Size(1280, 720),
        assessment: _assessment(
          total: 4,
          heldSteady: false,
          includeEmptyCoaching: false,
        ),
        expectRecommendation: false,
      );
      expect(find.text('Recommended Next Session'), findsNothing);
    });

    testWidgets('legacy empty coaching does not invent recommendation', (
      tester,
    ) async {
      await _openSummary(
        tester,
        size: const Size(1024, 768),
        assessment: _assessment(total: 9, includeEmptyCoaching: true),
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
      const size = Size(900, 600);
      await _openSummary(
        tester,
        size: size,
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

      await tester.tap(_primaryButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();

      expect(
        find.textContaining('Could not save your session'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Discard without saving'), findsOneWidget);
      expect(_isFullyVisible(tester, _actions, size), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('duplicate primary clicks issue one persistence operation', (
    tester,
  ) async {
    var saveCalls = 0;

    await _openSummary(
      tester,
      assessment: _assessment(
        total: 5,
        improvements: [_improvement('Keep your wrist steady')],
      ),
      onSave: (existingSessionId) async {
        saveCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return existingSessionId ?? 'session-duplicate';
      },
    );

    await tester.tap(_primaryButton, warnIfMissed: false);
    await tester.pump();
    await tester.tap(_primaryButton, warnIfMissed: false);
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
        total: 5,
        improvements: [_improvement('Keep your wrist steady')],
      ),
      onSave: (_) async {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      },
    );

    await tester.tap(_primaryButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(find.textContaining('Could not save your session'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Discard without saving'), findsOneWidget);
    expect(_primaryButton, findsOneWidget);
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
                      total: 5,
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

    await tester.tap(_primaryButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
    expect(find.textContaining('Could not save your session'), findsOneWidget);

    await tester.tap(_primaryButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();

    expect(saveCalls, 2);
    expect(result, SessionSummaryResult.saved);
  });

  testWidgets('discard without saving returns discarded result', (
    tester,
  ) async {
    var saveCalls = 0;
    SessionSummaryResult? result;

    tester.view.physicalSize = const Size(1200, 900);
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
                    assessment: _standardSummaryAssessment(),
                    onSave: (_) async {
                      saveCalls++;
                      return 'unused';
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

    await tester.tap(find.text('Discard without saving'));
    await tester.pumpAndSettle();
    expect(saveCalls, 0);
    expect(result, SessionSummaryResult.discarded);
  });

  testWidgets('try again returns tryAgain result', (tester) async {
    var saveCalls = 0;
    SessionSummaryResult? result;

    tester.view.physicalSize = const Size(1200, 900);
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
                    assessment: _standardSummaryAssessment(),
                    onSave: (_) async {
                      saveCalls++;
                      return 'unused';
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

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(saveCalls, 0);
    expect(result, SessionSummaryResult.tryAgain);
  });

  group('primary action persistence', () {
    testWidgets('with next movement shows Next and no Save & Continue', (
      tester,
    ) async {
      await _openSummary(
        tester,
        assessment: _standardSummaryAssessment(),
        nextMovement: _nextMovementFixture,
        onSave: (_) async => 'session-with-next',
      );

      expect(find.text("Next: Bartender's Grip"), findsOneWidget);
      expect(find.text('Save & Continue'), findsNothing);
      expect(find.text('Finish'), findsNothing);
      expect(_primaryButton, findsOneWidget);
    });

    testWidgets('without next movement shows Finish and no Save & Continue', (
      tester,
    ) async {
      await _openSummary(
        tester,
        assessment: _standardSummaryAssessment(),
        onSave: (_) async => 'session-no-next',
      );

      expect(find.textContaining('Next:'), findsNothing);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Save & Continue'), findsNothing);
      expect(_primaryButton, findsOneWidget);
    });

    testWidgets('Next awaits save then returns SessionSummaryResult.next', (
      tester,
    ) async {
      var saveCalls = 0;
      var saveCompleted = false;
      SessionSummaryResult? result;

      tester.view.physicalSize = const Size(1200, 900);
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
                      assessment: _standardSummaryAssessment(),
                      nextMovement: _nextMovementFixture,
                      onSave: (existingSessionId) async {
                        saveCalls++;
                        await Future<void>.delayed(
                          const Duration(milliseconds: 80),
                        );
                        saveCompleted = true;
                        return existingSessionId ?? 'session-next';
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

      await tester.tap(_primaryButtonLabeled("Next: Bartender's Grip"));
      await tester.pump();
      expect(saveCalls, 1);
      expect(saveCompleted, isFalse);
      expect(result, isNull);

      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
      expect(saveCompleted, isTrue);
      expect(result, SessionSummaryResult.next);
    });

    testWidgets('in-flight Next disables secondary actions and blocks re-tap', (
      tester,
    ) async {
      var saveCalls = 0;
      SessionSummaryResult? result;

      tester.view.physicalSize = const Size(1200, 900);
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
                      assessment: _standardSummaryAssessment(),
                      nextMovement: _nextMovementFixture,
                      onSave: (existingSessionId) async {
                        saveCalls++;
                        await Future<void>.delayed(
                          const Duration(milliseconds: 120),
                        );
                        return existingSessionId ?? 'session-next-inflight';
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

      await tester.tap(_primaryButtonLabeled("Next: Bartender's Grip"));
      await tester.pump();

      final primary = tester.widget<GameActionButton>(_primaryButton);
      expect(primary.isLoading, isTrue);
      expect(primary.onPressed, isNull);

      await tester.tap(_primaryButton, warnIfMissed: false);
      await tester.tap(find.text('Try Again'), warnIfMissed: false);
      await tester.tap(
        find.text('Discard without saving'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(saveCalls, 1);
      expect(result, isNull);

      await tester.pump(const Duration(milliseconds: 200));
      tester.takeException();
      expect(result, SessionSummaryResult.next);
    });

    testWidgets('Next save failure keeps dialog open and allows retry', (
      tester,
    ) async {
      var saveCalls = 0;
      SessionSummaryResult? result;

      tester.view.physicalSize = const Size(1200, 900);
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
                      assessment: _standardSummaryAssessment(),
                      nextMovement: _nextMovementFixture,
                      onSave: (existingSessionId) async {
                        saveCalls++;
                        if (saveCalls == 1) {
                          throw FirebaseException(
                            plugin: 'cloud_firestore',
                            code: 'unavailable',
                          );
                        }
                        return existingSessionId ?? 'session-next-retry';
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

      await tester.tap(_primaryButtonLabeled("Next: Bartender's Grip"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();

      expect(
        find.textContaining('Could not save your session'),
        findsOneWidget,
      );
      expect(result, isNull);
      expect(find.text("Next: Bartender's Grip"), findsOneWidget);

      final primaryAfterFailure = tester.widget<GameActionButton>(
        _primaryButton,
      );
      expect(primaryAfterFailure.isLoading, isFalse);
      expect(primaryAfterFailure.onPressed, isNotNull);

      await tester.tap(_primaryButtonLabeled("Next: Bartender's Grip"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();

      expect(saveCalls, 2);
      expect(result, SessionSummaryResult.next);
    });

    testWidgets('Finish awaits save then returns SessionSummaryResult.saved', (
      tester,
    ) async {
      var saveCalls = 0;
      SessionSummaryResult? result;

      tester.view.physicalSize = const Size(1200, 900);
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
                      assessment: _standardSummaryAssessment(),
                      onSave: (existingSessionId) async {
                        saveCalls++;
                        return existingSessionId ?? 'session-finish';
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

      expect(find.text('Save & Continue'), findsNothing);
      expect(find.text('Finish'), findsOneWidget);

      await tester.tap(_primaryButtonLabeled('Finish'));
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(result, SessionSummaryResult.saved);
    });
  });
}
