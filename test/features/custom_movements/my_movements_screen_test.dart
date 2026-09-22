import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/data/repositories/session_repository.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_builder_dialog.dart';
import 'package:elixr_application/features/custom_movements/my_movements_screen.dart';
import 'package:elixr_application/features/movements/movements_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _UnusedAuthRepository extends Fake implements AuthRepositoryBase {}

class _CustomRepository extends Fake implements CustomMovementRepository {
  _CustomRepository(List<CustomMovement> movements)
    : movements = List.of(movements) {
    _controller = StreamController<List<CustomMovement>>.broadcast();
  }

  final List<CustomMovement> movements;
  late final StreamController<List<CustomMovement>> _controller;
  CustomMovementRevision? revision;
  String? watchedOwnerUid;
  String? requestedRevisionId;
  String? archivedMovementId;

  void dispose() => _controller.close();

  void _emit() => _controller.add(List.unmodifiable(movements));

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({required String ownerUid}) {
    watchedOwnerUid = ownerUid;
    scheduleMicrotask(_emit);
    // Deliberately return every fixture. The widget must not trust a malformed
    // implementation to leak another owner's or a Teacher-owned movement.
    return _controller.stream;
  }

  @override
  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async => null;

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    requestedRevisionId = revisionId;
    return revision;
  }

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
  }) async {
    archivedMovementId = movementId;
    movements.removeWhere(
      (movement) => movement.id == movementId && movement.ownerUid == ownerUid,
    );
    _emit();
  }

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

class _NoSessionsRepository extends SessionRepository {
  @override
  Future<List<Session>> getSessionsForUser(String userId) async => const [];
}

const _trainee = User(
  id: 'trainee-1',
  firstName: 'Ada',
  lastName: 'Lovelace',
  email: 'ada@example.com',
  role: User.roleTrainee,
);

CustomMovement _movement({
  required String id,
  required String ownerUid,
  CustomMovementOwnerRole ownerRole = CustomMovementOwnerRole.trainee,
  String name = 'Own Cascade',
  String difficulty = 'Medium',
  TrainingProp prop = TrainingProp.shaker,
}) => CustomMovement(
  id: id,
  ownerUid: ownerUid,
  ownerRole: ownerRole,
  name: name,
  description: 'A personal automatic movement.',
  difficulty: difficulty,
  propType: prop,
  status: CustomMovementStatus.active,
  activeRevisionId: 'revision-$id',
);

