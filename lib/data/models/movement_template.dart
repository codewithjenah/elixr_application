import 'dart:convert';

/// Versioned, data-only representation of a recorded custom movement.
///
/// The backend remains authoritative for feature extraction and matching. The
/// Flutter client validates the envelope before persisting or sending it and
/// never interprets user-authored values as executable rules or thresholds.
class MovementTemplate {
  static const currentSchemaVersion = 1;
  static const currentCaptureVersion = 1;
  static const minimumReferences = 3;
  static const maximumEncodedBytes = 700 * 1024;

  const MovementTemplate({
    required this.schemaVersion,
    required this.captureVersion,
    required this.durationMs,
    required this.referenceCount,
    required this.requiredModalities,
    required this.normalizationMetadata,
    required this.featureCapabilities,
    required this.canonicalSequence,
    required this.variabilityMetadata,
    this.propEvents = const [],
  });

  final int schemaVersion;
  final int captureVersion;
  final int durationMs;
  final int referenceCount;
  final List<String> requiredModalities;
  final Map<String, dynamic> normalizationMetadata;
  final Map<String, bool> featureCapabilities;
  final List<Map<String, dynamic>> canonicalSequence;
  final Map<String, dynamic> variabilityMetadata;
  final List<Map<String, dynamic>> propEvents;

  bool get isReady => referenceCount >= minimumReferences;

  bool get claimsUnsupportedRotation =>
      featureCapabilities['prop_rotation'] == true;

  int get encodedBytes => utf8.encode(jsonEncode(toMap())).length;

  Map<String, dynamic> toMap() => {
    'schema_version': schemaVersion,
    'capture_version': captureVersion,
    'duration_ms': durationMs,
    'reference_count': referenceCount,
    'required_modalities': List<String>.from(requiredModalities),
    'normalization_metadata': Map<String, dynamic>.from(normalizationMetadata),
    'feature_capabilities': Map<String, bool>.from(featureCapabilities),
    'canonical_sequence': canonicalSequence
        .map((sample) => Map<String, dynamic>.from(sample))
        .toList(growable: false),
    'variability_metadata': Map<String, dynamic>.from(variabilityMetadata),
    'prop_events': propEvents
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false),
  };

  static MovementTemplate? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
    const allowed = {
      'schema_version',
      'capture_version',
      'duration_ms',
      'reference_count',
      'required_modalities',
      'normalization_metadata',
      'feature_capabilities',
      'canonical_sequence',
      'variability_metadata',
      'prop_events',
    };
    if (map.keys.any((key) => !allowed.contains(key))) return null;
    final schemaVersion = _int(map['schema_version']);
    final captureVersion = _int(map['capture_version']);
    final durationMs = _int(map['duration_ms']);
    final referenceCount = _int(map['reference_count']);
    final modalities = _strings(map['required_modalities']);
    final normalization = _map(map['normalization_metadata']);
    final capabilities = _boolMap(map['feature_capabilities']);
    final sequence = _maps(map['canonical_sequence']);
    final variability = _map(map['variability_metadata']);
    final propEvents = _maps(map['prop_events'] ?? const []);
    if (schemaVersion != currentSchemaVersion ||
        captureVersion == null ||
        captureVersion < 1 ||
        durationMs == null ||
        durationMs <= 0 ||
        durationMs > 120000 ||
        referenceCount == null ||
        referenceCount < 1 ||
        referenceCount > 10 ||
        modalities == null ||
        modalities.isEmpty ||
        modalities.length > 3 ||
        modalities.toSet().length != modalities.length ||
        modalities.any(
          (item) => !const {'pose', 'hands', 'prop_translation'}.contains(item),
        ) ||
        normalization == null ||
        capabilities == null ||
        sequence == null ||
        sequence.length < 2 ||
        sequence.length > 600 ||
        variability == null ||
        propEvents == null ||
        propEvents.length > 64 ||
        capabilities.keys.toSet().difference(const {
          'pose',
          'hands',
          'prop_translation',
          'release_catch',
          'prop_rotation',
        }).isNotEmpty ||
        !capabilities.keys.toSet().containsAll(const {
          'pose',
          'hands',
          'prop_translation',
          'release_catch',
          'prop_rotation',
        }) ||
        capabilities['prop_rotation'] == true) {
      return null;
    }
    final template = MovementTemplate(
      schemaVersion: schemaVersion!,
      captureVersion: captureVersion,
      durationMs: durationMs,
      referenceCount: referenceCount,
      requiredModalities: List.unmodifiable(modalities),
      normalizationMetadata: Map.unmodifiable(normalization),
      featureCapabilities: Map.unmodifiable(capabilities),
      canonicalSequence: List.unmodifiable(sequence),
      variabilityMetadata: Map.unmodifiable(variability),
      propEvents: List.unmodifiable(propEvents),
    );
    return template.encodedBytes <= maximumEncodedBytes ? template : null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return null;
  }

  static List<String>? _strings(Object? value) {
    if (value is! List || value.any((item) => item is! String)) return null;
    return value.cast<String>();
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, bool>? _boolMap(Object? value) {
    final map = _map(value);
    if (map == null || map.values.any((item) => item is! bool)) return null;
    return map.map((key, value) => MapEntry(key, value as bool));
  }

  static List<Map<String, dynamic>>? _maps(Object? value) {
    if (value is! List) return null;
    try {
      return value
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }
}
