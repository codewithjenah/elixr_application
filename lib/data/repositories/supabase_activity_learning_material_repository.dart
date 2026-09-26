import 'dart:async';
import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        FileOptions,
        FunctionException,
        PostgrestException,
        StorageException,
        SupabaseClient;

import '../models/activity_learning_material.dart';
import '../models/classroom_exceptions.dart';
import 'activity_learning_material_repository.dart';
import 'supabase_classroom_assignment_repository.dart';

String activityLearningMaterialCacheFileName({
  required String materialId,
  required String extension,
}) {
  final safeId = materialId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'material_$safeId.$extension';
}

bool isManagedActivityLearningMaterialCacheFile(String fileName) =>
    fileName.startsWith('material_');

bool isStaleActivityLearningMaterialCacheEntry({
  required DateTime lastModified,
  required DateTime now,
}) => now.difference(lastModified) > const Duration(days: 7);

/// Thin client for the server-authoritative Activity Learning Material API.
/// It has no authority to create final objects or metadata: Storage is used
/// only for the exact quarantine upload path returned by the server, and the
/// admin Edge Function validates bytes before publishing a material.
class SupabaseActivityLearningMaterialRepository
    implements ActivityLearningMaterialRepository {
  SupabaseActivityLearningMaterialRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _clientOverride = client;

  static const _bucket = 'activity-learning-materials';

  final SupabaseClient? _clientOverride;
  final Duration requestTimeout;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required String requestId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) async {
    final decoded = await _rpc('begin_activity_material_upload', {
      'p_assignment_id': assignmentId,
      'p_request_id': requestId,
      'p_type': type.wireValue,
      'p_display_name': displayName.trim(),
      'p_declared_content_type': declaredContentType.trim().toLowerCase(),
      'p_size_bytes': sizeBytes,
    });
    final upload = ActivityMaterialUpload.tryFromMap(decoded);
    if (upload == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    return upload;
  }

  @override
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  }) async {
    if (upload.expiresAt.isBefore(DateTime.now().toUtc()) ||
        !await file.exists()) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    try {
      await _client.storage
          .from(_bucket)
          .upload(
            upload.stagingPath,
            file,
            fileOptions: FileOptions(contentType: upload.declaredContentType),
          );
    } on StorageException catch (error) {
      // 409: an earlier ambiguous attempt already staged this exact object.
      if (error.statusCode != '409') {
        throw const ClassroomException(ClassroomError.invalidState);
      }
    }
    // Server-side validation (magic bytes, size) and the move to the final
    // path happen in the admin Edge Function; status is polled separately.
    await _invokeAdmin({
      'action': 'finalize_material_upload',
      'upload_id': upload.uploadId,
    });
  }

  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) async {
    final decoded = await _rpc('get_activity_material_upload_status', {
      'p_upload_id': uploadId,
    });
    final status = ActivityMaterialUploadStatus.tryFromMap(decoded);
    if (status == null || status.uploadId != uploadId) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    return status;
  }

  @override
  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
    required String requestId,
  }) async {
    final decoded = await _rpc('add_activity_learning_material_link', {
      'p_assignment_id': assignmentId,
      'p_display_name': displayName.trim(),
      'p_url': url.toString(),
      'p_request_id': requestId,
    });
    final material = ActivityLearningMaterial.tryFromMap(decoded);
    if (material == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    return material;
  }

  @override
  Future<void> remove({
    required String assignmentId,
    required String materialId,
  }) async {
    // Read access is revoked in the database transaction; the Edge Function
    // then removes the objects and the tombstone row with the service role.
    await _invokeAdmin({
      'action': 'remove_material',
      'assignment_id': assignmentId,
      'material_id': materialId,
    });
  }

  @override
  Future<List<ActivityLearningMaterial>> list({
    required String assignmentId,
  }) async {
    final decoded = await _rpc('list_activity_learning_materials', {
      'p_assignment_id': assignmentId,
    });
    return _materials(
      decoded,
      accept: (material) => material.assignmentId == assignmentId,
    );
  }

  @override
  Future<List<ActivityLearningMaterial>> listForTrainee() async {
    final decoded = await _rpc(
      'list_trainee_activity_learning_materials',
      const {},
    );
    return _materials(decoded, accept: (_) => true);
  }

  List<ActivityLearningMaterial> _materials(
    Map<String, dynamic> decoded, {
    required bool Function(ActivityLearningMaterial material) accept,
  }) {
    final raw = decoded['materials'];
    if (raw is! List) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final materials = <ActivityLearningMaterial>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      final parsed = ActivityLearningMaterial.tryFromMap(compactRow(item));
      if (parsed == null || !accept(parsed)) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      materials.add(parsed);
    }
    return List.unmodifiable(materials);
  }

  @override
  Future<File> openFile(ActivityLearningMaterial material) async {
    final path = material.storagePath;
    if (material.type == ActivityLearningMaterialType.link ||
        path == null ||
        path.isEmpty) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}activity_learning_materials',
    );
    await directory.create(recursive: true);
    await _clearStaleMaterialCache(directory);
    final extension = switch (material.type) {
      ActivityLearningMaterialType.pdf => 'pdf',
      ActivityLearningMaterialType.image =>
        material.detectedContentType == 'image/png' ? 'png' : 'jpg',
      ActivityLearningMaterialType.video => 'mp4',
      ActivityLearningMaterialType.link => throw StateError('unreachable'),
    };
    // Material IDs are server-generated identifiers. Still sanitize them so a
    // malicious display name or storage path can never influence the cache.
    final file = File(
      '${directory.path}${Platform.pathSeparator}${activityLearningMaterialCacheFileName(materialId: material.id, extension: extension)}',
    );
    final objects = _client.storage.from(_bucket);
    try {
      // A cache entry is never a read capability. Re-check the authenticated
      // Storage object (RLS-enforced) before returning it so removals and
      // access revocations take effect even when ELIXR still has local bytes.
      if (await file.exists()) {
        await objects.info(path);
        final age = DateTime.now().difference(await file.lastModified());
        final sizeMatches =
            material.sizeBytes == null ||
            await file.length() == material.sizeBytes;
        if (age < const Duration(hours: 24) && sizeMatches) {
          return file;
        }
      }
      final bytes = await objects.download(path);
      if (material.sizeBytes != null && bytes.length != material.sizeBytes) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on StorageException {
      if (await file.exists()) await file.delete();
      throw const ClassroomException(ClassroomError.notFound);
    } on ClassroomException {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> _clearStaleMaterialCache(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        final isManagedMaterial =
            entity is File &&
            isManagedActivityLearningMaterialCacheFile(
              entity.path.split(Platform.pathSeparator).last,
            );
        if (!isManagedMaterial) {
          continue;
        }
        if (isStaleActivityLearningMaterialCacheEntry(
          lastModified: await entity.lastModified(),
          now: DateTime.now(),
        )) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Cache cleanup is opportunistic. A locked file may still be open in a
      // Windows viewer and must not make an authorized material unavailable.
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    if (_client.auth.currentUser == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    try {
      final result = await _client
          .rpc<dynamic>(function, params: params)
          .timeout(requestTimeout);
      return asRowMap(result);
    } on PostgrestException catch (error) {
      throw classroomRpcFailure(error);
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FormatException {
      throw const ClassroomException(ClassroomError.malformed);
    }
  }

  Future<void> _invokeAdmin(Map<String, Object?> body) async {
    if (_client.auth.currentUser == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    try {
      final response = await _client.functions
          .invoke('elixr-admin', body: body)
          .timeout(const Duration(minutes: 2));
      if (response.status != HttpStatus.ok) {
        throw activityLearningMaterialFunctionFailure(
          response.status,
          response.data,
          receivedNonJson: response.data is! Map,
        );
      }
    } on FunctionException catch (error) {
      throw activityLearningMaterialFunctionFailure(
        error.status,
        error.details,
        receivedNonJson: error.details is! Map,
      );
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    }
  }
}

/// Maps only the safe, structured part of a Function response. In particular,
/// HTML from a gateway or wrong endpoint is never retained in an exception.
ClassroomException activityLearningMaterialFunctionFailure(
  int statusCode,
  Object? body, {
  required bool receivedNonJson,
}) {
  if (receivedNonJson) {
    return ClassroomException.fromFunction(
      ClassroomError.endpointUnavailable,
      httpStatus: statusCode,
      serverCode: 'non_json_function_response',
    );
  }
  final serverCode = body is Map ? body['error'] : null;
  final code = switch (statusCode) {
    HttpStatus.unauthorized || HttpStatus.forbidden => ClassroomError.forbidden,
    HttpStatus.notFound => ClassroomError.notFound,
    HttpStatus.badRequest => ClassroomError.malformed,
    HttpStatus.conflict => ClassroomError.conflict,
    _ => ClassroomError.invalidState,
  };
  return ClassroomException.fromFunction(
    code,
    httpStatus: statusCode,
    serverCode: serverCode is String ? serverCode : null,
  );
}
