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

  test('pin replacement keeps exactly one announcement pinned', () async {
    var counter = 0;
    final repository = InMemoryClassroomAnnouncementRepository(
      generateId: () => 'announcement-${counter++}',
      now: () => DateTime.utc(2026, 9, 2, 10, counter),
    );
    addTearDown(repository.dispose);
    final first = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'First',
      body: 'First body',
    );
    final second = await repository.createAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      title: 'Second',
      body: 'Second body',
    );

    await repository.setPinnedAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      announcementId: first.id,
    );
    var page = await repository.watchAnnouncements(groupId: 'group-1').first;
    expect(page.items.first.id, first.id);
    expect(page.items.where((item) => item.isPinned), hasLength(1));

    await repository.setPinnedAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
      announcementId: second.id,
    );
    page = await repository.watchAnnouncements(groupId: 'group-1').first;
    expect(page.items.first.id, second.id);
    expect(page.items.where((item) => item.isPinned), hasLength(1));
    expect(
      page.items.singleWhere((item) => item.id == first.id).isPinned,
      isFalse,
    );

    await repository.setPinnedAnnouncement(
      groupId: 'group-1',
      teacherId: 'teacher-1',
    );
    page = await repository.watchAnnouncements(groupId: 'group-1').first;
    expect(page.items.where((item) => item.isPinned), isEmpty);
  });

  test(
    'scheduled announcements remain teacher-only until rescheduled to now',
    () async {
      var instant = DateTime.utc(2026, 9, 4, 12);
      final repository = InMemoryClassroomAnnouncementRepository(
        now: () => instant,
      );
      addTearDown(repository.dispose);
      final announcement = await repository.createAnnouncement(
        groupId: 'group-1',
        teacherId: 'teacher-1',
        title: 'Scheduled',
        body: 'Practice later.',
        publishAt: instant.add(const Duration(hours: 1)),
      );

      expect(
        (await repository.watchAnnouncements(groupId: 'group-1').first).items,
        isEmpty,
      );
      expect(
        (await repository
                .watchAnnouncements(
                  groupId: 'group-1',
                  includeUnpublished: true,
                )
                .first)
            .items,
        hasLength(1),
      );
      await expectLater(
        repository.setPinnedAnnouncement(
          groupId: 'group-1',
          teacherId: 'teacher-1',
          announcementId: announcement.id,
        ),
        throwsStateError,
      );

      await repository.updateAnnouncement(
        groupId: 'group-1',
        announcementId: announcement.id,
        teacherId: 'teacher-1',
        title: 'Published now',
        body: 'Practice now.',
        publishAt: null,
      );
      final published = await repository
          .watchAnnouncements(groupId: 'group-1')
          .first;
      expect(published.items.single.publishAt, isNull);
      await repository.setPinnedAnnouncement(
        groupId: 'group-1',
        teacherId: 'teacher-1',
        announcementId: announcement.id,
      );
      expect(
        (await repository.watchAnnouncements(groupId: 'group-1').first)
            .items
            .single
            .isPinned,
        isTrue,
      );
      instant = instant.add(const Duration(minutes: 1));
    },
  );
}
