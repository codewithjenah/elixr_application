import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:supabase/supabase.dart';

/// Process-wide Supabase client used by repositories constructed without an
/// explicit client. The app registers it once after `Supabase.initialize`.
abstract final class ElixrSupabase {
  static SupabaseClient? _client;

  static void configure(SupabaseClient client) => _client = client;

  static SupabaseClient get client {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase has not been initialized for ELIXR.');
    }
    return client;
  }
}

/// Removes null-valued columns so rows parse like the former documents, where
/// optional fields were absent rather than null.
Map<String, dynamic> compactRow(Map<dynamic, dynamic> row) => {
  for (final entry in row.entries)
    if (entry.value != null) '${entry.key}': entry.value,
};

Map<String, dynamic> asRowMap(Object? value) {
  if (value is Map) return compactRow(value);
  throw const FormatException('Expected a JSON object from the database.');
}

final _random = Random.secure();
const _idAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Opaque 20-character client-allocated identifier (same shape as the IDs
/// already persisted), safe to reuse across retries of one write.
String newDocumentId() => List.generate(
  20,
  (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
).join();

/// Stable error code for a database RPC failure (the RPC's `message`), a
/// storage failure (HTTP status) or an auth failure.
String? backendErrorCode(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is StorageException) return error.statusCode;
  if (error is AuthException) return error.code ?? error.statusCode;
  return null;
}

bool isPermissionDeniedError(Object error) {
  if (error is PostgrestException) {
    return error.code == '42501' ||
        error.code == '28000' ||
        error.message == 'forbidden' ||
        error.message.contains('row-level security') ||
        error.message.contains('permission denied');
  }
  if (error is StorageException) {
    return error.statusCode == '403' ||
        error.statusCode == '401' ||
        error.message.toLowerCase().contains('row-level security');
  }
  return false;
}

bool isStorageObjectNotFound(Object error) {
  if (error is! StorageException) return false;
  return error.statusCode == '404' ||
      error.statusCode == '400' &&
          error.message.toLowerCase().contains('not found') ||
      error.message.toLowerCase().contains('object not found');
}

/// Transport-level failures where retrying later (or using the offline
/// snapshot) is appropriate. Server rejections are never classified here.
bool isBackendUnavailableError(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is HttpException ||
      error is HandshakeException ||
      error is AuthRetryableFetchException) {
    return true;
  }
  final text = error.toString();
  return text.contains('ClientException') ||
      text.contains('SocketException') ||
      text.contains('Connection refused') ||
      text.contains('Failed host lookup');
}

/// Maps a persisted object path (identical to the former Firebase Storage
/// path) to its private Supabase bucket.
String storageBucketForPath(String path) {
  if (path.startsWith('users/')) {
    final parts = path.split('/');
    if (parts.length >= 3) {
      switch (parts[2]) {
        case 'profile':
          return 'profile-images';
        case 'session_evidence':
          return 'session-evidence';
        case 'custom_movement_references':
          return 'custom-movement-references';
      }
    }
  } else if (path.startsWith('assignment_submissions/')) {
    return 'assignment-submissions';
  } else if (path.startsWith('teacher_activity_demos/')) {
    return 'teacher-activity-demos';
  } else if (path.startsWith('activity_material_staging/') ||
      path.startsWith('activity_learning_materials/')) {
    return 'activity-learning-materials';
  }
  throw ArgumentError.value(path, 'path', 'No storage bucket for this path');
}

/// Storage file API for a persisted object path.
StorageFileApi storageFor(SupabaseClient client, String path) =>
    client.storage.from(storageBucketForPath(path));

Future<Map<String, dynamic>> rpcMap(
  SupabaseClient client,
  String function, [
  Map<String, dynamic>? params,
]) async {
  final result = await client.rpc<dynamic>(function, params: params);
  return asRowMap(result);
}

/// Parses an RPC returning a JSON array of objects.
List<Map<String, dynamic>> rowsFrom(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected a JSON array from the database.');
  }
  return [
    for (final item in value)
      if (item is Map) compactRow(item),
  ];
}
