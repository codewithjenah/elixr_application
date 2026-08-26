import 'assessment_spec.dart';
import 'training_prop.dart';

/// Shared presentation contract for Teacher-created revision specs.
///
/// [TeacherReviewedMovementSpec] remains the Phase 5/6 teacher-reviewed
/// document. [TemplateScoredRevisionSpec] only parses the retired historical
/// Phase 7 wrapper.
abstract interface class TeacherMovementRevisionSpec {
  String get instructions;
  TrainingProp get requiredProp;
  String? get safetyGuidance;
  bool get isTeacherReviewOnly;
}

/// Historical-only parser for a Teacher-created revision that named a locked
/// automatic assessment. It has no serialization path by design.
class TemplateScoredRevisionSpec implements TeacherMovementRevisionSpec {
  static const _allowedKeys = {
    'instructions',
    'required_prop',
    'safety_guidance',
    'assessment',
  };

  // Keep presentation bounds aligned with TeacherReviewedMovementSpec.
  static const _instructionsMaxLength = 2000;
  static const _safetyGuidanceMaxLength = 1000;

  const TemplateScoredRevisionSpec({
    required this.instructions,
    required this.requiredProp,
    required this.assessment,
    this.safetyGuidance,
  });

  @override
  final String instructions;

  @override
  final TrainingProp requiredProp;

  @override
  final String? safetyGuidance;

  final AssessmentSpec assessment;

  @override
  bool get isTeacherReviewOnly => false;

  static TemplateScoredRevisionSpec? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }

    for (final key in map.keys) {
      if (!_allowedKeys.contains(key)) return null;
    }
    if (!map.containsKey('instructions') ||
        !map.containsKey('required_prop') ||
        !map.containsKey('assessment')) {
      return null;
    }

    final instructions = _readBounded(
      map['instructions'],
      maxLength: _instructionsMaxLength,
    );
    if (instructions == null) return null;

    if (TrainingProp.tryParseStrict(map['required_prop']) !=
        TrainingProp.bottle) {
      return null;
    }
    const requiredProp = TrainingProp.bottle;

    String? safety;
    if (map.containsKey('safety_guidance')) {
      safety = _readBounded(
        map['safety_guidance'],
        maxLength: _safetyGuidanceMaxLength,
      );
      if (safety == null) return null;
    }

    final assessment = AssessmentSpec.tryFrom(map['assessment']);
    if (assessment == null) return null;
    if (requiredProp.protocolValue != assessment.prop.wireValue) {
      return null;
    }

    return TemplateScoredRevisionSpec(
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safety,
      assessment: assessment,
    );
  }

  static String? _readBounded(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }
}
