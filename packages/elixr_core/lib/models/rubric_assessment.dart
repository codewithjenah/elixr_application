/// Assessment V2 rubric domain — sole Dart authority for 0..12 totals and
/// performance-level thresholds.
///
/// Do not duplicate threshold logic in widgets. Derive [total] and
/// [performanceLevel] from the four criterion scores; never trust a
/// client-supplied total or level when reading from Firestore.
library;

enum RubricCriterion {
  technique,
  stability,
  completion,
  propPositioning;

  String get wireValue => switch (this) {
    RubricCriterion.technique => 'technique',
    RubricCriterion.stability => 'stability',
    RubricCriterion.completion => 'completion',
    RubricCriterion.propPositioning => 'prop_positioning',
  };

  String get label => switch (this) {
    RubricCriterion.technique => 'Correct Technique',
    RubricCriterion.stability => 'Stability / Control',
    RubricCriterion.completion => 'Hold / Completion',
    RubricCriterion.propPositioning => 'Prop Positioning',
  };

  static RubricCriterion? tryParse(String? value) {
    if (value == null) return null;
    for (final criterion in RubricCriterion.values) {
      if (criterion.wireValue == value) return criterion;
    }
    return null;
  }
}

enum PerformanceLevel {
  beginning,
  developing,
  competent,
  proficient,
  mastered;

  String get wireValue => switch (this) {
    PerformanceLevel.beginning => 'beginning',
    PerformanceLevel.developing => 'developing',
    PerformanceLevel.competent => 'competent',
    PerformanceLevel.proficient => 'proficient',
    PerformanceLevel.mastered => 'mastered',
  };

  String get label => switch (this) {
    PerformanceLevel.beginning => 'Beginning',
    PerformanceLevel.developing => 'Developing',
    PerformanceLevel.competent => 'Competent',
    PerformanceLevel.proficient => 'Proficient',
    PerformanceLevel.mastered => 'Mastered',
  };

  /// Short badge label for compact UI.
  String get shortLabel => switch (this) {
    PerformanceLevel.beginning => 'Beg',
    PerformanceLevel.developing => 'Dev',
    PerformanceLevel.competent => 'Cmp',
    PerformanceLevel.proficient => 'Pro',
    PerformanceLevel.mastered => 'Mst',
  };

  static PerformanceLevel? tryParse(String? value) {
    if (value == null) return null;
    for (final level in PerformanceLevel.values) {
      if (level.wireValue == value) return level;
    }
    return null;
  }

  /// Authoritative thresholds: 0–3 / 4–6 / 7–9 / 10–11 / 12.
  static PerformanceLevel fromTotal(int total) {
    if (total < 0 || total > RubricAssessment.maxTotalScore) {
      throw ArgumentError.value(total, 'total', 'must be 0..12');
    }
    if (total <= 3) return PerformanceLevel.beginning;
    if (total <= 6) return PerformanceLevel.developing;
    if (total <= 9) return PerformanceLevel.competent;
    if (total <= 11) return PerformanceLevel.proficient;
    return PerformanceLevel.mastered;
  }

  /// Same thresholds applied to an average rubric total (rounded).
  static PerformanceLevel fromAverage(double average) {
    if (average < 0 || average > 12) {
      throw ArgumentError.value(average, 'average', 'must be 0..12');
    }
    return fromTotal(average.round().clamp(0, 12));
  }
}

class CriterionScore {
  const CriterionScore({
    required this.score,
    required this.reasonCode,
    this.explanation,
  }) : assert(score >= 0 && score <= 3);

  final int score;
  final String reasonCode;
  final String? explanation;

  Map<String, dynamic> toJson() => {
    'score': score,
    'reason_code': reasonCode,
    if (explanation != null) 'explanation': explanation,
  };

  static CriterionScore? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final scoreRaw = raw['score'];
    final reason = raw['reason_code'];
    if (scoreRaw is! num ||
        !scoreRaw.isFinite ||
        scoreRaw != scoreRaw.truncateToDouble() ||
        reason is! String ||
        reason.isEmpty) {
      return null;
    }
    final score = scoreRaw.toInt();
    if (score < 0 || score > 3) return null;
    final explanation = raw['explanation'];
    return CriterionScore(
      score: score,
      reasonCode: reason,
      explanation: explanation is String ? explanation : null,
    );
  }
}

class RubricAssessment {
  static const maxCriterionScore = 3;
  static const maxTotalScore = maxCriterionScore * 4;
  const RubricAssessment({
    required this.technique,
    required this.stability,
    required this.completion,
    required this.propPositioning,
    this.version = 2,
    this.techniqueReason,
    this.stabilityReason,
    this.completionReason,
    this.propPositioningReason,
  }) : assert(version == 2),
       assert(technique >= 0 && technique <= 3),
       assert(stability >= 0 && stability <= 3),
       assert(completion >= 0 && completion <= 3),
       assert(propPositioning >= 0 && propPositioning <= 3);

