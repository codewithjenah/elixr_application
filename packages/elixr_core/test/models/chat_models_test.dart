import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime? readDate(dynamic value) => value is DateTime ? value.toUtc() : null;

  test('message parser rejects malformed documents and accepts tombstones', () {
    final createdAt = DateTime.utc(2026, 8, 24);
    expect(
      ChatMessage.tryFromMap(
        {'sender_id': 'sender', 'body': '', 'created_at': createdAt},
        id: 'message',
        conversationId: 'conversation',
        readDate: readDate,
      ),
      isNull,
    );
    expect(
      ChatMessage.tryFromMap(
        {
          'sender_id': 'sender',
          'body': null,
          'created_at': createdAt,
          'deleted_at': createdAt.add(const Duration(seconds: 1)),
        },
        id: 'message',
        conversationId: 'conversation',
        readDate: readDate,
      )?.isDeleted,
      isTrue,
    );
  });

  test('message parser preserves migrated coaching metadata', () {
    final createdAt = DateTime.utc(2026, 8, 24);
    final message = ChatMessage.tryFromMap(
      {
        'sender_id': 'teacher',
        'body': 'Historical note',
        'created_at': createdAt,
        'legacy_coaching': {'movement_name': 'Hand Stall'},
      },
      id: 'legacy',
      conversationId: 'teacher__trainee',
      readDate: readDate,
    );
    expect(message?.isMigratedCoaching, isTrue);
    expect(message?.legacyMovementName, 'Hand Stall');
  });

  test('conversation parser filters malformed participant snapshots', () {
    final now = DateTime.utc(2026, 8, 24);
    final conversation = ChatConversation.tryFromMap(
      {
        'participant_snapshots': {
          'teacher': {
            'id': 'teacher',
            'display_name': 'Taylor Teacher',
            'role': 'Teacher',
          },
          'broken': {'display_name': '', 'role': 'Admin'},
        },
        'updated_at': now,
        'unread_counts': {'teacher': 0, 'broken': -1},
        'read_at': {'teacher': now},
        'cleared_at': {'teacher': now, 'broken': 'invalid'},
        'last_message_at': now,
        'status': 'active',
      },
      id: 'conversation',
      readDate: readDate,
    );
    expect(conversation?.participants.keys, ['teacher']);
    expect(conversation?.unreadCounts, {'teacher': 0});
    expect(conversation?.clearedAtFor('teacher'), now);
    expect(conversation?.isClearedFor('teacher'), isTrue);
    expect(
      ChatConversation.tryFromMap(
        {'participant_snapshots': {}, 'updated_at': now, 'status': 'active'},
        id: 'conversation',
        readDate: readDate,
      ),
      isNull,
    );
  });
}