MovementTemplate _template() => MovementTemplate.tryFrom({
  'schema_version': 1,
  'capture_version': 1,
  'duration_ms': 900,
  'reference_count': 3,
  'required_modalities': ['hands', 'prop_translation'],
  'normalization_metadata': {
    'anchor': 'shoulder_midpoint',
    'scale': 'shoulder_width',
    'mirrored': false,
  },
  'feature_capabilities': {
    'pose': false,
    'hands': true,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': false,
    'left_hand': true,
    'right_hand': false,
  },
  'canonical_sequence': [
    {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
    {'timestamp_ms': 900, 'pose': <String, dynamic>{}},
  ],
  'variability_metadata': {'duration_std_ms': 0.0},
  'prop_events': <Map<String, dynamic>>[],
})!;

AuthService _auth() => AuthService(
  repository: _UnusedAuthRepository(),
  awaitInitialAuthState: () async {},
)..seedAuthenticatedUser(_trainee);

Widget _movementsHost({
  required AuthService auth,
  required CustomMovementRepository repository,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthService>.value(value: auth),
    ChangeNotifierProvider<SessionService>(create: (_) => SessionService()),
    Provider<CustomMovementRepository>.value(value: repository),
  ],
  child: FluentApp(
    theme: AppTheme.dark,
    home: SizedBox(
      width: 1200,
      height: 900,
      child: MovementsScreen(
        sessionRepository: _NoSessionsRepository(),
        userId: _trainee.id,
      ),
    ),
  ),
);

void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trainee empty state opens the shared builder with save disabled',
    (tester) async {
      _useDesktopSurface(tester);
      final auth = _auth();
      addTearDown(auth.dispose);
      final repository = _CustomRepository(const []);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<CustomMovementRepository>.value(value: repository),
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

      expect(find.byKey(const ValueKey('my-movements-back')), findsOneWidget);
      expect(find.bySemanticsLabel('Back to Movements'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-movements-create')), findsOneWidget);
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

  testWidgets('standalone My Movements back control opens Movements', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final auth = _auth();
    addTearDown(auth.dispose);
    final repository = _CustomRepository(const []);
    addTearDown(repository.dispose);
    final router = GoRouter(
      initialLocation: AppRoutePaths.myMovements,
      routes: [
        GoRoute(
          path: AppRoutePaths.myMovements,
          builder: (_, _) => const MyMovementsScreen(),
        ),
        GoRoute(
          path: AppRoutePaths.movements,
          builder: (_, _) => const Text('canonical Movements'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<CustomMovementRepository>.value(value: repository),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('my-movements-back')));
    await tester.pumpAndSettle();

    expect(find.text('canonical Movements'), findsOneWidget);
  });

  testWidgets(
    'main Movements personal view shows only authenticated trainee movements',
    (tester) async {
      _useDesktopSurface(tester);
      final auth = _auth();
      addTearDown(auth.dispose);
      final repository = _CustomRepository([
        _movement(id: 'own', ownerUid: 'trainee-1'),
        _movement(
          id: 'other',
          ownerUid: 'trainee-2',
          name: 'Another trainee movement',
        ),
        _movement(
          id: 'assigned',
          ownerUid: 'teacher-1',
          ownerRole: CustomMovementOwnerRole.teacher,
          name: 'Teacher assignment movement',
        ),
      ]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        _movementsHost(auth: auth, repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('Official ELIXR'), findsOneWidget);
      expect(find.text('My Movements'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-movements-back')), findsNothing);
      expect(find.text('Own Cascade'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('movement-library-mine')));
      await tester.pumpAndSettle();

      expect(repository.watchedOwnerUid, 'trainee-1');
      expect(find.text('TRAINING LIBRARY'), findsOneWidget);
      expect(find.text('Movements'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-movements-back')), findsNothing);
      expect(find.text('Own Cascade'), findsOneWidget);
      expect(find.text('Medium · Cocktail Shaker'), findsOneWidget);
      expect(find.text('Another trainee movement'), findsNothing);
      expect(find.text('Teacher assignment movement'), findsNothing);
    },
  );

  testWidgets(
    'embedded personal library renders empty state and shared builder',
    (tester) async {
      _useDesktopSurface(tester);
      final auth = _auth();
      addTearDown(auth.dispose);
      final repository = _CustomRepository(const []);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        _movementsHost(auth: auth, repository: repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('movement-library-mine')));
      await tester.pumpAndSettle();

      expect(find.text('Create your first movement'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-movements-create')));
      await tester.pumpAndSettle();

      expect(find.byType(CustomMovementBuilderDialog), findsOneWidget);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text('Prop'), findsOneWidget);
      final propSelector = tester.widget<ComboBox<TrainingProp>>(
        find.byKey(const ValueKey('custom-movement-prop')),
      );
      expect(
        propSelector.items!.map((item) => item.value),
        containsAllInOrder([TrainingProp.bottle, TrainingProp.shaker]),
      );
    },
  );

  testWidgets('changing Prop invalidates an existing ready template', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final repository = _CustomRepository(const []);
    addTearDown(repository.dispose);
    final movement = _movement(
      id: 'editable',
      ownerUid: 'trainee-1',
      prop: TrainingProp.bottle,
    );

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: CustomMovementBuilderDialog(
          ownerUid: 'trainee-1',
          ownerRole: CustomMovementOwnerRole.trainee,
          repository: repository,
          existing: movement,
          existingRevision: CustomMovementRevision(
            id: movement.activeRevisionId,
            movementId: movement.id,
            ownerUid: movement.ownerUid,
            ownerRole: movement.ownerRole,
            template: _template(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Automatic assessment ready'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('custom-movement-save')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('custom-movement-prop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cocktail Shaker').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Automatic assessment needs 3 references'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('custom-movement-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Edit loads the active revision and Archive removes the card', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final auth = _auth();
    addTearDown(auth.dispose);
    final movement = _movement(id: 'actions', ownerUid: 'trainee-1');
    final repository = _CustomRepository([movement])
      ..revision = CustomMovementRevision(
        id: movement.activeRevisionId,
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: _template(),
      );
    addTearDown(repository.dispose);

    await tester.pumpWidget(_movementsHost(auth: auth, repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movement-library-mine')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('my-movement-edit-actions')));
    await tester.pumpAndSettle();
    expect(repository.requestedRevisionId, movement.activeRevisionId);
    expect(find.text('Edit Movement'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-movement-archive-actions')));
    await tester.pumpAndSettle();

    expect(repository.archivedMovementId, 'actions');
    expect(find.text('Own Cascade'), findsNothing);
    expect(find.text('Create your first movement'), findsOneWidget);
  });

  testWidgets(
    'canonical personal practice returns to Movements with My Movements selected',
    (tester) async {
      _useDesktopSurface(tester);
      final auth = _auth();
      addTearDown(auth.dispose);
      final repository = _CustomRepository([
        _movement(id: 'practice-me', ownerUid: 'trainee-1'),
      ]);
      addTearDown(repository.dispose);
      final router = GoRouter(
        initialLocation: AppRoutePaths.movements,
        routes: [
          GoRoute(
            path: AppRoutePaths.movements,
            builder: (_, state) => MovementsScreen(
              sessionRepository: _NoSessionsRepository(),
              userId: _trainee.id,
              initialMyMovements: AppRoutePaths.opensMyMovementsLibrary(
                state.uri,
              ),
            ),
          ),
          GoRoute(
            path: '${AppRoutePaths.movements}/practice/:movementId',
            builder: (context, state) => Column(
              children: [
                Text('practice:${state.pathParameters['movementId']}'),
                Button(
                  key: const ValueKey('training-header-back'),
                  onPressed: () =>
                      context.go(AppRoutePaths.movementsMyMovements),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<SessionService>(
              create: (_) => SessionService(),
            ),
            Provider<CustomMovementRepository>.value(value: repository),
          ],
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('movement-library-mine')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('my-movement-practice-practice-me')),
      );
      await tester.pumpAndSettle();

      expect(find.text('practice:practice-me'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('training-header-back')));
      await tester.pumpAndSettle();

      expect(find.text('practice:practice-me'), findsNothing);
      expect(find.text('Own Cascade'), findsOneWidget);
      expect(
        tester
            .widget<ToggleButton>(
              find.byKey(const ValueKey('movement-library-mine')),
            )
            .checked,
        isTrue,
      );
      expect(
        tester
            .widget<ToggleButton>(
              find.byKey(const ValueKey('movement-library-official')),
            )
            .checked,
        isFalse,
      );
    },
  );
}
