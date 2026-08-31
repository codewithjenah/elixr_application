import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('announcements paginate newest first without overlap', () async {
    var counter = 0;
    final repository = InMemoryClassroomAnnouncementRepository(
      generateId: () => 'announcement-${counter++}',
      now: () => DateTime.utc(2026, 8, 31, 12, counter),
    );
    addTearDown(repository.dispose);

    for (var index = 0; index < 5; index++) {
      await repository.createAnnouncement(
        groupId: 'group-1',
        teacherId: 'teacher-1',
        title: 'Title $index',
        body: 'Body $index',
      );
    }
    final first = await repository
        .watchAnnouncements(groupId: 'group-1', pageSize: 2)
        .first;
    final second = await repository.fetchOlderAnnouncements(
      groupId: 'group-1',
      startAfter: first.nextCursor!,
      pageSize: 2,
    );

    expect(first.items.map((item) => item.title), ['Title 4', 'Title 3']);
    expect(
      first.items
          .map((item) => item.id)
          .toSet()
          .intersection(second.items.map((item) => item.id).toSet()),
      isEmpty,
    );
  });

  test('only the author can edit or hard-delete an announcement', () async {
    final repository = InMemoryClassroomAnnouncementRepository();
    addTearDown(repository.dispose);
    final announcement = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'Original',
      body: 'Body',
    );

    await expectLater(
      repository.updateAnnouncement(
        groupId: 'group-1',
        announcementId: announcement.id,
        teacherId: 'teacher-2',
        title: 'Nope',
        body: 'Nope',
      ),
      throwsStateError,
    );
    await repository.updateAnnouncement(
      groupId: 'group-1',
      announcementId: announcement.id,
      teacherId: 'teacher-1',
      title: 'Updated',
      body: 'Updated body',
    );
    expect(repository.announcements[announcement.id]!.isEdited, isTrue);

    await repository.deleteAnnouncement(
      groupId: 'group-1',
      announcementId: announcement.id,
      teacherId: 'teacher-1',
    );
    expect(repository.announcements, isEmpty);
  });
}
