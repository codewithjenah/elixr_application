import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/features/student_progress/student_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'student_progress_test_support.dart';

void main() {
  late FakeTeacherRelationshipRepository relationships;
  late ControllableTeacherProgressRepository progress;
  late StudentProgressController controller;

  setUp(() {
    relationships = FakeTeacherRelationshipRepository();
    progress = ControllableTeacherProgressRepository();
    controller = StudentProgressController(
      relationships: relationships,
      progress: progress,
      teacherId: 'teacher',
      traineeId: 'trainee',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> authorize() async {
    await controller.start();
    relationships.add(approvedLink());
    await pumpEventQueue();
  }

  test(
    'does not load protected data before a verified effective link',
    () async {
      await controller.start();
      relationships.add(approvedLink(), verified: false);
      await pumpEventQueue();
      expect(controller.state, StudentProgressState.connectionRequired);
      expect(progress.requests, isEmpty);
      relationships.add(approvedLink());
      await pumpEventQueue();
      expect(controller.state, StudentProgressState.loading);
      expect(progress.requests, hasLength(1));
    },
  );

  test(
    'withdrawal clears data and ignores late summary and page callbacks',
    () async {
      await authorize();
      progress.summaries.single.add(summary());
      progress.requests.single.completer.complete(
        TeacherProgressPage(sessions: [session('one')], hasMore: false),
      );
      await pumpEventQueue();
      expect(controller.state, StudentProgressState.ready);

      relationships.add(approvedLink(access: false));
      await pumpEventQueue();
      expect(controller.state, StudentProgressState.accessWithdrawn);
      progress.summaries.single.add(summary(seconds: 600));
      await pumpEventQueue();
      expect(controller.summary, isNull);
      expect(controller.sessions, isEmpty);
    },
  );

  test('restart synchronously clears existing protected data', () async {
    await authorize();
    progress.summaries.single.add(summary());
    progress.requests.single.completer.complete(
      TeacherProgressPage(sessions: [session('one')], hasMore: false),
    );
    await pumpEventQueue();
    final restart = controller.start();
    expect(controller.state, StudentProgressState.loadingRelationship);
    expect(controller.summary, isNull);
    expect(controller.sessions, isEmpty);
    await restart;
  });

  test(
    'pagination appends de-duplicated sessions and preserves a retry cursor',
    () async {
      await authorize();
      progress.summaries.single.add(summary());
      progress.requests.single.completer.complete(
        TeacherProgressPage(
          sessions: [session('one')],
          hasMore: true,
          nextCursor: const TestCursor('1'),
        ),
      );
      await pumpEventQueue();
      controller.loadMore();
      expect(progress.requests.last.cursor, const TestCursor('1'));
      progress.requests.last.completer.complete(
        TeacherProgressPage(
          sessions: [session('one'), session('two')],
          hasMore: false,
        ),
      );
      await pumpEventQueue();
      expect(controller.sessions.map((s) => s.sessionId), ['one', 'two']);
    },
  );

  test('generic first-page failure is contained and enters error', () async {
    await authorize();
    progress.requests.single.completer.completeError(Exception('offline'));
    await pumpEventQueue();

    expect(controller.state, StudentProgressState.error);
    expect(controller.summary, isNull);
    expect(controller.sessions, isEmpty);
    expect(controller.loadingMore, isFalse);
  });

  test(
    'pagination failure preserves data and retry uses the same cursor',
    () async {
      await authorize();
      progress.summaries.single.add(summary());
      progress.requests.single.completer.complete(
        TeacherProgressPage(
          sessions: [session('one')],
          hasMore: true,
          nextCursor: const TestCursor('next'),
        ),
      );
      await pumpEventQueue();

      final loadMore = controller.loadMore();
      progress.requests.last.completer.completeError(Exception('offline'));
      await loadMore;
      expect(controller.state, StudentProgressState.ready);
      expect(controller.sessions.map((item) => item.sessionId), ['one']);
      expect(controller.paginationError, isA<Exception>());
      expect(controller.hasMore, isTrue);

      final retry = controller.retryLoadMore();
      expect(progress.requests.last.cursor, const TestCursor('next'));
      progress.requests.last.completer.complete(
        TeacherProgressPage(sessions: [session('two')], hasMore: false),
      );
      await retry;
      expect(controller.sessions.map((item) => item.sessionId), ['one', 'two']);
    },
  );

  test('old relationship errors cannot clear a newer start', () async {
    await controller.start();
    await controller.start();
    relationships.addError(Exception('old'), listener: 0);
    relationships.add(approvedLink(), listener: 1);
    await pumpEventQueue();
    expect(controller.state, StudentProgressState.loading);
  });

  test('pause and disposal reject late callbacks', () async {
    await authorize();
    controller.pause();
    progress.summaries.single.add(summary());
    progress.requests.single.completer.complete(
      TeacherProgressPage(sessions: [session('one')], hasMore: false),
    );
    await pumpEventQueue();
    expect(controller.state, StudentProgressState.connectionRequired);
    expect(controller.summary, isNull);
  });
}
