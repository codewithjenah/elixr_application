import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/class_challenge.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/class_challenge_repository.dart';
import 'package:elixr_application/features/class_challenges/class_challenge_play_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher/teacher_phase3_test_support.dart';

class _FakeClassChallengeRepository implements ClassChallengeRepository {
  _FakeClassChallengeRepository(this.challenge);

  final ClassChallenge challenge;

  @override
  Future<ClassChallenge?> getChallenge({required String challengeId}) async =>
      challenge;

  @override
  Stream<ClassChallengeParticipant?> watchParticipant({
    required String challengeId,
    required String traineeId,
  }) => Stream.value(null);

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchLeaderboard({
    required String challengeId,
    required String groupId,
    required String teacherId,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ready-up header stays readable and returns to Challenges', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final challenge = ClassChallenge(
      id: 'challenge-1',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      teacherDisplayName: 'Coach',
      title: 'Body Grip Challenge',
      description: 'Complete a clean body grip.',
      movementName: 'Body Grip',
      difficulty: 'Beginner',
      prop: TrainingProp.bottle,
      startAt: now.subtract(const Duration(days: 1)),
      deadline: now.add(const Duration(days: 1)),
    );
    final repository = _FakeClassChallengeRepository(challenge);
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    final playLocation = AppRoutePaths.classChallengePlay(
      challenge.groupId,
      challenge.id,
    );
    final router = GoRouter(
      initialLocation: playLocation,
      routes: [
        GoRoute(
          path:
              '${AppRoutePaths.classChallengePlayPrefix}/:groupId/:challengeId',
          builder: (context, state) => ClassChallengePlayScreen(
            groupId: state.pathParameters['groupId']!,
            challengeId: state.pathParameters['challengeId']!,
          ),
        ),
        GoRoute(
          path: '${AppRoutePaths.teacherAccess}/:groupId',
          builder: (context, state) => Text(
            'Destination: ${state.pathParameters['groupId']} '
            '${state.uri.queryParameters['tab']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ClassChallengeRepository>.value(value: repository),
          ChangeNotifierProvider<AuthService>.value(value: auth),
        ],
        child: FluentApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Body Grip Challenge'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Class Challenge')).style?.color,
      Colors.white,
    );
    expect(
      find.bySemanticsLabel('Back to classroom challenges'),
      findsOneWidget,
    );
    final backButton = tester.widget<Button>(
      find.descendant(
        of: find.byKey(const Key('class_challenge_play_back')),
        matching: find.byType(Button),
      ),
    );
    expect(
      backButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );

    await tester.tap(find.byKey(const Key('class_challenge_play_back')));
    await tester.pumpAndSettle();

    expect(find.text('Destination: group-1 challenges'), findsOneWidget);
  });
}
