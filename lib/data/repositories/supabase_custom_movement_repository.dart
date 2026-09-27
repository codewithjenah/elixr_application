import 'dart:typed_data';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, StorageException, SupabaseClient;

import '../models/custom_movement.dart';
import '../models/movement_template.dart';
import '../models/training_prop.dart';
import 'custom_movement_repository.dart';
import 'session_evidence_repository.dart';

class SupabaseCustomMovementRepository implements CustomMovementRepository {
  SupabaseCustomMovementRepository({
    SupabaseClient? client,
    SessionEvidenceRepository? evidenceRepository,
  }) : _clientOverride = client,
       _evidenceRepositoryOverride = evidenceRepository;

  final SupabaseClient? _clientOverride;
  final SessionEvidenceRepository? _evidenceRepositoryOverride;
  SessionEvidenceRepository? _evidenceRepositoryInstance;

  SessionEvidenceRepository get _evidenceRepository =>
      _evidenceRepositoryOverride ??
      (_evidenceRepositoryInstance ??= SessionEvidenceRepository(
        client: _clientOverride,
      ));

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static const _maxReferenceImageBytes = 512 * 1024;
  static const _referenceBucket = 'custom-movement-references';

  @override
  String allocateSessionId() => newDocumentId();

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({
    required String ownerUid,
  }) => _client
      .from('custom_movements')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .map((rows) {
        final movements = rows
            .map(
              (row) => CustomMovement.tryFromMap(
                compactRow(row),
                id: row['id'] as String,
              ),
            )
            .whereType<CustomMovement>()
            .where((movement) => movement.isActive)
            .toList(growable: false);
        movements.sort((a, b) {
          final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });
        return movements;
      });

  @override
  Stream<List<CustomMovementResult>> watchPersonalResults({
    required String ownerUid,
  }) => _client
      .from('custom_movement_results')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .map(
        (rows) => rows
            .map(
              (row) => CustomMovementResult.tryFromMap(
                compactRow(row),
                id: row['id'] as String,
              ),
            )
            .whereType<CustomMovementResult>()
            .toList(growable: false),
      );

