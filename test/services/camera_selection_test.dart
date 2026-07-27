import 'package:elixr_application/data/models/camera_device.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSocketService.buildStartPayload', () {
    test('omits camera_index for Auto-select', () {
      final payload = WebSocketService.buildStartPayload(
        movement: 'Hand Stall',
        difficulty: 'Medium',
      );

      expect(payload['action'], 'start');
      expect(payload['movement'], 'Hand Stall');
      expect(payload['difficulty'], 'Medium');
      expect(payload['bottle_detection_enabled'], isTrue);
      expect(payload.containsKey('camera_index'), isFalse);
    });

    test('includes explicit camera_index', () {
      final payload = WebSocketService.buildStartPayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        cameraIndex: 1,
      );

      expect(payload['camera_index'], 1);
    });
  });

  group('CameraDiscoveryResult', () {
    test('parses success response', () {
      final result = CameraDiscoveryResult.fromJson({
        'cameras': [
          {'index': 0, 'display_name': 'Camera 0'},
          {'index': 1, 'display_name': 'Camera 1'},
        ],
        'preferred_index': 1,
        'fallback_index': 0,
        'active_index': null,
      });

      expect(result.cameras, hasLength(2));
      expect(result.cameras.first.displayName, 'Camera 0');
      expect(result.preferredIndex, 1);
      expect(result.fallbackIndex, 0);
      expect(result.activeIndex, isNull);
    });

    test('parses empty camera list', () {
      final result = CameraDiscoveryResult.fromJson({
        'cameras': <dynamic>[],
        'preferred_index': 1,
        'fallback_index': 0,
        'active_index': null,
      });

      expect(result.cameras, isEmpty);
    });

    test('rejects malformed response', () {
      expect(
        () => CameraDiscoveryResult.fromJson({'cameras': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CameraDeviceService', () {
    test('handles success, empty, and backend errors', () async {
      final success = CameraDeviceService(
        httpGet: (_) async => '''
{
  "cameras": [{"index": 0, "display_name": "Camera 0"}],
  "preferred_index": 1,
  "fallback_index": 0,
  "active_index": null
}''',
      );
      await success.refresh();
      expect(success.state, CameraDiscoveryState.success);
      expect(success.cameras, hasLength(1));

      final empty = CameraDeviceService(
        httpGet: (_) async => '''
{
  "cameras": [],
  "preferred_index": 1,
  "fallback_index": 0,
  "active_index": null
}''',
      );
      await empty.refresh();
      expect(empty.state, CameraDiscoveryState.empty);

      final error = CameraDeviceService(
        httpGet: (_) async => throw const FormatException('bad'),
      );
      await error.refresh();
      expect(error.state, CameraDiscoveryState.error);
      expect(error.errorMessage, contains('invalid'));
    });
  });
}
