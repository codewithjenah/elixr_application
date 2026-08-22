/// Strict AssessmentSpec v1 for the Phase 7 Wrist Stall vertical slice.
///
/// Unknown keys and values outside the locked Bottle + Wrist matrix fail
/// closed. This is not a runtime evaluator and does not accept teacher
/// thresholds or executable expressions.
enum AssessmentTemplateId {
  balanceStallWristV1('balance_stall.wrist_v1');

  const AssessmentTemplateId(this.wireValue);

  final String wireValue;

  static AssessmentTemplateId? tryParse(Object? value) {
    if (value is! String) return null;
    for (final id in values) {
      if (id.wireValue == value) return id;
    }
    return null;
  }
}

enum AssessmentProp {
  bottle('bottle');

  const AssessmentProp(this.wireValue);

  final String wireValue;

  static AssessmentProp? tryParse(Object? value) {
    if (value is! String) return null;
    for (final prop in values) {
      if (prop.wireValue == value) return prop;
    }
    return null;
  }
}

enum AssessmentTarget {
  wrist('wrist');

  const AssessmentTarget(this.wireValue);

  final String wireValue;

  static AssessmentTarget? tryParse(Object? value) {
    if (value is! String) return null;
    for (final target in values) {
      if (target.wireValue == value) return target;
    }
    return null;
  }
}

enum AssessmentLaterality {
  either('either'),
  left('left'),
  right('right');

  const AssessmentLaterality(this.wireValue);

  final String wireValue;

  static AssessmentLaterality? tryParse(Object? value) {
    if (value is! String) return null;
    for (final laterality in values) {
      if (laterality.wireValue == value) return laterality;
    }
    return null;
  }
}

class AssessmentSpec {
  static const currentSchemaVersion = 1;

  static const _allowedKeys = {
    'schema_version',
    'template_id',
    'prop',
    'target',
    'laterality',
  };

  const AssessmentSpec({
    this.schemaVersion = currentSchemaVersion,
    this.templateId = AssessmentTemplateId.balanceStallWristV1,
    this.prop = AssessmentProp.bottle,
    this.target = AssessmentTarget.wrist,
    required this.laterality,
  });

  final int schemaVersion;
  final AssessmentTemplateId templateId;
  final AssessmentProp prop;
  final AssessmentTarget target;
  final AssessmentLaterality laterality;

  bool get isCanonicalWristStallV1 {
    return schemaVersion == currentSchemaVersion &&
        templateId == AssessmentTemplateId.balanceStallWristV1 &&
        prop == AssessmentProp.bottle &&
        target == AssessmentTarget.wrist;
  }

  Map<String, dynamic> toMap() {
    return {
      'schema_version': schemaVersion,
      'template_id': templateId.wireValue,
      'prop': prop.wireValue,
      'target': target.wireValue,
      'laterality': laterality.wireValue,
    };
  }

  static AssessmentSpec? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }

    if (map.length != _allowedKeys.length) return null;
    for (final key in map.keys) {
      if (!_allowedKeys.contains(key)) return null;
    }
    for (final key in _allowedKeys) {
      if (!map.containsKey(key)) return null;
    }

    final schemaVersion = map['schema_version'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      return null;
    }

    final templateId = AssessmentTemplateId.tryParse(map['template_id']);
    final prop = AssessmentProp.tryParse(map['prop']);
    final target = AssessmentTarget.tryParse(map['target']);
    final laterality = AssessmentLaterality.tryParse(map['laterality']);
    if (templateId == null ||
        prop == null ||
        target == null ||
        laterality == null) {
      return null;
    }

    return AssessmentSpec(
      schemaVersion: schemaVersion,
      templateId: templateId,
      prop: prop,
      target: target,
      laterality: laterality,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AssessmentSpec &&
        other.schemaVersion == schemaVersion &&
        other.templateId == templateId &&
        other.prop == prop &&
        other.target == target &&
        other.laterality == laterality;
  }

  @override
  int get hashCode =>
      Object.hash(schemaVersion, templateId, prop, target, laterality);
}
