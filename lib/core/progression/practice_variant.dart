import '../../data/models/training_prop.dart';

/// Stable domain/persistence identity for an exact practice variant.
class PracticeVariant {
  const PracticeVariant({
    required this.movementName,
    required this.trainingProp,
  });

  final String movementName;
  final TrainingProp trainingProp;

  /// Deterministic persistence token. Never store display labels.
  String get persistenceKey => '$movementName|${trainingProp.protocolValue}';

  static PracticeVariant? tryParsePersistenceKey(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final sep = trimmed.lastIndexOf('|');
    if (sep <= 0 || sep >= trimmed.length - 1) return null;
    final name = trimmed.substring(0, sep).trim();
    final prop = TrainingProp.tryParseStrict(trimmed.substring(sep + 1));
    if (name.isEmpty || prop == null) return null;
    return PracticeVariant(movementName: name, trainingProp: prop);
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeVariant &&
      other.movementName == movementName &&
      other.trainingProp == trainingProp;

  @override
  int get hashCode => Object.hash(movementName, trainingProp);

  @override
  String toString() => 'PracticeVariant($persistenceKey)';
}
