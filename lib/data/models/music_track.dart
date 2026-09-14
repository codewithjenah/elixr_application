enum MusicTrackSource { asset, localFile }

/// A single selectable background-music track for practice sessions.
class MusicTrack {
  const MusicTrack.asset({
    required this.id,
    required this.displayName,
    required this.assetPath,
  }) : source = MusicTrackSource.asset,
       filePath = null;

  const MusicTrack.localFile({
    required this.id,
    required this.displayName,
    required this.filePath,
  }) : source = MusicTrackSource.localFile,
       assetPath = null;

  /// Stable key used for persistence (`SettingsService.selectedMusicTrackId`).
  final String id;

  /// Shown in the music picker.
  final String displayName;

  final MusicTrackSource source;

  /// Path relative to `assets/` for bundled tracks.
  final String? assetPath;

  /// Absolute path for a user-selected file. ELIXR never owns this file.
  final String? filePath;

  bool get isBundled => source == MusicTrackSource.asset;
  bool get isCustom => source == MusicTrackSource.localFile;

  Map<String, String> toSettingsJson() => <String, String>{
    'id': id,
    'display_name': displayName,
    'file_path': filePath!,
  };
}
