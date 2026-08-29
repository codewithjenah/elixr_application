import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const teacher = ChatUser(
    id: 'teacher',
    displayName: 'Taylor Teacher',
    role: 'Teacher',
  );
  const trainee = ChatUser(
    id: 'trainee',
    displayName: 'Terry Trainee',
    role: 'Trainee',
  );

  test('deterministic pair id is stable in either order', () {
    expect(
      ChatRepository.conversationIdFor('teacher', 'trainee'),
      ChatRepository.conversationIdFor('trainee', 'teacher'),
    );
    expect(
      ChatRepository.conversationIdFor('teacher', 'trainee'),
      'teacher__trainee',
    );
  });

  test('message validation rejects blank and overlong bodies', () {
    expect(ChatMessage.validateBody(' \n '), isNotNull);
    expect(
      ChatMessage.validateBody('a' * ChatMessage.maximumBodyLength),
      isNull,
    );
    expect(
      ChatMessage.validateBody('a' * (ChatMessage.maximumBodyLength + 1)),
      isNotNull,
    );
  });

  test(
    'send creates one inbox row and increments only recipient unread',
    () async {
      final repository = InMemoryChatRepository();
      addTearDown(repository.dispose);

      final sent = await repository.sendMessage(
        sender: teacher,
        recipient: trainee,
        body: '  Keep your wrist steady.  ',
      );
      final id = ChatRepository.conversationIdFor(teacher.id, trainee.id);
      expect(sent.body, 'Keep your wrist steady.');
      expect(repository.conversations, hasLength(1));
      expect(repository.conversations[id]!.unreadFor(teacher.id), 0);
      expect(repository.conversations[id]!.unreadFor(trainee.id), 1);

      await repository.markRead(conversationId: id, currentUserId: trainee.id);
      expect(repository.conversations[id]!.unreadFor(trainee.id), 0);
      expect(repository.conversations[id]!.readAt[trainee.id], isNotNull);
    },
  );

  test(
    'assignment result messages are idempotent per review revision',
    () async {
      final repository = InMemoryChatRepository();
      addTearDown(repository.dispose);

      final first = await repository.sendAssignmentResult(
        sender: teacher,
        recipient: trainee,
        movementTitle: 'Tin Balance',
        earnedScore: 75,
        maxScore: 80,
        feedback: 'Good control.',
        submissionId: 'review_sub_asg1_trainee',
        reviewRevision: 1,
      );
      final retry = await repository.sendAssignmentResult(
        sender: teacher,
        recipient: trainee,
        movementTitle: 'Tin Balance',
        earnedScore: 75,
        maxScore: 80,
        feedback: 'Good control.',
        submissionId: 'review_sub_asg1_trainee',
        reviewRevision: 1,
      );
      final nextRevision = await repository.sendAssignmentResult(
        sender: teacher,
        recipient: trainee,
        movementTitle: 'Tin Balance',
        earnedScore: 78,
        maxScore: 80,
        submissionId: 'review_sub_asg1_trainee',
        reviewRevision: 2,
      );

      expect(first.id, retry.id);
      expect(first.body, 'Tin Balance\nScore: 75/80\nFeedback: Good control.');
      expect(nextRevision.id, isNot(first.id));
      final conversation = repository.conversations.values.single;
      expect(conversation.unreadFor(trainee.id), 2);
      expect(repository.messages.values.single, hasLength(2));
    },
  );

  test(
    'author edits and soft deletes while history keeps a tombstone',
    () async {
      final repository = InMemoryChatRepository();
      addTearDown(repository.dispose);
      final message = await repository.sendMessage(
        sender: trainee,
        recipient: teacher,
        body: 'Original',
      );
      await repository.editMessage(
        conversationId: message.conversationId,
        messageId: message.id,
        currentUserId: trainee.id,
        body: 'Edited',
      );
      expect(
        repository.messages[message.conversationId]!.single.body,
        'Edited',
      );
      expect(
        repository.messages[message.conversationId]!.single.isEdited,
        isTrue,
      );

      await repository.deleteMessage(
        conversationId: message.conversationId,
        messageId: message.id,
        currentUserId: trainee.id,
      );
      final tombstone = repository.messages[message.conversationId]!.single;
      expect(tombstone.body, isNull);
      expect(tombstone.isDeleted, isTrue);
      expect(
        repository.conversations[message.conversationId]!.lastMessageBody,
        'Message deleted',
      );
    },
  );

  test('block in either direction returns a generic send failure', () async {
    final repository = InMemoryChatRepository();
    addTearDown(repository.dispose);
    await repository.blockUser(
      currentUserId: teacher.id,
      blockedUserId: trainee.id,
    );

    for (final pair in [
      (sender: teacher, recipient: trainee),
      (sender: trainee, recipient: teacher),
    ]) {
      await expectLater(
        repository.sendMessage(
          sender: pair.sender,
          recipient: pair.recipient,
          body: 'Blocked',
        ),
        throwsA(
          isA<ChatException>()
              .having((error) => error.code, 'code', ChatError.blocked)
              .having(
                (error) => error.userMessage,
                'sanitized message',
                'Message could not be sent.',
              ),
        ),
      );
    }
  });

  test('message pagination has stable non-overlapping pages', () async {
    final repository = InMemoryChatRepository();
    addTearDown(repository.dispose);
    for (var index = 0; index < 5; index++) {
      await repository.sendMessage(
        sender: teacher,
        recipient: trainee,
        body: 'Message $index',
      );
    }
    final id = ChatRepository.conversationIdFor(teacher.id, trainee.id);
    final first = await repository
        .watchMessages(conversationId: id, pageSize: 2)
        .first;
    final second = await repository.fetchOlderMessages(
      conversationId: id,
      startAfter: first.nextCursor!,
      pageSize: 2,
    );
    expect(first.messages, hasLength(2));
    expect(second.messages, hasLength(2));
    expect(
      first.messages
          .map((message) => message.id)
          .toSet()
          .intersection(second.messages.map((message) => message.id).toSet()),
      isEmpty,
    );
  });

  test('mark unread adds one unread marker for only the caller', () async {
    final repository = InMemoryChatRepository();
    addTearDown(repository.dispose);
    final message = await repository.sendMessage(
      sender: teacher,
      recipient: trainee,
      body: 'Read this',
    );
    await repository.markRead(
      conversationId: message.conversationId,
      currentUserId: trainee.id,
    );

    await repository.markUnread(
      conversationId: message.conversationId,
      currentUserId: trainee.id,
    );

    expect(
      repository.conversations[message.conversationId]!.unreadFor(trainee.id),
      1,
    );
    expect(
      repository.conversations[message.conversationId]!.unreadFor(teacher.id),
      0,
    );
  });

  test(
    'clear hides only the caller copy and later messages restore the row',
    () async {
      final repository = InMemoryChatRepository();
      addTearDown(repository.dispose);
      final oldMessage = await repository.sendMessage(
        sender: teacher,
        recipient: trainee,
        body: 'Old history',
      );

      await repository.clearConversation(
        conversationId: oldMessage.conversationId,
        currentUserId: trainee.id,
      );

      expect(await repository.watchInbox(trainee.id).first, isEmpty);
      expect(await repository.watchInbox(teacher.id).first, hasLength(1));

      await repository.sendMessage(
        sender: teacher,
        recipient: trainee,
        body: 'New message',
      );
      expect(await repository.watchInbox(trainee.id).first, hasLength(1));
      expect(
        repository.conversations[oldMessage.conversationId]!.clearedAtFor(
          trainee.id,
        ),
        isNotNull,
      );
    },
  );
}