  @override
  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    final row = await _client
        .from('custom_movements')
        .select()
        .eq('id', movementId)
        .maybeSingle();
    final movement = row == null
        ? null
        : CustomMovement.tryFromMap(compactRow(row), id: movementId);
    return movement?.isOwnedBy(ownerUid) == true ? movement : null;
  }

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    final row = await _client
        .from('custom_movement_revisions')
        .select()
        .eq('id', revisionId)
        .eq('movement_id', movementId)
        .maybeSingle();
    return row == null
        ? null
        : CustomMovementRevision.tryFromMap(compactRow(row), id: revisionId);
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
    Uint8List? referenceImageJpegBytes,
  }) async {
    try {
      validateCustomMovementWrite(
        ownerUid: ownerUid,
        template: template,
        name: name,
        description: description,
        difficulty: difficulty,
        propType: propType,
      );
    } on Object catch (error, stackTrace) {
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.validation,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final movementId = newDocumentId();
    final revisionId = newDocumentId();
    final imagePath = referenceImageJpegBytes == null
        ? null
        : CustomMovement.referenceImagePath(ownerUid, movementId, revisionId);
    if (referenceImageJpegBytes != null) {
      await _uploadReferenceImage(imagePath!, referenceImageJpegBytes);
    }
    try {
      final row = await rpcMap(_client, 'create_custom_movement', {
        'p_movement_id': movementId,
        'p_revision_id': revisionId,
        'p_owner_role': ownerRole.wireValue,
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_difficulty': difficulty,
        'p_prop_type': propType.protocolValue,
        'p_template': template.toMap(),
        'p_reference_image_storage_path': imagePath,
      });
      return CustomMovement.tryFromMap(row, id: movementId) ??
          CustomMovement(
            id: movementId,
            ownerUid: ownerUid,
            ownerRole: ownerRole,
            name: name.trim(),
            description: description.trim(),
            difficulty: difficulty,
            propType: propType,
            status: CustomMovementStatus.active,
            activeRevisionId: revisionId,
            referenceImageStoragePath: imagePath,
          );
    } on Object catch (error, stackTrace) {
      if (imagePath != null) await _deleteReferenceImageBestEffort(imagePath);
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.databaseCommit,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
    Uint8List? referenceImageJpegBytes,
  }) async {
    try {
      validateCustomMovementWrite(
        ownerUid: current.ownerUid,
        template: template,
        name: name,
        description: description,
        difficulty: difficulty,
        propType: propType,
      );
    } on Object catch (error, stackTrace) {
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.validation,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final revisionId = newDocumentId();
    final imagePath = referenceImageJpegBytes == null
        ? null
        : CustomMovement.referenceImagePath(
            current.ownerUid,
            current.id,
            revisionId,
          );
    if (referenceImageJpegBytes != null) {
      await _uploadReferenceImage(imagePath!, referenceImageJpegBytes);
    }
    try {
      // The server rejects a stale active revision (optimistic concurrency).
      await _client.rpc<dynamic>(
        'publish_custom_movement_revision',
        params: {
          'p_movement_id': current.id,
          'p_expected_active_revision_id': current.activeRevisionId,
          'p_revision_id': revisionId,
          'p_name': name.trim(),
          'p_description': description.trim(),
          'p_difficulty': difficulty,
          'p_prop_type': propType.protocolValue,
          'p_template': template.toMap(),
          'p_reference_image_storage_path': imagePath,
        },
      );
    } on Object catch (error, stackTrace) {
      if (imagePath != null) await _deleteReferenceImageBestEffort(imagePath);
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.databaseCommit,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return CustomMovement(
      id: current.id,
      ownerUid: current.ownerUid,
      ownerRole: current.ownerRole,
      name: name.trim(),
      description: description.trim(),
      difficulty: difficulty,
      propType: propType,
      status: current.status,
      activeRevisionId: revisionId,
      createdAt: current.createdAt,
      referenceImageStoragePath: imagePath ?? current.referenceImageStoragePath,
    );
  }

  @override
  Future<void> archiveMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    final movement = await getOwnedMovement(
      movementId: movementId,
      ownerUid: ownerUid,
    );
    if (movement == null) throw StateError('Movement not found.');
    await _client.rpc<dynamic>(
      'archive_custom_movement',
      params: {'p_movement_id': movementId},
    );
  }

  @override
  Future<void> deleteOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    var stage = CustomMovementDeleteStage.movementLookup;
    try {
      final row = await _client
          .from('custom_movements')
          .select()
          .eq('id', movementId)
          .maybeSingle();
      if (row == null) return;
      final movement = CustomMovement.tryFromMap(
        compactRow(row),
        id: movementId,
      );
      if (movement == null || !movement.isOwnedBy(ownerUid)) {
        throw StateError('Movement changed or is not owned by this user.');
      }
      if (!movement.isActive) return;

      // Revisions and results are immutable historical records. Archiving
      // removes the definition from the active library while preserving
      // those references; it is the only deletion-like client transition.
      stage = CustomMovementDeleteStage.archive;
      await _client.rpc<dynamic>(
        'archive_custom_movement',
        params: {'p_movement_id': movementId},
      );
    } on Object catch (error, stackTrace) {
      throw CustomMovementDeleteException(
        stage: stage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

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
  }) async {
    if (!totalScore.isFinite ||
        totalScore < 0 ||
        totalScore > 100 ||
        durationSeconds < 0 ||
        durationSeconds > 86400 ||
        sessionId.trim().isEmpty ||
        sessionId.length > 128) {
      throw ArgumentError.value(totalScore, 'totalScore');
    }
    // Upload first (upsert is idempotent for the same session ID) so the
    // server can verify the object before attaching evidence metadata.
    if (evidenceJpegBytes != null) {
      await _evidenceRepository.upload(
        userId: ownerUid,
        sessionId: sessionId,
        jpegBytes: evidenceJpegBytes,
      );
    }
    // The result and its session-history mirror commit together; movement
    // identity fields and the evidence path are derived server-side.
    await _client.rpc<dynamic>(
      'save_custom_movement_practice_result',
      params: {
        'p_session_id': sessionId,
        'p_movement_id': movementId,
        'p_revision_id': revisionId,
        'p_total_score': totalScore,
        'p_component_scores': componentScores,
        'p_feedback': feedback.take(8).toList(growable: false),
        'p_duration_seconds': durationSeconds,
        'p_evidence_size_bytes': evidenceJpegBytes?.lengthInBytes,
      },
    );
  }

  Future<void> _uploadReferenceImage(String path, Uint8List bytes) async {
    try {
      if (bytes.lengthInBytes < 1024 ||
          bytes.lengthInBytes > _maxReferenceImageBytes) {
        throw ArgumentError.value(
          bytes.lengthInBytes,
          'referenceImageJpegBytes',
          'Reference JPEG must be 1–512 KiB',
        );
      }
      await _client.storage
          .from(_referenceBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    } on Object catch (error, stackTrace) {
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.referenceImageUpload,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _deleteReferenceImageBestEffort(String path) async {
    try {
      await _client.storage.from(_referenceBucket).remove([path]);
    } on StorageException {
      // The caller preserves the original error; an orphaned JPEG is
      // owner-private if Storage cleanup is temporarily unavailable.
    }
  }
}
