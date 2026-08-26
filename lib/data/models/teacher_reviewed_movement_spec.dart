import 'teacher_movement_revision_spec.dart';
import 'training_prop.dart';

/// Bounded Phase 5 spec for Teacher-created, teacher-reviewed movements.
///
/// This is not an AssessmentSpec evaluator and does not enable template
/// scoring. Capability is always teacher-review only.
class TeacherReviewedMovementSpec implements TeacherMovementRevisionSpec {
  static const currentSchemaVersion = 1;
  static const teacherReviewOnly = 'teacher_review_only';
  static const titleMaxLength = 80;
  static const instructionsMaxLength = 2000;
  static const safetyGuidanceMaxLength = 1000;

  const TeacherReviewedMovementSpec({
    required this.instructions,
    required this.requiredProp,
    this.safetyGuidance,
    this.capability = teacherReviewOnly,
  });

  @override
  final String instructions;
  @override
  final TrainingProp requiredProp;
  @override
  final String? safetyGuidance;
  final String capability;

  @override
  bool get isTeacherReviewOnly => capability == teacherReviewOnly;

  Map<String, dynamic> toMap() {
    return {
      'instructions': instructions,
      'required_prop': requiredProp.protocolValue,
      'capability': capability,
      if (safetyGuidance != null) 'safety_guidance': safetyGuidance,
    };
  }

  static TeacherReviewedMovementSpec? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final instructions = _readBounded(
      map['instructions'],
      maxLength: instructionsMaxLength,
    );
    final capability = _readBounded(map['capability'], maxLength: 64);
    if (instructions == null || capability != teacherReviewOnly) return null;

    final prop = TrainingProp.tryParseStrict(map['required_prop']);
    if (prop == null) return null;

    String? safety;
    if (map.containsKey('safety_guidance')) {
      safety = _readBounded(
        map['safety_guidance'],
        maxLength: safetyGuidanceMaxLength,
      );
      if (safety == null) return null;
    }

    return TeacherReviewedMovementSpec(
      instructions: instructions,
      requiredProp: prop,
      safetyGuidance: safety,
      capability: teacherReviewOnly,
    );
  }

  static String? validateTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter a movement title.';
    if (trimmed.length > titleMaxLength) {
      return 'Title must be $titleMaxLength characters or fewer.';
    }
    return null;
  }

  static String? validateInstructions(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter practice instructions.';
    if (trimmed.length > instructionsMaxLength) {
      return 'Instructions must be $instructionsMaxLength characters or fewer.';
    }
    return null;
  }

  static String? validateSafetyGuidance(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > safetyGuidanceMaxLength) {
      return 'Safety guidance must be $safetyGuidanceMaxLength characters or fewer.';
    }
    return null;
  }

  static String? _readBounded(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }
}
