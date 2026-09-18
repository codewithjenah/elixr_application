import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/services/trainee_progression_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<(Directory, TraineeProgressionSnapshotStore)> createStore() async {
    final directory = await Directory.systemTemp.createTemp('elixr_xp_');
    addTearDown(() => directory.delete(recursive: true));
    return (directory, TraineeProgressionSnapshotStore(directory: directory));
  }

  test('empty store is a cache miss', () async {
    final (_, store) = await createStore();
    expect(await store.load('uid-a'), isNull);
  });

  test('authoritative XP saves and reloads for the exact UID', () async {
    final (_, store) = await createStore();
    await store.save(
      TraineeProgressionSnapshot(
        userId: 'uid-a',
        totalXp: 750,
        authoritativeSnapshotAt: DateTime.utc(2026, 1, 2),
      ),
    );

    final loaded = await store.load('uid-a');
    expect(loaded?.totalXp, 750);
    expect(loaded?.authoritativeSnapshotAt, DateTime.utc(2026, 1, 2));
  });

  test(
    'accounts remain isolated and purging one preserves the other',
    () async {
      final (_, store) = await createStore();
      await store.save(
        const TraineeProgressionSnapshot(userId: 'uid-a', totalXp: 1),
      );
      await store.save(
        const TraineeProgressionSnapshot(userId: 'uid-b', totalXp: 2),
      );

      await store.purge('uid-a');

      expect(await store.load('uid-a'), isNull);
      expect((await store.load('uid-b'))?.totalXp, 2);
    },
  );

  test('malformed values fail safely', () async {
    final (directory, store) = await createStore();
    final file = File(
      '${directory.path}${Platform.pathSeparator}progression.json',
    );
    await file.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'accounts': {
          'uid-a': {'uid': 'uid-a', 'total_xp': -1},
        },
      }),
    );
    expect(await store.load('uid-a'), isNull);
  });

  test('serialized snapshots contain no credentials or tokens', () {
    final encoded = jsonEncode(
      const TraineeProgressionSnapshot(userId: 'uid-a', totalXp: 250).toJson(),
    );
    expect(encoded, isNot(contains('password')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('credential')));
  });
}
