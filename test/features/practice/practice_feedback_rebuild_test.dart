import 'dart:convert';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _headerKey = ValueKey<String>('rebuild-header');
const _panelKey = ValueKey<String>('rebuild-panel');
const _scoreKey = ValueKey<String>('rebuild-score');
const _holdKey = ValueKey<String>('rebuild-hold');

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
  );
}

/// Mirrors [LivePracticeScreen] active-feedback rebuild gating.
class _FreePracticeFeedbackHarness extends StatefulWidget {
  const _FreePracticeFeedbackHarness({required this.onFeedback});

  final void Function(void Function(PracticeFeedback) apply) onFeedback;

  @override
  State<_FreePracticeFeedbackHarness> createState() =>
      _FreePracticeFeedbackHarnessState();
}

class _FreePracticeFeedbackHarnessState
    extends State<_FreePracticeFeedbackHarness> {
  final ValueNotifier<Uint8List?> frameBytes = ValueNotifier<Uint8List?>(null);
  PracticeFeedback? latest;
  bool bottleDetected = false;
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
    final visibleChanged =
        bottleDetected != feedback.bottleDetected ||
        !feedback.freePracticeVisibleEquals(latest);
    if (visibleChanged) {
      setState(() {
        bottleDetected = feedback.bottleDetected;
        latest = feedback;
      });
    } else {
      latest = feedback;
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
                'Free header ${latest?.movement ?? '-'} '
                'detected=$bottleDetected',
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
              'panel ${latest?.propType.displayLabel ?? '-'}',
              key: _panelKey,
            );
          },
        ),
      ],
    );
  }
}

/// Mirrors [PracticeScreen] active-feedback rebuild gating with scoped score/hold.
class _ScoredPracticeFeedbackHarness extends StatefulWidget {
  const _ScoredPracticeFeedbackHarness({required this.onFeedback});

  final void Function(void Function(PracticeFeedback) apply) onFeedback;

  @override
  State<_ScoredPracticeFeedbackHarness> createState() =>
      _ScoredPracticeFeedbackHarnessState();
}

class _ScoredPracticeFeedbackHarnessState
    extends State<_ScoredPracticeFeedbackHarness> {
  final ValueNotifier<Uint8List?> frameBytes = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<int?> scoreNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<double> holdNotifier = ValueNotifier<double>(0);
  PracticeFeedback? latest;
  int headerBuilds = 0;
  int panelBuilds = 0;
  int scoreBuilds = 0;
  int holdBuilds = 0;

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
    super.dispose();
  }

  void applyFeedback(PracticeFeedback feedback) {
    if (feedback.frameJpegBytes != null) {
      frameBytes.value = feedback.frameJpegBytes;
    }
    scoreNotifier.value = feedback.score;
    holdNotifier.value = feedback.holdProgress;

    final chromeChanged = !feedback.scoredPracticeChromeEquals(latest);
    if (chromeChanged) {
      setState(() => latest = feedback);
    } else {
      latest = feedback;
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
              'Scored header ${latest?.movement ?? '-'}',
              key: _headerKey,
            );
          },
        ),
        Builder(
          builder: (context) {
            panelBuilds++;
            return Text(
              'panel posture=${latest?.postureStatus ?? '-'}',
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

    test('freePracticeVisibleEquals reacts to bottle detection', () {
      final a = _base(bottleDetected: true);
      final b = _base(bottleDetected: false);
      expect(a.freePracticeVisibleEquals(b), isFalse);
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
      expect(state.scoreBuilds, greaterThan(scoreAfterFirst));
      expect(state.holdBuilds, greaterThan(holdAfterFirst));
      expect(find.text('score=84'), findsOneWidget);
      expect(find.text('hold=0.65'), findsOneWidget);

      apply(_base(score: 84, holdProgress: 0.65, feedback: 'New tip'));
      await tester.pump();
      expect(state.headerBuilds, greaterThan(headersAfterFirst));
    });
  });
}
