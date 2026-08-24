import 'package:elixr_application/features/messages/messages_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

Finder _composerFinder() => find.byWidgetPredicate(
  (widget) => widget is TextBox && widget.placeholder == 'Write a message',
  description: 'message composer',
);
