import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submission record payloads have no video bytes', () {
    final start = WebSocketService.buildStartSubmissionRecordPayload(
      sessionId: 'session-1',
      requestId: 'req-1',
    );
    final stop = WebSocketService.buildStopSubmissionRecordPayload(
      sessionId: 'session-1',
      requestId: 'req-2',
    );
    final cancel = WebSocketService.buildCancelSubmissionRecordPayload(
      sessionId: 'session-1',
      requestId: 'req-3',
    );
    for (final payload in [start, stop, cancel]) {
      expect(payload['protocol_version'], 1);
      expect(payload['session_id'], 'session-1');
      expect(payload.keys, isNot(contains('video_base64')));
      expect(payload.keys, isNot(contains('bytes')));
      expect(payload.keys, isNot(contains('mp4')));
    }
    expect(start['action'], 'start_submission_record');
    expect(stop['action'], 'stop_submission_record');
    expect(cancel['action'], 'cancel_submission_record');
  });

  test('prepare omits allow_submission_recording unless requested', () {
    final normal = WebSocketService.buildPreparePayload(
      movement: 'Free Practice',
      difficulty: 'Easy',
      sessionId: 's1',
      requestId: 'r1',
    );
    expect(normal.keys, isNot(contains('allow_submission_recording')));
    final allowed = WebSocketService.buildPreparePayload(
      movement: 'Free Practice',
      difficulty: 'Easy',
      sessionId: 's1',
      requestId: 'r1',
      allowSubmissionRecording: true,
    );
    expect(allowed['allow_submission_recording'], isTrue);
  });

  test('CommandAck parses local clip metadata without bytes', () {
    final ack = CommandAck.fromJson({
      'protocol_version': 1,
      'request_id': 'req-stop',
      'session_id': 'session-1',
      'action': 'stop_submission_record',
      'accepted': true,
      'local_file_path': r'C:\Temp\elixr_submissions\clip.mp4',
      'video_duration_ms': 1800,
      'video_size_bytes': 4096,
      'content_type': 'video/mp4',
    });
    final result = SubmissionRecordResult.fromAck(ack);
    expect(result.localPath, contains('elixr_submissions'));
    expect(result.durationMs, 1800);
    expect(result.sizeBytes, 4096);
    expect(result.contentType, 'video/mp4');
  });
}
