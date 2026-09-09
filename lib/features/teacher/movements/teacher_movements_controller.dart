import 'dart:async';
import 'dart:io';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../core/auth/teacher_auth_messages.dart';
import '../../../core/constants/movements.dart';
import '../../../data/models/assessment_mode.dart';
import '../../../data/models/assessment_spec.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import 'teacher_assignment_composer.dart';

enum TeacherMovementsTab { official, mine }

/// State for the reusable movement library only.
///
/// Assignments remain here only as a deletion safeguard. Classroom roster,
/// attempts, playback, grading, and review state belong to Classwork.
class TeacherMovementsController extends ChangeNotifier {
  TeacherMovementsController({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.groupRepository,
    required this.movementRepository,
    required this.assignmentRepository,
    this.ensureTeacherAuthorization,
  });

  final String teacherId;
  final String teacherDisplayName;
  final GroupRepository groupRepository;
  final TeacherMovementRepository movementRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final Future<bool> Function()? ensureTeacherAuthorization;

  late final TeacherAssignmentCreationService assignmentCreationService =
      TeacherAssignmentCreationService(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        assignmentRepository: assignmentRepository,
        groupRepository: groupRepository,
        movementRepository: movementRepository,
        ensureTeacherAuthorization: ensureTeacherAuthorization,
      );

  TeacherMovementsTab tab = TeacherMovementsTab.official;
  List<ElixrGroup> groups = const [];
  List<TeacherMovement> myMovements = const [];
  Map<String, TeacherMovementRevision> currentRevisions = const {};
  List<GroupAssignment> assignments = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;

  StreamSubscription<List<ElixrGroup>>? _groupsSubscription;
  StreamSubscription<List<TeacherMovement>>? _movementsSubscription;
  StreamSubscription<List<GroupAssignment>>? _assignmentsSubscription;
  bool _disposed = false;

  List<Movement> get officialCatalog =>
      movementCatalog.where((movement) => movement.enabled).toList();

  List<ElixrGroup> get activeGroups =>
      groups.where((group) => group.isActive).toList();

  TeacherMovementRevision? revisionFor(TeacherMovement movement) {
    final cached = currentRevisions[movement.id];
    return cached?.id == movement.currentRevisionId ? cached : null;
  }

  bool canManageMovement(TeacherMovement movement) {
    final mode = revisionFor(movement)?.assessmentMode;
    return movement.isActive &&
        (mode == AssessmentMode.teacherReviewed ||
            mode == AssessmentMode.templateScored);
  }

  bool hasAssignmentsForMovement(TeacherMovement movement) => assignments.any(
    (assignment) =>
        assignment.isTeacherCreated && assignment.movementId == movement.id,
  );

  bool canDeleteMovement(TeacherMovement movement) =>
      canManageMovement(movement) && !hasAssignmentsForMovement(movement);