  final int technique;
  final int stability;
  final int completion;
  final int propPositioning;
  final int version;

  /// Optional reason codes from the live WebSocket payload.
  final String? techniqueReason;
  final String? stabilityReason;
  final String? completionReason;
  final String? propPositioningReason;

  int get total => technique + stability + completion + propPositioning;

  PerformanceLevel get performanceLevel => PerformanceLevel.fromTotal(total);

  int scoreFor(RubricCriterion criterion) => switch (criterion) {
    RubricCriterion.technique => technique,
    RubricCriterion.stability => stability,
    RubricCriterion.completion => completion,
    RubricCriterion.propPositioning => propPositioning,
  };

  /// Firestore session write fields (Assessment V2).
  Map<String, dynamic> toFirestoreFields() => {
    'assessment_version': version,
    'rubric': {
      'technique': technique,
      'stability': stability,
      'completion': completion,
      'prop_positioning': propPositioning,
    },
    'rubric_total': total,
    'performance_level': performanceLevel.wireValue,
  };

  Map<String, dynamic> toJson() => {
    'version': version,
    'criteria': {
      'technique': {
        'score': technique,
        'reason_code': techniqueReason ?? 'technique',
      },
      'stability': {
        'score': stability,
        'reason_code': stabilityReason ?? 'stability',
      },
      'completion': {
        'score': completion,
        'reason_code': completionReason ?? 'completion',
      },
      'prop_positioning': {
        'score': propPositioning,
        'reason_code': propPositioningReason ?? 'prop_positioning',
      },
    },
    'total': total,
    'performance_level': performanceLevel.wireValue,
  };

  /// Parse WebSocket `assessment` payload. Returns null on malformed input.
  /// Ignores a client-supplied total/level and re-derives them.
  static RubricAssessment? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    if (version is! num || version != 2) return null;
    final criteria = raw['criteria'];
    if (criteria is! Map) return null;

    final technique = CriterionScore.tryFromJson(criteria['technique']);
    final stability = CriterionScore.tryFromJson(criteria['stability']);
    final completion = CriterionScore.tryFromJson(criteria['completion']);
    final prop = CriterionScore.tryFromJson(criteria['prop_positioning']);
    if (technique == null ||
        stability == null ||
        completion == null ||
        prop == null) {
      return null;
    }

    final assessment = RubricAssessment(
      technique: technique.score,
      stability: stability.score,
      completion: completion.score,
      propPositioning: prop.score,
      techniqueReason: technique.reasonCode,
      stabilityReason: stability.reasonCode,
      completionReason: completion.reasonCode,
      propPositioningReason: prop.reasonCode,
    );

    // Reject payloads whose claimed total/level disagree with derivation.
    final claimedTotal = raw['total'];
    if (claimedTotal is num &&
        (!claimedTotal.isFinite ||
            claimedTotal != claimedTotal.truncateToDouble() ||
            claimedTotal.toInt() != assessment.total)) {
      return null;
    }
    final claimedLevel = raw['performance_level'];
    if (claimedLevel is String &&
        claimedLevel != assessment.performanceLevel.wireValue) {
      return null;
    }
    return assessment;
  }

  /// Parse a Firestore session document map (partial or full).
  static RubricAssessment? tryFromFirestore(Map<String, dynamic> map) {
    final version = map['assessment_version'];
    if (version is! num || version != 2) return null;
    final rubric = map['rubric'];
    if (rubric is! Map) return null;

    int? readCriterion(String key) {
      final value = rubric[key];
      if (value is! num ||
          !value.isFinite ||
          value != value.truncateToDouble()) {
        return null;
      }
      final score = value.toInt();
      if (score < 0 || score > 3) return null;
      return score;
    }

    final technique = readCriterion('technique');
    final stability = readCriterion('stability');
    final completion = readCriterion('completion');
    final prop = readCriterion('prop_positioning');
    if (technique == null ||
        stability == null ||
        completion == null ||
        prop == null) {
      return null;
    }

    final assessment = RubricAssessment(
      technique: technique,
      stability: stability,
      completion: completion,
      propPositioning: prop,
    );

    final claimedTotal = map['rubric_total'];
    if (claimedTotal is num &&
        (!claimedTotal.isFinite ||
            claimedTotal != claimedTotal.truncateToDouble() ||
            claimedTotal.toInt() != assessment.total)) {
      return null;
    }
    final claimedLevel = map['performance_level'];
    if (claimedLevel is String &&
        claimedLevel != assessment.performanceLevel.wireValue) {
      return null;
    }
    return assessment;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RubricAssessment &&
        other.technique == technique &&
        other.stability == stability &&
        other.completion == completion &&
        other.propPositioning == propPositioning &&
        other.version == version;
  }

  @override
  int get hashCode =>
      Object.hash(technique, stability, completion, propPositioning, version);
}
