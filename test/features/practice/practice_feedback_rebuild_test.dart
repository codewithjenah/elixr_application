import 'dart:convert';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/practice_feedback_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _headerKey = ValueKey<String>('rebuild-header');
const _panelKey = ValueKey<String>('rebuild-panel');
const _scoreKey = ValueKey<String>('rebuild-score');
const _holdKey = ValueKey<String>('rebuild-hold');
const _comboKey = ValueKey<String>('rebuild-combo');
const _bestComboKey = ValueKey<String>('rebuild-best-combo');
const _popupKey = ValueKey<String>('rebuild-popup');

final _jpegA = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

final _jpegB = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8BQDwAEhQGAhKmM'
    'IwAAAABJRU5ErkJggg==',
  ),
);

PracticeFeedback _base({
  bool bottleDetected = true,
  String movement = 'Hand Stall',
  int score = 70,
  String feedback = 'Hold steady',
  String feedbackType = 'warning',
  String postureStatus = 'stable',
  Uint8List? jpeg,
  double holdProgress = 0.2,
  int holdDurationMs = 100,
  double positiveFrameRatio = 0.9,
  TrainingProp propType = TrainingProp.bottle,
  String? sessionState = 'active',
  bool holdConfirmed = false,
}) {
  return PracticeFeedback(
    bottleDetected: bottleDetected,
    movement: movement,
    score: score,
    feedback: feedback,
    feedbackType: feedbackType,
    postureStatus: postureStatus,
    frameJpegBytes: jpeg ?? _jpegA,
    holdProgress: holdProgress,
    holdDurationMs: holdDurationMs,
    positiveFrameRatio: positiveFrameRatio,
    propType: propType,
    sessionState: sessionState,
    holdConfirmed: holdConfirmed,
  );
}

/// Widget harness wired to [PracticeFeedbackController].
class _ScoredPracticeFeedbackHarness extends StatefulWidget {
  const _ScoredPracticeFeedbackHarness({required this.onFeedback});

  final void Function(void Function(PracticeFeedback) apply) onFeedback;

  @override
  State<_ScoredPracticeFeedbackHarness> createState() =>
      _ScoredPracticeFeedbackHarnessState();
}

class _ScoredPracticeFeedbackHarnessState
    extends State<_ScoredPracticeFeedbackHarness> {
  final controller = PracticeFeedbackController();
  final frameBytes = ValueNotifier<Uint8List?>(null);
  final scoreNotifier = ValueNotifier<int?>(null);
  final holdNotifier = ValueNotifier<double>(0);
  final comboNotifier = ValueNotifier<ComboState>(const ComboState());
  final scorePopupNotifier = ValueNotifier<ScorePopupState>(
    const ScorePopupState(),
  );

  int headerBuilds = 0;
  int panelBuilds = 0;
  int scoreBuilds = 0;
  int holdBuilds = 0;
  int comboBuilds = 0;
  int bestComboBuilds = 0;
  int popupBuilds = 0;
  int holdConfirmations = 0;

  @override
  void initState() {
    super.initState();
    widget.onFeedback(applyFeedback);
  }

  @override
  void dispose() {
    frameBytes.dispose();
    scoreNotifier.dispose();
    holdNotifier.dispose();
    comboNotifier.dispose();
    scorePopupNotifier.dispose();
    super.dispose();
  }

  void applyFeedback(PracticeFeedback feedback) {
    if (feedback.frameJpegBytes != null) {
      frameBytes.value = feedback.frameJpegBytes;
    }

    final result = controller.applyActiveFeedback(feedback);
    scoreNotifier.value = feedback.score;
    holdNotifier.value = feedback.holdProgress;

    if (result.comboChanged) {
      comboNotifier.value = result.comboState;
    }
    if (result.scorePopupChanged) {
      scorePopupNotifier.value = result.scorePopupState;
    }

    if (result.needsChromeRebuild) {
      setState(() {});
    }

    if (result.holdConfirmed) {
      holdConfirmations++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Builder(
          builder: (context) {
            headerBuilds++;
            return Text(
              'Scored header ${controller.latestFeedback?.movement ?? '-'}',
              key: _headerKey,
            );
          },
        ),
        Builder(
          builder: (context) {
            panelBuilds++;
            return Text(
              'panel posture=${controller.latestFeedback?.postureStatus ?? '-'} '
              'history=${controller.feedbackHistory.length}',
              key: _panelKey,
            );
          },
        ),
        ValueListenableBuilder<int?>(
          valueListenable: scoreNotifier,
          builder: (context, score, _) {
            scoreBuilds++;
            return Text('score=$score', key: _scoreKey);
          },
        ),
        ValueListenableBuilder<double>(
          valueListenable: holdNotifier,
          builder: (context, hold, _) {
            holdBuilds++;
            return Text('hold=$hold', key: _holdKey);
          },
        ),
        ValueListenableBuilder<ComboState>(
          valueListenable: comboNotifier,
          builder: (context, comboState, _) {
            comboBuilds++;
            return Text('combo=${comboState.combo}', key: _comboKey);
          },
        ),
        ValueListenableBuilder<ComboState>(
          valueListenable: comboNotifier,
          builder: (context, comboState, _) {
            bestComboBuilds++;
            return Text('best=${comboState.bestCombo}', key: _bestComboKey);
          },
        ),
        ValueListenableBuilder<ScorePopupState>(
          valueListenable: scorePopupNotifier,
          builder: (context, popupState, _) {
            popupBuilds++;
            return Text(
              'popup=${popupState.trigger}:${popupState.delta}',
              key: _popupKey,
            );
          },
        ),
      ],
    );
  }
}

