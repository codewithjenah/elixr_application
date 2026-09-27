import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/custom_movement_reference_image.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_screen.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

/// In-memory owner library. Deletion archives (removes from the active
/// stream) and records every call; it never touches revisions or results.
class _CustomRepository extends Fake implements CustomMovementRepository {
  _CustomRepository(List<CustomMovement> movements)
    : movements = List.of(movements);

  final List<CustomMovement> movements;
  final _controller = StreamController<List<CustomMovement>>.broadcast();
  final List<({String movementId, String ownerUid})> deleteCalls = [];
  Completer<void>? deleteGate;
  bool failDelete = false;

  void _emit() => _controller.add(List.unmodifiable(movements));

  void dispose() => _controller.close();

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({required String ownerUid}) {
    scheduleMicrotask(_emit);
    // Deliberately unfiltered: the section must not trust a malformed
    // implementation to hide foreign or archived movements.
    return _controller.stream;
  }

  @override
  Future<void> deleteOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    deleteCalls.add((movementId: movementId, ownerUid: ownerUid));
    await deleteGate?.future;
    if (failDelete) throw StateError('delete failed');
    movements.removeWhere(
      (movement) => movement.id == movementId && movement.ownerUid == ownerUid,
    );
    _emit();
  }

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async => null;

  @override
  Future<void> savePersonalResult({
    required String ownerUid,
    required String movementId,
    required String revisionId,
    required double totalScore,
    required Map<String, double> componentScores,
    required List<String> feedback,
    required String sessionId,
    required String movementName,
    required String difficulty,
    required TrainingProp propType,
    required int durationSeconds,
    String? referenceImageStoragePath,
    Uint8List? evidenceJpegBytes,
  }) async {}
}

