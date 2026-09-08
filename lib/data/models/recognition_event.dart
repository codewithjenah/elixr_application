import '../models/training_prop.dart';

enum RecognitionKind {
  movement,
  flip,
  advancedTechnique,
  failedAction,
  unknown,
}

enum RecognitionQuality { perfect, great, nice }

enum RecognitionState { searching, candidate, confirmed, paused, unknown }

class RecognitionEvent {
  const RecognitionEvent({
    required this.sessionId,
    required this.eventId,
    required this.kind,
    required this.displayLabel,
    required this.identityRevealed,
    this.quality,
    this.movement,
    this.propType,
    this.supportingMessage,
    this.captureSequence,
  });

  final String sessionId;
  final String eventId;
  final RecognitionKind kind;
  final String displayLabel;
  final bool identityRevealed;
  final RecognitionQuality? quality;
  final String? movement;
  final TrainingProp? propType;
  final String? supportingMessage;
  final int? captureSequence;

  bool get countsForCombo =>
      kind == RecognitionKind.movement ||
      kind == RecognitionKind.flip ||
      kind == RecognitionKind.advancedTechnique;

  bool get breaksCombo => kind == RecognitionKind.failedAction;

  factory RecognitionEvent.fromJson(Map<String, dynamic> json) {
    final revealed = json['identity_revealed'] == true;
    var kind = _kindFromWire(json['kind'] as String?);
    if (kind == RecognitionKind.movement && !revealed) {
      kind = RecognitionKind.advancedTechnique;
    }
    final rawMovement = json['movement'] as String?;
    final sanitizedMovement = revealed && kind == RecognitionKind.movement
        ? _nonEmpty(rawMovement)
        : null;
    final identityRevealed = switch (kind) {
      RecognitionKind.flip => true,
      RecognitionKind.movement => sanitizedMovement != null,
      _ => false,
    };
    return RecognitionEvent(
      sessionId: json['session_id'] as String? ?? '',
      eventId: json['event_id'] as String? ?? '',
      kind: kind,
      displayLabel: _safeDisplayLabel(
        kind: kind,
        revealed: revealed,
        raw: json['display_label'] as String?,
      ),
      identityRevealed: identityRevealed,
      quality: _qualityFromWire(json['quality'] as String?),
      movement: sanitizedMovement,
      propType: TrainingProp.tryParseStrict(json['prop_type']),
      supportingMessage: revealed
          ? json['supporting_message'] as String?
          : (kind == RecognitionKind.advancedTechnique
                ? 'Keep progressing to discover this movement.'
                : null),
      captureSequence: (json['capture_sequence'] as num?)?.toInt(),
    );
  }

  static String _safeDisplayLabel({
    required RecognitionKind kind,
    required bool revealed,
    required String? raw,
  }) {
    if (kind == RecognitionKind.advancedTechnique ||
        (!revealed && kind == RecognitionKind.movement)) {
      return 'Advanced technique detected';
    }
    if (kind == RecognitionKind.flip) {
      return 'Flip';
    }
    if (kind == RecognitionKind.failedAction) {
      return '';
    }
    final label = _nonEmpty(raw);
    if (!revealed) {
      return 'Advanced technique detected';
    }
    return label ?? 'Technique';
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static RecognitionKind _kindFromWire(String? value) => switch (value) {
    'movement' => RecognitionKind.movement,
    'flip' => RecognitionKind.flip,
    'advanced_technique' => RecognitionKind.advancedTechnique,
    'failed_action' => RecognitionKind.failedAction,
    _ => RecognitionKind.unknown,
  };

  static RecognitionQuality? _qualityFromWire(String? value) => switch (value) {
    'perfect' => RecognitionQuality.perfect,
    'great' => RecognitionQuality.great,
    'nice' => RecognitionQuality.nice,
    _ => null,
  };
}

RecognitionState recognitionStateFromWire(String? value) => switch (value) {
  'searching' => RecognitionState.searching,
  'candidate' => RecognitionState.candidate,
  'confirmed' => RecognitionState.confirmed,
  'paused' => RecognitionState.paused,
  _ => RecognitionState.unknown,
};

extension RecognitionQualityLabel on RecognitionQuality {
  String get label => switch (this) {
    RecognitionQuality.perfect => 'Perfect',
    RecognitionQuality.great => 'Great',
    RecognitionQuality.nice => 'Nice',
  };
}
