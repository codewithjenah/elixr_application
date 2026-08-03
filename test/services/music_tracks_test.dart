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

    test(
      'falls back to a catalog entry (shuffle) for a stale/unknown id',
      () {
        final track = resolveTrack('no-such-track-id');
        expect(musicTrackCatalog.map((t) => t.id), contains(track.id));
      },
    );

    test(
      'a single-entry catalog always resolves to that entry regardless of input',
      () {
        // musicTrackCatalog currently ships with exactly one track; this
        // assertion documents and locks in that "always the one track"
        // degradation until a second track is added to the catalog.
        expect(musicTrackCatalog.length, 1);
        expect(resolveTrack(null).id, musicTrackCatalog.first.id);
        expect(resolveTrack('unknown').id, musicTrackCatalog.first.id);
        expect(
          resolveTrack(musicTrackCatalog.first.id).id,
          musicTrackCatalog.first.id,
        );
      },
    );
  });
}
