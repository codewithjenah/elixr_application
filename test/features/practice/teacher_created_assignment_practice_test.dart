import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('teacher-created assignment practice always uses Free Practice', () {
    const assignment = GroupAssignment(
      id: 'asg1',
      teacherId: 'teacher-1',
      groupId: 'g1',
      movementId: 'tm1',
      revisionId: 'tm1_v1',
      origin: MovementOrigin.teacherCreated,
      assessmentMode: AssessmentMode.teacherReviewed,
      status: GroupAssignmentStatus.active,
      displayTitle: 'Tin Balance',
      teacherDisplayName: 'Grace Hopper',
      groupName: 'BSHM 4A',
      displayInstructions: 'Hold the tin upright.',
      allowedProp: TrainingProp.shaker,
    );
    const mode = TeacherCreatedAssignmentPractice(assignment: assignment);
    expect(
      TeacherCreatedAssignmentPractice.backendMovementName,
      'Free Practice',
    );
    expect(mode.title, 'Tin Balance');
    expect(mode.instructions, 'Hold the tin upright.');
    expect(mode.prop, TrainingProp.shaker);
  });

  test(
    'Teacher-created prepare payload uses Free Practice and assignment prop',
    () {
      final payload = WebSocketService.buildPreparePayload(
        movement: TeacherCreatedAssignmentPractice.backendMovementName,
        difficulty: 'Easy',
        prop: TrainingProp.bottle,
        cameraDeviceId: 'win32:integrated',
        sessionId: 'session-tc',
        requestId: 'req-tc',
      );
      expect(payload['action'], 'prepare');
      expect(payload['movement'], 'Free Practice');
      expect(payload['difficulty'], 'Easy');
      expect(payload['prop_type'], TrainingProp.bottle.protocolValue);
      expect(payload['bottle_detection_enabled'], isTrue);
      expect(payload['session_id'], 'session-tc');
      expect(payload['request_id'], 'req-tc');
      expect(payload['protocol_version'], 1);
      expect(payload.containsKey('camera_device_id'), isTrue);
      expect(payload.containsKey('camera_index'), isFalse);
      expect(payload.values, isNot(contains('Basic Bottle Balances')));
      expect(payload.keys, isNot(contains('assignment_id')));
      expect(payload.keys, isNot(contains('teacher_id')));
      expect(payload.keys, isNot(contains('group_id')));
      expect(payload.keys, isNot(contains('revision_id')));
    },
  );

  test('prepare failure messages stay user-safe', () {
    expect(
      livePracticePrepareFailureMessage(
        CommandTimeoutException('req', 'prepare'),
      ),
      contains('timed out'),
    );
    expect(
      livePracticePrepareFailureMessage(
        CommandDisconnectedException('req', 'prepare'),
      ),
      contains('Lost connection'),
    );
    expect(
      livePracticePrepareFailureMessage(
        CommandAckMismatchException(
          requestId: 'req',
          pendingAction: 'prepare',
          pendingSessionId: 's1',
          ackAction: 'activate',
          actionMismatch: true,
          sessionMismatch: false,
        ),
      ),
      contains('out of sync'),
    );
    expect(
      livePracticePrepareFailureMessage(
        StateError('A prepare command is already pending'),
      ),
      contains('Camera preparation failed'),
    );
    expect(
      livePracticePrepareFailureMessage(Exception('socket exploded')),
      contains('Camera preparation failed'),
    );
  });
}
