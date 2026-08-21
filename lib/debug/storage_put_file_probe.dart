import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/models/phase6_submission_diagnostics.dart';

/// 1x1 transparent PNG used only by the debug putFile transport probe.
final Uint8List storagePutFileProbePngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const bool kStoragePutFileProbeDartDefine =
    bool.fromEnvironment('ELIXR_STORAGE_PUTFILE_PROBE') ||
    String.fromEnvironment('ELIXR_STORAGE_PUTFILE_PROBE') == '1';

enum StoragePutFileProbeRemoteCleanup { success, failure, notCreated }

enum StoragePutFileProbeLocalCleanup { success, failure }

class StoragePutFileProbeResult {
  const StoragePutFileProbeResult({
    required this.invoked,
    required this.uploadSucceeded,
    required this.remoteCleanup,
    required this.localCleanup,
    this.uid,
    this.bucket,
    this.sizeBytes,
    this.errorType,
    this.plugin,
    this.code,
    this.safeMessage,
  });

  final bool invoked;
  final bool uploadSucceeded;
  final StoragePutFileProbeRemoteCleanup remoteCleanup;
  final StoragePutFileProbeLocalCleanup localCleanup;
  final String? uid;
  final String? bucket;
  final int? sizeBytes;
  final String? errorType;
  final String? plugin;
  final String? code;
  final String? safeMessage;
}

typedef StoragePutFileUpload =
    Future<void> Function({
      required File file,
      required String storagePath,
      required String contentType,
    });

typedef StoragePutFileDelete = Future<void> Function(String storagePath);

void storagePutFileProbeDefaultLog(String line) {
  if (kDebugMode) {
    debugPrint(line);
  }
}

Future<StoragePutFileProbeResult?> maybeRunLiveStoragePutFileProbe({
  bool? debugMode,
  bool? dartDefineEnabled,
  Future<StoragePutFileProbeResult> Function()? runLive,
}) async {
  final enabledDebug = debugMode ?? kDebugMode;
  final enabledDefine = dartDefineEnabled ?? kStoragePutFileProbeDartDefine;
  if (!enabledDebug || !enabledDefine) {
    return null;
  }
  final runner = runLive ?? runLiveStoragePutFileProbe;
  return runner();
}

/// Live production-bucket probe. No-op in Release.
Future<StoragePutFileProbeResult> runLiveStoragePutFileProbe({
  bool debugMode = kDebugMode,
  String? Function()? readUid,
  String? Function()? readBucket,
  FirebaseStorage? storage,
  Directory? tempDirectory,
  DateTime Function()? now,
  Uint8List? imageBytes,
  String contentType = 'image/png',
  void Function(String line)? log,
}) {
  final resolvedStorage = storage ?? FirebaseStorage.instance;
  return runStoragePutFileProbe(
    debugMode: debugMode,
    uid: (readUid ?? () => FirebaseAuth.instance.currentUser?.uid)(),
    bucket: (readBucket ?? () => resolvedStorage.bucket)(),
    imageBytes: imageBytes ?? storagePutFileProbePngBytes,
    contentType: contentType,
    tempDirectory: tempDirectory ?? Directory.systemTemp,
    now: now?.call() ?? DateTime.now(),
    log: log ?? storagePutFileProbeDefaultLog,
    putFile:
        ({required file, required storagePath, required contentType}) async {
          await resolvedStorage
              .ref(storagePath)
              .putFile(file, SettableMetadata(contentType: contentType));
        },
    deleteRemote: (storagePath) => resolvedStorage.ref(storagePath).delete(),
  );
}

