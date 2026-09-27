import 'dart:typed_data';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, StorageException, SupabaseClient;

/// Private Storage access for one confirmed-movement image per session.
class SessionEvidenceRepository {
  SessionEvidenceRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static const _bucket = 'session-evidence';
  static const _maxBytes = 256 * 1024;

  static String pathFor({required String userId, required String sessionId}) =>
      'users/$userId/session_evidence/$sessionId.jpg';

  /// Whether [upload] and the database evidence constraint accept this size.
  static bool acceptsJpegSize(int bytes) => bytes >= 1024 && bytes <= _maxBytes;

  Future<void> upload({
    required String userId,
    required String sessionId,
    required Uint8List jpegBytes,
  }) async {
    if (!acceptsJpegSize(jpegBytes.lengthInBytes)) {
      throw ArgumentError.value(
        jpegBytes.lengthInBytes,
        'jpegBytes',
        'Evidence JPEG must be 1–256 KiB',
      );
    }
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          pathFor(userId: userId, sessionId: sessionId),
          jpegBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
  }

  Future<Uint8List?> download(String storagePath) async {
    final bytes = await _client.storage.from(_bucket).download(storagePath);
    if (bytes.lengthInBytes > _maxBytes) {
      throw StateError('Evidence object exceeds the download limit.');
    }
    return bytes;
  }

  /// Reconciles retained private evidence into the sanitized projection before
  /// a per-Teacher grant becomes effective. No Storage path is projected, and
  /// only already-published projections are updated server-side.
  Future<void> reconcilePublicEvidenceAvailability(String userId) async {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Evidence can only be reconciled by its owner.');
    }
    await _client.rpc<dynamic>('reconcile_public_evidence_availability');
  }

  /// Idempotently removes evidence objects and their session references.
  /// Storage is purged first: a failure leaves the database references intact
  /// so the user can retry rather than losing track of an object.
  Future<void> deleteAllForUser(String userId) async {
    final storage = _client.storage.from(_bucket);
    final prefix = 'users/$userId/session_evidence';
    while (true) {
      final listed = await storage.list(path: prefix);
      final paths = [
        for (final item in listed)
          if (item.id != null) '$prefix/${item.name}',
      ];
      if (paths.isEmpty) break;
      try {
        await storage.remove(paths);
      } on StorageException catch (error) {
        if (!isStorageObjectNotFound(error)) rethrow;
      }
      if (paths.length < 100) break;
    }
    await _client.rpc<dynamic>('clear_session_evidence_metadata');
  }
}
