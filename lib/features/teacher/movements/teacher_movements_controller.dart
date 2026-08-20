import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/movements.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';

enum TeacherMovementsTab { official, mine, assignments }

class TeacherMovementsController extends ChangeNotifier {
  TeacherMovementsController({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.groupRepository,
    required this.movementRepository,
    required this.assignmentRepository,
  });

  final String teacherId;
  final String teacherDisplayName;
  final GroupRepository groupRepository;
  final TeacherMovementRepository movementRepository;
  final ClassroomAssignmentRepository assignmentRepository;

  TeacherMovementsTab tab = TeacherMovementsTab.official;
  List<ElixrGroup> groups = const [];
  List<TeacherMovement> myMovements = const [];
  List<GroupAssignment> assignments = const [];
  List<AssignmentAttempt> attempts = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<TeacherMovement>>? _movementsSub;
  StreamSubscription<List<GroupAssignment>>? _assignmentsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;

  List<Movement> get officialCatalog =>
      movementCatalog.where((movement) => movement.enabled).toList();

  List<ElixrGroup> get activeGroups =>
      groups.where((group) => group.isActive).toList();

  List<TeacherMovement> get activeMyMovements =>
      myMovements.where((movement) => movement.isActive).toList();

  List<AssignmentAttempt> attemptsFor(String assignmentId) {
    return attempts
        .where((attempt) => attempt.assignmentId == assignmentId)
        .toList();
  }

  String groupName(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    for (final assignment in assignments) {
      if (assignment.groupId == groupId) return assignment.groupName;
    }
    return 'Classroom';
  }

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([
        _listenOnce(
          () => _groupsSub,
          (sub) => _groupsSub = sub,
          groupRepository.watchTeacherGroups(teacherId: teacherId),
          (value) => groups = value,
        ),
        _listenOnce(
          () => _movementsSub,
          (sub) => _movementsSub = sub,
          movementRepository.watchTeacherMovements(teacherId: teacherId),
          (value) => myMovements = value,
        ),
        _listenOnce(
          () => _assignmentsSub,
          (sub) => _assignmentsSub = sub,
          assignmentRepository.watchTeacherAssignments(teacherId: teacherId),
          (value) => assignments = value,
        ),
        _listenOnce(
          () => _attemptsSub,
          (sub) => _attemptsSub = sub,
          assignmentRepository.watchAttemptsForTeacher(teacherId: teacherId),
          (value) => attempts = value,
        ),
      ]);
    } catch (_) {
      errorMessage = 'Could not load movements and assignments.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  void setTab(TeacherMovementsTab value) {
    if (tab == value) return;
    tab = value;
    notifyListeners();
  }

  Future<void> createMovement({
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    return _runWrite(
      () => movementRepository.createMovement(
        teacherId: teacherId,
        title: title,
        instructions: instructions,
        requiredProp: requiredProp,
        safetyGuidance: safetyGuidance,
      ),
    );
  }

  Future<void> editMovement({
    required TeacherMovement movement,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    return _runWrite(
      () => movementRepository.editMovement(
        teacherId: teacherId,
        movementId: movement.id,
        title: title,
        instructions: instructions,
        requiredProp: requiredProp,
        safetyGuidance: safetyGuidance,
      ),
    );
  }

  Future<void> archiveMovement(TeacherMovement movement) {
    return _runWrite(
      () => movementRepository.archiveMovement(
        teacherId: teacherId,
        movementId: movement.id,
      ),
    );
  }

  Future<void> assignOfficial({
    required Movement movement,
    required ElixrGroup group,
    DateTime? dueAt,
  }) {
    return _runWrite(
      () => assignmentRepository.createOfficialAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        officialMovementName: movement.name,
        dueAt: dueAt,
        displayInstructions: movement.description,
      ),
    );
  }

  Future<void> assignTeacherCreated({
    required TeacherMovement movement,
    required ElixrGroup group,
    DateTime? dueAt,
  }) {
    return _runWrite(() async {
      final revision = await movementRepository.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      );
      if (revision == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      await assignmentRepository.createTeacherCreatedAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        movement: movement,
        revision: revision,
        dueAt: dueAt,
      );
    });
  }

  Future<void> archiveAssignment(GroupAssignment assignment) {
    return _runWrite(
      () => assignmentRepository.archiveAssignment(
        teacherId: teacherId,
        assignmentId: assignment.id,
      ),
    );
  }

  Future<void> _runWrite(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on ClassroomException catch (error) {
      errorMessage =
          error.message ?? 'That classroom action could not be completed.';
    } catch (_) {
      errorMessage = 'That classroom action could not be completed.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _listenOnce<T>(
    StreamSubscription<T>? Function() read,
    void Function(StreamSubscription<T>) write,
    Stream<T> stream,
    void Function(T value) onData,
  ) async {
    await read()?.cancel();
    final first = Completer<void>();
    write(
      stream.listen(
        (value) {
          onData(value);
          if (!first.isCompleted) first.complete();
          notifyListeners();
        },
        onError: (Object error) {
          if (!first.isCompleted) first.completeError(error);
        },
      ),
    );
    await first.future;
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _movementsSub?.cancel();
    _assignmentsSub?.cancel();
    _attemptsSub?.cancel();
    super.dispose();
  }
}
