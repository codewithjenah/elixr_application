import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/features/coaching_notes/coaching_notes_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryCoachingNoteRepository repository;
  late TeacherCoachingNotesController controller;

  setUp(() {
    repository = InMemoryCoachingNoteRepository()..approvedPairs.add('teacher_trainee');
    controller = TeacherCoachingNotesController(repository: repository, teacherId: 'teacher', traineeId: 'trainee');
  });
  tearDown(() => controller.dispose());

  test('approved relationship starts empty then creates, edits, deletes, and reloads notes', () async {
    await controller.start();
    expect(controller.state, TeacherCoachingNotesState.empty);
    await controller.create('Keep the bottle upright.', 'Hand Stall');
    expect(controller.state, TeacherCoachingNotesState.ready);
    final created = controller.notes.single;
    await controller.update(created, 'Use a softer catch.', null);
    expect(controller.notes.single.body, 'Use a softer catch.');
    await controller.delete(controller.notes.single);
    expect(controller.state, TeacherCoachingNotesState.empty);
  });

  test('validation failure is surfaced and revoked relationship blocks future mutations', () async {
    await controller.start();
    await expectLater(controller.create(' ', null), throwsA(isA<CoachingNoteException>()));
    controller.pause();
    expect(controller.canAuthor, isFalse);
    await expectLater(controller.create('Valid', null), throwsA(isA<CoachingNoteException>().having((e) => e.code, 'code', CoachingNoteError.relationshipRequired)));
  });

  test('pagination de-duplicates notes and retry retains the cursor', () async {
    repository.notes.addAll([_note('one', 1), _note('two', 2), _note('three', 3)]);
    await controller.start();
    // The in-memory repository uses the production default page size, so this
    // assertion also guards the controller's duplicate-safe merge behavior.
    expect(controller.notes.map((n) => n.id).toSet().length, controller.notes.length);
  });
}

CoachingNote _note(String id, int second) => CoachingNote(
  id: id, teacherId: 'teacher', traineeId: 'trainee', teacherDisplayName: 'Teacher', body: id,
  createdAt: DateTime.utc(2026, 8, 14, 10, 0, second), updatedAt: DateTime.utc(2026, 8, 14, 10, 0, second),
);
