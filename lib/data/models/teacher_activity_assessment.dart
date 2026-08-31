import 'training_prop.dart';

/// Versioned, portable assessment contract used by Teacher Activity revisions,
/// published Assignments, and immutable assessment-attempt snapshots.
abstract final class TeacherActivityAssessmentContract {
  static const schemaVersion = 2;
  static const defaultMaximumScore = 50;
  static const supportedMaximumScores = <int>{30, 50, 100};
  static const supportedRecordingDurations = <int>{15, 30, 45, 60};
  static const defaultRecordingDurationSeconds = 30;
  static const maximumRecordingDurationSeconds = 60;
  static const maximumVideoSizeBytes = 50 * 1024 * 1024;
}

enum ActivityPropRequirement {
  none('none', 'No prop'),
  oneBottle('one_bottle', 'One bottle'),
  oneShaker('one_shaker', 'One shaker'),
  bottleAndShaker('bottle_and_shaker', 'Bottle + shaker'),
  twoBottles('two_bottles', 'Two bottles');

  const ActivityPropRequirement(this.wireValue, this.displayLabel);
  final String wireValue;
  final String displayLabel;

  static ActivityPropRequirement? tryParse(Object? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

enum ActivityHandRequirement {
  none('none', 'No hand requirement'),
  oneHand('one_hand', 'One hand visible'),
  twoHands('two_hands', 'Two hands visible');

  const ActivityHandRequirement(this.wireValue, this.displayLabel);
  final String wireValue;
  final String displayLabel;

  static ActivityHandRequirement? tryParse(Object? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

enum ActivityBodyRequirement {
  none('none', 'No body requirement'),
  upperBody('upper_body', 'Upper body visible');

  const ActivityBodyRequirement(this.wireValue, this.displayLabel);
  final String wireValue;
  final String displayLabel;

  static ActivityBodyRequirement? tryParse(Object? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

class TeacherActivityReadinessSpec {
  const TeacherActivityReadinessSpec({
    this.prop = ActivityPropRequirement.none,
    this.hands = ActivityHandRequirement.none,
    this.body = ActivityBodyRequirement.none,
  });

  final ActivityPropRequirement prop;
  final ActivityHandRequirement hands;
  final ActivityBodyRequirement body;

  bool get isCameraOnly =>
      prop == ActivityPropRequirement.none &&
      hands == ActivityHandRequirement.none &&
      body == ActivityBodyRequirement.none;

  Map<String, dynamic> toMap() => {
    'prop': prop.wireValue,
    'hands': hands.wireValue,
    'body': body.wireValue,
  };

  static TeacherActivityReadinessSpec? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map.keys.toSet().difference({'prop', 'hands', 'body'}).isNotEmpty) {
      return null;
    }
    final prop = ActivityPropRequirement.tryParse(map['prop']);
    final hands = ActivityHandRequirement.tryParse(map['hands']);
    final body = ActivityBodyRequirement.tryParse(map['body']);
    if (prop == null || hands == null || body == null) return null;
    return TeacherActivityReadinessSpec(prop: prop, hands: hands, body: body);
  }

  factory TeacherActivityReadinessSpec.legacy(TrainingProp prop) {
    return TeacherActivityReadinessSpec(
      prop: switch (prop) {
        TrainingProp.bottle => ActivityPropRequirement.oneBottle,
        TrainingProp.shaker => ActivityPropRequirement.oneShaker,
        TrainingProp.bottleAndShaker => ActivityPropRequirement.bottleAndShaker,
      },
    );
  }
}

class TeacherActivityAttemptPolicy {
  const TeacherActivityAttemptPolicy.finite(int maximumAttempts)
    : maximumAttempts = maximumAttempts,
      assert(maximumAttempts >= 1 && maximumAttempts <= 3);
  const TeacherActivityAttemptPolicy.unlimited() : maximumAttempts = null;

  static const defaultPolicy = TeacherActivityAttemptPolicy.finite(3);
  final int? maximumAttempts;
  bool get isUnlimited => maximumAttempts == null;
  String get displayLabel => isUnlimited ? 'Unlimited' : '$maximumAttempts';

  Map<String, dynamic> toMap() => {
    'type': isUnlimited ? 'unlimited' : 'finite',
    if (!isUnlimited) 'maximum_attempts': maximumAttempts,
  };

  static TeacherActivityAttemptPolicy? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type'];
    if (type == 'unlimited' && map.length == 1) {
      return const TeacherActivityAttemptPolicy.unlimited();
    }
    final maximum = map['maximum_attempts'];
    if (type == 'finite' &&
        map.length == 2 &&
        maximum is int &&
        maximum >= 1 &&
        maximum <= 3) {
      return TeacherActivityAttemptPolicy.finite(maximum);
    }
    return null;
  }
}

enum TeacherActivityRubricTemplate {
  standardTechnique('standard_technique', 'Standard Technique'),
  beginnerFundamentals('beginner_fundamentals', 'Beginner Fundamentals'),
  controlConsistency('control_consistency', 'Control & Consistency'),
  performanceFlow('performance_flow', 'Performance & Flow'),
  custom('custom', 'Custom');

  const TeacherActivityRubricTemplate(this.wireValue, this.displayLabel);
  final String wireValue;
  final String displayLabel;

  static TeacherActivityRubricTemplate? tryParse(Object? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

class TeacherActivityRubricCriterion {
  const TeacherActivityRubricCriterion({
    required this.id,
    required this.label,
    required this.description,
    required this.maximumPoints,
    this.weight,
  });

  final String id;
  final String label;
  final String description;
  final int maximumPoints;
  final int? weight;

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'description': description,
    'maximum_points': maximumPoints,
    if (weight != null) 'weight': weight,
  };

  static TeacherActivityRubricCriterion? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = _boundedText(map['id'], 64);
    final label = _boundedText(map['label'], 80);
    final description = _boundedText(map['description'], 500);
    final maximum = map['maximum_points'];
    final weight = map['weight'];
    if (id == null ||
        label == null ||
        description == null ||
        maximum is! int ||
        maximum < 1 ||
        maximum > 100 ||
        (weight != null && (weight is! int || weight < 1 || weight > 100))) {
      return null;
    }
    return TeacherActivityRubricCriterion(
      id: id,
      label: label,
      description: description,
      maximumPoints: maximum,
      weight: weight as int?,
    );
  }
}

class TeacherActivityRubric {
  const TeacherActivityRubric({
    required this.template,
    required this.maximumScore,
    required this.criteria,
  });

  final TeacherActivityRubricTemplate template;
  final int maximumScore;
  final List<TeacherActivityRubricCriterion> criteria;

  bool get isValid =>
      maximumScore >= 1 &&
      maximumScore <= 100 &&
      criteria.length >= 3 &&
      criteria.length <= 5 &&
      criteria.map((item) => item.id).toSet().length == criteria.length &&
      criteria.fold<int>(0, (sum, item) => sum + item.maximumPoints) ==
          maximumScore;

  Map<String, dynamic> toMap() {
    if (!isValid) throw StateError('Rubric criteria must total maximum score.');
    return {
      'template_id': template.wireValue,
      'maximum_score': maximumScore,
      'criteria': criteria.map((item) => item.toMap()).toList(),
    };
  }

  static TeacherActivityRubric? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final template = TeacherActivityRubricTemplate.tryParse(map['template_id']);
    final maximum = map['maximum_score'];
    final rawCriteria = map['criteria'];
    if (template == null || maximum is! int || rawCriteria is! List) {
      return null;
    }
    final criteria = rawCriteria
        .map(TeacherActivityRubricCriterion.tryFrom)
        .whereType<TeacherActivityRubricCriterion>()
        .toList(growable: false);
    if (criteria.length != rawCriteria.length) return null;
    final rubric = TeacherActivityRubric(
      template: template,
      maximumScore: maximum,
      criteria: criteria,
    );
    return rubric.isValid ? rubric : null;
  }

  factory TeacherActivityRubric.builtIn(
    TeacherActivityRubricTemplate template,
    int maximumScore,
  ) {
    if (template == TeacherActivityRubricTemplate.custom) {
      throw ArgumentError.value(template, 'template', 'Use a custom rubric.');
    }
    if (maximumScore < 1 || maximumScore > 100) {
      throw ArgumentError.value(maximumScore, 'maximumScore');
    }
    final definitions = _builtInCriteria[template]!;
    final caps = _scaleWeights(
      definitions.map((item) => item.$4).toList(),
      maximumScore,
    );
    return TeacherActivityRubric(
      template: template,
      maximumScore: maximumScore,
      criteria: [
        for (var index = 0; index < definitions.length; index++)
          TeacherActivityRubricCriterion(
            id: definitions[index].$1,
            label: definitions[index].$2,
            description: definitions[index].$3,
            maximumPoints: caps[index],
            weight: definitions[index].$4,
          ),
      ],
    );
  }

  static const _builtInCriteria =
      <TeacherActivityRubricTemplate, List<(String, String, String, int)>>{
        TeacherActivityRubricTemplate.standardTechnique: [
          (
            'setup',
            'Setup',
            'Uses the required setup and starting position.',
            20,
          ),
          (
            'technique',
            'Technique',
            'Performs the demonstrated technique safely and accurately.',
            40,
          ),
          (
            'control',
            'Control',
            'Maintains deliberate control of props and body position.',
            25,
          ),
          (
            'finish',
            'Finish',
            'Completes the movement with a stable, intentional finish.',
            15,
          ),
        ],
        TeacherActivityRubricTemplate.beginnerFundamentals: [
          (
            'readiness',
            'Preparation',
            'Begins prepared and follows the activity instructions.',
            25,
          ),
          (
            'fundamentals',
            'Core fundamentals',
            'Shows the essential beginner mechanics.',
            35,
          ),
          (
            'safety',
            'Safe execution',
            'Keeps the practice controlled and follows safety guidance.',
            25,
          ),
          ('completion', 'Completion', 'Completes the requested sequence.', 15),
        ],
        TeacherActivityRubricTemplate.controlConsistency: [
          (
            'control',
            'Prop control',
            'Keeps the prop controlled throughout the attempt.',
            35,
          ),
          (
            'consistency',
            'Consistency',
            'Repeats the movement with consistent mechanics.',
            30,
          ),
          ('timing', 'Timing', 'Uses steady and intentional timing.', 20),
          (
            'recovery',
            'Recovery',
            'Recovers smoothly without unsafe movement.',
            15,
          ),
        ],
        TeacherActivityRubricTemplate.performanceFlow: [
          (
            'flow',
            'Flow',
            'Connects actions smoothly without unnecessary pauses.',
            30,
          ),
          ('timing', 'Timing', 'Maintains purposeful rhythm and pacing.', 25),
          (
            'presentation',
            'Presentation',
            'Shows confidence, clarity, and audience awareness.',
            25,
          ),
          (
            'control',
            'Control',
            'Preserves safe technical control throughout.',
            20,
          ),
        ],
      };
}

enum TeacherActivityDemoSource {
  uploaded('uploaded'),
  recorded('recorded');

  const TeacherActivityDemoSource(this.wireValue);
  final String wireValue;

  static TeacherActivityDemoSource? tryParse(Object? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

class TeacherActivityVideoMetadata {
  const TeacherActivityVideoMetadata({
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.durationMs,
    required this.source,
  });

  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final int durationMs;
  final TeacherActivityDemoSource source;

  Map<String, dynamic> toMap() => {
    'storage_path': storagePath,
    'content_type': contentType,
    'size_bytes': sizeBytes,
    'duration_ms': durationMs,
    'source': source.wireValue,
  };

  static TeacherActivityVideoMetadata? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final path = _boundedText(map['storage_path'], 1024);
    final type = map['content_type'];
    final size = map['size_bytes'];
    final duration = map['duration_ms'];
    final source = TeacherActivityDemoSource.tryParse(map['source']);
    if (path == null ||
        type != 'video/mp4' ||
        size is! int ||
        size < 1 ||
        size > TeacherActivityAssessmentContract.maximumVideoSizeBytes ||
        duration is! int ||
        duration < 1 ||
        duration > 60000 ||
        source == null) {
      return null;
    }
    return TeacherActivityVideoMetadata(
      storagePath: path,
      contentType: type as String,
      sizeBytes: size,
      durationMs: duration,
      source: source,
    );
  }
}

class TeacherActivityAssessmentConfig {
  const TeacherActivityAssessmentConfig({
    required this.readiness,
    required this.rubric,
    this.attemptPolicy = TeacherActivityAttemptPolicy.defaultPolicy,
    this.recordingDurationSeconds =
        TeacherActivityAssessmentContract.defaultRecordingDurationSeconds,
    this.demonstrationVideo,
    this.schemaVersion = TeacherActivityAssessmentContract.schemaVersion,
  });

  final int schemaVersion;
  final TeacherActivityReadinessSpec readiness;
  final TeacherActivityRubric rubric;
  final TeacherActivityAttemptPolicy attemptPolicy;
  final int recordingDurationSeconds;
  final TeacherActivityVideoMetadata? demonstrationVideo;

  bool get isValid =>
      schemaVersion == TeacherActivityAssessmentContract.schemaVersion &&
      TeacherActivityAssessmentContract.supportedRecordingDurations.contains(
        recordingDurationSeconds,
      ) &&
      rubric.isValid;

  Map<String, dynamic> toMap() {
    if (!isValid) throw StateError('Invalid Teacher Activity assessment.');
    return {
      'schema_version': schemaVersion,
      'readiness': readiness.toMap(),
      'rubric': rubric.toMap(),
      'attempt_policy': attemptPolicy.toMap(),
      'recording_duration_seconds': recordingDurationSeconds,
      if (demonstrationVideo != null)
        'demonstration_video': demonstrationVideo!.toMap(),
    };
  }

  static TeacherActivityAssessmentConfig? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['schema_version'] !=
        TeacherActivityAssessmentContract.schemaVersion) {
      return null;
    }
    final readiness = TeacherActivityReadinessSpec.tryFrom(map['readiness']);
    final rubric = TeacherActivityRubric.tryFrom(map['rubric']);
    final attempts = TeacherActivityAttemptPolicy.tryFrom(
      map['attempt_policy'],
    );
    final duration = map['recording_duration_seconds'];
    TeacherActivityVideoMetadata? demo;
    if (map.containsKey('demonstration_video')) {
      demo = TeacherActivityVideoMetadata.tryFrom(map['demonstration_video']);
      if (demo == null) return null;
    }
    if (readiness == null ||
        rubric == null ||
        attempts == null ||
        duration is! int) {
      return null;
    }
    final config = TeacherActivityAssessmentConfig(
      readiness: readiness,
      rubric: rubric,
      attemptPolicy: attempts,
      recordingDurationSeconds: duration,
      demonstrationVideo: demo,
    );
    return config.isValid ? config : null;
  }

  static TeacherActivityAssessmentConfig newActivityDefaults({
    TrainingProp legacyProp = TrainingProp.bottle,
  }) => TeacherActivityAssessmentConfig(
    readiness: TeacherActivityReadinessSpec.legacy(legacyProp),
    rubric: TeacherActivityRubric.builtIn(
      TeacherActivityRubricTemplate.standardTechnique,
      TeacherActivityAssessmentContract.defaultMaximumScore,
    ),
  );
}

List<int> _scaleWeights(List<int> weights, int total) {
  final weightTotal = weights.fold<int>(0, (sum, value) => sum + value);
  final caps = <int>[];
  final fractions = <(int, double)>[];
  var allocated = 0;
  for (var index = 0; index < weights.length; index++) {
    final exact = total * weights[index] / weightTotal;
    final floor = exact.floor();
    caps.add(floor);
    allocated += floor;
    fractions.add((index, exact - floor));
  }
  fractions.sort((a, b) {
    final byFraction = b.$2.compareTo(a.$2);
    return byFraction != 0 ? byFraction : a.$1.compareTo(b.$1);
  });
  for (var index = 0; index < total - allocated; index++) {
    caps[fractions[index].$1] += 1;
  }
  return caps;
}

String? _boundedText(Object? value, int maximumLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maximumLength) return null;
  return trimmed;
}
