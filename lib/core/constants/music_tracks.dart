import 'dart:io';
import 'dart:math';

import '../../data/models/music_track.dart';

/// Catalog of selectable practice session background music.
///
/// IDs are intentionally independent of filenames so persisted selections can
/// survive display-name or asset-path changes.
const musicTrackCatalog = <MusicTrack>[
  MusicTrack.asset(
    id: 'sky_full_of_stars',
    displayName: 'A Sky Full of Stars',
    assetPath: 'music/A Sky Full of Stars.mp3',
  ),
  MusicTrack.asset(
    id: 'animals',
    displayName: 'Martin Garrix - Animals',
    assetPath: 'music/Martin Garrix - Animals.mp3',
  ),
  MusicTrack.asset(
    id: 'fireball',
    displayName: 'Fireball',
    assetPath: 'music/Fireball.mp3',
  ),
  MusicTrack.asset(
    id: 'danza_kuduro',
    displayName: 'Danza Kuduro',
    assetPath: 'music/Danza Kuduro.mp3',
  ),
  MusicTrack.asset(
    id: 'timber',
    displayName: 'Timber',
    assetPath: 'music/Timber.mp3',
  ),
];

const legacyMusicTrackIds = <String>{
  'practice_classic',
  'just_dance_1',
  'just_dance_2',
};

List<MusicTrack> availablePracticeTracks(
  Iterable<MusicTrack> customTracks, {
  bool Function(String path)? fileExists,
}) {
  final exists = fileExists ?? (String path) => File(path).existsSync();
  return <MusicTrack>[
    ...musicTrackCatalog,
    for (final track in customTracks)
      if (track.isCustom && track.filePath != null && exists(track.filePath!))
        track,
  ];
}

/// Resolves [selectedId] to a catalog entry, or a random entry when
/// [selectedId] is `null` or no longer present in [musicTrackCatalog].
///
/// With a single-entry catalog this naturally always returns that entry.
MusicTrack resolveTrack(
  String? selectedId, {
  Iterable<MusicTrack> customTracks = const <MusicTrack>[],
  Random? random,
  bool Function(String path)? fileExists,
}) {
  final tracks = availablePracticeTracks(customTracks, fileExists: fileExists);
  if (selectedId != null) {
    for (final track in tracks) {
      if (track.id == selectedId) return track;
    }
  }
  return tracks[(random ?? Random()).nextInt(tracks.length)];
}

MusicTrack nextShuffleTrack(
  List<MusicTrack> tracks, {
  String? previousTrackId,
  Random? random,
}) {
  if (tracks.isEmpty) {
    throw ArgumentError.value(tracks, 'tracks', 'Must not be empty');
  }
  if (tracks.length == 1) return tracks.single;

  final candidates = tracks
      .where((track) => track.id != previousTrackId)
      .toList(growable: false);
  return candidates[(random ?? Random()).nextInt(candidates.length)];
}
