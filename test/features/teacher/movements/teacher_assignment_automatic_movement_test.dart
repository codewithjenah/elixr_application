import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/data/repositories/supabase_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_assignment_composer.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

const _group = ElixrGroup(
  id: 'group-1',
  teacherId: 'teacher-1',
  name: 'BSIT-4A',
  status: ElixrGroupStatus.active,
);

/// Stored schema-v3 static template: `rotation_trace` is a present JSON null.
Map<String, dynamic> _staticTemplateMap() => {
  'schema_version': 3,
  'capture_version': 1,
  'duration_ms': 2000,
  'reference_count': 1,
  'required_modalities': ['hands', 'prop_translation'],
  'normalization_metadata': <String, dynamic>{},
  'feature_capabilities': {
    'pose': false,
    'hands': true,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': false,
  },
  'canonical_sequence': [
    for (var index = 0; index < 32; index++)
      {'timestamp_ms': index * 25, 'pose': <String, dynamic>{}},
  ],
  'variability_metadata': <String, dynamic>{},
  'prop_events': <Map<String, dynamic>>[],
  'rotation_trace': null,
  'movement_behavior': 'static',
};

CustomMovement _movement({
  String activeRevisionId = 'rev-1',
  CustomMovementStatus status = CustomMovementStatus.active,
}) => CustomMovement(
  id: 'auto-1',
  ownerUid: 'teacher-1',
  ownerRole: CustomMovementOwnerRole.teacher,
  name: 'Spin Hold',
  description: 'Hold the bottle still at shoulder height.',
  difficulty: 'Easy',
  propType: TrainingProp.bottle,
  status: status,
  activeRevisionId: activeRevisionId,
);

CustomMovementRevision _revision(String id) => CustomMovementRevision(
  id: id,
  movementId: 'auto-1',
  ownerUid: 'teacher-1',
  ownerRole: CustomMovementOwnerRole.teacher,
  template: MovementTemplate.tryFrom(_staticTemplateMap())!,
);

class _LoopbackHttp extends HttpOverrides {}

class _AutomaticMovements extends Fake implements CustomMovementRepository {
  _AutomaticMovements(this.current);

  /// Authoritative server state; the stream may lag behind it.
  CustomMovement current;
  final _controller = StreamController<List<CustomMovement>>.broadcast();

  void emit(List<CustomMovement> movements) => _controller.add(movements);

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({
    required String ownerUid,
  }) async* {
    yield [current];
    yield* _controller.stream;
  }

  @override
  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async =>
      movementId == current.id && ownerUid == current.ownerUid ? current : null;

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async => movementId == current.id ? _revision(revisionId) : null;

  Future<void> dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late InMemoryTeacherMovementRepository teacherMovements;
  late _AutomaticMovements automatic;

  setUp(() {
    groups = InMemoryGroupRepository()..seedGroup(_group);
    assignments = InMemoryClassroomAssignmentRepository(
      groupRepository: groups,
    );
    teacherMovements = InMemoryTeacherMovementRepository(
      generateId: () => 'movement-1',
    );
    automatic = _AutomaticMovements(_movement());
  });

  tearDown(() async {
    groups.dispose();
    assignments.dispose();
    teacherMovements.dispose();
    await automatic.dispose();
  });

  TeacherAssignmentCreationService service() =>
      TeacherAssignmentCreationService(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        assignmentRepository: assignments,
        groupRepository: groups,
        movementRepository: teacherMovements,
        customMovementRepository: automatic,
      );

