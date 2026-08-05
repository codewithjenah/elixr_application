import '../../data/models/practice_feedback.dart';
import 'coaching/session_coaching_models.dart';
import 'coaching/session_recommendation.dart';

export 'coaching/session_coaching_models.dart';

/// One persistent technique issue identified across an active session.
class SessionImprovement {
  const SessionImprovement({
    required this.message,
    required this.occurrenceCount,
    required this.occurrenceRatio,
    required this.feedbackType,
    required this.representativeFeedback,
    this.code,
  });

  final String message;
  final int occurrenceCount;
  final double occurrenceRatio;
  final String feedbackType;
  final PracticeFeedback representativeFeedback;

  /// Stable backend feedback code when present; null for legacy message keys.
  final String? code;

  /// Sample-honest alias for [occurrenceCount] (frame/sample count, not events).
  int get sampleCount => occurrenceCount;

  /// Sample-honest alias for [occurrenceRatio].
  double get sampleRatio => occurrenceRatio;
}

/// Post-session coaching snapshot composed under [SessionAssessment].
class SessionCoachingSummary {
  const SessionCoachingSummary({
    required this.strengths,
    required this.improvements,
    this.recommendation,
  });

  /// Empty coaching for legacy/manual [SessionAssessment] construction.
  /// Does not fabricate a recommendation or movement name.
  const SessionCoachingSummary.empty()
    : strengths = const [],
      improvements = const [],
      recommendation = null;

  final List<SessionStrength> strengths;

  /// Same list instance as [SessionAssessment.improvements] on production builds.
  final List<SessionImprovement> improvements;

  final SessionRecommendation? recommendation;

  bool get hasRecommendation => recommendation != null;

  bool get isEmpty =>
      strengths.isEmpty && improvements.isEmpty && recommendation == null;
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
    this.maxHoldDurationMs = 0,
    this.maxHoldProgress = 0.0,
    this.holdTargetMs = 0,
    this.coaching = const SessionCoachingSummary.empty(),
  });

  final int finalScore;
  final bool heldSteady;
  final int totalApplicableSamples;
  final int positiveSampleCount;
  final double positiveRatio;
  final List<SessionImprovement> improvements;
  final PracticeFeedback? latestFeedback;
  final int maxHoldDurationMs;
  final double maxHoldProgress;
  final int holdTargetMs;
  final SessionCoachingSummary coaching;

  bool get hasImprovements => improvements.isNotEmpty;

  List<String> get improvementMessages =>
      improvements.map((i) => i.message).toList(growable: false);

  /// Representative frames for summarized session improvements.
  List<PracticeFeedback> get improvementFeedbacks =>
      improvements.map((i) => i.representativeFeedback).toList(growable: false);
}

class _BucketAccumulator {
  _BucketAccumulator(this.representative, {this.code});

  final PracticeFeedback representative;
  final String? code;
  int count = 0;
}

/// Aggregates every active-session feedback frame into session-level assessment.
class SessionAssessmentAccumulator {
  static const minOccurrenceCount = 3;
  static const minOccurrenceRatio = 0.15;
  static const maxImprovements = 3;
  static const maxStrengths = 3;

  static const unconfirmedMinProgress = 0.40;
  static const unconfirmedMinDurationMs = 1000;
  static const exceptionalHoldExtraMs = 500;

  /// Environment and detection messages excluded from technique assessment
  /// when [PracticeFeedback.feedbackCategory] is absent (legacy frames).
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

  static const _excludedCategories = {'visibility', 'environment', 'system'};

  int _totalApplicableSamples = 0;
  int _positiveSampleCount = 0;
  final Map<String, _BucketAccumulator> _issues = {};
  final Map<String, _BucketAccumulator> _positiveBuckets = {};

  int _maxHoldDurationMs = 0;
  double _maxHoldProgress = 0;
  int _holdTargetMs = 0;
  bool _holdTargetConflictLogged = false;

  int get totalApplicableSamples => _totalApplicableSamples;

  int get positiveSampleCount => _positiveSampleCount;

  double get positiveRatio => _totalApplicableSamples == 0
      ? 0
      : _positiveSampleCount / _totalApplicableSamples;

