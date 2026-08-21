import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/models/phase6_submission_diagnostics.dart';

/// Tiny non-empty payload for the isolated Storage -> Firestore diagnostic.
final Uint8List storageCrossServiceProbeBytes = Uint8List.fromList(
  List<int>.filled(128, 0x43),
);

const bool kStorageCrossServiceProbeDartDefine =
    bool.fromEnvironment('ELIXR_STORAGE_CROSS_SERVICE_PROBE') ||
    String.fromEnvironment('ELIXR_STORAGE_CROSS_SERVICE_PROBE') == '1';

const String kStorageCrossServiceProbeTraineeId =
    'OeflNaVfBkZ93BLOsGhRyOv6WAD3';

const String kStorageCrossServiceProbeContentType = 'application/octet-stream';

const List<String> kStorageCrossServiceProbeCases = [
  'request_local',
  'membership_one_get',
  'assignment_one_get',
  'two_gets',
];

enum StorageCrossServiceProbeRemoteCleanup { success, failure, notCreated }

class StorageCrossServiceProbeCaseResult {
  const StorageCrossServiceProbeCaseResult({
    required this.caseName,
    required this.uploadSucceeded,
    required this.remoteCleanup,
    required this.storagePath,
    this.plugin,
    this.code,
    this.safeMessage,
  });

  final String caseName;
  final bool uploadSucceeded;
  final StorageCrossServiceProbeRemoteCleanup remoteCleanup;
  final String storagePath;
  final String? plugin;
  final String? code;
  final String? safeMessage;
}

class StorageCrossServiceProbeSuiteResult {
  const StorageCrossServiceProbeSuiteResult({
    required this.invoked,
    required this.cases,
    this.uid,
    this.bucket,
    this.sizeBytes,
    this.firstFailure,
    this.errorType,
    this.plugin,
    this.code,
    this.safeMessage,
  });

  final bool invoked;
  final List<StorageCrossServiceProbeCaseResult> cases;
  final String? uid;
  final String? bucket;
  final int? sizeBytes;
  final String? firstFailure;
  final String? errorType;
  final String? plugin;
  final String? code;
  final String? safeMessage;

  bool get allSucceeded =>
      invoked &&
      firstFailure == null &&
      cases.length == kStorageCrossServiceProbeCases.length &&
      cases.every((result) => result.uploadSucceeded);
}

typedef StorageCrossServiceUpload =
    Future<void> Function({
      required Uint8List bytes,
      required String storagePath,
      required String contentType,
    });

typedef StorageCrossServiceDelete = Future<void> Function(String storagePath);

String storageCrossServiceProbePath({
  required String traineeId,
  required String probeName,
}) {
  return '__elixr_diagnostics__/phase6_cross_service/'
      '$traineeId/$probeName.bin';
}

void storageCrossServiceProbeDefaultLog(String line) {
  if (kDebugMode) {
    debugPrint(line);
  }
}

Future<StorageCrossServiceProbeSuiteResult?>
maybeRunLiveStorageCrossServiceProbe({
  bool? debugMode,
  bool? dartDefineEnabled,
  Future<StorageCrossServiceProbeSuiteResult> Function()? runLive,
}) async {
  final enabledDebug = debugMode ?? kDebugMode;
  final enabledDefine =
      dartDefineEnabled ?? kStorageCrossServiceProbeDartDefine;
  if (!enabledDebug || !enabledDefine) {
    return null;
  }
  final runner = runLive ?? runLiveStorageCrossServiceProbe;
  return runner();
}

/// Live production-bucket diagnostic. No-op in Release.
/// Does not create or mutate Firestore documents.
Future<StorageCrossServiceProbeSuiteResult> runLiveStorageCrossServiceProbe({
  bool debugMode = kDebugMode,
  String? Function()? readUid,
  String? Function()? readBucket,
  FirebaseStorage? storage,
  Uint8List? payload,
  void Function(String line)? log,
}) {
  final resolvedStorage = storage ?? FirebaseStorage.instance;
  return runStorageCrossServiceProbe(
    debugMode: debugMode,
    uid: (readUid ?? () => FirebaseAuth.instance.currentUser?.uid)(),
    bucket: (readBucket ?? () => resolvedStorage.bucket)(),
    payload: payload ?? storageCrossServiceProbeBytes,
    log: log ?? storageCrossServiceProbeDefaultLog,
    putData:
        ({required bytes, required storagePath, required contentType}) async {
          await resolvedStorage
              .ref(storagePath)
              .putData(bytes, SettableMetadata(contentType: contentType));
        },
    deleteRemote: (storagePath) => resolvedStorage.ref(storagePath).delete(),
  );
}