  group('createAutomatic', () {
    test('re-reads the active revision before writing', () async {
      final stale = _movement();
      automatic.current = _movement(activeRevisionId: 'rev-2');

      final created = await service().createAutomatic(
        group: _group,
        movement: stale,
      );

      expect(created.revisionId, 'rev-2');
      expect(created.assessmentMode, AssessmentMode.referenceMatched);
      expect(created.maxScore, 12);
      expect(assignments.assignments, hasLength(1));
    });

    test('rejects a movement archived after it was listed', () async {
      automatic.current = _movement(status: CustomMovementStatus.archived);

      await expectLater(
        service().createAutomatic(group: _group, movement: _movement()),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.archived,
          ),
        ),
      );
      expect(assignments.assignments, isEmpty);
    });
  });

  testWidgets(
    'Assignment Studio lists Teacher-reviewed and automatic Teacher Activities',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await teacherMovements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'Balance the tin upright.',
        requiredProp: TrainingProp.bottle,
      );
      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: ElixShadThemeBridge(
            child: TeacherAssignmentComposer(
              teacherId: 'teacher-1',
              teacherDisplayName: 'Grace Hopper',
              groups: const [_group],
              lockedGroup: _group,
              movementRepository: teacherMovements,
              groupRepository: groups,
              creationService: service(),
              customMovementRepository: automatic,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Official ELIXR remains the default source.
      expect(
        find.text('Official ELIXR guided assessment · Bottle'),
        findsWidgets,
      );

      final mine = find.byKey(const Key('teacher_assignment_source_mine'));
      await tester.ensureVisible(mine);
      await tester.pumpAndSettle();
      await tester.tap(mine);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('teacher_assignment_custom_movement-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_automatic_auto-1')),
        findsOneWidget,
      );
      expect(find.text('Teacher reviewed · Bottle'), findsOneWidget);

      final select = find.byKey(
        const Key('teacher_assignment_select_automatic_auto-1'),
      );
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();

      final summary = find.byKey(const Key('teacher_assignment_summary'));
      expect(
        find.descendant(of: summary, matching: find.text('Spin Hold')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Automatic · Reference matched · Bottle'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Up to 12 points')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_automatic_audience_note')),
        findsOneWidget,
      );
      // Teacher-reviewed rubric/max-score and unsupported fields are hidden.
      expect(
        find.byKey(const Key('teacher_assignment_customize_activity')),
        findsNothing,
      );
      expect(find.byKey(const Key('teacher_assignment_topic')), findsNothing);
      expect(
        tester
            .widget<shad.ShadButton>(
              find.descendant(
                of: find.byKey(const Key('teacher_assignment_save_draft')),
                matching: find.byType(shad.ShadButton),
              ),
            )
            .onPressed,
        isNull,
      );

      // The picker snapshot is now stale; the write must pin the live revision.
      automatic.current = _movement(activeRevisionId: 'rev-2');
      final publish = find.byKey(const Key('teacher_assignment_publish_now'));
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();

      final created = assignments.assignments.values.single;
      expect(created.movementId, 'auto-1');
      expect(created.revisionId, 'rev-2');
      expect(created.assessmentMode, AssessmentMode.referenceMatched);
      expect(created.maxScore, 12);
      expect(created.audience.isEntireClass, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  group('SupabaseClassroomAssignmentRepository custom assignment', () {
    late HttpServer server;
    late Map<String, dynamic> responseBody;
    var rpcCalls = 0;

    setUp(() async {
      rpcCalls = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (request.uri.path.endsWith(
          '/rpc/create_custom_movement_assignment',
        )) {
          rpcCalls++;
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(responseBody));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Map<String, dynamic> serverAssignment(Map<String, dynamic> template) => {
      'id': 'assignment-1',
      'teacher_id': 'teacher-1',
      'group_id': _group.id,
      'movement_id': 'auto-1',
      'revision_id': 'rev-1',
      'origin': 'teacher_created',
      'assessment_mode': 'reference_matched',
      'status': 'active',
      'display_title': 'Spin Hold',
      'teacher_display_name': 'Grace Hopper',
      'group_name': _group.name,
      'display_instructions': 'Hold the bottle still at shoulder height.',
      'allowed_prop': 'bottle',
      'audience_type': 'entire_class',
      'attempt_policy': {'type': 'unlimited'},
      'max_score': 12,
      'movement_template': template,
      'created_at': '2026-09-27T09:12:00Z',
      'updated_at': '2026-09-27T09:12:00Z',
    };

    // The Flutter test binding replaces HttpClient with a 400 stub; this
    // repository must reach the local server over real loopback HTTP.
    Future<GroupAssignment> create() => HttpOverrides.runWithHttpOverrides(
      () =>
          SupabaseClassroomAssignmentRepository(
            client: SupabaseClient(
              'http://${server.address.address}:${server.port}',
              'test-key',
            ),
          ).createCustomMovementAssignment(
            teacherId: 'teacher-1',
            teacherDisplayName: 'Grace Hopper',
            group: _group,
            movement: _movement(),
            revision: _revision('rev-1'),
          ),
      _LoopbackHttp(),
    );

    test('a committed write with rotation_trace null parses', () async {
      responseBody = serverAssignment(_staticTemplateMap());
      final created = await create();

      expect(rpcCalls, 1);
      expect(created.id, 'assignment-1');
      expect(created.isReferenceMatched, isTrue);
      expect(created.maxScore, 12);
      expect(created.movementTemplate?.movementBehavior, 'static');
    });

    test('the old recursively stripped response is still rejected', () async {
      // Documents why the server must keep the nested key: schema-v3
      // validation is intentionally not weakened on the client.
      responseBody = serverAssignment(
        _staticTemplateMap()..remove('rotation_trace'),
      );
      await expectLater(
        create(),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.malformed,
          ),
        ),
      );
    });
  });
}