CustomMovement _movement({
  required String id,
  String ownerUid = 'teacher-1',
  String name = 'Teacher Cascade',
  String description = 'Toss the bottle and catch it cleanly.',
  CustomMovementStatus status = CustomMovementStatus.active,
}) => CustomMovement(
  id: id,
  ownerUid: ownerUid,
  ownerRole: CustomMovementOwnerRole.teacher,
  name: name,
  description: description,
  difficulty: 'Hard',
  propType: TrainingProp.shaker,
  status: status,
  activeRevisionId: 'revision-$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryTeacherMovementRepository movements;
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late TeacherMovementsController controller;

  setUp(() {
    movements = InMemoryTeacherMovementRepository();
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
  });

  tearDown(() {
    controller.dispose();
    movements.dispose();
    groups.dispose();
    assignments.dispose();
  });

  Future<void> pumpLibrary(
    WidgetTester tester,
    _CustomRepository repository, {
    Size size = const Size(1280, 900),
    FluentThemeData? theme,
    bool startController = true,
  }) async {
    if (startController) await controller.start();
    controller.setTab(TeacherMovementsTab.mine);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<GroupRepository>.value(value: groups),
          Provider<CustomMovementRepository>.value(value: repository),
        ],
        child: FluentApp(
          theme: theme ?? AppTheme.dark,
          builder: (context, child) => ElixShadThemeBridge(
            child: shad.ShadToaster(child: child ?? const SizedBox.shrink()),
          ),
          home: TeacherMovementsScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Teacher custom movements render as full cards with four actions',
    (tester) async {
      final repository = _CustomRepository([
        _movement(id: 'own'),
        _movement(id: 'foreign', ownerUid: 'teacher-2', name: 'Foreign move'),
        _movement(
          id: 'archived',
          name: 'Archived move',
          status: CustomMovementStatus.archived,
        ),
      ]);
      addTearDown(repository.dispose);

      await pumpLibrary(tester, repository);

      final card = find.byKey(
        const ValueKey('teacher-custom-movement-card-own'),
      );
      expect(card, findsOneWidget);
      Finder inCard(Finder finder) =>
          find.descendant(of: card, matching: finder);
      expect(inCard(find.byType(CustomMovementReferenceImage)), findsOne);
      expect(inCard(find.text('Teacher Cascade')), findsOne);
      expect(inCard(find.text('CUSTOM')), findsOne);
      expect(inCard(find.text('Hard')), findsOne);
      expect(inCard(find.text('Cocktail Shaker')), findsOne);
      expect(
        inCard(find.text('Toss the bottle and catch it cleanly.')),
        findsOne,
      );
      for (final action in ['test', 'edit', 'assign', 'delete']) {
        expect(
          find.byKey(ValueKey('teacher-custom-movement-$action-own')),
          findsOne,
        );
      }
      // Assign keeps the existing "requires an active class" behavior.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('teacher-custom-movement-assign-own')),
            )
            .onPressed,
        isNull,
      );
      // Foreign and archived movements never render or offer Delete.
      expect(find.text('Foreign move'), findsNothing);
      expect(find.text('Archived move'), findsNothing);
      expect(
        find.byKey(const ValueKey('teacher-custom-movement-delete-foreign')),
        findsNothing,
      );
      // Cards are sized like the trainee library, not full-width rows.
      expect(tester.getSize(card).width, lessThan(460));
    },
  );

  testWidgets('long content ellipsizes without overflow at desktop widths', (
    tester,
  ) async {
    final repository = _CustomRepository([
      _movement(
        id: 'long',
        name: List.filled(8, 'Extraordinarily long movement').join(' '),
        description: List.filled(30, 'Keep the shaker controlled.').join(' '),
      ),
      _movement(id: 'second'),
    ]);
    addTearDown(repository.dispose);

    var started = false;
    for (final size in [
      const Size(1366, 768),
      const Size(1280, 900),
      const Size(760, 780),
    ]) {
      for (final theme in [
        AppTheme.dark,
        AppTheme.light,
        AppTheme.highContrastDark,
      ]) {
        await pumpLibrary(
          tester,
          repository,
          size: size,
          theme: theme,
          startController: !started,
        );
        started = true;
        expect(
          find.byKey(const ValueKey('teacher-custom-movement-card-long')),
          findsOne,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets(
    'Delete confirms, archives once through the owner contract, and toasts',
    (tester) async {
      final repository = _CustomRepository([_movement(id: 'own')]);
      addTearDown(repository.dispose);
      await pumpLibrary(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey('teacher-custom-movement-delete-own')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete movement?'), findsOne);
      expect(
        find.text(
          '"Teacher Cascade" will be removed from your active movement '
          'library. Existing assignment and result history will be kept.',
        ),
        findsOne,
      );

      await tester.tap(
        find.byKey(const ValueKey('teacher-custom-movement-delete-cancel')),
      );
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, isEmpty);
      expect(
        find.byKey(const ValueKey('teacher-custom-movement-card-own')),
        findsOne,
      );

      await tester.tap(
        find.byKey(const ValueKey('teacher-custom-movement-delete-own')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('teacher-custom-movement-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, [
        (movementId: 'own', ownerUid: 'teacher-1'),
      ]);
      expect(find.text('Delete movement?'), findsNothing);
      expect(
        find.byKey(const ValueKey('teacher-custom-movement-card-own')),
        findsNothing,
      );
      expect(
        find.text('Teacher Cascade was deleted from your activities.'),
        findsOne,
      );
      // Let the toast dismiss so no timers outlive the test.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Delete is single-flight and failure stays actionable', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _CustomRepository([_movement(id: 'own')])
      ..deleteGate = gate;
    addTearDown(repository.dispose);
    await pumpLibrary(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey('teacher-custom-movement-delete-own')),
    );
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('teacher-custom-movement-delete-confirm'),
    );
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(confirm);
    await tester.pump();
    expect(repository.deleteCalls, hasLength(1));
    expect(find.text('Deleting…'), findsOne);

    repository.failDelete = true;
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Could not delete movement'), findsOne);
    expect(find.textContaining('delete failed'), findsNothing);
    expect(
      find.byKey(const ValueKey('teacher-custom-movement-card-own')),
      findsOne,
    );
    expect(repository.deleteCalls, hasLength(1));

    // Retry is available from the same dialog.
    repository
      ..failDelete = false
      ..deleteGate = null;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, hasLength(2));
    expect(
      find.byKey(const ValueKey('teacher-custom-movement-card-own')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
