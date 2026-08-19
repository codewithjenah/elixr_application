import 'package:elixr_core/elixr_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const teacherId = 'teacher-1';
  const traineeId = 'trainee-1';
  const groupA = 'group-a';
  const groupB = 'group-b';

  late FakeFirebaseFirestore firestore;
  late FirebaseCoachingNoteRepository repository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = FirebaseCoachingNoteRepository(firestore: firestore);
    await firestore.collection(FirestoreCollections.users).doc(teacherId).set({
      'full_name': 'Teacher One',
      'role': 'Teacher',
    });
    await firestore
        .collection(FirestoreCollections.teacherStudentLinks)
        .doc('${teacherId}_$traineeId')
        .set({
          'teacher_id': teacherId,
          'trainee_id': traineeId,
          'status': 'approved',
        });
    await _seedMembership(firestore, groupId: groupA);
    await _seedMembership(firestore, groupId: groupB);
  });

  test('group A query only returns group A notes', () async {
    await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Note A1',
      groupId: groupA,
    );
    await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Note B1',
      groupId: groupB,
    );
    final page = await repository.fetchForTeacher(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupA,
    );
    expect(page.notes.map((n) => n.body), ['Note A1']);
    expect(page.notes.single.groupId, groupA);
  });

  test('group B query only returns group B notes', () async {
    await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Note A1',
      groupId: groupA,
    );
    await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Note B1',
      groupId: groupB,
    );
    final page = await repository.fetchForTeacher(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupB,
    );
    expect(page.notes.map((n) => n.body), ['Note B1']);
  });

  test('pagination remains scoped to the requested group', () async {
    for (var i = 0; i < 3; i++) {
      await repository.createNote(
        teacherId: teacherId,
        traineeId: traineeId,
        body: 'A$i',
        groupId: groupA,
      );
    }
    await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'B0',
      groupId: groupB,
    );
    final first = await repository.fetchForTeacher(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupA,
      pageSize: 2,
    );
    expect(first.notes.length, 2);
    expect(first.hasMore, isTrue);
    expect(first.notes.every((n) => n.groupId == groupA), isTrue);
    final second = await repository.fetchForTeacher(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupA,
      pageSize: 2,
      startAfter: first.nextCursor,
    );
    expect(second.notes.length, 1);
    expect(second.notes.single.groupId, groupA);
    expect(second.notes.single.body, isNot(equals('B0')));
  });

  test(
    'legacy fetch returns a historical note only after provenance backfill',
    () async {
      await firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .doc('historical-legacy')
          .set({
            'teacher_id': teacherId,
            'trainee_id': traineeId,
            'teacher_display_name': 'Teacher One',
            'body': 'Historical advice.',
            'created_at': DateTime.utc(2026, 1, 2),
            'updated_at': DateTime.utc(2026, 1, 2),
          });
      final before = await repository.fetchForTeacher(
        teacherId: teacherId,
        traineeId: traineeId,
      );
      expect(before.notes, isEmpty);

      await firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .doc('historical-legacy')
          .update({
            CoachingNote.authorizationSourceField:
                CoachingNote.authorizationSourceLegacyLink,
          });
      final after = await repository.fetchForTeacher(
        teacherId: teacherId,
        traineeId: traineeId,
      );
      expect(after.notes.map((n) => n.id), ['historical-legacy']);
      expect(after.notes.single.body, 'Historical advice.');
    },
  );

  test(
    'legacy fetch excludes group-backed notes and writes provenance',
    () async {
      await repository.createNote(
        teacherId: teacherId,
        traineeId: traineeId,
        body: 'Classroom',
        groupId: groupA,
      );
      final legacy = await repository.createNote(
        teacherId: teacherId,
        traineeId: traineeId,
        body: 'Legacy note',
      );
      final page = await repository.fetchForTeacher(
        teacherId: teacherId,
        traineeId: traineeId,
      );
      expect(page.notes.map((n) => n.id), [legacy.id]);
      final stored = await firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .doc(legacy.id)
          .get();
      expect(
        stored.data()?[CoachingNote.authorizationSourceField],
        CoachingNote.authorizationSourceLegacyLink,
      );
      expect(stored.data()?.containsKey('group_id'), isFalse);
    },
  );

  test(
    'create group-backed note persists group_id without provenance field',
    () async {
      final created = await repository.createNote(
        teacherId: teacherId,
        traineeId: traineeId,
        body: 'Keep the stall high.',
        groupId: groupA,
      );
      expect(created.groupId, groupA);
      final stored = await firestore
          .collection(FirestoreCollections.teacherCoachingNotes)
          .doc(created.id)
          .get();
      expect(stored.data()?['group_id'], groupA);
      expect(
        stored.data()?.containsKey(CoachingNote.authorizationSourceField),
        isFalse,
      );
    },
  );

  test('update preserves group_id and delete uses stored provenance', () async {
    final created = await repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Original',
      groupId: groupA,
    );
    final updated = await repository.updateNote(
      noteId: created.id,
      teacherId: teacherId,
      traineeId: traineeId,
      body: 'Updated',
    );
    expect(updated.groupId, groupA);
    await repository.deleteNote(
      noteId: created.id,
      teacherId: teacherId,
      traineeId: traineeId,
    );
    final stored = await firestore
        .collection(FirestoreCollections.teacherCoachingNotes)
        .doc(created.id)
        .get();
    expect(stored.exists, isFalse);
  });
}

Future<void> _seedMembership(
  FakeFirebaseFirestore firestore, {
  required String groupId,
}) async {
  await firestore.collection(FirestoreCollections.groups).doc(groupId).set({
    'teacher_id': 'teacher-1',
    'name': groupId,
    'status': 'active',
  });
  await firestore
      .collection(FirestoreCollections.groupMemberships)
      .doc('${groupId}_trainee-1')
      .set({
        'group_id': groupId,
        'teacher_id': 'teacher-1',
        'trainee_id': 'trainee-1',
        'status': GroupMembershipStatus.approved.name,
      });
}
