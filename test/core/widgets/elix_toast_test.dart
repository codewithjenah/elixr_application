import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/incoming_event_toast_coordinator.dart';
import 'package:elixr_application/core/widgets/elix_toast.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/teacher/activity_center/teacher_activity_controller.dart';
import 'package:elixr_application/features/trainee/activity_center/trainee_activity_controller.dart';
import 'package:elixr_application/services/message_unread_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../features/teacher/teacher_phase3_test_support.dart';

void main() {
  Future<void> pumpToastHost(
    WidgetTester tester, {
    Size? size,
    String message = 'Unarchived BSIT-3A.',
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: shad.ShadToaster(
            child: Builder(
              builder: (context) => Button(
                onPressed: () =>
                    ElixToast.showSuccess(context, message: message),
                child: const Text('Show toast'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders once and can be dismissed manually', (tester) async {
    await pumpToastHost(tester);

    await tester.tap(find.text('Show toast'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsOneWidget);
    expect(find.text('Unarchived BSIT-3A.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('elix_toast_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsNothing);
  });

  testWidgets('auto-dismisses and keeps long text within a narrow window', (
    tester,
  ) async {
    await pumpToastHost(
      tester,
      size: const Size(260, 480),
      message:
          'The classroom was successfully updated with a longer confirmation message.',
    );

    await tester.tap(find.text('Show toast'));
    await tester.pumpAndSettle();

    final toast = tester.getRect(find.byKey(const Key('elix_toast')));
    expect(toast.width, lessThanOrEqualTo(228));

    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsNothing);
  });

  testWidgets('error toasts use a distinct title', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: shad.ShadToaster(
            child: Builder(
              builder: (context) => Button(
                onPressed: () =>
                    ElixToast.showError(context, message: 'Upload failed.'),
                child: const Text('Show error'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show error'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Upload failed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a request during build is deferred without a rendering error', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: shad.ShadToaster(child: _ToastRequestedDuringBuild()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Requested during build.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid requests show only the newest toast deterministically', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: shad.ShadToaster(
            child: Builder(
              builder: (context) => Button(
                onPressed: () {
                  ElixToast.showSuccess(context, message: 'Older toast.');
                  ElixToast.showError(context, message: 'Newest toast.');
                },
                child: const Text('Show rapid toasts'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show rapid toasts'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Older toast.'), findsNothing);
    expect(find.text('Newest toast.'), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued request does nothing after its host is disposed', (
    tester,
  ) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: shad.ShadToaster(
            child: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    ElixToast.showInfo(toastContext, message: 'Disposed host.');
    await tester.pumpWidget(const SizedBox.shrink());

    expect(find.text('Disposed host.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incoming-message listener presents a toast safely', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    final messages = _TestMessageUnreadService();
    final teacherActivities = TeacherActivityController(
      groupRepository: InMemoryGroupRepository(),
      assignmentRepository: InMemoryClassroomAssignmentRepository(),
      chatRepository: InMemoryChatRepository(),
      readStore: InMemoryActivityReadStore(),
    );
    final traineeActivities = TraineeActivityController(
      groupRepository: InMemoryGroupRepository(),
      assignmentRepository: InMemoryClassroomAssignmentRepository(),
      announcementRepository: InMemoryClassroomAnnouncementRepository(),
      readStore: InMemoryActivityReadStore(),
    );
    addTearDown(auth.dispose);
    addTearDown(messages.dispose);
    addTearDown(teacherActivities.dispose);
    addTearDown(traineeActivities.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider<MessageUnreadService>.value(value: messages),
          ChangeNotifierProvider.value(value: teacherActivities),
          ChangeNotifierProvider.value(value: traineeActivities),
        ],
        child: FluentApp(
          theme: AppTheme.dark,
          home: ElixShadThemeBridge(
            child: shad.ShadToaster(
              child: IncomingEventToastCoordinator(
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    messages.emit('conversation-1:message-1', 'Ada');
    await tester.pump();
    await tester.pump();

    expect(find.text('New message from Ada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ToastRequestedDuringBuild extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    ElixToast.showInfo(context, message: 'Requested during build.');
    return const SizedBox.shrink();
  }
}

class _TestMessageUnreadService extends MessageUnreadService {
  _TestMessageUnreadService() : super(repository: InMemoryChatRepository());

  IncomingMessageEvent? _event;

  @override
  IncomingMessageEvent? get latestIncomingMessage => _event;

  void emit(String id, String senderName) {
    _event = IncomingMessageEvent(id: id, senderName: senderName);
    notifyListeners();
  }
}
