import '../constants/coaching_movement_names.dart';

/// Privacy-gated aggregate details at `public_profiles/{userId}/details/summary`.
///
/// Historical session documents may still contain retired movement names, but
/// this aggregate exposes only movements in the current coaching catalog.
class PublicProfileSummary {
  const PublicProfileSummary({
    required this.totalDurationSeconds,
    required this.completedMovementNames,
    this.updatedAt,
    this.lastBackfillSessionId,
  });

  final int totalDurationSeconds;
  final List<String> completedMovementNames;
  final String? updatedAt;
  final String? lastBackfillSessionId;

  static PublicProfileSummary? tryFromMap(Map<String, dynamic> map) {
    final duration = _readInt(map['total_duration_seconds']) ?? 0;
    final movements = _readStringList(map['completed_movement_names']);

    return PublicProfileSummary(
      totalDurationSeconds: duration < 0 ? 0 : duration,
      completedMovementNames: movements,
      updatedAt: _readTimestampString(map['updated_at']),
      lastBackfillSessionId: _readString(map['last_backfill_session_id']),
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static String? _readString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final item in value) {
      if (item is String) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty &&
            isRecognizedCoachingMovement(trimmed) &&
            !out.contains(trimmed)) {
          out.add(trimmed);
        }
      }
    }
    return List<String>.unmodifiable(out);
  }

  static String? _readTimestampString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toIso8601String();
      }
    } catch (_) {}
    return null;
  }
}
