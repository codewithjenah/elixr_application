import 'dart:math';

import '../../data/models/music_track.dart';

/// Catalog of selectable practice session background music.
///
/// To add a new track later (exactly 3 edits, no other code changes):
/// 1. Drop the `.mp3` file under `assets/music/`.
/// 2. Add one line for it to `pubspec.yaml`'s `assets:` list.
/// 3. Add one `MusicTrack(...)` entry to the list below.
const musicTrackCatalog = <MusicTrack>[
  MusicTrack(
    id: 'practice_classic',
    displayName: 'Classic Loop',
    assetPath: 'music/practice.mp3',
  ),
  MusicTrack(
    id: 'just_dance_1',
    displayName: 'Just Dance 1',
    assetPath: 'music/just_dance_1.mp3',
  ),
  MusicTrack(
    id: 'just_dance_2',
    displayName: 'Just Dance 2',
    assetPath: 'music/just_dance_2.mp3',
  ),
];

/// Resolves [selectedId] to a catalog entry, or a random entry when
/// [selectedId] is `null` or no longer present in [musicTrackCatalog].
///
/// With a single-entry catalog this naturally always returns that entry.
MusicTrack resolveTrack(String? selectedId) {
  if (selectedId != null) {
    for (final track in musicTrackCatalog) {
      if (track.id == selectedId) return track;
    }
  }
  return musicTrackCatalog[Random().nextInt(musicTrackCatalog.length)];
}