  String movementModeLabel(TeacherMovement movement) {
    final revision = revisionFor(movement);
    if (revision?.isTemplateScored == true) {
      return 'Automatic ELIXR Assessment · Wrist Stall';
    }
    if (!movement.isActive) {
      return 'Archived Activity · Historical assignments stay pinned';
    }
    if (revision?.assessmentMode == AssessmentMode.teacherReviewed) {
      return 'Teacher-reviewed Activity · No automatic ELIXR score';
    }
    return 'Teacher Activity';
  }

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([
        _listenOnce(
          () => _groupsSubscription,
          (value) => _groupsSubscription = value,
          groupRepository.watchTeacherGroups(teacherId: teacherId),
          (value) => groups = value,
        ),
        _listenOnce(
          () => _movementsSubscription,
          (value) => _movementsSubscription = value,
          movementRepository.watchTeacherMovements(teacherId: teacherId),
          (value) {
            myMovements = value;
            unawaited(_syncCurrentRevisions(value));
          },
        ),
        _listenOnce(
          () => _assignmentsSubscription,
          (value) => _assignmentsSubscription = value,
          assignmentRepository.watchTeacherAssignments(teacherId: teacherId),
          (value) => assignments = value,
        ),
      ]);
      await _syncCurrentRevisions(myMovements);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TeacherMovements] start failed: $error\n$stackTrace');
      }
      errorMessage = 'Could not load Teacher Activities.';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
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
    TeacherActivityAssessmentConfig? assessment,
    AssessmentSpec? automaticAssessment,
  }) => _runWrite(
    () => movementRepository.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
      automaticAssessment: automaticAssessment,
    ),
    permissionDeniedMessage: TeacherAuthMessages.teacherActivityCreateDenied,
  );

  Future<TeacherActivityVideoMetadata> uploadActivityDemonstration({
    required File localFile,
    required Duration duration,
    required TeacherActivityDemoSource source,
  }) => movementRepository.uploadActivityDemonstration(
    teacherId: teacherId,
    localFile: localFile,
    duration: duration,
    source: source,
  );

  Future<void> editMovement({
    required TeacherMovement movement,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
    AssessmentSpec? automaticAssessment,
  }) => _runWrite(
    () => movementRepository.editMovement(
      teacherId: teacherId,
      movementId: movement.id,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
      automaticAssessment: automaticAssessment,
    ),
  );

  Future<void> archiveMovement(TeacherMovement movement) => _runWrite(
    () => movementRepository.archiveMovement(
      teacherId: teacherId,
      movementId: movement.id,
    ),
  );

  Future<void> deleteMovement(TeacherMovement movement) => _runWrite(() async {
    if (!canManageMovement(movement)) {
      throw const ClassroomException(
        ClassroomError.invalidState,
        'Only unused Teacher Activities can be deleted.',
      );
    }
    if (hasAssignmentsForMovement(movement)) {
      throw const ClassroomException(
        ClassroomError.invalidState,
        'This Teacher Activity cannot be deleted because it is used by an assignment.',
      );
    }
    await movementRepository.deleteMovement(
      teacherId: teacherId,
      movementId: movement.id,
    );
  });

  Future<void> assignOfficial({
    required Movement movement,
    required ElixrGroup group,
    DateTime? dueAt,
  }) => _runWrite(
    () => assignmentCreationService.create(
      group: group,
      officialMovement: movement,
      dueAt: dueAt,
    ),
  );

  Future<void> assignTeacherCreated({
    required TeacherMovement movement,
    required ElixrGroup group,
    int maxScore = 100,
    DateTime? dueAt,
  }) => _runWrite(
    () => assignmentCreationService.create(
      group: group,
      teacherCreatedMovement: movement,
      maxScore: maxScore,
      dueAt: dueAt,
    ),
  );

  Future<void> _syncCurrentRevisions(List<TeacherMovement> items) async {
    final next = <String, TeacherMovementRevision>{};
    for (final movement in items) {
      final cached = revisionFor(movement);
      final revision =
          cached ??
          await movementRepository.getRevision(
            movementId: movement.id,
            revisionId: movement.currentRevisionId,
          );
      if (revision != null) next[movement.id] = revision;
    }
    if (_disposed) return;
    currentRevisions = next;
    notifyListeners();
  }

  Future<void> _runWrite(
    Future<void> Function() action, {
    String permissionDeniedMessage = 'That action could not be completed.',
  }) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final ensure = ensureTeacherAuthorization;
      if (ensure != null && !await ensure()) {
        errorMessage = TeacherAuthMessages.teacherAuthorizationRefreshRequired;
        return;
      }
      await action();
    } on ClassroomException catch (error) {
      errorMessage = error.message ?? 'That action could not be completed.';
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TeacherMovements] write failed: $error\n$stackTrace');
      }
      errorMessage = _isPermissionDenied(error)
          ? permissionDeniedMessage
          : 'That action could not be completed.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool _isPermissionDenied(Object error) {
    final text = error.toString();
    return text.contains('permission-denied') ||
        text.contains('PERMISSION_DENIED');
  }

  Future<void> _listenOnce<T>(
    StreamSubscription<T>? Function() read,
    void Function(StreamSubscription<T>) write,
    Stream<T> stream,
    void Function(T) onData,
  ) async {
    await read()?.cancel();
    final first = Completer<void>();
    write(
      stream.listen(
        (value) {
          if (_disposed) return;
          onData(value);
          if (!first.isCompleted) first.complete();
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!first.isCompleted) first.completeError(error, stackTrace);
        },
      ),
    );
    await first.future;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_groupsSubscription?.cancel());
    unawaited(_movementsSubscription?.cancel());
    unawaited(_assignmentsSubscription?.cancel());
    super.dispose();
  }
}
