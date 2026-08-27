import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/features/assigned_movements/widgets/submission_detail_body.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _teacherAssignment() {
  return const GroupAssignment(
    id: 'asg-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Basic Bottle Balances',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
  );
}

GroupAssignment _officialAssignment() {
  return const GroupAssignment(
    id: 'asg-official',
    teacherId: 'teacher-1',
    groupId: 'g1',
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Hand Stall',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    officialMovementName: 'Hand Stall',
  );
}

AssignmentAttempt _approvedExpired({required String feedback}) {
  return AssignmentAttempt(
    id: 'attempt-approved',
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: 'asg-1',
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.approved,
    videoContentType: 'video/mp4',
    videoSizeBytes: 2048,
    videoDurationMs: 4000,
    submittedAt: DateTime.utc(2026, 8, 10, 12),
    videoExpiresAt: DateTime.utc(2026, 8, 24),
    videoDeletedAt: DateTime.utc(2026, 8, 25),
    reviewVerdict: AssignmentReviewVerdict.approved,
    reviewFeedback: feedback,
    reviewedAt: DateTime.utc(2026, 8, 12, 9),
    createdAt: DateTime.utc(2026, 8, 10, 12),
  );
}

AssignmentAttempt _officialPointer() {
  return AssignmentAttempt(
    id: 'attempt-official',
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: 'asg-official',
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    attemptKind: AssignmentAttemptKind.practicePointer,
    status: AssignmentAttemptStatus.submitted,
    sourceSessionId: 'session-1',
    rubric: const RubricAssessment(
      technique: 3,
      stability: 2,
      completion: 2,
      propPositioning: 1,
    ),
    durationSeconds: 42,
    completedAt: DateTime.utc(2026, 8, 20, 8, 30),
    createdAt: DateTime.utc(2026, 8, 20, 8, 30),
  );
}

Future<void> _pumpBody(
  WidgetTester tester, {
  required GroupAssignment assignment,
  required AssignmentAttempt attempt,
  Future<void> Function()? releaseLocalPlayback,
  Future<SubmissionPlaybackFile?> Function(AssignmentAttempt attempt)?
  openLocalPlayback,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.light,
      home: ScaffoldPage(
        content: SingleChildScrollView(
          child: SubmissionDetailBody(
            assignment: assignment,
            attempt: attempt,
            viewerRole: SubmissionDetailViewerRole.trainee,
            releaseLocalPlayback: releaseLocalPlayback,
            openLocalPlayback: openLocalPlayback,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

AssignmentAttempt _submittedClip() {
  return AssignmentAttempt(
    id: 'attempt-clip',
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: 'asg-1',
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.submitted,
    videoStoragePath:
        'assignment_submissions/teacher-1/g1/asg-1/trainee-1/attempt-clip.mp4',
    videoContentType: 'video/mp4',
    videoSizeBytes: 2048,
    videoDurationMs: 4000,
    submittedAt: DateTime.utc(2026, 8, 27, 4),
    videoExpiresAt: DateTime.utc(2026, 9, 26),
    createdAt: DateTime.utc(2026, 8, 27, 4),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'expired video shows retention empty state and approved feedback',
    (tester) async {
      await _pumpBody(
        tester,
        assignment: _teacherAssignment(),
        attempt: _approvedExpired(
          feedback: 'Clean catch. Hold longer next time.',
        ),
      );

      expect(
        find.byKey(const Key('submission_retention_empty')),
        findsOneWidget,
      );
      expect(find.textContaining('30 days'), findsOneWidget);
      expect(find.textContaining('14 days'), findsOneWidget);
      expect(
        find.byKey(const Key('submission_review_feedback')),
        findsOneWidget,
      );
      expect(find.text('Clean catch. Hold longer next time.'), findsOneWidget);
      expect(find.textContaining('Approved'), findsWidgets);
    },
  );

  testWidgets('official guided attempt renders rubric total and criteria', (
    tester,
  ) async {
    await _pumpBody(
      tester,
      assignment: _officialAssignment(),
      attempt: _officialPointer(),
    );
    await tester.pump();

    expect(find.byKey(const Key('submission_official_rubric')), findsOneWidget);
    expect(
      find.byKey(const Key('submission_official_no_clip')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('submission_clip_preview')), findsNothing);
    expect(find.textContaining('8 / 12'), findsOneWidget);
    expect(find.textContaining('Competent'), findsOneWidget);
    expect(find.textContaining('Correct Technique: 3/3'), findsOneWidget);
    expect(find.textContaining('Stability / Control: 2/3'), findsOneWidget);
    expect(find.textContaining('Hold / Completion: 2/3'), findsOneWidget);
    expect(find.textContaining('Prop Positioning: 1/3'), findsOneWidget);
    expect(find.text('AI coaching'), findsNothing);
    expect(find.textContaining('does not save a video clip'), findsOneWidget);
  });

  testWidgets('dispose releases playback even when the clip is gone', (
    tester,
  ) async {
    var released = 0;
    await _pumpBody(
      tester,
      assignment: _teacherAssignment(),
      attempt: _approvedExpired(feedback: 'Nice work.'),
      releaseLocalPlayback: () async => released++,
    );
    expect(released, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(released, 1);
  });

  testWidgets(
    'teacher-reviewed submission offers a clip preview and loads playback',
    (tester) async {
      AssignmentAttempt? opened;
      await _pumpBody(
        tester,
        assignment: _teacherAssignment(),
        attempt: _submittedClip(),
        openLocalPlayback: (attempt) async {
          opened = attempt;
          return null;
        },
      );
      await tester.pump();

      expect(find.byKey(const Key('submission_clip_preview')), findsOneWidget);
      expect(
        find.byKey(const Key('submission_official_no_clip')),
        findsNothing,
      );
      expect(find.text('Your clip'), findsOneWidget);
      expect(opened?.id, 'attempt-clip');
    },
  );
}
