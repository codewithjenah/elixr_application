import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';

import '../models/assignment_attempt.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/teacher_movement.dart';
import 'classroom_assignment_repository.dart';

class InMemoryClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  InMemoryClassroomAssignmentRepository({
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now,
       _generateId = generateId ?? _defaultId;

  final DateTime Function()? _now;
  final String Function() _generateId;

  final Map<String, GroupAssignment> assignments = {};
  final Map<String, AssignmentAttempt> attempts = {};

  final _teacherControllers =
      <String, StreamController<List<GroupAssignment>>>{};
  final _assignmentAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _traineeAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _teacherAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};

  static String _defaultId() => 'asg-${DateTime.now().microsecondsSinceEpoch}';

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void dispose() {
    for (final controller in _teacherControllers.values) {
      controller.close();
    }
    for (final controller in _assignmentAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _traineeAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _teacherAttemptControllers.values) {
      controller.close();
    }
  }

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final id = _generateId();
    final created = now;
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      createdAt: created,
      updatedAt: created,
    );
    final assignment =
        GroupAssignment.tryFromMap(payload, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    DateTime? dueAt,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final id = _generateId();
    final created = now;
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      dueAt: dueAt,
      createdAt: created,
      updatedAt: created,
    );
    final assignment =
        GroupAssignment.tryFromMap(payload, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    assignments[assignmentId] = GroupAssignment(
      id: existing.id,
      teacherId: existing.teacherId,
      groupId: existing.groupId,
      movementId: existing.movementId,
      revisionId: existing.revisionId,
      origin: existing.origin,
      assessmentMode: existing.assessmentMode,
      status: GroupAssignmentStatus.archived,
      displayTitle: existing.displayTitle,
      teacherDisplayName: existing.teacherDisplayName,
      groupName: existing.groupName,
      officialMovementName: existing.officialMovementName,
      displayInstructions: existing.displayInstructions,
      displaySafetyGuidance: existing.displaySafetyGuidance,
      allowedProp: existing.allowedProp,
      dueAt: existing.dueAt,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    _emitTeacher(teacherId);
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    return assignments[assignmentId];
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _watch(
      _teacherControllers,
      teacherId,
      () => _emitTeacher(teacherId),
    );
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  }) async {
    final items = assignments.values
        .where((assignment) => assignment.groupId == groupId)
        .toList();
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _watch(
      _assignmentAttemptControllers,
      '$teacherId|$assignmentId',
      () => _emitAssignmentAttempts(teacherId, assignmentId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _watch(
      _traineeAttemptControllers,
      traineeId,
      () => _emitTraineeAttempts(traineeId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _watch(
      _teacherAttemptControllers,
      teacherId,
      () => _emitTeacherAttempts(teacherId),
    );
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    return attempts[attemptId];
  }

  @override
  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    final draft = teacherCreatedDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
      createdAt: now,
    );
    final existing = attempts[draft.id];
    if (existing != null) return existing;
    attempts[draft.id] = draft;
    _emitAssignmentAttempts(assignment.teacherId, assignment.id);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(assignment.teacherId);
    return draft;
  }

  void seedAssignment(GroupAssignment assignment) {
    assignments[assignment.id] = assignment;
    _emitTeacher(assignment.teacherId);
  }

  void seedAttempt(AssignmentAttempt attempt) {
    attempts[attempt.id] = attempt;
    _emitAssignmentAttempts(attempt.teacherId, attempt.assignmentId);
    _emitTraineeAttempts(attempt.traineeId);
    _emitTeacherAttempts(attempt.teacherId);
  }

  void _emitTeacher(String teacherId) {
    final controller = _teacherControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    final items = assignments.values
        .where((assignment) => assignment.teacherId == teacherId)
        .toList();
    _sortAssignments(items);
    controller.add(items);
  }

  void _emitAssignmentAttempts(String teacherId, String assignmentId) {
    final controller =
        _assignmentAttemptControllers['$teacherId|$assignmentId'];
    if (controller == null || controller.isClosed) return;
    final items = attempts.values
        .where(
          (attempt) =>
              attempt.teacherId == teacherId &&
              attempt.assignmentId == assignmentId,
        )
        .toList();
    controller.add(items);
  }

  void _emitTraineeAttempts(String traineeId) {
    final controller = _traineeAttemptControllers[traineeId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.traineeId == traineeId)
          .toList(),
    );
  }

  void _emitTeacherAttempts(String teacherId) {
    final controller = _teacherAttemptControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.teacherId == teacherId)
          .toList(),
    );
  }

  Stream<List<T>> _watch<T>(
    Map<String, StreamController<List<T>>> controllers,
    String key,
    void Function() emit,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>.broadcast(onListen: emit);
    controllers[key] = controller;
    return controller.stream;
  }

  static void _sortAssignments(List<GroupAssignment> items) {
    items.sort((a, b) {
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue != null && bDue != null) return aDue.compareTo(bDue);
      if (aDue != null) return -1;
      if (bDue != null) return 1;
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
  }
}
