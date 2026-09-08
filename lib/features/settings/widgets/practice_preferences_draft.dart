import 'package:flutter/foundation.dart';

import '../../../core/progression/practice_variant.dart';

/// Immutable snapshot of Live Practice setlist / pace / music preferences.
@immutable
class PracticePreferencesDraft {
  const PracticePreferencesDraft({
    required this.practiceVariants,
    required this.intervalSeconds,
    this.musicTrackId,
  });

  final List<PracticeVariant> practiceVariants;
  final int intervalSeconds;
  final String? musicTrackId;

  PracticePreferencesDraft copyWith({
    List<PracticeVariant>? practiceVariants,
    int? intervalSeconds,
    Object? musicTrackId = _unset,
  }) {
    return PracticePreferencesDraft(
      practiceVariants: practiceVariants ?? this.practiceVariants,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      musicTrackId: identical(musicTrackId, _unset)
          ? this.musicTrackId
          : musicTrackId as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PracticePreferencesDraft &&
        listEquals(other.practiceVariants, practiceVariants) &&
        other.intervalSeconds == intervalSeconds &&
        other.musicTrackId == musicTrackId;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(practiceVariants),
    intervalSeconds,
    musicTrackId,
  );
}

const Object _unset = Object();
