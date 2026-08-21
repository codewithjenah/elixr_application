import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/phase6_submission_diagnostics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

AssignmentAttempt draftAttempt({
  String id = 'review_sub_prodshaped1',
  String teacherId = 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
  String traineeId = 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
  DateTime? abandonedAt,
  AssignmentAttemptStatus status = AssignmentAttemptStatus.draft,
}) {
  return AssignmentAttempt(
    id: id,
    traineeId: traineeId,
    teacherId: teacherId,
    groupId: 'i0CaSM4nEA9sNuKSRagO',
    assignmentId: 'ENvAezoRemcyihux3wpP',
    movementId: 'CYdQM78YMPbLTCTblERB',
    revisionId: 'DNLnQUFnxmwUP0y5uIM9',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: status,
    abandonedAt: abandonedAt,
  );
}

Phase6StorageRequestSnapshot requestSnapshot({
  String? authUid = 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
  String storagePath =
      'assignment_submissions/WNFvwRJ4bzTFpVmsgv5x3qV2urt1/'
      'i0CaSM4nEA9sNuKSRagO/ENvAezoRemcyihux3wpP/'
      'OeflNaVfBkZ93BLOsGhRyOv6WAD3/review_sub_prodshaped1.mp4',
}) {
  return Phase6StorageRequestSnapshot(
    authUid: authUid,
    projectId: 'elixr-app-2026',
    bucket: 'elixr-app-2026.firebasestorage.app',
    attemptId: 'review_sub_prodshaped1',
    teacherId: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
    groupId: 'i0CaSM4nEA9sNuKSRagO',
    assignmentId: 'ENvAezoRemcyihux3wpP',
    traineeId: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
    movementId: 'CYdQM78YMPbLTCTblERB',
    revisionId: 'DNLnQUFnxmwUP0y5uIM9',
    storagePath: storagePath,
    fileSizeBytes: 2048,
    contentType: AssignmentSubmissionLimits.contentType,
    metadataKeys: assignmentSubmissionCustomMetadata(
      teacherId: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
      groupId: 'i0CaSM4nEA9sNuKSRagO',
      assignmentId: 'ENvAezoRemcyihux3wpP',
      traineeId: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
      attemptId: 'review_sub_prodshaped1',
      movementId: 'CYdQM78YMPbLTCTblERB',
      revisionId: 'DNLnQUFnxmwUP0y5uIM9',
    ).keys.toList(),
  );
}

