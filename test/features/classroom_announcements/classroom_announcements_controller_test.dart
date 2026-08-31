import 'package:elixr_application/features/classroom_announcements/classroom_announcements_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'teacher controller reflects create, edit, and hard delete live',
    () async {
      final repository = InMemoryClassroomAnnouncementRepository();
      final controller = ClassroomAnnouncementsController(
        repository: repository,
        groupId: 'group-1',
        currentUserId: 'teacher-1',
        canManage: true,
        isGroupActive: () => true,
        ensureTeacherAuthorization: () async => true,
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);

      await controller.start();
      expect(
        await controller.create(title: 'Reminder', body: 'Practice today.'),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.single.title, 'Reminder');

      final item = controller.items.single;
      expect(
        await controller.update(
          item,
          title: 'Updated reminder',
          body: 'Practice tomorrow.',
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.single.isEdited, isTrue);

      expect(await controller.delete(controller.items.single), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items, isEmpty);
    },
  );

  test('archived classroom blocks publishing but permits deletion', () async {
    var active = false;
    final repository = InMemoryClassroomAnnouncementRepository();
    final existing = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'Existing',
      body: 'Existing body',
    );
    final controller = ClassroomAnnouncementsController(
      repository: repository,
      groupId: 'group-1',
      currentUserId: 'teacher-1',
      canManage: true,
      isGroupActive: () => active,
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.start();
    expect(await controller.create(title: 'New', body: 'New body'), isFalse);
    expect(controller.errorMessage, 'Archived classes cannot be changed.');
    expect(await controller.delete(existing), isTrue);
    active = true;
  });
}
