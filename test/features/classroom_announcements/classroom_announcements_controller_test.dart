import 'package:elixr_application/features/classroom_announcements/classroom_announcements_controller.dart';
import 'package:elixr_application/features/classroom_announcements/classroom_announcements_pane.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingPinRepository extends InMemoryClassroomAnnouncementRepository {
  @override
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  }) async {
    throw StateError('offline');
  }
}

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

  test('trainee controller cannot pin or unpin announcements', () async {
    final repository = InMemoryClassroomAnnouncementRepository();
    final item = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'Reminder',
      body: 'Practice today.',
    );
    final controller = ClassroomAnnouncementsController(
      repository: repository,
      groupId: 'group-1',
      currentUserId: 'trainee-1',
      canManage: false,
      isGroupActive: () => true,
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.start();

    expect(await controller.pin(item), isFalse);
    expect(
      controller.errorMessage,
      'Only the teacher can manage announcements.',
    );
    expect(repository.pinnedAnnouncementIds, isEmpty);
  });

  testWidgets('pin action uses the shared ELIXR success toast', (tester) async {
    final repository = InMemoryClassroomAnnouncementRepository();
    final item = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'Reminder',
      body: 'Practice today.',
    );
    final controller = ClassroomAnnouncementsController(
      repository: repository,
      groupId: 'group-1',
      currentUserId: 'teacher-1',
      canManage: true,
      isGroupActive: () => true,
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: ClassroomAnnouncementsPane(
            controller: controller,
            teacherDisplayName: 'Grace Hopper',
            canManage: true,
            groupIsActive: true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(Key('classroom_announcement_pin_${item.id}')));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Pinned announcement.'), findsOneWidget);
    expect(
      controller.items.where((announcement) => announcement.isPinned),
      hasLength(1),
    );
    await tester.tap(find.byKey(const Key('elix_toast_close')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed pin keeps inline error feedback and shows no success toast',
    (tester) async {
      final repository = _FailingPinRepository();
      final item = await repository.createAnnouncement(
        groupId: 'group-1',
        teacherId: 'teacher-1',
        title: 'Reminder',
        body: 'Practice today.',
      );
      final controller = ClassroomAnnouncementsController(
        repository: repository,
        groupId: 'group-1',
        currentUserId: 'teacher-1',
        canManage: true,
        isGroupActive: () => true,
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);
      await controller.start();

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: ClassroomAnnouncementsPane(
              controller: controller,
              teacherDisplayName: 'Grace Hopper',
              canManage: true,
              groupIsActive: true,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(Key('classroom_announcement_pin_${item.id}')),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Pinned announcement.'), findsNothing);
      expect(
        controller.errorMessage,
        'Could not save the announcement. Try again.',
      );
      expect(repository.pinnedAnnouncementIds, isEmpty);
    },
  );
}