  int get maxHoldDurationMs => _maxHoldDurationMs;

  double get maxHoldProgress => _maxHoldProgress;

  int get holdTargetMs => _holdTargetMs;

  /// True when a later nonzero target differed from the first captured target.
  bool get holdTargetHadConflict => _holdTargetConflictLogged;

  void record(PracticeFeedback feedback) {
    _trackHoldMetrics(feedback);

    if (!_isApplicableTechniqueSample(feedback)) {
      return;
    }

    _totalApplicableSamples++;
    if (feedback.feedbackType == 'positive') {
      _positiveSampleCount++;
      final code = feedback.feedbackCode;
      if (code != null && code.isNotEmpty) {
        final bucket = _positiveBuckets.putIfAbsent(
          code,
          () => _BucketAccumulator(feedback, code: code),
        );
        bucket.count++;
      }
      return;
    }

    final key = _issueKey(feedback);
    final issue = _issues.putIfAbsent(
      key,
      () => _BucketAccumulator(feedback, code: feedback.feedbackCode),
    );
    issue.count++;
  }

  void reset() {
    _totalApplicableSamples = 0;
    _positiveSampleCount = 0;
    _issues.clear();
    _positiveBuckets.clear();
    _maxHoldDurationMs = 0;
    _maxHoldProgress = 0;
    _holdTargetMs = 0;
    _holdTargetConflictLogged = false;
  }

  SessionAssessment buildAssessment({
    required String movement,
    required int finalScore,
    required bool heldSteady,
    PracticeFeedback? latestFeedback,
  }) {
    final improvements = _deriveImprovements();
    final strengths = _deriveStrengths(heldSteady: heldSteady);
    final recommendation = buildSessionRecommendation(
      movement: movement,
      heldSteady: heldSteady,
      finalScore: finalScore,
      positiveRatio: positiveRatio,
      totalApplicableSamples: _totalApplicableSamples,
      improvements: improvements,
      maxHoldDurationMs: _maxHoldDurationMs,
      maxHoldProgress: _maxHoldProgress,
      holdTargetMs: _holdTargetMs,
    );
    final coaching = SessionCoachingSummary(
      strengths: strengths,
      improvements: improvements,
      recommendation: recommendation,
    );

    return SessionAssessment(
      finalScore: finalScore,
      heldSteady: heldSteady,
      totalApplicableSamples: _totalApplicableSamples,
      positiveSampleCount: _positiveSampleCount,
      positiveRatio: positiveRatio,
      improvements: improvements,
      latestFeedback: latestFeedback,
      maxHoldDurationMs: _maxHoldDurationMs,
      maxHoldProgress: _maxHoldProgress,
      holdTargetMs: _holdTargetMs,
      coaching: coaching,
    );
  }

  void _trackHoldMetrics(PracticeFeedback feedback) {
    if (feedback.holdDurationMs > _maxHoldDurationMs) {
      _maxHoldDurationMs = feedback.holdDurationMs;
    }
    if (feedback.holdProgress > _maxHoldProgress) {
      _maxHoldProgress = feedback.holdProgress;
    }

    final target = feedback.holdTargetMs;
    if (target <= 0) {
      return;
    }
    if (_holdTargetMs == 0) {
      _holdTargetMs = target;
      return;
    }
    if (target != _holdTargetMs) {
      // Keep the first nonzero target; do not silently replace.
      _holdTargetConflictLogged = true;
    }
  }

