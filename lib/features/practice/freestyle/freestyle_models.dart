import '../../../data/models/recognition_event.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/models/movement_template.dart';

enum EndlessTargetKind { movement, customMovement, tossCatch }

enum FreestyleSessionPhase {
  idle,
  preparing,
  ready,
  active,
  paused,
  ending,
  completed,
  error,
}

class EndlessTarget {
  const EndlessTarget({
    required this.movement,
    required this.prop,
    required this.difficulty,
    this.kind = EndlessTargetKind.movement,
    this.customMovementId,
    this.revisionId,
    this.template,
  });

  final String movement;
  final TrainingProp prop;
  final String difficulty;
  final EndlessTargetKind kind;
  final String? customMovementId;
  final String? revisionId;
  final MovementTemplate? template;
  bool get isTossCatch => kind == EndlessTargetKind.tossCatch;
  String get identity => switch (kind) {
    EndlessTargetKind.movement => 'official:${prop.protocolValue}:$movement',
    EndlessTargetKind.customMovement => 'custom:$customMovementId:$revisionId',
    EndlessTargetKind.tossCatch => 'toss_catch:${prop.protocolValue}',
  };
  int get seconds {
    final base = switch (difficulty) {
      'Hard' => 12,
      'Medium' => 10,
      _ => 8,
    };
    if (kind != EndlessTargetKind.customMovement || template == null) {
      return base;
    }
    // Allow the full learned sequence, including moderate speed variation,
    // before the target expires. Authoring currently records up to 15 seconds.
    final learned = (template!.durationMs + 799) ~/ 800 + 1;
    return learned > base ? learned : base;
  }
}

class FreestyleFeedEntry {
  const FreestyleFeedEntry({
    required this.displayLabel,
    required this.quality,
    required this.kind,
  });

  final String displayLabel;
  final RecognitionQuality? quality;
  final RecognitionKind kind;
}

class FreestyleSessionStats {
  const FreestyleSessionStats({
    this.movementsRecognized = 0,
    this.uniqueUnlockedMovements = 0,
    this.flips = 0,
    this.advancedTechniques = 0,
    this.perfect = 0,
    this.great = 0,
    this.nice = 0,
    this.bestCombo = 0,
    this.combo = 0,
    this.missed = 0,
    this.runScore = 0,
    this.props = const {},
    this.feed = const [],
  });

  final int movementsRecognized;
  final int uniqueUnlockedMovements;
  final int flips;
  final int advancedTechniques;
  final int perfect;
  final int great;
  final int nice;
  final int bestCombo;
  final int combo;
  final int missed;
  final int runScore;
  final Set<TrainingProp> props;
  final List<FreestyleFeedEntry> feed;

  FreestyleSessionStats copyWith({
    int? movementsRecognized,
    int? uniqueUnlockedMovements,
    int? flips,
    int? advancedTechniques,
    int? perfect,
    int? great,
    int? nice,
    int? bestCombo,
    int? combo,
    int? missed,
    int? runScore,
    Set<TrainingProp>? props,
    List<FreestyleFeedEntry>? feed,
  }) {
    return FreestyleSessionStats(
      movementsRecognized: movementsRecognized ?? this.movementsRecognized,
      uniqueUnlockedMovements:
          uniqueUnlockedMovements ?? this.uniqueUnlockedMovements,
      flips: flips ?? this.flips,
      advancedTechniques: advancedTechniques ?? this.advancedTechniques,
      perfect: perfect ?? this.perfect,
      great: great ?? this.great,
      nice: nice ?? this.nice,
      bestCombo: bestCombo ?? this.bestCombo,
      combo: combo ?? this.combo,
      missed: missed ?? this.missed,
      runScore: runScore ?? this.runScore,
      props: props ?? this.props,
      feed: feed ?? this.feed,
    );
  }
}
