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
}
