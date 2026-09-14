import 'package:elixr_application/services/message_unread_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks unread inbox total and resets when user is cleared', () async {
    final repository = InMemoryChatRepository();
    final service = MessageUnreadService(repository: repository);
    addTearDown(service.dispose);
    addTearDown(repository.dispose);

    const trainee = ChatUser(
      id: 'trainee-1',
      displayName: 'Trainee One',
      role: 'Trainee',
    );
    const teacher = ChatUser(
      id: 'teacher-1',
      displayName: 'Teacher One',
      role: 'Teacher',
    );

    service.setUser(trainee.id);
    await pumpEventQueue();
    await repository.sendMessage(
      sender: teacher,
      recipient: trainee,
      body: 'First',
    );
    await repository.sendMessage(
      sender: teacher,
      recipient: trainee,
      body: 'Second',
    );
    await pumpEventQueue();

    expect(service.unreadCount, 2);

    await repository.markRead(
      conversationId: ChatRepository.conversationIdFor(trainee.id, teacher.id),
      currentUserId: trainee.id,
    );
    await pumpEventQueue();
    expect(service.unreadCount, 0);

    service.setUser(null);
    expect(service.unreadCount, 0);
  });

  test(
    'emits one incoming-message event after its initial inbox baseline',
    () async {
      final repository = InMemoryChatRepository();
      final service = MessageUnreadService(repository: repository);
      addTearDown(service.dispose);
      addTearDown(repository.dispose);
      const recipient = ChatUser(
        id: 'recipient',
        displayName: 'Recipient',
        role: 'Trainee',
      );
      const sender = ChatUser(
        id: 'sender',
        displayName: 'Sam Sender',
        role: 'Teacher',
      );

      service.setUser(recipient.id);
      await pumpEventQueue();
      expect(service.latestIncomingMessage, isNull);

      await repository.sendMessage(
        sender: sender,
        recipient: recipient,
        body: 'Hello',
      );
      await pumpEventQueue();
      final event = service.latestIncomingMessage;
      expect(event?.senderName, sender.displayName);
      expect(event?.id, contains('message_1'));

      // The repository can publish unrelated updates without repeating the event.
      await repository.markUnread(
        conversationId: ChatRepository.conversationIdFor(
          recipient.id,
          sender.id,
        ),
        currentUserId: recipient.id,
      );
      await pumpEventQueue();
      expect(service.latestIncomingMessage?.id, event?.id);
    },
  );

  test('does not carry incoming-message baseline across accounts', () async {
    final repository = InMemoryChatRepository();
    final service = MessageUnreadService(repository: repository);
    addTearDown(service.dispose);
    addTearDown(repository.dispose);
    const first = ChatUser(id: 'first', displayName: 'First', role: 'Trainee');
    const second = ChatUser(
      id: 'second',
      displayName: 'Second',
      role: 'Trainee',
    );
    const sender = ChatUser(
      id: 'sender',
      displayName: 'Sender',
      role: 'Teacher',
    );

    service.setUser(first.id);
    await pumpEventQueue();
    await repository.sendMessage(
      sender: sender,
      recipient: first,
      body: 'For first',
    );
    await pumpEventQueue();
    expect(service.latestIncomingMessage, isNotNull);

    await repository.sendMessage(
      sender: sender,
      recipient: second,
      body: 'Before switch',
    );
    service.setUser(second.id);
    await pumpEventQueue();
    expect(service.latestIncomingMessage, isNull);
  });
}
