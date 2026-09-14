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

    test('catalog contains exactly the five bundled Practice tracks', () {
      expect(musicTrackCatalog.map((track) => track.displayName).toList(), [
        'A Sky Full of Stars',
        'Martin Garrix - Animals',
        'Fireball',
        'Danza Kuduro',
        'Timber',
      ]);
      expect(musicTrackCatalog, hasLength(5));
    });

    test('non-Practice audio is excluded from the selectable catalog', () {
      final paths = musicTrackCatalog.map((track) => track.assetPath);
      expect(
        paths,
        isNot(
          contains(
            anyOf(
              'music/hcc.mp3',
              'music/notification.mp3',
              'music/countdown.mp3',
              'music/congrats.mp3',
            ),
          ),
        ),
      );
    });

    test('shuffle does not immediately repeat with multiple tracks', () {
      for (final previous in musicTrackCatalog) {
        final next = nextShuffleTrack(
          musicTrackCatalog,
          previousTrackId: previous.id,
        );
        expect(next.id, isNot(previous.id));
      }
    });
  });
}