Future<StoragePutFileProbeResult> runStoragePutFileProbe({
  required bool debugMode,
  required String? uid,
  required String? bucket,
  required Uint8List imageBytes,
  required String contentType,
  required Directory tempDirectory,
  required DateTime now,
  required void Function(String line) log,
  required StoragePutFileUpload putFile,
  required StoragePutFileDelete deleteRemote,
}) async {
  if (!debugMode) {
    return const StoragePutFileProbeResult(
      invoked: false,
      uploadSucceeded: false,
      remoteCleanup: StoragePutFileProbeRemoteCleanup.notCreated,
      localCleanup: StoragePutFileProbeLocalCleanup.success,
    );
  }

  if (uid == null || uid.isEmpty) {
    log(
      '[StoragePutFileProbe]\n'
      'result=failure\n'
      'error_type=Unauthenticated',
    );
    log('[StoragePutFileProbe] remote_cleanup=not_created');
    log('[StoragePutFileProbe] local_cleanup=success');
    return const StoragePutFileProbeResult(
      invoked: false,
      uploadSucceeded: false,
      remoteCleanup: StoragePutFileProbeRemoteCleanup.notCreated,
      localCleanup: StoragePutFileProbeLocalCleanup.success,
      errorType: 'Unauthenticated',
    );
  }

  final sizeBytes = imageBytes.length;
  final storagePath =
      'users/$uid/profile/transport_probe_${now.millisecondsSinceEpoch}.png';
  log(
    '[StoragePutFileProbe]\n'
    'uid=$uid\n'
    'bucket=$bucket\n'
    'content_type=$contentType\n'
    'size_bytes=$sizeBytes',
  );

  File? tempFile;
  var uploaded = false;
  var remoteCleanup = StoragePutFileProbeRemoteCleanup.notCreated;
  var localCleanup = StoragePutFileProbeLocalCleanup.success;
  String? errorType;
  String? plugin;
  String? code;
  String? safeMessage;
  var uploadSucceeded = false;

  try {
    tempFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}'
      'elixr_transport_probe_${now.millisecondsSinceEpoch}.png',
    );
    await tempFile.writeAsBytes(imageBytes, flush: true);
    await putFile(
      file: tempFile,
      storagePath: storagePath,
      contentType: contentType,
    );
    uploaded = true;
    uploadSucceeded = true;
    log('[StoragePutFileProbe] result=success bytes=$sizeBytes');
  } on FirebaseException catch (error) {
    errorType = 'FirebaseException';
    plugin = sanitizePhase6DiagnosticText(error.plugin);
    code = sanitizePhase6DiagnosticText(error.code);
    final message = error.message;
    safeMessage = message == null || message.isEmpty
        ? null
        : sanitizePhase6DiagnosticText(message);
    log(
      '[StoragePutFileProbe]\n'
      'result=failure\n'
      'error_type=FirebaseException\n'
      'plugin=$plugin\n'
      'code=$code'
      '${safeMessage == null ? '' : '\nmessage=$safeMessage'}',
    );
  } catch (error) {
    errorType = error.runtimeType.toString();
    safeMessage = sanitizePhase6DiagnosticText(error.toString());
    log(
      '[StoragePutFileProbe]\n'
      'result=failure\n'
      'error_type=$errorType\n'
      'message=$safeMessage',
    );
  } finally {
    if (uploaded) {
      try {
        await deleteRemote(storagePath);
        remoteCleanup = StoragePutFileProbeRemoteCleanup.success;
      } catch (_) {
        remoteCleanup = StoragePutFileProbeRemoteCleanup.failure;
      }
      log(
        '[StoragePutFileProbe] remote_cleanup='
        '${remoteCleanup == StoragePutFileProbeRemoteCleanup.success ? 'success' : 'failure'}',
      );
    } else {
      log('[StoragePutFileProbe] remote_cleanup=not_created');
    }

    try {
      if (tempFile != null && tempFile.existsSync()) {
        await tempFile.delete();
      }
      localCleanup = StoragePutFileProbeLocalCleanup.success;
    } catch (_) {
      localCleanup = StoragePutFileProbeLocalCleanup.failure;
    }
    log(
      '[StoragePutFileProbe] local_cleanup='
      '${localCleanup == StoragePutFileProbeLocalCleanup.success ? 'success' : 'failure'}',
    );
  }

  return StoragePutFileProbeResult(
    invoked: true,
    uploadSucceeded: uploadSucceeded,
    remoteCleanup: remoteCleanup,
    localCleanup: localCleanup,
    uid: uid,
    bucket: bucket,
    sizeBytes: sizeBytes,
    errorType: errorType,
    plugin: plugin,
    code: code,
    safeMessage: safeMessage,
  );
}
