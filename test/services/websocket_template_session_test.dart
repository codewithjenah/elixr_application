import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spec = AssessmentSpec(laterality: AssessmentLaterality.either);

  test('official prepare omits session_purpose and assessment_spec', () {
    final payload = WebSocketService.buildPreparePayload(
      movement: 'Normal Grip',
      difficulty: 'Easy',
      sessionId: 'session-1',
      requestId: 'req-1',
    );

    expect(payload['action'], 'prepare');
    expect(payload['movement'], 'Normal Grip');
    expect(payload['difficulty'], 'Easy');
    expect(payload.containsKey('session_purpose'), isFalse);
    expect(payload.containsKey('assessment_spec'), isFalse);
    expect(payload.containsKey('allow_submission_recording'), isFalse);
  });

  test(
    'explicit official purpose still omits default official wire fields',
    () {
      final payload = WebSocketService.buildPreparePayload(
        movement: 'Hand Stall',
        difficulty: 'Medium',
        sessionId: 'session-1',
        requestId: 'req-1',
        sessionPurpose: WebSocketSessionPurpose.official,
      );

      expect(payload.containsKey('session_purpose'), isFalse);
      expect(payload.containsKey('assessment_spec'), isFalse);
    },
  );

  test('template_scored prepare emits canonical AssessmentSpec map', () {
    final payload = WebSocketService.buildPreparePayload(
      movement: kTemplateAssessmentMovement,
      difficulty: kTemplateAssessmentDifficulty,
      sessionId: 'session-t',
      requestId: 'req-t',
      sessionPurpose: WebSocketSessionPurpose.templateScored,
      assessmentSpec: spec,
    );

    expect(payload['session_purpose'], 'template_scored');
    expect(payload['assessment_spec'], {
      'schema_version': 1,
      'template_id': 'balance_stall.wrist_v1',
      'prop': 'bottle',
      'target': 'wrist',
      'laterality': 'either',
    });
    expect(payload.containsKey('allow_submission_recording'), isFalse);
  });

  test('live_test prepare emits the same typed spec contract', () {
    const left = AssessmentSpec(laterality: AssessmentLaterality.left);
    final payload = WebSocketService.buildPreparePayload(
      movement: kTemplateAssessmentMovement,
      difficulty: kTemplateAssessmentDifficulty,
      sessionId: 'session-live',
      requestId: 'req-live',
      sessionPurpose: WebSocketSessionPurpose.liveTest,
      assessmentSpec: left,
    );

    expect(payload['session_purpose'], 'live_test');
    expect(payload['assessment_spec'], left.toMap());
    expect(payload['assessment_spec']['laterality'], 'left');
  });

  test('template purposes cannot be built without AssessmentSpec', () {
    expect(
      () => WebSocketService.buildPreparePayload(
        movement: kTemplateAssessmentMovement,
        difficulty: kTemplateAssessmentDifficulty,
        sessionId: 'session-t',
        requestId: 'req-t',
        sessionPurpose: WebSocketSessionPurpose.templateScored,
      ),
      throwsArgumentError,
    );
    expect(
      () => WebSocketService.buildPreparePayload(
        movement: kTemplateAssessmentMovement,
        difficulty: kTemplateAssessmentDifficulty,
        sessionId: 'session-t',
        requestId: 'req-t',
        sessionPurpose: WebSocketSessionPurpose.liveTest,
      ),
      throwsArgumentError,
    );
  });

  test('official prepare cannot carry an AssessmentSpec', () {
    expect(
      () => WebSocketService.buildPreparePayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: 'session-1',
        requestId: 'req-1',
        assessmentSpec: spec,
      ),
      throwsArgumentError,
    );
  });

  test('template prepare cannot enable submission recording', () {
    expect(
      () => WebSocketService.buildPreparePayload(
        movement: kTemplateAssessmentMovement,
        difficulty: kTemplateAssessmentDifficulty,
        sessionId: 'session-t',
        requestId: 'req-t',
        sessionPurpose: WebSocketSessionPurpose.templateScored,
        assessmentSpec: spec,
        allowSubmissionRecording: true,
      ),
      throwsArgumentError,
    );
  });

  test('legacy start payload remains official-only', () {
    final payload = WebSocketService.buildStartPayload(
      movement: 'Normal Grip',
      difficulty: 'Easy',
      sessionId: 'session-1',
      requestId: 'req-start',
    );

    expect(payload['action'], 'start');
    expect(payload.containsKey('session_purpose'), isFalse);
    expect(payload.containsKey('assessment_spec'), isFalse);
  });
}
