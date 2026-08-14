import '../constants/coaching_movement_names.dart';

class CoachingNote {
  static const maximumBodyLength = 1000;
  const CoachingNote({
    required this.id,
    required this.teacherId,
    required this.traineeId,
    required this.teacherDisplayName,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.movementName,
  });

  final String id;
  final String teacherId;
  final String traineeId;
  final String teacherDisplayName;
  final String body;
  final String? movementName;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEdited => updatedAt.isAfter(createdAt);

  static String? validateDraft({required String body, String? movementName}) {
    if (body.trim().isEmpty || body.trim().length > maximumBodyLength) {
      return 'Recommendation must be 1 to $maximumBodyLength characters.';
    }
    if (movementName != null && !isRecognizedCoachingMovement(movementName)) {
      return 'Choose a movement from the ELIXR catalogue.';
    }
    return null;
  }

  static CoachingNote? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    String? string(String key) {
      final value = map[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    DateTime? date(String key) {
      final value = map[key];
      if (value is DateTime) return value.toUtc();
      try {
        final dynamic timestamp = value;
        if (timestamp?.toDate is Function)
          return (timestamp.toDate() as DateTime).toUtc();
      } catch (_) {}
      return null;
    }

    final teacherId = string('teacher_id');
    final traineeId = string('trainee_id');
    final teacherName = string('teacher_display_name');
    final body = string('body');
    final createdAt = date('created_at');
    final updatedAt = date('updated_at');
    final movement = map['movement_name'];
    if (teacherId == null ||
        traineeId == null ||
        teacherId == traineeId ||
        teacherName == null ||
        body == null ||
        body.length > maximumBodyLength ||
        createdAt == null ||
        updatedAt == null ||
        updatedAt.isBefore(createdAt) ||
        (movement != null && (movement is! String || movement.trim().isEmpty)))
      return null;
    return CoachingNote(
      id: id,
      teacherId: teacherId,
      traineeId: traineeId,
      teacherDisplayName: teacherName,
      body: body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      movementName: movement as String?,
    );
  }
}
