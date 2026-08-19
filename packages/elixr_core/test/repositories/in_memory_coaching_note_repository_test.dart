import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryCoachingNoteRepository repository;

  setUp(() {
    repository = InMemoryCoachingNoteRepository()
      ..approvedPairs.add('teacher_trainee');
  });

  test(
    'creates, updates, deletes, and fetches approved teacher notes',
    () async {
      final created = await repository.createNote(
        teacherId: 'teacher',
        traineeId: 'trainee',
        body: ' Keep wrists stable. ',
        movementName: 'Hand Stall',
      );
      expect(created.body, 'Keep wrists stable.');
      final updated = await repository.updateNote(
        noteId: created.id,
        teacherId: 'teacher',
        traineeId: 'trainee',
        body: 'Use a softer catch.',
      );
      expect(updated.body, 'Use a softer catch.');
      expect(
        (await repository.fetchForTeacher(
          teacherId: 'teacher',
          traineeId: 'trainee',
        )).notes,
        [updated],
      );
      await repository.deleteNote(
        noteId: created.id,
        teacherId: 'teacher',
        traineeId: 'trainee',
      );
      expect(
        (await repository.fetchReceived(traineeId: 'trainee')).notes,
        isEmpty,
      );
    },
  );

  test(
    'group-backed fetch stays scoped and legacy fetch excludes group notes',
    () async {
      repository.approvedClassroom.add('group-a::teacher::trainee');
      repository.approvedClassroom.add('group-b::teacher::trainee');
      final noteA = await repository.createNote(
        teacherId: 'teacher',
        traineeId: 'trainee',
        body: 'Group A note',
        groupId: 'group-a',
      );
      final noteB = await repository.createNote(
        teacherId: 'teacher',
        traineeId: 'trainee',
        body: 'Group B note',
        groupId: 'group-b',
      );
      final legacy = await repository.createNote(
        teacherId: 'teacher',
        traineeId: 'trainee',
        body: 'Legacy note',
      );
      expect(
        (await repository.fetchForTeacher(
          teacherId: 'teacher',
          traineeId: 'trainee',
          groupId: 'group-a',
        )).notes.map((n) => n.id),
        [noteA.id],
      );
      expect(
        (await repository.fetchForTeacher(
          teacherId: 'teacher',
          traineeId: 'trainee',
          groupId: 'group-b',
        )).notes.map((n) => n.id),
        [noteB.id],
      );
      expect(
        (await repository.fetchForTeacher(
          teacherId: 'teacher',
          traineeId: 'trainee',
        )).notes.map((n) => n.id),
        [legacy.id],
      );
    },
  );

  test(
    'orders newest first, paginates without duplicates, and rejects foreign cursors',
    () async {
      repository.notes.addAll([
        _note('one', 1),
        _note('two', 3),
        _note('three', 2),
      ]);
      final first = await repository.fetchReceived(
        traineeId: 'trainee',
        pageSize: 2,
      );
      expect(first.notes.map((n) => n.id), ['two', 'three']);
      expect(first.hasMore, isTrue);
      final second = await repository.fetchReceived(
        traineeId: 'trainee',
        pageSize: 2,
        startAfter: first.nextCursor,
      );
      expect(second.notes.map((n) => n.id), ['one']);
      expect(second.hasMore, isFalse);
      await expectLater(
        repository.fetchReceived(
          traineeId: 'trainee',
          startAfter: const _ForeignCursor(),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'enforces page bounds and typed relationship, validation, and missing-note errors',
    () async {
      await expectLater(
        repository.fetchReceived(traineeId: 'trainee', pageSize: 0),
        throwsArgumentError,
      );
      await expectLater(
        repository.fetchReceived(traineeId: 'trainee', pageSize: 51),
        throwsArgumentError,
      );
      await expectLater(
        repository.createNote(
          teacherId: 'other',
          traineeId: 'trainee',
          body: 'Valid',
        ),
        throwsA(
          isA<CoachingNoteException>().having(
            (e) => e.code,
            'code',
            CoachingNoteError.relationshipRequired,
          ),
        ),
      );
      await expectLater(
        repository.createNote(
          teacherId: 'teacher',
          traineeId: 'trainee',
          body: ' ',
        ),
        throwsA(
          isA<CoachingNoteException>().having(
            (e) => e.code,
            'code',
            CoachingNoteError.invalidNote,
          ),
        ),
      );
      await expectLater(
        repository.deleteNote(
          noteId: 'missing',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
        throwsA(
          isA<CoachingNoteException>().having(
            (e) => e.code,
            'code',
            CoachingNoteError.notFound,
          ),
        ),
      );
    },
  );
}

CoachingNote _note(String id, int second) => CoachingNote(
  id: id,
  teacherId: 'teacher',
  traineeId: 'trainee',
  teacherDisplayName: 'Teacher',
  body: id,
  createdAt: DateTime.utc(2026, 8, 14, 10, 0, second),
  updatedAt: DateTime.utc(2026, 8, 14, 10, 0, second),
);

class _ForeignCursor extends CoachingNoteCursor {
  const _ForeignCursor();
}
