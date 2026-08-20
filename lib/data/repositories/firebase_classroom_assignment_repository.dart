import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/models/elixr_group.dart';

import '../models/assignment_attempt.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/teacher_movement.dart';
import 'classroom_assignment_repository.dart';

class FirebaseClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  FirebaseClassroomAssignmentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection(FirestoreCollections.groupAssignments);

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection(FirestoreCollections.assignmentAttempts);

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
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );
    final ref = _assignments.doc();
    await ref.set(payload);
    final parsed = Map<String, dynamic>.from(payload)
      ..['created_at'] = DateTime.now().toUtc()
      ..['updated_at'] = DateTime.now().toUtc();
    if (dueAt != null) parsed['due_at'] = dueAt;
    return GroupAssignment.tryFromMap(parsed, id: ref.id) ??
        (throw const ClassroomException(ClassroomError.malformed));
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
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      dueAt: dueAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );
    final ref = _assignments.doc();
    await ref.set(payload);
    return GroupAssignment.tryFromMap({
          ...payload,
          'created_at': DateTime.now().toUtc(),
          'updated_at': DateTime.now().toUtc(),
          'due_at': ?dueAt,
        }, id: ref.id) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final ref = _assignments.doc(assignmentId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final current = GroupAssignment.tryFromMap(
      snap.data() ?? const {},
      id: snap.id,
    );
    if (current == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await ref.update({
      'status': GroupAssignmentStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    final snap = await _assignments.doc(assignmentId).get();
    if (!snap.exists || snap.data() == null) return null;
    return GroupAssignment.tryFromMap(snap.data()!, id: snap.id);
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _assignments
        .where('teacher_id', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => GroupAssignment.tryFromMap(doc.data(), id: doc.id))
              .whereType<GroupAssignment>()
              .toList();
          _sortAssignments(items);
          return items;
        });
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  }) async {
    final snapshot = await _assignments
        .where('group_id', isEqualTo: groupId)
        .get();
    final items = snapshot.docs
        .map((doc) => GroupAssignment.tryFromMap(doc.data(), id: doc.id))
        .whereType<GroupAssignment>()
        .toList();
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _attempts
        .where('teacher_id', isEqualTo: teacherId)
        .where('assignment_id', isEqualTo: assignmentId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id),
              )
              .whereType<AssignmentAttempt>()
              .toList();
        });
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _attempts.where('teacher_id', isEqualTo: teacherId).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id))
          .whereType<AssignmentAttempt>()
          .toList();
    });
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _attempts.where('trainee_id', isEqualTo: traineeId).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id))
          .whereType<AssignmentAttempt>()
          .toList();
    });
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    final snap = await _attempts.doc(attemptId).get();
    if (!snap.exists || snap.data() == null) return null;
    return AssignmentAttempt.tryFromMap(snap.data()!, id: snap.id);
  }

  @override
  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    final draft = teacherCreatedDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
    );
    final ref = _attempts.doc(draft.id);
    final existing = await ref.get();
    if (existing.exists) {
      return AssignmentAttempt.tryFromMap(
            existing.data() ?? const {},
            id: existing.id,
          ) ??
          draft;
    }
    await ref.set(draft.toCreateMap(createdAt: FieldValue.serverTimestamp()));
    return draft;
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
