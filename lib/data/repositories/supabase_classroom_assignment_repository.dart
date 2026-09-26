import 'dart:async';
import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, PostgrestException, SupabaseClient;

import '../models/assignment_attempt_policy.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/phase6_submission_diagnostics.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import '../models/training_prop.dart';
import '../models/custom_movement.dart';
import 'classroom_assignment_repository.dart';

/// Classroom assignments and attempts. Every state transition is a single
/// server transaction (RPC); reads and live lists are RLS-scoped.
class SupabaseClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  SupabaseClassroomAssignmentRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  final Duration requestTimeout;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  String? get _currentUid => _client.auth.currentUser?.id;

  Future<dynamic> _rpc(
    String name,
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    try {
      return await _client
          .rpc<dynamic>(name, params: params)
          .timeout(timeout ?? requestTimeout);
    } on PostgrestException catch (error) {
      throw classroomRpcFailure(error);
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    }
  }

  static GroupAssignment _assignment(Object? raw) {
    final map = asRowMap(raw);
    final id = map.remove('id');
    if (id is! String) throw const ClassroomException(ClassroomError.malformed);
    return GroupAssignment.tryFromMap(map, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  static AssignmentAttempt _attempt(Object? raw) {
    final map = asRowMap(raw);
    final id = map.remove('id');
    if (id is! String) throw const ClassroomException(ClassroomError.malformed);
    return AssignmentAttempt.tryFromMap(map, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  static List<AssignmentAttempt> _attempts(List<Map<String, dynamic>> rows) => [
    for (final row in rows)
      ?AssignmentAttempt.tryFromMap(compactRow(row), id: row['id'] as String),
  ];

  @override
  Future<GroupAssignment> createCustomMovementAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required CustomMovement movement,
    required CustomMovementRevision revision,
    DateTime? dueAt,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
  }) async {
    // Local validation keeps the established error semantics; the server
    // re-validates ownership, active revision and template.
    customMovementAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      attemptPolicy: attemptPolicy,
      dueAt: dueAt,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _assignment(
      await _rpc('create_custom_movement_assignment', {
        'p_group_id': group.id,
        'p_movement_id': movement.id,
        'p_revision_id': revision.id,
        'p_attempt_policy': attemptPolicy.toMap(),
        'p_due_at': dueAt?.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<void> saveCustomMovementAssignmentAttempt({
    required GroupAssignment assignment,
    required String traineeId,
    required int total,
    required String performanceLevel,
    required Map<String, int> componentScores,
  }) async {
    if (!assignment.isReferenceMatched ||
        assignment.movementTemplate == null ||
        total < 0 ||
        total > 12 ||
        componentScores.keys.toSet().length !=
            referenceMatchedComponentNames.length ||
        !componentScores.keys.toSet().containsAll(
          referenceMatchedComponentNames,
        ) ||
        componentScores.values.any((value) => value < 0 || value > 3) ||
        referenceMatchedTotal(componentScores.values) != total ||
        referenceMatchedPerformanceLevel(total) != performanceLevel) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    await _rpc('save_reference_match_attempt', {
      'p_assignment_id': assignment.id,
      'p_total': total,
      'p_performance_level': performanceLevel,
      'p_component_scores': componentScores,
    });
  }

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    required TrainingProp allowedProp,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? displayInstructions,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createOfficialAssignmentWithTopic(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    officialMovementName: officialMovementName,
    allowedProp: allowedProp,
    dueAt: dueAt,
    status: status,
    publishAt: publishAt,
    displayInstructions: displayInstructions,
    attemptPolicy: attemptPolicy,
    audience: audience,
  );

  @override
  Future<GroupAssignment> createOfficialAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    required TrainingProp allowedProp,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? displayInstructions,
    String? topic,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    await _ensureAudienceTargetsAreApprovedMembers(
      teacherId: teacherId,
      group: group,
      audience: audience,
    );
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      allowedProp: allowedProp,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      status: status,
      publishAt: publishAt,
      topic: topic,
      audience: audience,
      attemptPolicy: attemptPolicy,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _createAssignment(payload: payload, audience: audience);
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createTeacherCreatedAssignmentWithTopic(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    movement: movement,
    revision: revision,
    maxScore: maxScore,
    activityAssessment: activityAssessment,
    attemptPolicy: attemptPolicy,
    displayTitle: displayTitle,
    displayInstructions: displayInstructions,
    displaySafetyGuidance: displaySafetyGuidance,
    dueAt: dueAt,
    status: status,
    publishAt: publishAt,
    audience: audience,
  );

  @override
  Future<GroupAssignment> createTeacherCreatedAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? topic,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    await _ensureAudienceTargetsAreApprovedMembers(
      teacherId: teacherId,
      group: group,
      audience: audience,
    );
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      activityAssessment: activityAssessment,
      attemptPolicy: attemptPolicy,
      displayTitle: displayTitle,
      displayInstructions: displayInstructions,
      displaySafetyGuidance: displaySafetyGuidance,
      dueAt: dueAt,
      status: status,
      publishAt: publishAt,
      topic: topic,
      audience: audience,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _createAssignment(payload: payload, audience: audience);
  }

  Future<GroupAssignment> _loadAssignment(String assignmentId) async {
    final current = await getAssignment(assignmentId: assignmentId);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    return current;
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final current = await _loadAssignment(assignmentId);
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (current.isRetiredTemplate) {
      throw const ClassroomException(
        ClassroomError.identityMismatch,
        'Retired template-scored assignments are read-only.',
      );
    }
    if (current.status != GroupAssignmentStatus.active) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _rpc('set_assignment_status', {
      'p_assignment_id': assignmentId,
      'p_action': 'archive',
    });
  }

  @override
  Future<void> restoreAssignment({
    required String teacherId,
    required String assignmentId,
  }) => _transitionPublication(
    teacherId: teacherId,
    assignmentId: assignmentId,
    allowed: {GroupAssignmentStatus.archived},
    action: 'restore',
  );

  @override
  Future<void> publishAssignmentNow({
    required String teacherId,
    required String assignmentId,
  }) => _transitionPublication(
    teacherId: teacherId,
    assignmentId: assignmentId,
    allowed: {GroupAssignmentStatus.draft, GroupAssignmentStatus.scheduled},
    action: 'publish_now',
  );

  @override
  Future<void> scheduleAssignmentPublication({
    required String teacherId,
    required String assignmentId,
    required DateTime publishAt,
  }) async {
    final at = publishAt.toUtc();
    if (!at.isAfter(DateTime.now().toUtc())) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final current = await _loadAssignment(assignmentId);
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if ((!current.isDraft && !current.isScheduled) ||
        (current.dueAt != null && !current.dueAt!.toUtc().isAfter(at))) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _rpc('schedule_assignment_publication', {
      'p_assignment_id': assignmentId,
      'p_publish_at': at.toIso8601String(),
    });
  }

  Future<void> _transitionPublication({
    required String teacherId,
    required String assignmentId,
    required Set<GroupAssignmentStatus> allowed,
    required String action,
  }) async {
    final current = await _loadAssignment(assignmentId);
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!allowed.contains(current.status)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _rpc('set_assignment_status', {
      'p_assignment_id': assignmentId,
      'p_action': action,
    });
  }

  @override
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
    String? topic,
  }) async {
    if (maxScore != null) ensureTeacherAssignmentMaxScore(maxScore);
    final current = await _loadAssignment(assignmentId);
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if ((!current.isActive && !current.isDraft && !current.isScheduled) ||
        current.isRetiredTemplate) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (maxScore != null &&
        (!current.isTeacherCreated || current.gradingLocked)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _rpc('update_assignment_settings', {
      'p_assignment_id': assignmentId,
      'p_due_at': dueAt?.toUtc().toIso8601String(),
      'p_max_score': maxScore,
      'p_topic': topic?.trim(),
    });
    return current.copyWith(
      dueAt: dueAt,
      clearDueAt: dueAt == null,
      maxScore: maxScore,
      topic: topic,
      clearTopic: topic == null || topic.trim().isEmpty,
      gradingLocked: maxScore == null ? null : false,
      clearGradingLockedAt: maxScore != null,
    );
  }

  @override
  Future<bool> hasTraineeWork({required String assignmentId}) async {
    final rows = await _client
        .from('assignment_attempts')
        .select('id')
        .eq('assignment_id', assignmentId)
        .limit(1);
    return rows.isNotEmpty;
  }

  GroupAssignment _assignmentWithRecipients(Map<String, dynamic> decoded) {
    final parsed = _assignment(decoded['assignment']);
    final recipients = decoded['recipient_ids'];
    if (recipients is List && !parsed.audience.isEntireClass) {
      return parsed.copyWith(
        audience: parsed.audience.withRecipientIds(
          recipients.whereType<String>(),
        ),
      );
    }
    return parsed;
  }

  @override
  Future<GroupAssignment> updateAssignmentConfiguration({
    required String teacherId,
    required String assignmentId,
    required int expectedConfigurationRevision,
    required ElixrGroup group,
    String? officialMovementName,
    TrainingProp? officialAllowedProp,
    TeacherMovement? teacherMovement,
    TeacherMovementRevision? teacherMovementRevision,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    String? topic,
    DateTime? dueAt,
    required AssignmentAudience audience,
    required AssignmentAttemptPolicy attemptPolicy,
    TeacherActivityAssessmentConfig? activityAssessment,
  }) async {
    if (_currentUid != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final decoded = asRowMap(
      await _rpc('update_assignment_configuration', {
        'p': {
          'assignment_id': assignmentId,
          'expected_configuration_revision': expectedConfigurationRevision,
          'group_id': group.id,
          'official_movement_name': officialMovementName?.trim(),
          'allowed_prop': officialAllowedProp?.protocolValue,
          'teacher_movement_id': teacherMovement?.id,
          'teacher_revision_id': teacherMovementRevision?.id,
          'display_title': displayTitle?.trim(),
          'display_instructions': displayInstructions?.trim(),
          'display_safety_guidance': displaySafetyGuidance?.trim(),
          'topic': topic?.trim(),
          'due_at': dueAt?.toUtc().toIso8601String(),
          'audience_type': audience.type.wireValue,
          'recipient_ids': audience.isEntireClass
              ? const <String>[]
              : audience.targetTraineeIds,
          'attempt_policy': attemptPolicy.toMap(),
          'activity_assessment': activityAssessment?.toMap(),
        },
      }),
    );
    return _assignmentWithRecipients(decoded);
  }

  @override
  Future<GroupAssignment> updateTeacherActivityAssignment({
    required String teacherId,
    required String assignmentId,
    required int expectedConfigurationRevision,
    required String displayTitle,
    required String instructions,
    String? safetyGuidance,
    String? topic,
    DateTime? dueAt,
    required AssignmentAudience audience,
    required TeacherActivityAssessmentConfig activityAssessment,
    required AssignmentAttemptPolicy attemptPolicy,
    required TrainingProp requiredProp,
  }) async {
    if (_currentUid != teacherId || !activityAssessment.isValid) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final decoded = asRowMap(
      await _rpc('update_teacher_activity_assignment', {
        'p': {
          'assignment_id': assignmentId,
          'expected_configuration_revision': expectedConfigurationRevision,
          'display_title': displayTitle.trim(),
          'display_instructions': instructions.trim(),
          'display_safety_guidance': safetyGuidance?.trim(),
          'topic': topic?.trim(),
          'due_at': dueAt?.toUtc().toIso8601String(),
          'audience_type': audience.type.wireValue,
          'recipient_ids': audience.isEntireClass
              ? const <String>[]
              : audience.targetTraineeIds,
          'activity_assessment': activityAssessment.toMap(),
          'attempt_policy': attemptPolicy.toMap(),
          'allowed_prop': requiredProp.protocolValue,
        },
      }),
    );
    return _assignment(decoded['assignment']).copyWith(audience: audience);
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    final row = await _client
        .from('group_assignments')
        .select()
        .eq('id', assignmentId)
        .maybeSingle();
    if (row == null) return null;
    final assignment = GroupAssignment.tryFromMap(
      compactRow(row),
      id: assignmentId,
    );
    if (assignment == null || assignment.audience.isEntireClass) {
      return assignment;
    }
    final uid = _currentUid;
    if (uid == null) return null;
    if (uid == assignment.teacherId) {
      final items = await _hydrateTeacherAssignments([assignment], uid);
      return items.isEmpty ? null : items.single;
    }
    final recipient = await _client
        .from('assignment_recipients')
        .select()
        .eq('assignment_id', assignmentId)
        .eq('trainee_id', uid)
        .maybeSingle();
    return _validRecipient(recipient, assignment, uid)
        ? assignment.copyWith(
            audience: assignment.audience.withRecipientIds([uid]),
          )
        : null;
  }

  @override
  Future<AssignmentDeadlineOverride?> getDeadlineOverride({
    required String assignmentId,
    required String traineeId,
  }) async {
    final data = await _client
        .from('assignment_deadline_overrides')
        .select()
        .eq('assignment_id', assignmentId)
        .eq('trainee_id', traineeId)
        .maybeSingle();
    if (data == null) return null;
    final dueAt = TeacherRosterInvite.readDateTime(data['due_at']);
    if (dueAt == null ||
        data['group_id'] is! String ||
        data['teacher_id'] is! String) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    return AssignmentDeadlineOverride(
      assignmentId: assignmentId,
      groupId: data['group_id'] as String,
      teacherId: data['teacher_id'] as String,
      traineeId: traineeId,
      dueAt: dueAt,
    );
  }

  @override
  Future<void> setDeadlineOverride({
    required String teacherId,
    required GroupAssignment assignment,
    required String traineeId,
    required DateTime dueAt,
  }) async {
    final base = assignment.dueAt;
    if (assignment.teacherId != teacherId ||
        base == null ||
        !assignment.isAvailableToTrainee(traineeId) ||
        !dueAt.isAfter(base)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('set_deadline_override', {
      'p_assignment_id': assignment.id,
      'p_trainee_id': traineeId,
      'p_due_at': dueAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> clearDeadlineOverride({
    required String teacherId,
    required GroupAssignment assignment,
    required String traineeId,
  }) async {
    if (assignment.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('clear_deadline_override', {
      'p_assignment_id': assignment.id,
      'p_trainee_id': traineeId,
    });
  }

  @override
  Future<bool> hasTeacherAssignmentForMovement({
    required String teacherId,
    required String movementId,
  }) async {
    final rows = await _client
        .from('group_assignments')
        .select('id')
        .eq('teacher_id', teacherId)
        .eq('movement_id', movementId)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _client
        .from('group_assignments')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .asyncMap((rows) async {
          final items = [
            for (final row in rows)
              ?GroupAssignment.tryFromMap(
                compactRow(row),
                id: row['id'] as String,
              ),
          ];
          final hydrated = await _hydrateTeacherAssignments(items, teacherId);
          _sortAssignments(hydrated);
          return hydrated;
        });
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
    required String teacherId,
  }) async {
    final rows = await _client
        .from('group_assignments')
        .select()
        .eq('group_id', groupId)
        .eq('teacher_id', teacherId);
    final items = [
      for (final row in rows)
        ?GroupAssignment.tryFromMap(compactRow(row), id: row['id'] as String),
    ];
    _sortAssignments(items);
    return items;
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForTrainee({
    required String traineeId,
    String? groupId,
  }) async {
    if (_currentUid != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final values = await _rpc('list_trainee_assignments', {
      'p_group_id': groupId,
    });
    if (values is! List) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final items = <GroupAssignment>[];
    for (final map in rowsFrom(values)) {
      final id = map['id'];
      if (id is! String || id.trim().isEmpty || id.trim().length > 128) {
        continue;
      }
      final assignment = GroupAssignment.tryFromMap(map, id: id.trim());
      if (assignment != null &&
          (groupId == null || assignment.groupId == groupId)) {
        // The server already authorized this recipient and never returns
        // other trainees' identities.
        items.add(
          assignment.copyWith(
            audience: assignment.audience.withRecipientIds([traineeId]),
          ),
        );
      }
    }
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _client
        .from('assignment_attempts')
        .stream(primaryKey: ['id'])
        .eq('assignment_id', assignmentId)
        .map(
          (rows) => _attempts(
            rows.where((row) => row['teacher_id'] == teacherId).toList(),
          ),
        );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _client
        .from('assignment_attempts')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .map(_attempts);
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _client
        .from('assignment_attempts')
        .stream(primaryKey: ['id'])
        .eq('trainee_id', traineeId)
        .map(_attempts);
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    final row = await _client
        .from('assignment_attempts')
        .select()
        .eq('id', attemptId)
        .maybeSingle();
    if (row == null) return null;
    return AssignmentAttempt.tryFromMap(compactRow(row), id: attemptId);
  }

  @override
  Future<AssignmentAttempt> reserveTeacherActivityAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required String requestId,
  }) async {
    if (_currentUid != traineeId || assignment.activityAssessment == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final decoded = asRowMap(
      await _rpc('reserve_teacher_activity_attempt', {
        'p_assignment_id': assignment.id,
        'p_request_id': requestId,
      }),
    );
    return _attempt(decoded['attempt']);
  }

  @override
  Future<void> consumeTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    if (_currentUid != traineeId ||
        attempt.activityAssessmentSnapshot == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('consume_teacher_activity_attempt', {
      'p_assignment_id': attempt.assignmentId,
      'p_attempt_id': attempt.id,
    });
  }

  @override
  Future<void> abandonTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    if (_currentUid != traineeId ||
        attempt.traineeId != traineeId ||
        attempt.activityAssessmentSnapshot == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('abandon_teacher_activity_attempt', {
      'p_assignment_id': attempt.assignmentId,
      'p_attempt_id': attempt.id,
    });
  }

  @override
  Future<void> permanentlyDeleteAssignment({
    required String teacherId,
    required String assignmentId,
    required String confirmation,
  }) async {
    if (_currentUid != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _invokeAdmin({
      'action': 'permanent_delete_assignment',
      'assignment_id': assignmentId,
      'confirmation': confirmation,
    });
  }

  @override
  Future<void> permanentlyDeleteClassroom({
    required String teacherId,
    required String groupId,
    required String confirmation,
  }) async {
    if (_currentUid != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _invokeAdmin({
      'action': 'permanent_delete_classroom',
      'group_id': groupId,
      'confirmation': confirmation,
    });
  }

  /// Deletion cascades need service-role Storage cleanup, so they run in the
  /// admin Edge Function after it verifies the caller's JWT.
  Future<void> _invokeAdmin(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions
          .invoke('elixr-admin', body: body)
          .timeout(const Duration(minutes: 9));
      if (response.status != 200) {
        throw classroomFunctionFailure(
          statusCode: response.status,
          responseBody: response.data,
        );
      }
    } on FunctionException catch (error) {
      throw classroomFunctionFailure(
        statusCode: error.status,
        responseBody: error.details,
      );
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    }
  }

  static bool _isAttemptExists(Object error) =>
      error is ClassroomException && error.serverCode == 'attempt_exists';

  Future<AssignmentAttempt> _createAttempt({
    required AssignmentAttempt draft,
    required GroupAssignment assignment,
  }) async {
    return _attempt(
      await _rpc('create_assignment_attempt', {
        'p_attempt_id': draft.id,
        'p_assignment_id': assignment.id,
        'p_attempt_kind': draft.attemptKind.wireValue,
        'p_status': draft.status.wireValue,
        'p_supersedes_attempt_id': draft.supersedesAttemptId,
      }),
    );
  }

  Future<AssignmentAttempt> _transition(
    AssignmentAttempt attempt,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    return _attempt(
      await _rpc('transition_trainee_attempt', {
        'p_attempt_id': attempt.id,
        'p_action': action,
        'p_payload': payload,
      }),
    );
  }

  @override
  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  }) {
    return startTeacherCreatedAttemptWorkflow(
      traineeId: traineeId,
      assignment: assignment,
      create: (draft) => _createAttempt(draft: draft, assignment: assignment),
      readExisting: (attemptId) async {
        final existing = await getAttempt(attemptId: attemptId);
        return existing;
      },
      promoteDraftToInProgress: (existing) => _transition(existing, 'promote'),
      isPermissionDenied: _isAttemptExists,
    );
  }

  @override
  Future<AssignmentAttempt> createTeacherReviewSubmissionDraft({
    required String traineeId,
    required GroupAssignment assignment,
    String? supersedesAttemptId,
    String? attemptId,
  }) async {
    if (supersedesAttemptId != null) {
      final previous = await getAttempt(attemptId: supersedesAttemptId);
      if (previous == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      ensureCanSupersedeNeedsRetry(
        previous: previous,
        traineeId: traineeId,
        assignment: assignment,
      );
    }
    final draft = teacherReviewSubmissionDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
      attemptId: attemptId ?? newTeacherReviewSubmissionAttemptId(),
      supersedesAttemptId: supersedesAttemptId,
    );
    return _createAttempt(draft: draft, assignment: assignment);
  }

  @override
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    if (!isTeacherAssignmentSubmissionOpen(assignment: assignment)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    return getOrCreateCanonicalTeacherReviewSubmissionWorkflow(
      traineeId: traineeId,
      assignment: assignment,
      create: (canonical) =>
          _createAttempt(draft: canonical, assignment: assignment),
      readExisting: (attemptId) => getAttempt(attemptId: attemptId),
      promoteLegacyDraft: (existing) => _transition(existing, 'promote'),
      shouldReadAfterCreateFailure: _isAttemptExists,
      isFallbackReadFailure: (error) => error is PostgrestException,
    );
  }

  @override
  Future<void> markTeacherReviewSubmissionAbandoned({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? abandonedAt,
    DateTime? videoDeletedAt,
    bool deletionFailed = false,
    DateTime? deletionFailedAt,
  }) async {
    if (!canMarkTeacherReviewSubmissionAbandoned(
      attempt: attempt,
      traineeId: traineeId,
    )) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (deletionFailed && videoDeletedAt != null) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _transition(attempt, 'abandon', {
      'video_deleted': videoDeletedAt != null,
      'deletion_failed': deletionFailed,
    });
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    if (attempt.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        attempt.abandonedAt != null ||
        (attempt.status != AssignmentAttemptStatus.draft &&
            attempt.status != AssignmentAttemptStatus.inProgress)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureTeacherReviewSubmissionVideo(
      attempt: attempt,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    if (attempt.activityAssessmentSnapshot != null) {
      // The server verifies the uploaded object's size and type before
      // attaching it to the reserved attempt.
      final decoded = asRowMap(
        await _rpc('finalize_teacher_activity_attempt', {
          'p_assignment_id': attempt.assignmentId,
          'p_attempt_id': attempt.id,
          'p_video_storage_path': videoStoragePath,
          'p_video_content_type': videoContentType,
          'p_video_size_bytes': videoSizeBytes,
          'p_video_duration_ms': videoDurationMs,
        }, timeout: const Duration(seconds: 30)),
      );
      return _attempt(decoded['attempt']);
    }
    try {
      return await _transition(attempt, 'submit', {
        'video_storage_path': videoStoragePath,
        'video_content_type': videoContentType,
        'video_size_bytes': videoSizeBytes,
        'video_duration_ms': videoDurationMs,
      });
    } on ClassroomException catch (error) {
      emitPhase6SubmissionDiagnostic(
        stage: Phase6SubmissionStage.databaseSubmit,
        error: error,
      );
      rethrow;
    }
  }

  @override
  Future<AssignmentAttempt> saveTeacherReviewDraftClip({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime savedAt,
  }) async {
    if (attempt.traineeId != traineeId ||
        !attempt.isCanonicalTeacherReviewSubmission ||
        attempt.status != AssignmentAttemptStatus.inProgress ||
        attempt.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureLocalTeacherReviewDraftVideo(
      attempt: attempt,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
    );
    try {
      return await _transition(attempt, 'attach_draft', {
        'video_storage_path': videoStoragePath,
        'video_content_type': videoContentType,
        'video_size_bytes': videoSizeBytes,
        'video_duration_ms': videoDurationMs,
      });
    } on ClassroomException catch (error) {
      emitPhase6SubmissionDiagnostic(
        stage: Phase6SubmissionStage.databaseSubmit,
        error: error,
      );
      rethrow;
    }
  }

  @override
  Future<AssignmentAttempt> turnInTeacherReviewSubmission({
    required String traineeId,
    required AssignmentAttempt attempt,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    if (attempt.traineeId != traineeId || !attempt.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _transition(attempt, 'turn_in');
  }

  @override
  Future<AssignmentAttempt> turnInAssignmentAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    if (attempt.traineeId != traineeId ||
        !attempt.isSelectableSubmissionCandidate) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final decoded = asRowMap(
      await _rpc('turn_in_assignment_attempt', {
        'p_assignment_id': attempt.assignmentId,
        'p_attempt_id': attempt.id,
      }, timeout: const Duration(seconds: 30)),
    );
    final retired = decoded['cleanup_storage_path'];
    if (retired is String && retired.startsWith('assignment_submissions/')) {
      // The server already detached the superseded video (unlimited policy);
      // removing the object is best-effort housekeeping.
      unawaited(
        storageFor(
          _client,
          retired,
        ).remove([retired]).then<void>((_) {}, onError: (_) {}),
      );
    }
    return _attempt(decoded['attempt']);
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    if (attempt.traineeId != traineeId || !attempt.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _transition(attempt, 'begin_draft_removal');
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    if (attempt.traineeId != traineeId || !attempt.isDraftClipRemovalPending) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _transition(attempt, 'complete_draft_removal');
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    final current = await getAttempt(attemptId: attempt.id);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (current.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!current.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (current.status == AssignmentAttemptStatus.unsubmitting) return current;
    if (current.status != AssignmentAttemptStatus.submitted ||
        !current.hasPlayableVideo) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _transition(current, 'begin_unsubmit');
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? completedAt,
  }) async {
    final current = await getAttempt(attemptId: attempt.id);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (!current.isCanonicalTeacherReviewSubmission ||
        current.traineeId != traineeId ||
        current.status != AssignmentAttemptStatus.unsubmitting) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _transition(current, 'complete_unsubmit');
  }

  @override
  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  }) async {
    if (attempt.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final maxScore = attempt.gradeMaxScore ?? assignment.maxScore ?? 100;
    ensureTeacherReviewGrade(gradeScore: gradeScore, maxScore: maxScore);
    return _attempt(
      await _rpc('save_teacher_review', {
        'p_attempt_id': attempt.id,
        'p_grade_score': gradeScore,
        'p_feedback': feedback?.trim(),
      }),
    );
  }

  @override
  Future<AssignmentAttempt> saveTeacherActivityRubricReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required Map<String, int> criterionScores,
    String? feedback,
  }) async {
    if (_currentUid != teacherId ||
        attempt.activityAssessmentSnapshot == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final decoded = asRowMap(
      await _rpc('grade_teacher_activity_attempt', {
        'p_attempt_id': attempt.id,
        'p_criterion_scores': criterionScores,
        'p_feedback': feedback?.trim(),
      }),
    );
    return _attempt(decoded['attempt']);
  }

  @override
  Future<GroupAssignment> updateTeacherAssignmentMaxScore({
    required String teacherId,
    required String assignmentId,
    required int maxScore,
  }) async {
    final current = await _loadAssignment(assignmentId);
    return updateAssignmentSettings(
      teacherId: teacherId,
      assignmentId: assignmentId,
      dueAt: current.dueAt,
      maxScore: maxScore,
      topic: current.topic,
    );
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewResultSent({
    required String teacherId,
    required AssignmentAttempt attempt,
    required String messageId,
    DateTime? sentAt,
  }) async {
    if (attempt.teacherId != teacherId || messageId.trim().isEmpty) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _attempt(
      await _rpc('mark_review_result_sent', {
        'p_attempt_id': attempt.id,
        'p_message_id': messageId.trim(),
      }),
    );
  }

  @override
  Future<AssignmentAttempt> reviewTeacherSubmission({
    required String teacherId,
    required AssignmentAttempt attempt,
    required AssignmentReviewVerdict verdict,
    String? feedback,
    required DateTime reviewedAt,
    required DateTime videoExpiresAt,
  }) async {
    if (attempt.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _attempt(
      await _rpc('review_teacher_submission', {
        'p_attempt_id': attempt.id,
        'p_verdict': verdict.wireValue,
        'p_feedback': feedback?.trim(),
      }),
    );
  }

  @override
  Future<void> markSubmissionVideoDeleted({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime deletedAt,
  }) async {
    if (attempt.traineeId != actorId && attempt.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission &&
        attempt.traineeId == actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('mark_attempt_video_state', {
      'p_attempt_id': attempt.id,
      'p_deleted': true,
    });
  }

  @override
  Future<void> markSubmissionDeletionFailed({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime failedAt,
  }) async {
    if (attempt.traineeId != actorId && attempt.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission &&
        (attempt.traineeId != actorId ||
            attempt.status != AssignmentAttemptStatus.unsubmitting)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _rpc('mark_attempt_video_state', {
      'p_attempt_id': attempt.id,
      'p_deleted': false,
    });
  }

  /// Re-reads the approved roster immediately before a targeted assignment
  /// is created (the server re-validates every recipient transactionally).
  Future<void> _ensureAudienceTargetsAreApprovedMembers({
    required String teacherId,
    required ElixrGroup group,
    required AssignmentAudience audience,
  }) async {
    if (audience.isEntireClass) return;
    final rows = await _client
        .from('group_memberships')
        .select()
        .eq('teacher_id', teacherId)
        .eq('group_id', group.id)
        .eq('status', GroupMembershipStatus.approved.name);
    ensureAssignmentAudienceMatchesRoster(
      audience: audience,
      group: group,
      memberships: [
        for (final row in rows)
          ?GroupMembership.tryFromMap(compactRow(row), id: row['id'] as String),
      ],
    );
  }

  /// The assignment and its recipient rows are one server transaction; the
  /// server derives the Teacher, display names and timestamps itself.
  Future<GroupAssignment> _createAssignment({
    required Map<String, dynamic> payload,
    required AssignmentAudience audience,
  }) async {
    if (_currentUid != payload['teacher_id']) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final requestPayload =
        <String, dynamic>{
            ...payload,
            'recipient_ids': audience.isEntireClass
                ? const <String>[]
                : audience.targetTraineeIds,
          }
          ..remove('teacher_id')
          ..remove('teacher_display_name')
          ..remove('group_name')
          ..remove('created_at')
          ..remove('updated_at');
    for (final key in const ['due_at', 'publish_at']) {
      final value = requestPayload[key];
      if (value is DateTime) {
        requestPayload[key] = value.toUtc().toIso8601String();
      }
    }
    final decoded = asRowMap(
      await _rpc('create_classroom_assignment', {'p': requestPayload}),
    );
    final parsed = _assignment(decoded['assignment']);
    final responseRecipients = decoded['recipient_ids'];
    if (responseRecipients is! List ||
        responseRecipients.length != audience.targetTraineeIds.length ||
        !responseRecipients.every(
          (value) =>
              value is String &&
              audience.targetTraineeIds.contains(value.trim()),
        ) ||
        parsed.audience.type != audience.type) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    return parsed.copyWith(
      audience: parsed.audience.withRecipientIds(
        responseRecipients.cast<String>().map((value) => value.trim()),
      ),
    );
  }

  Future<List<GroupAssignment>> _hydrateTeacherAssignments(
    List<GroupAssignment> assignments,
    String teacherId,
  ) async {
    final targeted = assignments
        .where((assignment) => !assignment.audience.isEntireClass)
        .toList(growable: false);
    final recipientsByAssignment = <String, Set<String>>{};
    if (targeted.isNotEmpty) {
      final rows = await _client
          .from('assignment_recipients')
          .select()
          .eq('teacher_id', teacherId)
          .inFilter('assignment_id', [for (final item in targeted) item.id]);
      final byId = {for (final item in targeted) item.id: item};
      for (final row in rows) {
        final assignment = byId[row['assignment_id']];
        final traineeId = row['trainee_id'];
        if (assignment != null &&
            traineeId is String &&
            _validRecipient(row, assignment, traineeId)) {
          recipientsByAssignment
              .putIfAbsent(assignment.id, () => <String>{})
              .add(traineeId);
        }
      }
    }
    return [
      for (final assignment in assignments)
        if (assignment.audience.isEntireClass)
          assignment
        else if (recipientsByAssignment.containsKey(assignment.id) &&
            (assignment.audience.type !=
                    AssignmentAudienceType.individualStudent ||
                recipientsByAssignment[assignment.id]!.length == 1))
          assignment.copyWith(
            audience: assignment.audience.withRecipientIds(
              recipientsByAssignment[assignment.id]!,
            ),
          ),
    ];
  }

  static bool _validRecipient(
    Map<String, dynamic>? data,
    GroupAssignment assignment,
    String traineeId,
  ) {
    if (data == null || assignment.audience.isEntireClass) return false;
    return data['assignment_id'] == assignment.id &&
        data['group_id'] == assignment.groupId &&
        data['teacher_id'] == assignment.teacherId &&
        data['trainee_id'] == traineeId &&
        data['audience_type'] == assignment.audience.type.wireValue &&
        data['schema_version'] == 1 &&
        TeacherRosterInvite.readDateTime(data['created_at']) != null;
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

/// Maps a database RPC rejection to the classroom error contract. The RPC
/// error message is the stable server code (formerly the Function `error`).
ClassroomException classroomRpcFailure(PostgrestException error) {
  final status = switch (error.code) {
    '42501' || '28000' => HttpStatus.forbidden,
    'P0002' => HttpStatus.notFound,
    _ => HttpStatus.conflict,
  };
  return classroomFunctionFailure(
    statusCode: status,
    responseBody: {
      'error': error.message,
      if (error.details is String) 'active_attempt_id': error.details,
    },
  );
}

ClassroomException classroomFunctionFailure({
  required int statusCode,
  required Object? responseBody,
}) {
  final serverCode = responseBody is Map && responseBody['error'] is String
      ? responseBody['error'] as String
      : null;
  final error = switch (serverCode) {
    'unauthenticated' || 'forbidden' => ClassroomError.forbidden,
    'not_found' => ClassroomError.notFound,
    'conflict' => ClassroomError.conflict,
    'attempt_limit_conflict' => ClassroomError.attemptLimitConflict,
    'invalid_recipient' => ClassroomError.invalidRecipient,
    'trainee_work_exists' => ClassroomError.invalidState,
    'invalid_publication' => ClassroomError.invalidState,
    'invalid_movement' => ClassroomError.identityMismatch,
    'identity_mismatch' => ClassroomError.identityMismatch,
    'movement_not_found' || 'revision_not_found' => ClassroomError.notFound,
    'movement_archived' || 'archived' => ClassroomError.archived,
    'stale_revision' => ClassroomError.identityMismatch,
    'invalid_movement_owner' => ClassroomError.forbidden,
    'invalid_movement_spec' || 'malformed' => ClassroomError.malformed,
    'invalid_activity_assessment' ||
    'invalid_grade' => ClassroomError.invalidGrade,
    'invalid_instructions' => ClassroomError.malformed,
    'invalid_identity' || 'invalid_state' => ClassroomError.invalidState,
    'invalid_payload' ||
    'invalid_due_at' ||
    'invalid_audience' ||
    'invalid_topic' ||
    'invalid_confirmation' ||
    'method_not_allowed' => ClassroomError.malformed,
    'deadline_passed' => ClassroomError.deadlinePassed,
    'graded' => ClassroomError.invalidState,
    'attempt_in_progress' || 'attempt_exists' => ClassroomError.conflict,
    'attempt_conflict' ||
    'upload_mismatch' ||
    'upload_missing' => ClassroomError.conflict,
    'attempts_exhausted' => ClassroomError.attemptLimitConflict,
    'unavailable' => ClassroomError.invalidState,
    _
        when statusCode == HttpStatus.unauthorized ||
            statusCode == HttpStatus.forbidden =>
      ClassroomError.forbidden,
    _ => ClassroomError.invalidState,
  };
  final message = switch (serverCode) {
    'unauthenticated' => 'Your sign-in has expired. Sign in again and retry.',
    'forbidden' =>
      'You no longer have permission to create an assignment for this classroom.',
    'invalid_recipient' =>
      'One or more selected trainees are no longer approved members of this classroom.',
    'trainee_work_exists' =>
      'This assignment already has trainee work, so movement, audience, attempts, and scoring can no longer be changed.',
    'invalid_publication' =>
      'The due date must be later than the scheduled publication time.',
    'invalid_movement' =>
      'This movement changed or is no longer available. Refresh it and try again.',
    'movement_not_found' =>
      'This Teacher Activity is no longer available. Refresh the activity list and try again.',
    'revision_not_found' =>
      'The current Teacher Activity revision is unavailable. Refresh the activity and try again.',
    'movement_archived' => 'Archived Teacher Activities cannot be assigned.',
    'stale_revision' =>
      'This Teacher Activity was updated. Refresh it and try again.',
    'invalid_movement_owner' =>
      'You no longer have permission to assign this Teacher Activity.',
    'invalid_movement_spec' =>
      'This Teacher Activity has incomplete or unsupported details. Edit it and try again.',
    'invalid_activity_assessment' =>
      'The Teacher Activity assessment configuration is invalid. Review its rubric and try again.',
    'invalid_instructions' =>
      'Instructions must be between 1 and 2,000 characters.',
    'invalid_identity' =>
      'Your Teacher profile or classroom is missing required identity details.',
    'invalid_payload' =>
      'Some assignment details are invalid. Review the form and try again.',
    'invalid_due_at' => 'Choose a valid due date and time.',
    'invalid_audience' => 'Choose a valid assignment audience.',
    'invalid_topic' => 'Topic must be between 1 and 80 characters.',
    'method_not_allowed' => 'Assignment creation is temporarily unavailable.',
    'deadline_passed' => 'This Teacher Activity is past its deadline.',
    'graded' => 'This Teacher Activity has already been graded.',
    'attempt_in_progress' =>
      'This Teacher Activity could not recover a previous recording attempt. Try again.',
    'attempt_conflict' =>
      'This recording attempt was already cancelled or completed. Refresh and try again.',
    'upload_mismatch' || 'upload_missing' =>
      'The uploaded recording could not be verified. Record the attempt again.',
    'attempts_exhausted' =>
      'This Teacher Activity has no remaining recordings.',
    'unavailable' =>
      'The classroom service is unavailable. Check your connection and try again.',
    _ => null,
  };
  final activeAttemptId =
      responseBody is Map &&
          responseBody['active_attempt_id'] is String &&
          (responseBody['active_attempt_id'] as String).trim().isNotEmpty
      ? (responseBody['active_attempt_id'] as String).trim()
      : null;
  return ClassroomException.fromFunction(
    error,
    message: message,
    httpStatus: statusCode,
    serverCode: serverCode,
    activeAttemptId: activeAttemptId,
  );
}
