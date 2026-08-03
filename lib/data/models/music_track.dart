/// A single selectable background-music track for practice sessions.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.displayName,
    required this.assetPath,
  });

  /// Stable key used for persistence (`SettingsService.selectedMusicTrackId`).
  final String id;

  /// Shown in the music picker.
  final String displayName;

  /// Path relative to `assets/`, e.g. `music/practice.mp3`.
  final String assetPath;
}