Future<StorageCrossServiceProbeSuiteResult> runStorageCrossServiceProbe({
  required bool debugMode,
  required String? uid,
  required String? bucket,
  required Uint8List payload,
  required void Function(String line) log,
  required StorageCrossServiceUpload putData,
  required StorageCrossServiceDelete deleteRemote,
}) async {
  if (!debugMode) {
    return const StorageCrossServiceProbeSuiteResult(invoked: false, cases: []);
  }

  if (uid == null || uid.isEmpty) {
    log(
      '[StorageCrossServiceProbe]\n'
      'case=request_local\n'
      'result=failure\n'
      'error_type=Unauthenticated',
    );
    log('[StorageCrossServiceProbe] remote_cleanup=not_created');
    return const StorageCrossServiceProbeSuiteResult(
      invoked: false,
      cases: [],
      firstFailure: 'request_local',
      errorType: 'Unauthenticated',
    );
  }

  if (uid != kStorageCrossServiceProbeTraineeId) {
    log(
      '[StorageCrossServiceProbe]\n'
      'case=request_local\n'
      'result=failure\n'
      'error_type=WrongTrainee',
    );
    log('[StorageCrossServiceProbe] remote_cleanup=not_created');
    return StorageCrossServiceProbeSuiteResult(
      invoked: false,
      cases: const [],
      uid: uid,
      bucket: bucket,
      firstFailure: 'request_local',
      errorType: 'WrongTrainee',
    );
  }

  final sizeBytes = payload.length;
  final caseResults = <StorageCrossServiceProbeCaseResult>[];
  String? firstFailure;
  String? errorType;
  String? plugin;
  String? code;
  String? safeMessage;

  for (final caseName in kStorageCrossServiceProbeCases) {
    final storagePath = storageCrossServiceProbePath(
      traineeId: uid,
      probeName: caseName,
    );
    var uploaded = false;
    var uploadSucceeded = false;
    var remoteCleanup = StorageCrossServiceProbeRemoteCleanup.notCreated;
    String? casePlugin;
    String? caseCode;
    String? caseMessage;

    try {
      await putData(
        bytes: payload,
        storagePath: storagePath,
        contentType: kStorageCrossServiceProbeContentType,
      );
      uploaded = true;
      uploadSucceeded = true;
      log(
        '[StorageCrossServiceProbe]\n'
        'case=$caseName\n'
        'result=success',
      );
    } on FirebaseException catch (error) {
      errorType = 'FirebaseException';
      casePlugin = sanitizePhase6DiagnosticText(error.plugin);
      caseCode = sanitizePhase6DiagnosticText(error.code);
      plugin = casePlugin;
      code = caseCode;
      final message = error.message;
      caseMessage = message == null || message.isEmpty
          ? null
          : sanitizePhase6DiagnosticText(message);
      safeMessage = caseMessage;
      log(
        '[StorageCrossServiceProbe]\n'
        'case=$caseName\n'
        'result=failure\n'
        'plugin=$casePlugin\n'
        'code=$caseCode'
        '${caseMessage == null ? '' : '\nmessage=$caseMessage'}',
      );
    } catch (error) {
      errorType = error.runtimeType.toString();
      caseMessage = sanitizePhase6DiagnosticText(error.toString());
      safeMessage = caseMessage;
      log(
        '[StorageCrossServiceProbe]\n'
        'case=$caseName\n'
        'result=failure\n'
        'message=$caseMessage',
      );
    }

    if (uploaded) {
      try {
        await deleteRemote(storagePath);
        remoteCleanup = StorageCrossServiceProbeRemoteCleanup.success;
      } catch (_) {
        remoteCleanup = StorageCrossServiceProbeRemoteCleanup.failure;
      }
      log(
        '[StorageCrossServiceProbe] remote_cleanup='
        '${remoteCleanup == StorageCrossServiceProbeRemoteCleanup.success ? 'success' : 'failure'}',
      );
    } else {
      log('[StorageCrossServiceProbe] remote_cleanup=not_created');
    }

    caseResults.add(
      StorageCrossServiceProbeCaseResult(
        caseName: caseName,
        uploadSucceeded: uploadSucceeded,
        remoteCleanup: remoteCleanup,
        storagePath: storagePath,
        plugin: casePlugin,
        code: caseCode,
        safeMessage: caseMessage,
      ),
    );

    if (!uploadSucceeded) {
      firstFailure = caseName;
      break;
    }
  }

  return StorageCrossServiceProbeSuiteResult(
    invoked: true,
    cases: caseResults,
    uid: uid,
    bucket: bucket,
    sizeBytes: sizeBytes,
    firstFailure: firstFailure,
    errorType: errorType,
    plugin: plugin,
    code: code,
    safeMessage: safeMessage,
  );
}
