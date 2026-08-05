import 'package:flutter/foundation.dart';

/// Immutable snapshot of Live Practice setlist / pace / music preferences.
@immutable
class PracticePreferencesDraft {
  const PracticePreferencesDraft({
    required this.movementNames,
    required this.intervalSeconds,
    this.musicTrackId,
  });

  final List<String> movementNames;
  final int intervalSeconds;
  final String? musicTrackId;

  PracticePreferencesDraft copyWith({
    List<String>? movementNames,
    int? intervalSeconds,
    Object? musicTrackId = _unset,
  }) {
    return PracticePreferencesDraft(
      movementNames: movementNames ?? this.movementNames,
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
        listEquals(other.movementNames, movementNames) &&
        other.intervalSeconds == intervalSeconds &&
        other.musicTrackId == musicTrackId;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(movementNames), intervalSeconds, musicTrackId);
}

const Object _unset = Object();
