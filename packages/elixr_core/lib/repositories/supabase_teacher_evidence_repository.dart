import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import 'teacher_evidence_repository.dart';

typedef TeacherEvidenceDownload = Future<Uint8List> Function(String path);

/// Downloads a Trainee's private evidence still. Storage policies grant the
/// read only to the owner or a Teacher with a current evidence grant or
/// classroom authorization while the Trainee's consent is enabled.
class SupabaseTeacherEvidenceRepository implements TeacherEvidenceRepository {
  SupabaseTeacherEvidenceRepository({
    SupabaseClient? client,
    TeacherEvidenceDownload? downloadData,
  }) : _clientOverride = client,
       _downloadData = downloadData;

  final SupabaseClient? _clientOverride;
  final TeacherEvidenceDownload? _downloadData;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static String pathFor({
    required String traineeId,
    required String sessionId,
  }) => 'users/$traineeId/session_evidence/$sessionId.jpg';

  @override
  Future<Uint8List?> downloadEvidence({
    required String traineeId,
    required String sessionId,
  }) async {
    final path = pathFor(traineeId: traineeId, sessionId: sessionId);
    final Uint8List bytes;
    try {
      bytes =
          await (_downloadData?.call(path) ??
              storageFor(_client, path).download(path));
    } on StorageException catch (error) {
      // A stale projection may point at a missing object: that is an expected
      // no-image state. Denied and transient failures stay visible.
      if (isStorageObjectNotFound(error)) return null;
      rethrow;
    }
    if (bytes.lengthInBytes > TeacherEvidenceRepository.maximumBytes) {
      throw StateError('Evidence image exceeds the download limit.');
    }
    return bytes;
  }
}
