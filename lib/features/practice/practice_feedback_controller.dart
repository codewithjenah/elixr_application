import '../../data/models/practice_feedback.dart';
import 'session_assessment.dart';

/// High-frequency combo UI state scoped outside page rebuilds.
class ComboState {
  const ComboState({this.combo = 0, this.bestCombo = 0});

  final int combo;
  final int bestCombo;

  @override
  bool operator ==(Object other) {
    return other is ComboState &&
        combo == other.combo &&
        bestCombo == other.bestCombo;
  }

  @override
  int get hashCode => Object.hash(combo, bestCombo);
}

/// Score popup animation trigger state.
class ScorePopupState {
  const ScorePopupState({this.trigger = 0, this.delta = 0});

  final int trigger;
  final int delta;

  @override
  bool operator ==(Object other) {
    return other is ScorePopupState &&
        trigger == other.trigger &&
        delta == other.delta;
  }

  @override
  int get hashCode => Object.hash(trigger, delta);
}

/// Result of applying one active-session feedback frame.
class PracticeFeedbackApplyResult {
  const PracticeFeedbackApplyResult({
    required this.chromeChanged,
    required this.historyChanged,
    required this.scoreChanged,
    required this.holdChanged,
    required this.comboChanged,
    required this.scorePopupChanged,
    required this.holdConfirmed,
    required this.comboState,
    required this.scorePopupState,
    required this.latestFeedback,
    required this.feedbackHistory,
  });

  final bool chromeChanged;
  final bool historyChanged;
  final bool scoreChanged;
  final bool holdChanged;
  final bool comboChanged;
  final bool scorePopupChanged;
  final bool holdConfirmed;
  final ComboState comboState;
  final ScorePopupState scorePopupState;
  final PracticeFeedback latestFeedback;
  final List<PracticeFeedback> feedbackHistory;

  bool get needsChromeRebuild => chromeChanged || historyChanged;
}

/// Active-session feedback reducer extracted from [PracticeScreen].
class PracticeFeedbackController {
  PracticeFeedback? latestFeedback;
  final List<PracticeFeedback> feedbackHistory = [];
  ComboState comboState = const ComboState();
  ScorePopupState scorePopupState = const ScorePopupState();
  final SessionAssessmentAccumulator _assessmentAccumulator =
      SessionAssessmentAccumulator();

  PracticeFeedbackApplyResult applyActiveFeedback(PracticeFeedback feedback) {
    _assessmentAccumulator.record(feedback);
    final previous = latestFeedback;
    final previousScore = previous?.score;
    final previousHold = previous?.holdProgress ?? 0;

    final scoreChanged = previousScore != feedback.score;
    final holdChanged = previousHold != feedback.holdProgress;
    final chromeChanged = !feedback.scoredPracticeChromeEquals(previous);
    final historyChanged =
        feedbackHistory.isEmpty ||
        feedbackHistory.first.feedback != feedback.feedback;

    var nextCombo = comboState.combo;
    var nextBest = comboState.bestCombo;
    var comboChanged = false;
    if (feedback.feedbackType == 'positive') {
      nextCombo = comboState.combo + 1;
      if (nextCombo > comboState.bestCombo) {
        nextBest = nextCombo;
      }
      comboChanged =
          nextCombo != comboState.combo || nextBest != comboState.bestCombo;
    } else if (feedback.feedbackType == 'error' ||
        feedback.feedbackType == 'warning') {
      if (comboState.combo != 0) {
        nextCombo = 0;
        comboChanged = true;
      }
    }

    var scorePopupTrigger = scorePopupState.trigger;
    var scorePopupDelta = scorePopupState.delta;
    var scorePopupChanged = false;
    if (previousScore != null && feedback.score > previousScore) {
      scorePopupDelta = feedback.score - previousScore;
      scorePopupTrigger++;
      scorePopupChanged = true;
    }

    final nextComboState = ComboState(combo: nextCombo, bestCombo: nextBest);
    if (comboChanged) {
      comboState = nextComboState;
    }

    final nextScorePopupState = ScorePopupState(
      trigger: scorePopupTrigger,
      delta: scorePopupDelta,
    );
    if (scorePopupChanged) {
      scorePopupState = nextScorePopupState;
    }

    latestFeedback = feedback;
    if (historyChanged) {
      feedbackHistory.insert(0, feedback);
      if (feedbackHistory.length > 50) {
        feedbackHistory.removeLast();
      }
    }

    return PracticeFeedbackApplyResult(
      chromeChanged: chromeChanged,
      historyChanged: historyChanged,
      scoreChanged: scoreChanged,
      holdChanged: holdChanged,
      comboChanged: comboChanged,
      scorePopupChanged: scorePopupChanged,
      holdConfirmed: feedback.holdConfirmed,
      comboState: comboState,
      scorePopupState: scorePopupState,
      latestFeedback: feedback,
      feedbackHistory: List<PracticeFeedback>.unmodifiable(feedbackHistory),
    );
  }

  /// Free Practice prop-detection path (no score/combo/hold).
  bool applyFreePracticeFeedback(PracticeFeedback feedback) {
    final visibleChanged =
        latestFeedback?.bottleDetected != feedback.bottleDetected ||
        !feedback.freePracticeVisibleEquals(latestFeedback);
    latestFeedback = feedback;
    return visibleChanged;
  }

  SessionAssessment buildSessionAssessment({
    required int finalScore,
    required bool heldSteady,
  }) {
    return _assessmentAccumulator.buildAssessment(
      finalScore: finalScore,
      heldSteady: heldSteady,
      latestFeedback: latestFeedback,
    );
  }

  void reset() {
    latestFeedback = null;
    feedbackHistory.clear();
    comboState = const ComboState();
    scorePopupState = const ScorePopupState();
    _assessmentAccumulator.reset();
  }
}
