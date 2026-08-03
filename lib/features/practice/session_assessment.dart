import '../../data/models/practice_feedback.dart';

/// One persistent technique issue identified across an active session.
class SessionImprovement {
  const SessionImprovement({
    required this.message,
    required this.occurrenceCount,
    required this.occurrenceRatio,
    required this.feedbackType,
    required this.representativeFeedback,
  });

  final String message;
  final int occurrenceCount;
  final double occurrenceRatio;
  final String feedbackType;
  final PracticeFeedback representativeFeedback;
}

/// Immutable completed-session assessment snapshot.
class SessionAssessment {
  const SessionAssessment({
    required this.finalScore,
    required this.heldSteady,
    required this.totalApplicableSamples,
    required this.positiveSampleCount,
    required this.positiveRatio,
    required this.improvements,
    this.latestFeedback,
  });

  final int finalScore;
  final bool heldSteady;
  final int totalApplicableSamples;
  final int positiveSampleCount;
  final double positiveRatio;
  final List<SessionImprovement> improvements;
  final PracticeFeedback? latestFeedback;

  bool get hasImprovements => improvements.isNotEmpty;

  List<String> get improvementMessages =>
      improvements.map((i) => i.message).toList(growable: false);

  /// Representative frames for summarized session improvements.
  List<PracticeFeedback> get improvementFeedbacks =>
      improvements.map((i) => i.representativeFeedback).toList(growable: false);
}

class _IssueAccumulator {
  _IssueAccumulator(this.representative);

  final PracticeFeedback representative;
  int count = 0;
}

/// Aggregates every active-session feedback frame into session-level assessment.
class SessionAssessmentAccumulator {
  static const minOccurrenceCount = 3;
  static const minOccurrenceRatio = 0.15;
  static const maxImprovements = 3;

  /// Environment and detection messages excluded from technique assessment.
  static const environmentSkipPhrases = [
    'not detected',
    'not visible',
    'Keep the bottle visible',
    'Step back',
    'Face the camera',
    'in frame',
    'Camera unavailable',
    'Model load failed',
    'Target body part',
  ];

  int _totalApplicableSamples = 0;
  int _positiveSampleCount = 0;
  final Map<String, _IssueAccumulator> _issues = {};

  int get totalApplicableSamples => _totalApplicableSamples;

  int get positiveSampleCount => _positiveSampleCount;

  double get positiveRatio => _totalApplicableSamples == 0
      ? 0
      : _positiveSampleCount / _totalApplicableSamples;

  void record(PracticeFeedback feedback) {
    if (!_isApplicableTechniqueSample(feedback)) {
      return;
    }

    _totalApplicableSamples++;
    if (feedback.feedbackType == 'positive') {
      _positiveSampleCount++;
      return;
    }

    final message = feedback.feedback;
    final issue = _issues.putIfAbsent(
      message,
      () => _IssueAccumulator(feedback),
    );
    issue.count++;
  }

  void reset() {
    _totalApplicableSamples = 0;
    _positiveSampleCount = 0;
    _issues.clear();
  }

  SessionAssessment buildAssessment({
    required int finalScore,
    required bool heldSteady,
    PracticeFeedback? latestFeedback,
  }) {
    final improvements = _deriveImprovements(
      finalScore: finalScore,
      heldSteady: heldSteady,
      latestFeedback: latestFeedback,
    );

    return SessionAssessment(
      finalScore: finalScore,
      heldSteady: heldSteady,
      totalApplicableSamples: _totalApplicableSamples,
      positiveSampleCount: _positiveSampleCount,
      positiveRatio: positiveRatio,
      improvements: improvements,
      latestFeedback: latestFeedback,
    );
  }

  List<SessionImprovement> _deriveImprovements({
    required int finalScore,
    required bool heldSteady,
    PracticeFeedback? latestFeedback,
  }) {
    if (heldSteady &&
        finalScore == 100 &&
        latestFeedback?.feedbackType == 'positive') {
      return const [];
    }

    if (_totalApplicableSamples == 0) {
      return const [];
    }

    final candidates = <SessionImprovement>[];
    for (final entry in _issues.entries) {
      final count = entry.value.count;
      final ratio = count / _totalApplicableSamples;
      if (count < minOccurrenceCount || ratio < minOccurrenceRatio) {
        continue;
      }

      final representative = entry.value.representative;
      candidates.add(
        SessionImprovement(
          message: entry.key,
          occurrenceCount: count,
          occurrenceRatio: ratio,
          feedbackType: representative.feedbackType,
          representativeFeedback: representative,
        ),
      );
    }

    candidates.sort((a, b) {
      final ratioCompare = b.occurrenceRatio.compareTo(a.occurrenceRatio);
      if (ratioCompare != 0) return ratioCompare;
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    });

    return List<SessionImprovement>.unmodifiable(
      candidates.take(maxImprovements),
    );
  }

  static bool _isApplicableTechniqueSample(PracticeFeedback feedback) {
    if (feedback.isPreparing) return false;
    if (feedback.sessionState != null && feedback.sessionState != 'active') {
      return false;
    }
    if (feedback.isSessionFatal) return false;
    if (_isEnvironmentMessage(feedback.feedback)) return false;
    return true;
  }

  static bool _isEnvironmentMessage(String message) {
    return environmentSkipPhrases.any(message.contains);
  }
}