class _FreePracticeFeedbackHarness extends StatefulWidget {
  const _FreePracticeFeedbackHarness({required this.onFeedback});

  final void Function(void Function(PracticeFeedback) apply) onFeedback;

  @override
  State<_FreePracticeFeedbackHarness> createState() =>
      _FreePracticeFeedbackHarnessState();
}

class _FreePracticeFeedbackHarnessState
    extends State<_FreePracticeFeedbackHarness> {
  final controller = PracticeFeedbackController();
  final frameBytes = ValueNotifier<Uint8List?>(null);
  int headerBuilds = 0;
  int panelBuilds = 0;

  @override
  void initState() {
    super.initState();
    widget.onFeedback(applyFeedback);
  }

  @override
  void dispose() {
    frameBytes.dispose();
    super.dispose();
  }

  void applyFeedback(PracticeFeedback feedback) {
    if (feedback.frameJpegBytes != null) {
      frameBytes.value = feedback.frameJpegBytes;
    }
    if (controller.applyFreePracticeFeedback(feedback)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Builder(
            builder: (context) {
              headerBuilds++;
              return Text(
                'Free header ${controller.latestFeedback?.movement ?? '-'} '
                'detected=${controller.latestFeedback?.bottleDetected ?? false}',
                key: _headerKey,
              );
            },
          ),
        ),
        ValueListenableBuilder<Uint8List?>(
          valueListenable: frameBytes,
          builder: (context, bytes, _) =>
              Text('frame=${bytes?.length ?? 0}', key: const ValueKey('frame')),
        ),
        Builder(
          builder: (context) {
            panelBuilds++;
            return Text(
              'panel ${controller.latestFeedback?.propType.displayLabel ?? '-'}',
              key: _panelKey,
            );
          },
        ),
      ],
    );
  }
}

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: child),
  );
}

