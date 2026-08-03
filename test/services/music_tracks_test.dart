import 'package:elixr_application/core/constants/music_tracks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTrack', () {
    test('returns the matching entry for a valid id', () {
      final track = resolveTrack(musicTrackCatalog.first.id);
      expect(track.id, musicTrackCatalog.first.id);
    });

    test('falls back to a catalog entry (shuffle) for a null id', () {
      final track = resolveTrack(null);
      expect(musicTrackCatalog.map((t) => t.id), contains(track.id));
    });

    test('falls back to a catalog entry (shuffle) for a stale/unknown id', () {
      final track = resolveTrack('no-such-track-id');
      expect(musicTrackCatalog.map((t) => t.id), contains(track.id));
    });

    test('resolves each catalog entry by id', () {
      for (final expected in musicTrackCatalog) {
        expect(resolveTrack(expected.id).id, expected.id);
      }
    });

    test('catalog includes the Just Dance session tracks', () {
      final ids = musicTrackCatalog.map((t) => t.id).toSet();
      expect(
        ids,
        containsAll(['practice_classic', 'just_dance_1', 'just_dance_2']),
      );
    });
  });
}
