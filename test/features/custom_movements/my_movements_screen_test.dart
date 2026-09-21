import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/features/custom_movements/my_movements_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _UnusedAuthRepository extends Fake implements AuthRepositoryBase {}

class _CustomRepository extends Fake implements CustomMovementRepository {
  _CustomRepository(this.movements);

  final List<CustomMovement> movements;

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({
    required String ownerUid,
  }) => Stream.value(
    movements.where((movement) => movement.ownerUid == ownerUid).toList(),
  );

  @override
  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async => null;

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async => null;

  @override
  Future<CustomMovement> createMovement({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
  }) => throw UnimplementedError();

  @override
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
  }) => throw UnimplementedError();

  @override
  Future<void> archiveMovement({
    required String movementId,
    required String ownerUid,
  }) async {}

  @override
  Future<void> savePersonalResult({
    required String ownerUid,
    required String movementId,
    required String revisionId,
    required double totalScore,
    required Map<String, double> componentScores,
    required List<String> feedback,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trainee empty state opens the shared builder with save disabled',
    (tester) async {
      final auth =
          AuthService(
            repository: _UnusedAuthRepository(),
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
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<CustomMovementRepository>.value(
              value: _CustomRepository(const []),
            ),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const SizedBox(
              width: 1200,
              height: 800,
              child: MyMovementsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your first movement'), findsOneWidget);
      expect(find.textContaining('three references'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('my-movements-create')));
      await tester.pumpAndSettle();

      expect(find.text('Create Movement'), findsWidgets);
      expect(
        find.text('Automatic assessment needs 3 references'),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('custom-movement-save')),
      );
      expect(save.onPressed, isNull);
    },
  );
}
