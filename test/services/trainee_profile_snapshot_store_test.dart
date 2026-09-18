import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/services/trainee_profile_snapshot_store.dart';
import 'package:elixr_core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<(Directory, TraineeProfileSnapshotStore)> createStore() async {
    final directory = await Directory.systemTemp.createTemp('elixr_profile_');
    addTearDown(() => directory.delete(recursive: true));
    return (directory, TraineeProfileSnapshotStore(directory: directory));
  }

  TraineeProfileSnapshot trainee(String id) =>
      TraineeProfileSnapshot.fromAuthoritativeUser(
        User(
          id: id,
          firstName: 'Ada',
          middleName: 'Byron',
          lastName: 'Lovelace',
          email: 'ada@example.test',
          role: User.roleTrainee,
          sessionEvidenceEnabled: true,
          // This must never reach the local snapshot.
          profilePictureUrl: 'https://storage.example.test/avatar?token=secret',
        ),
        emailVerified: true,
      )!;

  test('valid Trainee snapshot persists with its exact UID', () async {
    final (_, store) = await createStore();
    await store.save(trainee('uid-A'));

    final loaded = await store.load('uid-A');

    expect(loaded?.user.id, 'uid-A');
    expect(loaded?.user.isTrainee, isTrue);
    expect(loaded?.emailVerified, isTrue);
  });

  test('account snapshots remain isolated', () async {
    final (_, store) = await createStore();
    await store.save(trainee('uid-A'));
    await store.save(trainee('uid-B'));

    expect((await store.load('uid-A'))?.user.id, 'uid-A');
    expect((await store.load('uid-B'))?.user.id, 'uid-B');
  });

  test('malformed cache fails safely', () async {
    final (directory, store) = await createStore();
    await File(
      '${directory.path}${Platform.pathSeparator}profiles.json',
    ).writeAsString('{not-json');

    expect(await store.load('uid-A'), isNull);
  });

  test('Teacher snapshots cannot be constructed for offline restoration', () {
    final snapshot = TraineeProfileSnapshot.fromAuthoritativeUser(
      const User(
        id: 'teacher-A',
        firstName: 'T',
        lastName: 'Eacher',
        email: 'teacher@example.test',
        role: User.roleTeacher,
      ),
      emailVerified: true,
    );

    expect(snapshot, isNull);
  });

  test('serialized snapshot contains no credentials or download token', () {
    final encoded = jsonEncode(trainee('uid-A').toJson());

    expect(encoded, isNot(contains('password')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('teacher_access_code')));
    expect(encoded, isNot(contains('profile_picture_url')));
  });

  test('purge removes only the requested account snapshot', () async {
    final (_, store) = await createStore();
    await store.save(trainee('uid-A'));
    await store.save(trainee('uid-B'));

    await store.purge('uid-A');

    expect(await store.load('uid-A'), isNull);
    expect((await store.load('uid-B'))?.user.id, 'uid-B');
  });
}