  List<SessionImprovement> _deriveImprovements() {
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
          message: representative.feedback,
          occurrenceCount: count,
          occurrenceRatio: ratio,
          feedbackType: representative.feedbackType,
          representativeFeedback: representative,
          code: entry.value.code,
        ),
      );
    }

    candidates.sort((a, b) {
      final severity = _severityRank(
        b.feedbackType,
      ).compareTo(_severityRank(a.feedbackType));
      if (severity != 0) return severity;
      final ratioCompare = b.occurrenceRatio.compareTo(a.occurrenceRatio);
      if (ratioCompare != 0) return ratioCompare;
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    });

    return List<SessionImprovement>.unmodifiable(
      candidates.take(maxImprovements),
    );
  }

  List<SessionStrength> _deriveStrengths({required bool heldSteady}) {
    final strengths = <SessionStrength>[];

    final holdStrength = _deriveHoldStrength(heldSteady: heldSteady);
    if (holdStrength != null) {
      strengths.add(holdStrength);
    }

    if (_totalApplicableSamples > 0) {
      final positiveCandidates = <SessionStrength>[];
      for (final entry in _positiveBuckets.entries) {
        final count = entry.value.count;
        final ratio = count / _totalApplicableSamples;
        if (count < minOccurrenceCount || ratio < minOccurrenceRatio) {
          continue;
        }
        positiveCandidates.add(
          SessionStrength(
            code: entry.key,
            message: entry.value.representative.feedback,
            sampleCount: count,
            sampleRatio: ratio,
            evidenceKind: 'positiveCode',
          ),
        );
      }
      positiveCandidates.sort((a, b) {
        final ratioCompare = b.sampleRatio.compareTo(a.sampleRatio);
        if (ratioCompare != 0) return ratioCompare;
        return b.sampleCount.compareTo(a.sampleCount);
      });
      for (final candidate in positiveCandidates) {
        if (strengths.length >= maxStrengths) break;
        strengths.add(candidate);
      }
    }

    return List<SessionStrength>.unmodifiable(strengths.take(maxStrengths));
  }

  SessionStrength? _deriveHoldStrength({required bool heldSteady}) {
    if (heldSteady) {
      final exceptional =
          _holdTargetMs > 0 &&
          _maxHoldDurationMs >= _holdTargetMs + exceptionalHoldExtraMs;
      if (exceptional) {
        final seconds = (_maxHoldDurationMs / 1000.0).toStringAsFixed(1);
        return SessionStrength(
          code: 'hold_confirmed',
          message: 'Hold confirmed — best hold $seconds seconds',
          sampleCount: 1,
          sampleRatio: 1,
          evidenceKind: 'holdExceptionalDuration',
        );
      }
      return const SessionStrength(
        code: 'hold_confirmed',
        message: 'Hold confirmed',
        sampleCount: 1,
        sampleRatio: 1,
        evidenceKind: 'holdConfirmed',
      );
    }

    if (_holdTargetMs > 0 && _maxHoldProgress >= unconfirmedMinProgress) {
      final percent = (_maxHoldProgress * 100).floor().clamp(0, 99);
      return SessionStrength(
        code: 'hold_partial_progress',
        message: 'Best hold reached $percent% of the target',
        sampleCount: 1,
        sampleRatio: _maxHoldProgress,
        evidenceKind: 'holdPartialProgress',
      );
    }

    if (_maxHoldDurationMs >= unconfirmedMinDurationMs) {
      final seconds = (_maxHoldDurationMs / 1000.0).toStringAsFixed(1);
      return SessionStrength(
        code: 'hold_partial_duration',
        message: 'Best hold $seconds seconds',
        sampleCount: 1,
        sampleRatio: 1,
        evidenceKind: 'holdPartialDuration',
      );
    }

    return null;
  }

  static String _issueKey(PracticeFeedback feedback) {
    final code = feedback.feedbackCode;
    if (code != null && code.isNotEmpty) {
      return 'code:$code';
    }
    return 'legacy:${feedback.feedback}';
  }

  static int _severityRank(String feedbackType) {
    switch (feedbackType) {
      case 'error':
        return 2;
      case 'warning':
        return 1;
      default:
        return 0;
    }
  }

  static bool _isApplicableTechniqueSample(PracticeFeedback feedback) {
    if (feedback.isPreparing) return false;
    if (feedback.sessionState != null && feedback.sessionState != 'active') {
      return false;
    }
    if (feedback.isSessionFatal) return false;

    final category = feedback.feedbackCategory;
    if (category != null) {
      if (_excludedCategories.contains(category)) {
        return false;
      }
      return true;
    }

    if (_isEnvironmentMessage(feedback.feedback)) return false;
    return true;
  }

  static bool _isEnvironmentMessage(String message) {
    return environmentSkipPhrases.any(message.contains);
  }
}