void main() {
  test('storage request log includes ids and omits secrets', () {
    final line = formatPhase6StorageRequest(requestSnapshot());
    expect(line, startsWith('[Phase6StorageRequest]'));
    expect(line, contains('auth_uid=OeflNaVfBkZ93BLOsGhRyOv6WAD3'));
    expect(line, contains('project_id=elixr-app-2026'));
    expect(line, contains('bucket=elixr-app-2026.firebasestorage.app'));
    expect(line, contains('content_type=video/mp4'));
    expect(
      line,
      contains(
        'metadata_keys=assignment_id,attempt_id,group_id,movement_id,revision_id,teacher_id,trainee_id',
      ),
    );
    expect(line, contains('auth_uid_matches_trainee=true'));
    expect(line, contains('path_matches_expected=true'));
    expect(line, isNot(contains('AIza')));
    expect(line, isNot(contains('token')));
    expect(line, isNot(contains(r'C:\')));
    expect(line, isNot(contains('@')));
  });

  test('storage request flags uid and path mismatches', () {
    final line = formatPhase6StorageRequest(
      requestSnapshot(
        authUid: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
        storagePath: 'assignment_submissions/other/path.mp4',
      ),
    );
    expect(line, contains('auth_uid_matches_trainee=false'));
    expect(line, contains('path_matches_expected=false'));
  });

  test('durable draft identity matches are logged', () {
    final draft = draftAttempt();
    final line = formatPhase6StorageAnchor(draft: draft, durable: draft);
    expect(line, contains('attempt_exists=true'));
    expect(line, contains('status=draft'));
    expect(line, contains('abandoned=false'));
    expect(line, contains('awards_global_xp=false'));
    expect(line, contains('teacher_match=true'));
    expect(line, contains('group_match=true'));
    expect(line, contains('assignment_match=true'));
    expect(line, contains('trainee_match=true'));
    expect(line, contains('movement_match=true'));
    expect(line, contains('revision_match=true'));
    expect(line, contains('origin_match=true'));
    expect(line, contains('assessment_mode_match=true'));
  });

  test('missing durable draft logs non-matches', () {
    final line = formatPhase6StorageAnchor(
      draft: draftAttempt(),
      durable: null,
    );
    expect(line, contains('attempt_exists=false'));
    expect(line, contains('status=null'));
    expect(line, contains('abandoned=false'));
    expect(line, contains('awards_global_xp=null'));
    expect(line, contains('teacher_match=false'));
  });

  test('abandoned durable draft is reported', () {
    final line = formatPhase6StorageAnchor(
      draft: draftAttempt(),
      durable: draftAttempt(abandonedAt: DateTime.utc(2026, 8, 21)),
    );
    expect(line, contains('abandoned=true'));
    expect(line, contains('status=draft'));
  });

  test('durable draft read failure is logged and swallowed', () async {
    final logs = <String>[];
    await emitPhase6DurableDraftAnchor(
      draft: draftAttempt(),
      readAttempt: ({required attemptId}) async {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        );
      },
      diagnosticLog: logs.add,
    );
    expect(logs, hasLength(1));
    expect(logs.single, contains('[Phase6StorageAnchor] read_failed'));
    expect(logs.single, contains('plugin=cloud_firestore'));
    expect(logs.single, contains('code=permission-denied'));
    expect(logs.single, isNot(contains('token')));
  });

  test('debug pre-upload probes force-refresh the token once', () async {
    final logs = <String>[];
    var refreshCount = 0;
    await runPhase6DebugPreUploadProbes(
      request: requestSnapshot(),
      auth: Phase6StorageAuthProbe(
        uid: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
        forceRefreshIdToken: () async {
          refreshCount += 1;
        },
      ),
      log: logs.add,
    );
    expect(refreshCount, 1);
    expect(
      logs.where((line) => line.contains('[Phase6StorageRequest]')),
      isNotEmpty,
    );
    expect(
      logs,
      contains('[Phase6StorageAuth] uid=OeflNaVfBkZ93BLOsGhRyOv6WAD3'),
    );
    expect(logs, contains('[Phase6StorageAuth] token_refresh=forced'));
    expect(logs.join('\n'), isNot(contains('eyJ')));
    expect(logs.join('\n'), isNot(contains('Bearer')));
  });

  test(
    'debug pre-upload probes continue after token refresh failure',
    () async {
      final logs = <String>[];
      await runPhase6DebugPreUploadProbes(
        request: requestSnapshot(),
        auth: Phase6StorageAuthProbe(
          uid: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
          forceRefreshIdToken: () async {
            throw FirebaseException(
              plugin: 'firebase_auth',
              code: 'network-request-failed',
              message: 'id_token=abc.secret refresh_token=xyz',
            );
          },
        ),
        log: logs.add,
      );
      expect(
        logs.singleWhere((line) => line.contains('token_refresh_failed')),
        contains('code=network-request-failed'),
      );
      expect(logs.join('\n'), isNot(contains('abc.secret')));
      expect(logs.join('\n'), isNot(contains('xyz')));
    },
  );

  test('null auth skips token refresh', () async {
    final logs = <String>[];
    await runPhase6DebugPreUploadProbes(
      request: requestSnapshot(authUid: null),
      auth: const Phase6StorageAuthProbe(uid: null),
      log: logs.add,
    );
    expect(logs, contains('[Phase6StorageAuth] uid=null'));
    expect(logs, contains('[Phase6StorageAuth] token_refresh=skipped'));
  });
}
