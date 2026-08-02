import 'training_prop.dart';

class Session {
  const Session({
    this.id,
    required this.userId,
    required this.movementName,
    required this.difficulty,
    required this.score,
    required this.durationSeconds,
    this.createdAt,
    this.propType = TrainingProp.bottle,
  });

  final String? id;
  final String userId;
  final String movementName;
  final String difficulty;
  final int score;
  final int durationSeconds;
  final String? createdAt;
  final TrainingProp propType;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'movement_name': movementName,
      'difficulty': difficulty,
      'score': score,
      'duration_seconds': durationSeconds,
      'created_at': createdAt,
      'prop_type': propType.protocolValue,
    };
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as String?,
      userId: map['user_id'] as String,
      movementName: map['movement_name'] as String,
      difficulty: map['difficulty'] as String,
      score: (map['score'] as num).toInt(),
      durationSeconds: (map['duration_seconds'] as num).toInt(),
      createdAt: map['created_at'] as String?,
      propType: TrainingProp.fromProtocolValue(map['prop_type']),
    );
  }
}
