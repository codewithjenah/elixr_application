import 'dart:async';

import '../models/assessment_mode.dart';
import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/training_prop.dart';
import 'teacher_movement_repository.dart';

class InMemoryTeacherMovementRepository implements TeacherMovementRepository {
  InMemoryTeacherMovementRepository({
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now,
       _generateId = generateId ?? _defaultId;

  final DateTime Function()? _now;
  final String Function() _generateId;

  final Map<String, TeacherMovement> movements = {};
  final Map<String, TeacherMovementRevision> revisions = {};
  int _counter = 0;

  final _teacherControllers =
      <String, StreamController<List<TeacherMovement>>>{};

  static String _defaultId() => 'tm-${DateTime.now().microsecondsSinceEpoch}';

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void dispose() {
    for (final controller in _teacherControllers.values) {
      controller.close();
    }
    _teacherControllers.clear();
  }

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
    final movementId = _generateId();
    final revisionId = '${movementId}_v${++_counter}';
    final created = now;
    final revision = TeacherMovementRevision(
      id: revisionId,
      movementId: movementId,
      teacherId: teacherId,
      assessmentMode: AssessmentMode.teacherReviewed,
      spec: spec,
      createdAt: created,
    );
    final movement = TeacherMovement(
      id: movementId,
      teacherId: teacherId,
      title: title.trim(),
      status: TeacherMovementStatus.active,
      currentRevisionId: revisionId,
      createdAt: created,
      updatedAt: created,
    );
    revisions['$movementId/$revisionId'] = revision;
    movements[movementId] = movement;
    _emit(teacherId);
    return movement;
  }

  @override
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final existing = movements[movementId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    ensureRevisionAssessmentMode(
      revision: revisions['$movementId/${existing.currentRevisionId}'],
      expected: AssessmentMode.teacherReviewed,
    );
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
    final previousRevisionId = existing.currentRevisionId;
    final revisionId = '${movementId}_v${++_counter}';
    final created = now;
    revisions['$movementId/$revisionId'] = TeacherMovementRevision(
      id: revisionId,
      movementId: movementId,
      teacherId: teacherId,
      assessmentMode: AssessmentMode.teacherReviewed,
      spec: spec,
      createdAt: created,
    );
    final updated = TeacherMovement(
      id: existing.id,
      teacherId: existing.teacherId,
      title: title.trim(),
      status: existing.status,
      currentRevisionId: revisionId,
      createdAt: existing.createdAt,
      updatedAt: created,
    );
    movements[movementId] = updated;
    assert(revisions['$movementId/$previousRevisionId'] != null);
    _emit(teacherId);
    return updated;
  }

  @override
  Future<void> archiveMovement({
    required String teacherId,
    required String movementId,
  }) async {
    final existing = movements[movementId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    ensureRevisionAssessmentMode(
      revision: revisions['$movementId/${existing.currentRevisionId}'],
      expected: AssessmentMode.teacherReviewed,
    );
    movements[movementId] = TeacherMovement(
      id: existing.id,
      teacherId: existing.teacherId,
      title: existing.title,
      status: TeacherMovementStatus.archived,
      currentRevisionId: existing.currentRevisionId,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    _emit(teacherId);
  }

  @override
  Stream<List<TeacherMovement>> watchTeacherMovements({
    required String teacherId,
  }) {
    final existing = _teacherControllers[teacherId];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<TeacherMovement>> controller;
    controller = StreamController<List<TeacherMovement>>.broadcast(
      onListen: () => _emit(teacherId),
    );
    _teacherControllers[teacherId] = controller;
    return controller.stream;
  }

  @override
  Future<TeacherMovement?> getMovement({required String movementId}) async {
    return movements[movementId];
  }

  @override
  Future<TeacherMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    return revisions['$movementId/$revisionId'];
  }

  void _emit(String teacherId) {
    final controller = _teacherControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    final items =
        movements.values.where((m) => m.teacherId == teacherId).toList()
          ..sort((a, b) {
            final aAt =
                a.updatedAt ??
                a.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bAt =
                b.updatedAt ??
                b.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bAt.compareTo(aAt);
          });
    controller.add(items);
  }
}
