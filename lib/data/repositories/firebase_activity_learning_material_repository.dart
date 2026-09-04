import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/activity_learning_material.dart';
import '../models/classroom_exceptions.dart';
import 'activity_learning_material_repository.dart';

/// Thin client for the server-authoritative Activity Learning Material API.
/// It has no authority to create final objects or metadata: Firebase Storage is
/// used only for the exact quarantine upload path returned by Functions.
class FirebaseActivityLearningMaterialRepository
    implements ActivityLearningMaterialRepository {
  FirebaseActivityLearningMaterialRepository({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_ASSIGNMENTS_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;

  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) async {
    final decoded = await _post('beginActivityMaterialUpload', {
      'assignment_id': assignmentId,
      'type': type.wireValue,
      'display_name': displayName.trim(),
      'declared_content_type': declaredContentType.trim().toLowerCase(),
      'size_bytes': sizeBytes,
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
    await _storage
        .ref(upload.stagingPath)
        .putFile(
          file,
          SettableMetadata(contentType: upload.declaredContentType),
        );
  }

  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) async {
    final decoded = await _post('getActivityMaterialUploadStatus', {
      'upload_id': uploadId,
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
  }) async {
    final decoded = await _post('addActivityLearningMaterialLink', {
      'assignment_id': assignmentId,
      'display_name': displayName.trim(),
      'url': url.toString(),
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
    await _post('removeActivityLearningMaterial', {
      'assignment_id': assignmentId,
      'material_id': materialId,
    });
  }

  @override
  Future<List<ActivityLearningMaterial>> list({
    required String assignmentId,
  }) async {
    final decoded = await _post('listActivityLearningMaterials', {
      'assignment_id': assignmentId,
    });
    final raw = decoded['materials'];
    if (raw is! List) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final materials = <ActivityLearningMaterial>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      final parsed = ActivityLearningMaterial.tryFromMap(
        Map<String, dynamic>.from(item),
      );
      if (parsed == null || parsed.assignmentId != assignmentId) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      materials.add(parsed);
    }
    return List.unmodifiable(materials);
  }

  @override
  Future<File> openFile(ActivityLearningMaterial material) async {
    if (material.type == ActivityLearningMaterialType.link ||
        material.storagePath == null) {
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
    final safeId = material.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      '${directory.path}${Platform.pathSeparator}material_$safeId.$extension',
    );
    // A cache entry is never a read capability. Re-check the authenticated
    // Storage object before returning it so removals and access revocations
    // take effect even when ELIXR still has local bytes.
    final reference = referenceFor(material);
    if (await file.exists()) {
      await reference.getMetadata();
      final age = DateTime.now().difference(await file.lastModified());
      final sizeMatches =
          material.sizeBytes == null ||
          await file.length() == material.sizeBytes;
      if (age < const Duration(hours: 24) && sizeMatches) {
        return file;
      }
    }
    try {
      await reference.writeToFile(file);
      if (material.sizeBytes != null &&
          await file.length() != material.sizeBytes) {
        await file.delete();
        throw const ClassroomException(ClassroomError.malformed);
      }
      return file;
    } on FirebaseException {
      if (await file.exists()) await file.delete();
      throw const ClassroomException(ClassroomError.notFound);
    }
  }

  Future<void> _clearStaleMaterialCache(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        final isManagedMaterial =
            entity is File &&
            entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('material_');
        if (!isManagedMaterial) {
          continue;
        }
        if (DateTime.now().difference(await entity.lastModified()) >
            const Duration(days: 7)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Cache cleanup is opportunistic. A locked file may still be open in a
      // Windows viewer and must not make an authorized material unavailable.
    }
  }

  /// Returns an authenticated Storage reference for a file material. Storage
  /// rules enforce the same server-owned projection at read time, so a stale
  /// metadata response cannot become a download capability.
  Reference referenceFor(ActivityLearningMaterial material) {
    final path = material.storagePath;
    if (path == null || path.isEmpty) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _storage.ref(path);
  }

  Future<Map<String, dynamic>> _post(
    String functionName,
    Map<String, Object?> payload,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ClassroomException(ClassroomError.forbidden);
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(apiBaseUri.resolve(functionName))
          .timeout(requestTimeout);
      request.headers.set('X-Firebase-Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(requestTimeout);
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      Object? decoded;
      try {
        decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      } on FormatException {
        if (response.statusCode == HttpStatus.ok) rethrow;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw _functionFailure(response.statusCode, decoded);
      }
      if (decoded is! Map) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      return Map<String, dynamic>.from(decoded);
    } on ClassroomException {
      rethrow;
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FirebaseException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FormatException {
      throw const ClassroomException(ClassroomError.malformed);
    } finally {
      client.close(force: true);
    }
  }

  static ClassroomException _functionFailure(int statusCode, Object? body) {
    final serverCode = body is Map ? body['error'] : null;
    final code = switch (statusCode) {
      HttpStatus.unauthorized ||
      HttpStatus.forbidden => ClassroomError.forbidden,
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
}