void main() {
  group('PracticeFeedbackController', () {
    test('deduplicates consecutive identical feedback history entries', () {
      final controller = PracticeFeedbackController();
      controller.applyActiveFeedback(_base(feedback: 'Keep steady'));
      controller.applyActiveFeedback(_base(feedback: 'Keep steady'));
      expect(controller.feedbackHistory.length, 1);

      controller.applyActiveFeedback(_base(feedback: 'Lower elbow'));
      expect(controller.feedbackHistory.length, 2);
      expect(controller.feedbackHistory.first.feedback, 'Lower elbow');

      controller.applyActiveFeedback(_base(feedback: 'Lower elbow'));
      expect(controller.feedbackHistory.length, 2);
    });

    test('positive frames increment combo without chrome rebuild', () {
      final controller = PracticeFeedbackController();
      controller.applyActiveFeedback(
        _base(feedbackType: 'positive', score: 70),
      );
      final first = controller.applyActiveFeedback(
        _base(feedbackType: 'positive', score: 70),
      );
      expect(first.comboChanged, isTrue);
      expect(first.chromeChanged, isFalse);
      expect(controller.comboState.combo, 2);

      final second = controller.applyActiveFeedback(
        _base(feedbackType: 'positive', score: 72),
      );
      expect(second.comboChanged, isTrue);
      expect(second.chromeChanged, isFalse);
      expect(second.needsChromeRebuild, isFalse);
      expect(controller.comboState.combo, 3);
    });
  });

  group('PracticeFeedback rebuild equality', () {
    test('freePracticeVisibleEquals ignores score and hold fields', () {
      final a = _base(score: 10, holdProgress: 0.1, holdDurationMs: 50);
      final b = _base(score: 99, holdProgress: 0.9, holdDurationMs: 900);
      expect(a.freePracticeVisibleEquals(b), isTrue);
      expect(a.semanticEquals(b), isFalse);
    });

    test('scoredPracticeChromeEquals ignores score and hold progress', () {
      final a = _base(score: 10, holdProgress: 0.1, positiveFrameRatio: 0.5);
      final b = _base(score: 80, holdProgress: 0.8, positiveFrameRatio: 0.99);
      expect(a.scoredPracticeChromeEquals(b), isTrue);
      expect(a.semanticEquals(b), isFalse);
    });
  });

  group('Free Practice feedback handling path', () {
    testWidgets('JPEG and hidden field changes do not rebuild header/panel', (
      tester,
    ) async {
      late void Function(PracticeFeedback) apply;
      await tester.pumpWidget(
        _wrap(
          _FreePracticeFeedbackHarness(
            onFeedback: (handler) => apply = handler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_FreePracticeFeedbackHarnessState>(
        find.byType(_FreePracticeFeedbackHarness),
      );
      apply(_base(movement: 'Free Practice', score: 0, holdProgress: 0));
      await tester.pump();
      final headersAfterFirst = state.headerBuilds;
      final panelsAfterFirst = state.panelBuilds;

      apply(
        _base(
          movement: 'Free Practice',
          score: 55,
          holdProgress: 0.7,
          holdDurationMs: 1200,
          positiveFrameRatio: 0.4,
          jpeg: _jpegB,
        ),
      );
      await tester.pump();

      expect(state.headerBuilds, headersAfterFirst);
      expect(state.panelBuilds, panelsAfterFirst);
      expect(find.textContaining('frame=${_jpegB.length}'), findsOneWidget);

      apply(
        _base(
          movement: 'Free Practice',
          bottleDetected: false,
          score: 55,
          jpeg: _jpegA,
        ),
      );
      await tester.pump();
      expect(state.headerBuilds, greaterThan(headersAfterFirst));
      expect(find.textContaining('detected=false'), findsOneWidget);
    });
  });

  group('Scored Practice feedback handling path', () {
    testWidgets('score and hold updates rebuild only scoped listeners', (
      tester,
    ) async {
      late void Function(PracticeFeedback) apply;
      await tester.pumpWidget(
        _wrap(
          _ScoredPracticeFeedbackHarness(
            onFeedback: (handler) => apply = handler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_ScoredPracticeFeedbackHarnessState>(
        find.byType(_ScoredPracticeFeedbackHarness),
      );
      apply(_base(score: 70, holdProgress: 0.2));
      await tester.pump();
      final headersAfterFirst = state.headerBuilds;
      final panelsAfterFirst = state.panelBuilds;
      final scoreAfterFirst = state.scoreBuilds;
      final holdAfterFirst = state.holdBuilds;
      final comboAfterFirst = state.comboBuilds;

      apply(
        _base(
          score: 84,
          holdProgress: 0.65,
          holdDurationMs: 800,
          positiveFrameRatio: 0.95,
          jpeg: _jpegB,
        ),
      );
      await tester.pump();

      expect(state.headerBuilds, headersAfterFirst);
      expect(state.panelBuilds, panelsAfterFirst);
      expect(state.comboBuilds, comboAfterFirst);
      expect(state.scoreBuilds, greaterThan(scoreAfterFirst));
      expect(state.holdBuilds, greaterThan(holdAfterFirst));
      expect(find.text('score=84'), findsOneWidget);
      expect(find.text('hold=0.65'), findsOneWidget);

      apply(_base(score: 84, holdProgress: 0.65, feedback: 'New tip'));
      await tester.pump();
      expect(state.headerBuilds, greaterThan(headersAfterFirst));
      expect(find.textContaining('history=2'), findsOneWidget);
    });

    testWidgets('positive combo updates rebuild only combo listeners', (
      tester,
    ) async {
      late void Function(PracticeFeedback) apply;
      await tester.pumpWidget(
        _wrap(
          _ScoredPracticeFeedbackHarness(
            onFeedback: (handler) => apply = handler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_ScoredPracticeFeedbackHarnessState>(
        find.byType(_ScoredPracticeFeedbackHarness),
      );
      apply(_base(feedbackType: 'positive', score: 70));
      await tester.pump();
      final headersAfterFirst = state.headerBuilds;
      final panelsAfterFirst = state.panelBuilds;
      final comboAfterFirst = state.comboBuilds;

      apply(_base(feedbackType: 'positive', score: 72));
      await tester.pump();

      expect(state.headerBuilds, headersAfterFirst);
      expect(state.panelBuilds, panelsAfterFirst);
      expect(state.comboBuilds, greaterThan(comboAfterFirst));
      expect(find.text('combo=2'), findsOneWidget);
    });

    testWidgets('duplicate feedback does not grow history', (tester) async {
      late void Function(PracticeFeedback) apply;
      await tester.pumpWidget(
        _wrap(
          _ScoredPracticeFeedbackHarness(
            onFeedback: (handler) => apply = handler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      apply(_base(feedback: 'Keep steady'));
      await tester.pump();
      apply(_base(feedback: 'Keep steady', score: 71));
      await tester.pump();
      expect(find.textContaining('history=1'), findsOneWidget);

      apply(_base(feedback: 'Lower elbow', score: 72));
      await tester.pump();
      expect(find.textContaining('history=2'), findsOneWidget);

      apply(_base(feedback: 'Lower elbow', score: 73));
      await tester.pump();
      expect(find.textContaining('history=2'), findsOneWidget);
    });

    testWidgets('posture changes rebuild chrome and hold confirmation works', (
      tester,
    ) async {
      late void Function(PracticeFeedback) apply;
      await tester.pumpWidget(
        _wrap(
          _ScoredPracticeFeedbackHarness(
            onFeedback: (handler) => apply = handler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_ScoredPracticeFeedbackHarnessState>(
        find.byType(_ScoredPracticeFeedbackHarness),
      );
      apply(_base(postureStatus: 'stable'));
      await tester.pump();
      final panelsAfterFirst = state.panelBuilds;

      apply(_base(postureStatus: 'unstable'));
      await tester.pump();
      expect(state.panelBuilds, greaterThan(panelsAfterFirst));
      expect(find.textContaining('posture=unstable'), findsOneWidget);

      apply(_base(holdConfirmed: true));
      await tester.pump();
      expect(state.holdConfirmations, 1);
    });
  });
}
