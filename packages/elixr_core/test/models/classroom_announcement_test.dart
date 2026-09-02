import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('announcement parser tolerates pending server timestamps', () {
    final announcement = ClassroomAnnouncement.tryFromMap({
      'group_id': 'group-1',
      'teacher_id': 'teacher-1',
      'title': 'Practice reminder',
      'body': 'Review Hand Stall before Friday.',
      'created_at': null,
      'edited_at': null,
      'schema_version': 1,
    }, id: 'announcement-1');

    expect(announcement, isNotNull);
    expect(announcement!.createdAt, isNull);
    expect(announcement.isEdited, isFalse);
    expect(announcement.isPinned, isFalse);
    expect(announcement.pinnedAt, isNull);
  });

  test('announcement validation rejects blank and overlong fields', () {
    expect(ClassroomAnnouncement.validateTitle('   '), isNotNull);
    expect(
      ClassroomAnnouncement.validateTitle(
        'a' * ClassroomAnnouncement.maxTitleLength,
      ),
      isNull,
    );
    expect(
      ClassroomAnnouncement.validateBody(
        'a' * (ClassroomAnnouncement.maxBodyLength + 1),
      ),
      isNotNull,
    );
  });
}
