import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'historical template assignment stays read-only and never opens the camera',
    (tester) async {
      final auth =
          AuthService(
            repository: _UnusedAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            const User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      final assignments = InMemoryClassroomAssignmentRepository();
      final groups = InMemoryGroupRepository();
      addTearDown(() {
        auth.dispose();
        assignments.dispose();
        groups.dispose();
      });

      assignments.assignments['retired-assignment'] = const GroupAssignment(
        id: 'retired-assignment',
        teacherId: 'teacher-1',
        groupId: 'group-1',
        movementId: 'movement-1',
        revisionId: 'revision-1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.templateScored,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Historical Wrist Stall',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        allowedProp: TrainingProp.bottle,
        assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.either),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            Provider<GroupRepository>.value(value: groups),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const SizedBox(
              width: 1200,
              height: 800,
              child: AssignedPracticeScreen(assignmentId: 'retired-assignment'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Automatic template assessment has been retired'),
        findsOneWidget,
      );
      expect(find.byType(LivePracticeScreen), findsNothing);
    },
  );
}
