import 'package:elixr_application/features/messages/messages_screen.dart';
import 'package:elixr_application/features/profile/profile_route_args.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_card.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher/teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trainee = ChatUser(
    id: 'trainee',
    displayName: 'Terry Trainee',
    role: 'Trainee',
  );
  late AuthService auth;
  late InMemoryChatRepository repository;

  setUp(() {
    auth = phase3TeacherAuth();
    repository = InMemoryChatRepository()..users.add(trainee);
  });

  tearDown(() async {
    auth.dispose();
    await repository.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    bool initialConversation = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ChatRepository>.value(value: repository),
        ],
        child: FluentApp(
          home: MessagesScreen(
            initialUserId: initialConversation ? trainee.id : null,
            initialDisplayName: initialConversation
                ? trainee.displayName
                : null,
            initialRole: initialConversation ? trainee.role : null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('wide layout shows people and conversation panes together', (
    tester,
  ) async {
    await pump(tester, size: const Size(1200, 800), initialConversation: true);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Terry Trainee'), findsOneWidget);
    expect(find.text('No messages yet. Say hello.'), findsOneWidget);
    expect(_composerFinder(), findsOneWidget);
  });

  testWidgets('messages header and conversation cards use consistent sizing', (
    tester,
  ) async {
    await pump(tester, size: const Size(640, 760));
    final authUser = auth.currentUser!;
    final recipient = ChatUser(
      id: authUser.id!,
      displayName: authUser.fullName,
      role: authUser.role,
    );
    const firstSender = ChatUser(
      id: 'first-sender',
      displayName: 'First Sender',
      role: 'Teacher',
    );
    const secondSender = ChatUser(
      id: 'second-sender',
      displayName: 'Second Sender',
      role: 'Trainee',
    );

    await repository.sendMessage(
      sender: firstSender,
      recipient: recipient,
      body: 'First preview',
    );
    await repository.sendMessage(
      sender: secondSender,
      recipient: recipient,
      body: 'Second preview',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('messages-header-icon')), findsOneWidget);
    final firstCard = find.ancestor(
      of: find.text(firstSender.displayName),
      matching: find.byType(ElixCard),
    );
    final secondCard = find.ancestor(
      of: find.text(secondSender.displayName),
      matching: find.byType(ElixCard),
    );
    expect(firstCard, findsOneWidget);
    expect(secondCard, findsOneWidget);
    expect(tester.getSize(firstCard), tester.getSize(secondCard));
    expect(tester.getSize(firstCard).height, 88);
  });

  testWidgets('narrow conversation has Back and Enter sends', (tester) async {
    await pump(tester, size: const Size(640, 760), initialConversation: true);
    expect(find.byIcon(FluentIcons.back), findsOneWidget);
    final composer = _composerFinder();
    await tester.enterText(composer, 'Hello from keyboard');
    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(repository.messages.values.single, hasLength(1));
    expect(find.text('Hello from keyboard'), findsOneWidget);
  });

  testWidgets('failed send shows the safe chat error and keeps Retry', (
    tester,
  ) async {
    repository = _FailingChatRepository()..users.add(trainee);
    await pump(tester, size: const Size(640, 760), initialConversation: true);
    await tester.enterText(_composerFinder(), 'This will fail safely');
    await tester.tap(find.byIcon(FluentIcons.send));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('message-send-error')), findsOneWidget);
    expect(
      find.text('Messages could not connect. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('incoming message shows the sender avatar beside its bubble', (
    tester,
  ) async {
    final authUser = auth.currentUser!;
    await repository.sendMessage(
      sender: trainee,
      recipient: ChatUser(
        id: authUser.id!,
        displayName: authUser.fullName,
        role: authUser.role,
        avatarUrl: authUser.profilePictureUrl,
      ),
      body: 'Hello po!',
    );

    await pump(tester, size: const Size(640, 760), initialConversation: true);
    await tester.pump();

    expect(find.text('Hello po!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('message-sender-avatar-message_1')),
      findsOneWidget,
    );
  });

  testWidgets('conversation actions stay in an overflow menu', (tester) async {
    final authUser = auth.currentUser!;
    await repository.sendMessage(
      sender: trainee,
      recipient: ChatUser(
        id: authUser.id!,
        displayName: authUser.fullName,
        role: authUser.role,
      ),
      body: 'Menu test',
    );
    await pump(tester, size: const Size(1200, 800));

    expect(find.text('Mark as unread'), findsNothing);
    expect(find.text('Delete conversation'), findsNothing);

    final row = find.text('Terry Trainee');
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
    await tester.pumpAndSettle();

    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Delete conversation'), findsOneWidget);

    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);
    expect(find.textContaining('does not delete their copy'), findsOneWidget);
  });

  testWidgets('search result without a conversation only offers View profile', (
    tester,
  ) async {
    await pump(tester, size: const Size(1200, 800));
    await _searchPeople(tester, 'Te');

    expect(find.text('SEARCH RESULTS'), findsOneWidget);
    expect(find.text('Terry Trainee'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
    await tester.pumpAndSettle();

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Mark as unread'), findsNothing);
    expect(find.text('Delete conversation'), findsNothing);
  });

  testWidgets(
    'search result with a conversation can delete it without removing the user',
    (tester) async {
      final authUser = auth.currentUser!;
      await repository.sendMessage(
        sender: trainee,
        recipient: ChatUser(
          id: authUser.id!,
          displayName: authUser.fullName,
          role: authUser.role,
        ),
        body: 'Search delete',
      );
      await pump(
        tester,
        size: const Size(1200, 800),
        initialConversation: true,
      );
      await tester.pump();
      expect(find.text('Search delete'), findsWidgets);

      await _searchPeople(tester, 'Te');
      await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
      await tester.pumpAndSettle();

      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Mark as unread'), findsOneWidget);
      expect(find.text('Delete conversation'), findsOneWidget);

      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();
      expect(find.text('Delete conversation?'), findsOneWidget);
      expect(find.textContaining('does not delete their copy'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('SEARCH RESULTS'), findsOneWidget);
      expect(find.text('Terry Trainee'), findsOneWidget);
      expect(
        find.text('Select a conversation or search for someone to message.'),
        findsOneWidget,
      );
      expect(repository.users, contains(trainee));
      expect(
        repository.conversations.values.single.isClearedFor(authUser.id!),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Mark as unread'), findsNothing);
      expect(find.text('Delete conversation'), findsNothing);

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(FluentIcons.clear));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('RECENT CONVERSATIONS'), findsOneWidget);
      expect(find.text('Terry Trainee'), findsNothing);
      expect(
        find.text(
          'Search for a teacher or trainee to send your first message.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('search result can mark an existing conversation unread', (
    tester,
  ) async {
    final authUser = auth.currentUser!;
    await repository.sendMessage(
      sender: ChatUser(
        id: authUser.id!,
        displayName: authUser.fullName,
        role: authUser.role,
      ),
      recipient: trainee,
      body: 'Outbound for unread',
    );
    await pump(tester, size: const Size(1200, 800));
    await tester.pump();

    await _searchPeople(tester, 'Te');
    await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as unread'));
    await tester.pumpAndSettle();

    final conversationId = ChatRepository.conversationIdFor(
      authUser.id!,
      trainee.id,
    );
    expect(
      repository.conversations[conversationId]!.unreadFor(authUser.id!),
      1,
    );
  });

  testWidgets('search result View profile still opens the person', (
    tester,
  ) async {
    String? openedPath;
    ProfileRouteArgs? openedArgs;
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (context, state) => const MessagesScreen(),
        ),
        GoRoute(
          path: '/teacher/profile/:userId',
          builder: (context, state) {
            openedPath = state.uri.path;
            openedArgs = state.extra is ProfileRouteArgs
                ? state.extra! as ProfileRouteArgs
                : null;
            return const ScaffoldPage(content: Text('Profile page'));
          },
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ChatRepository>.value(value: repository),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await _searchPeople(tester, 'Te');
    await tester.tap(find.byKey(const ValueKey('conversation-menu-trainee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View profile'));
    await tester.pumpAndSettle();

    expect(openedPath, '/teacher/profile/trainee');
    expect(openedArgs?.displayName, trainee.displayName);
    expect(openedArgs?.role, User.roleTrainee);
  });

  testWidgets(
    'new-message alert stays in the inbox flow and can be dismissed',
    (tester) async {
      await pump(tester, size: const Size(640, 760));
      final authUser = auth.currentUser!;
      final recipient = ChatUser(
        id: authUser.id!,
        displayName: authUser.fullName,
        role: authUser.role,
        avatarUrl: authUser.profilePictureUrl,
      );

      for (var index = 0; index < 8; index++) {
        final sender = ChatUser(
          id: 'sender-$index',
          displayName: 'Conversation $index',
          role: index.isEven ? 'Teacher' : 'Trainee',
        );
        repository.users.add(sender);
        await repository.sendMessage(
          sender: sender,
          recipient: recipient,
          body: 'New message $index',
        );
      }
      await tester.pump();
      await tester.pump();

      final alert = find.byKey(const ValueKey('messages-alert'));
      final summary = find.text('RECENT CONVERSATIONS');
      expect(alert, findsOneWidget);
      expect(summary, findsOneWidget);
      expect(
        tester.getBottomLeft(alert).dy,
        lessThanOrEqualTo(tester.getTopLeft(summary).dy),
      );

      await tester.pump(const Duration(seconds: 4));
      expect(alert, findsOneWidget);

      await tester.tap(
        find.descendant(of: alert, matching: find.byIcon(FluentIcons.clear)),
      );
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
    },
  );

  testWidgets(
    'new-message alert remains while any unread conversation remains',
    (tester) async {
      await pump(tester, size: const Size(640, 760));
      final authUser = auth.currentUser!;
      final recipient = ChatUser(
        id: authUser.id!,
        displayName: authUser.fullName,
        role: authUser.role,
      );
      const sender = ChatUser(
        id: 'new-sender',
        displayName: 'New Sender',
        role: 'Teacher',
      );
      const anotherSender = ChatUser(
        id: 'another-new-sender',
        displayName: 'Another New Sender',
        role: 'Teacher',
      );

      await repository.sendMessage(
        sender: sender,
        recipient: recipient,
        body: 'Please open this message.',
      );
      await repository.sendMessage(
        sender: anotherSender,
        recipient: recipient,
        body: 'Please open this other message.',
      );
      await tester.pump();
      await tester.pump();

      final alert = find.byKey(const ValueKey('messages-alert'));
      expect(alert, findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(alert, findsOneWidget);

      final senderTile = find.text(sender.displayName);
      await tester.ensureVisible(senderTile);
      await tester.tap(senderTile);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();
      expect(alert, findsOneWidget);

      final anotherSenderTile = find.text(anotherSender.displayName);
      await tester.ensureVisible(anotherSenderTile);
      await tester.tap(anotherSenderTile);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
    },
  );

  testWidgets('trainee viewing a teacher keeps the teacher role on profile', (
    tester,
  ) async {
    auth.dispose();
    auth =
        AuthService(
          repository: Phase3TestAuthRepository(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          const User(
            id: 'trainee',
            firstName: 'Terry',
            lastName: 'Trainee',
            email: 'trainee@example.com',
            role: User.roleTrainee,
          ),
        );
    const teacher = ChatUser(
      id: 'teacher-1',
      displayName: 'Jiro Lapuz',
      role: 'Teacher',
      avatarUrl: 'https://example.com/jiro.png',
    );
    await repository.sendMessage(
      sender: teacher,
      recipient: trainee,
      body: 'Welcome to class.',
    );

    String? openedPath;
    ProfileRouteArgs? openedArgs;
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (context, state) => const MessagesScreen(),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (context, state) {
            openedPath = state.uri.path;
            openedArgs = state.extra is ProfileRouteArgs
                ? state.extra! as ProfileRouteArgs
                : null;
            return const ScaffoldPage(content: Text('Profile page'));
          },
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ChatRepository>.value(value: repository),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conversation-menu-teacher-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View profile'));
    await tester.pumpAndSettle();

    expect(openedPath, '/profile/teacher-1');
    expect(openedArgs?.displayName, teacher.displayName);
    expect(openedArgs?.profilePictureUrl, teacher.avatarUrl);
    expect(openedArgs?.role, User.roleTeacher);
  });
}

Finder _composerFinder() => find.byWidgetPredicate(
  (widget) => widget is TextBox && widget.placeholder == 'Write a message...',
  description: 'message composer',
);

Finder _peopleSearchFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is TextBox && widget.placeholder == 'Find a Teacher or Trainee',
  description: 'people search',
);

Future<void> _searchPeople(WidgetTester tester, String query) async {
  await tester.enterText(_peopleSearchFinder(), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

class _FailingChatRepository extends InMemoryChatRepository {
  @override
  Future<ChatMessage> sendMessage({
    required ChatUser sender,
    required ChatUser recipient,
    required String body,
    String? idempotencyKey,
  }) async => throw const ChatException(ChatError.network);
}
