import 'package:elixr_application/features/messages/messages_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = ChatUser(
    id: 'current',
    displayName: 'Current Trainee',
    role: 'Trainee',
  );
  const other = ChatUser(
    id: 'other',
    displayName: 'Other Teacher',
    role: 'Teacher',
  );

  test('search waits for two characters and returns sanitized users', () async {
    final repository = InMemoryChatRepository()..users.add(other);
    addTearDown(repository.dispose);
    final controller = MessagesController(
      repository: repository,
      currentUser: current,
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.updateSearch('o');
    expect(controller.searchState, MessageSearchState.waiting);
    controller.updateSearch('ot');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.searchState, MessageSearchState.ready);
    expect(controller.searchResults.single, same(other));
  });

  test(
    'opening a person keeps the thread empty until first successful send',
    () async {
      final repository = _CountingChatRepository();
      addTearDown(repository.dispose);
      final controller = MessagesController(
        repository: repository,
        currentUser: current,
      );
      addTearDown(controller.dispose);
      controller.start();
      await controller.openUser(other);
      await Future<void>.delayed(Duration.zero);

      expect(repository.conversations, isEmpty);
      expect(repository.messageWatchCount, 0);
      expect(controller.messageState, MessagePaneState.empty);
      expect(await controller.send('Hello'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repository.conversations, hasLength(1));
      expect(repository.messageWatchCount, 1);
      expect(controller.messages.single.body, 'Hello');

      await repository.sendMessage(
        sender: other,
        recipient: current,
        body: 'Reply',
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.messages.map((message) => message.body), [
        'Reply',
        'Hello',
      ]);
    },
  );

  test('blocked composer state follows live block changes', () async {
    final repository = InMemoryChatRepository();
    addTearDown(repository.dispose);
    final controller = MessagesController(
      repository: repository,
      currentUser: current,
    );
    addTearDown(controller.dispose);
    controller.start();
    await controller.openUser(other);
    await Future<void>.delayed(Duration.zero);
    await controller.toggleBlock();
    await Future<void>.delayed(Duration.zero);
    expect(controller.blockState.blockedByMe, isTrue);
    expect(await controller.send('Cannot send'), isFalse);
  });

  test(
    'real-time arrivals retain loaded older pages and their cursor',
    () async {
      final repository = InMemoryChatRepository();
      addTearDown(repository.dispose);
      for (var index = 1; index <= 45; index++) {
        await repository.sendMessage(
          sender: current,
          recipient: other,
          body: 'Message $index',
        );
      }
      final controller = MessagesController(
        repository: repository,
        currentUser: current,
      );
      addTearDown(controller.dispose);
      controller.start();
      await Future<void>.delayed(Duration.zero);
      await controller.openUser(other);
      await Future<void>.delayed(Duration.zero);

      expect(controller.messages, hasLength(40));
      expect(controller.hasOlder, isTrue);
      await controller.loadOlder();
      expect(controller.messages, hasLength(45));
      expect(controller.hasOlder, isFalse);

      await repository.sendMessage(
        sender: other,
        recipient: current,
        body: 'Live reply',
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.messages, hasLength(46));
      expect(
        controller.messages.any((message) => message.body == 'Message 1'),
        isTrue,
      );
      expect(controller.hasOlder, isFalse);
    },
  );
}

class _CountingChatRepository extends InMemoryChatRepository {
  int messageWatchCount = 0;

  @override
  Stream<ChatMessagePage> watchMessages({
    required String conversationId,
    int pageSize = ChatRepository.defaultMessagePageSize,
  }) {
    messageWatchCount++;
    return super.watchMessages(
      conversationId: conversationId,
      pageSize: pageSize,
    );
  }
}
