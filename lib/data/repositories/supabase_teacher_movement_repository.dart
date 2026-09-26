import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, SupabaseClient;

import '../models/assessment_mode.dart';
import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import '../models/teacher_reviewed_movement_spec.dart';
import '../models/training_prop.dart';
import 'supabase_classroom_assignment_repository.dart';
import 'teacher_movement_repository.dart';

class SupabaseTeacherMovementRepository implements TeacherMovementRepository {
  SupabaseTeacherMovementRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static const _demoBucket = 'teacher-activity-demos';

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      if (error.message == 'movement_in_use') {
        throw const ClassroomException(
          ClassroomError.invalidState,
          'This movement cannot be deleted because it is used by an assignment.',
        );
      }
      throw classroomRpcFailure(error);
    }
  }

  @override
  Future<File> openActivityDemonstration(
    TeacherActivityVideoMetadata metadata,
  ) async {
    if (!metadata.storagePath.startsWith('teacher_activity_demos/') ||
        metadata.contentType != 'video/mp4') {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final root = await getTemporaryDirectory();
    final cache = Directory('${root.path}/elixr_activity_demos');
    await cache.create(recursive: true);
    final objectName = metadata.storagePath.split('/').last;
    final destination = File(
      '${cache.path}/${DateTime.now().microsecondsSinceEpoch}_$objectName',
    );
    try {
      final bytes = await _client.storage
          .from(_demoBucket)
          .download(metadata.storagePath);
      if (bytes.isEmpty ||
          bytes.length >
              TeacherActivityAssessmentContract.maximumVideoSizeBytes) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      await destination.writeAsBytes(bytes, flush: true);
      return destination;
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<void> releaseActivityDemonstration(File localFile) async {
    try {
      if (await localFile.exists()) await localFile.delete();
    } on FileSystemException {
      // A best-effort cache cleanup must not fail page navigation.
    }
  }

  @override
  Future<TeacherActivityVideoMetadata> uploadActivityDemonstration({
    required String teacherId,
    required File localFile,
    required Duration duration,
    required TeacherActivityDemoSource source,
    String? assignmentId,
  }) async {
    final sizeBytes = await _validatedDemoFileSize(
      teacherId: teacherId,
      localFile: localFile,
      duration: duration,
    );
    // An opaque generated ID avoids using a user-controlled local filename
    // in the object path.
    final opaqueId = newDocumentId();
    final assignmentScope = assignmentId?.trim();
    final storagePath = assignmentScope == null || assignmentScope.isEmpty
        ? 'teacher_activity_demos/$teacherId/$opaqueId.mp4'
        : 'teacher_activity_demos/$teacherId/assignments/$assignmentScope/$opaqueId.mp4';
    await _client.storage
        .from(_demoBucket)
        .upload(
          storagePath,
          localFile,
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );
    return TeacherActivityVideoMetadata(
      storagePath: storagePath,
      contentType: 'video/mp4',
      sizeBytes: sizeBytes,
      durationMs: duration.inMilliseconds,
      source: source,
    );
  }

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
    );
    final row = await _mapped(
      () => rpcMap(_client, 'create_teacher_movement', {
        'p_title': title.trim(),
        'p_spec': spec.toMap(),
        'p_schema_version': TeacherReviewedMovementSpec.currentSchemaVersion,
      }),
    );
    return TeacherMovement.tryFromMap(row, id: row['id'] as String) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  Future<TeacherMovement> _requireOwnedTeacherReviewed({
    required String teacherId,
    required String movementId,
  }) async {
    final current = await getMovement(movementId: movementId);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    ensureRevisionAssessmentMode(
      revision: await getRevision(
        movementId: movementId,
        revisionId: current.currentRevisionId,
      ),
      expected: AssessmentMode.teacherReviewed,
    );
    return current;
  }

  @override
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
    );
    await _requireOwnedTeacherReviewed(
      teacherId: teacherId,
      movementId: movementId,
    );
    final row = await _mapped(
      () => rpcMap(_client, 'edit_teacher_movement', {
        'p_movement_id': movementId,
        'p_title': title.trim(),
        'p_spec': spec.toMap(),
        'p_schema_version': TeacherReviewedMovementSpec.currentSchemaVersion,
      }),
    );
    return TeacherMovement.tryFromMap(row, id: movementId) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  @override
  Future<void> archiveMovement({
    required String teacherId,
    required String movementId,
  }) async {
    await _requireOwnedTeacherReviewed(
      teacherId: teacherId,
      movementId: movementId,
    );
    await _mapped(
      () => _client.rpc<dynamic>(
        'archive_teacher_movement',
        params: {'p_movement_id': movementId},
      ),
    );
  }

  @override
  Future<void> deleteMovement({
    required String teacherId,
    required String movementId,
  }) async {
    await _requireOwnedTeacherReviewed(
      teacherId: teacherId,
      movementId: movementId,
    );
    // Revisions cascade with the movement in the same transaction; linked
    // assignments block deletion server-side.
    await _mapped(
      () => _client.rpc<dynamic>(
        'delete_teacher_movement',
        params: {'p_movement_id': movementId},
      ),
    );
  }

  @override
  Stream<List<TeacherMovement>> watchTeacherMovements({
    required String teacherId,
  }) {
    return _client
        .from('teacher_movements')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .map((rows) {
          final items = [
            for (final row in rows)
              ?TeacherMovement.tryFromMap(
                compactRow(row),
                id: row['id'] as String,
              ),
          ];
          items.sort((a, b) {
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
          return items;
        });
  }

  @override
  Future<TeacherMovement?> getMovement({required String movementId}) async {
    final row = await _client
        .from('teacher_movements')
        .select()
        .eq('id', movementId)
        .maybeSingle();
    if (row == null) return null;
    return TeacherMovement.tryFromMap(compactRow(row), id: movementId);
  }

  @override
  Future<TeacherMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    final row = await _client
        .from('teacher_movement_revisions')
        .select()
        .eq('id', revisionId)
        .eq('movement_id', movementId)
        .maybeSingle();
    if (row == null) return null;
    return TeacherMovementRevision.tryFromMap(compactRow(row), id: revisionId);
  }
}

Future<int> _validatedDemoFileSize({
  required String teacherId,
  required File localFile,
  required Duration duration,
}) async {
  if (teacherId.trim().isEmpty) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Missing teacher.',
    );
  }
  if (duration.inMilliseconds < 1 || duration.inMilliseconds > 60000) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Demonstration videos must be 60 seconds or less.',
    );
  }
  final stat = await localFile.stat();
  if (stat.type != FileSystemEntityType.file ||
      stat.size < 1 ||
      stat.size > 50 * 1024 * 1024) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Demonstration videos must be an MP4 no larger than 50 MiB.',
    );
  }
  return stat.size;
}
