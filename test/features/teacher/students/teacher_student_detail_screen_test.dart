import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_detail_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late FakeTeacherLinksRepository links;
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late InMemoryCoachingNoteRepository coaching;
  late AuthService auth;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    links = FakeTeacherLinksRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    coaching = InMemoryCoachingNoteRepository();
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<TeacherRelationshipRepository>.value(value: links),
          Provider<TeacherProgressRepository>.value(value: progress),
          Provider<PublicProfileRepository>.value(value: profiles),
          Provider<CoachingNoteRepository>.value(value: coaching),
        ],
        child: const FluentApp(
          home: TeacherStudentDetailScreen(traineeId: 'trainee'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'waiting for progress access shows classroom copy without unauthorized lock',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      await pumpDetail(tester);
      links.emit(const []);
      await tester.pump();

      expect(find.text('Waiting for progress access'), findsOneWidget);
      expect(
        find.textContaining('has not shared official practice progress'),
        findsOneWidget,
      );
      expect(find.text('Not authorized'), findsNothing);
      expect(find.textContaining('Private public profile'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
    },
  );

  testWidgets(
    'private profile badge stays visible while consented progress remains available',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
          traineeName: 'Ada Lovelace',
        ),
      );
      progress.inner.setSummary('trainee', sampleSummary());
      progress.inner.sessions['trainee'] = [sampleSession()];
      await pumpDetail(tester);
      profiles.emitProfile(
        'trainee',
        const PublicProfile(
          userId: 'trainee',
          displayName: 'Ada Lovelace',
          visibility: ProfileVisibility.private,
        ),
      );
      links.emit([approvedProgressLink()]);
      await tester.pump();

      expect(find.text('Ada Lovelace'), findsWidgets);
      expect(find.textContaining('Private public profile'), findsOneWidget);
      expect(find.text('Practice progress'), findsOneWidget);
      expect(find.text('Hand Stall'), findsWidgets);
      expect(find.text('Not authorized'), findsNothing);
    },
  );

  testWidgets(
    'unauthorized guessed uid hides progress, coaching, and protected profile details',
    (tester) async {
      await pumpDetail(tester);

      expect(find.text('Not authorized'), findsOneWidget);
      expect(find.textContaining('not in any of your groups'), findsOneWidget);
      expect(find.text('Practice progress'), findsNothing);
      expect(find.text('Add note'), findsNothing);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.textContaining('Private public profile'), findsNothing);
    },
  );

  testWidgets('progress ready, empty, and withdrawn states', (tester) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await pumpDetail(tester);
    links.emit([approvedProgressLink()]);
    await tester.pump();
    expect(find.text('Hand Stall'), findsWidgets);

    links.emit([
      approvedProgressLink().copyWith(
        progressAccess: TeacherProgressAccess.none,
      ),
    ]);
    await tester.pump();
    expect(find.text('Progress access withdrawn'), findsOneWidget);
    expect(find.text('Hand Stall'), findsNothing);
  });

  testWidgets('empty progress history shows empty copy', (tester) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
    progress.inner.setSummary('trainee', null);
    await pumpDetail(tester);
    links.emit([approvedProgressLink()]);
    await tester.pump();

    expect(find.text('No practice history yet'), findsOneWidget);
    expect(find.text('Hand Stall'), findsNothing);
  });
}
