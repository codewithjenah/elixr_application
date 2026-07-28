import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/camera_device.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSocketService camera_device_id payloads', () {
    test('includes null camera_device_id for Auto-select', () {
      final payload = WebSocketService.buildStartPayload(
        movement: 'Hand Stall',
        difficulty: 'Medium',
      );

      expect(payload['action'], 'start');
      expect(payload['movement'], 'Hand Stall');
      expect(payload['difficulty'], 'Medium');
      expect(payload['bottle_detection_enabled'], isTrue);
      expect(payload.containsKey('camera_device_id'), isTrue);
      expect(payload['camera_device_id'], isNull);
      expect(payload.containsKey('camera_index'), isFalse);
    });

    test('includes explicit camera_device_id', () {
      final payload = WebSocketService.buildStartPayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        cameraDeviceId: r'\\?\usb#vid_1234&pid_5678',
      );

      expect(payload['camera_device_id'], r'\\?\usb#vid_1234&pid_5678');
      expect(payload.containsKey('camera_index'), isFalse);
    });

    test('prepare payload uses camera_device_id', () {
      final payload = WebSocketService.buildPreparePayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        cameraDeviceId: 'dev-b',
      );
      expect(payload['action'], 'prepare');
      expect(payload['camera_device_id'], 'dev-b');
      expect(payload.containsKey('camera_index'), isFalse);
    });

    test('pending legacy migration may send camera_index once', () {
      final payload = WebSocketService.buildPreparePayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        legacyCameraIndex: 1,
      );
      expect(payload.containsKey('camera_device_id'), isFalse);
      expect(payload['camera_index'], 1);
    });
  });

  group('CameraDiscoveryResult', () {
    test('parses identity fields and preserves backend display names', () {
      final result = CameraDiscoveryResult.fromJson({
        'cameras': [
          {
            'device_id': 'dev-a',
            'display_name': 'Integrated Camera',
            'runtime_index': 0,
            'is_active': false,
            'identity_stable': true,
          },
          {
            'device_id': 'dev-b',
            'display_name': 'HIKVISION USB Camera',
            'runtime_index': 1,
            'is_active': true,
            'identity_stable': true,
          },
        ],
        'active_device_id': 'dev-b',
        'preferred_index': 1,
        'fallback_index': 0,
        'active_index': 1,
      });

      expect(result.cameras, hasLength(2));
      expect(result.cameras[0].displayName, 'Integrated Camera');
      expect(result.cameras[1].displayName, 'HIKVISION USB Camera');
      expect(result.cameras[1].deviceId, 'dev-b');
      expect(result.activeDeviceId, 'dev-b');
      expect(result.preferredIndex, 1);
      expect(result.fallbackIndex, 0);
    });

    test('device reorder keeps identity by device_id', () {
      final first = CameraDiscoveryResult.fromJson({
        'cameras': [
          {
            'device_id': 'dev-a',
            'display_name': 'Integrated Camera',
            'runtime_index': 0,
            'is_active': false,
            'identity_stable': true,
          },
          {
            'device_id': 'dev-b',
            'display_name': 'HIKVISION',
            'runtime_index': 1,
            'is_active': false,
            'identity_stable': true,
          },
        ],
        'active_device_id': null,
      });
      final second = CameraDiscoveryResult.fromJson({
        'cameras': [
          {
            'device_id': 'dev-b',
            'display_name': 'HIKVISION',
            'runtime_index': 0,
            'is_active': false,
            'identity_stable': true,
          },
          {
            'device_id': 'dev-a',
            'display_name': 'Integrated Camera',
            'runtime_index': 1,
            'is_active': false,
            'identity_stable': true,
          },
        ],
        'active_device_id': null,
      });

      final saved = 'dev-b';
      final before = first.cameras.firstWhere((c) => c.deviceId == saved);
      final after = second.cameras.firstWhere((c) => c.deviceId == saved);
      expect(before.runtimeIndex, 1);
      expect(after.runtimeIndex, 0);
      expect(after.displayName, 'HIKVISION');
    });

    test('duplicate friendly names remain distinguishable', () {
      final cameras = [
        const CameraDevice(
          deviceId: 'path-1',
          displayName: 'USB Camera',
          runtimeIndex: 0,
          identityStable: true,
        ),
        const CameraDevice(
          deviceId: 'path-2',
          displayName: 'USB Camera',
          runtimeIndex: 1,
          identityStable: true,
        ),
      ];
      final labels = distinguishableCameraLabels(cameras);
      expect(labels[0], 'USB Camera · Camera 0');
      expect(labels[1], 'USB Camera · Camera 1');
      expect(cameras[0].deviceId, isNot(cameras[1].deviceId));
    });

    test('rejects malformed response', () {
      expect(
        () => CameraDiscoveryResult.fromJson({'cameras': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CameraDeviceService', () {
    const successBody = '''
{
  "cameras": [{
    "device_id": "dev-a",
    "display_name": "Integrated Camera",
    "runtime_index": 0,
    "is_active": false,
    "identity_stable": true
  }],
  "active_device_id": null
}''';

    test('handles success, empty, and backend errors', () async {
      final success = CameraDeviceService(httpGet: (_) async => successBody);
      await success.refresh();
      expect(success.state, CameraDiscoveryState.success);
      expect(success.cameras, hasLength(1));
      expect(success.findByDeviceId('dev-a')?.displayName, 'Integrated Camera');
      expect(success.findByRuntimeIndex(0)?.deviceId, 'dev-a');

      final empty = CameraDeviceService(
        httpGet: (_) async => '''
{
  "cameras": [],
  "active_device_id": null
}''',
      );
      await empty.refresh();
      expect(empty.state, CameraDiscoveryState.empty);

      final error = CameraDeviceService(
        httpGet: (_) async => throw const FormatException('bad'),
      );
      await error.refresh();
      expect(error.state, CameraDiscoveryState.error);
      expect(error.errorKind, CameraDiscoveryErrorKind.invalidResponse);
      expect(error.errorMessage, contains('invalid'));
    });

    test('does not replace a missing selected device', () async {
      final service = CameraDeviceService(httpGet: (_) async => successBody);
      await service.refresh();
      expect(service.findByDeviceId('missing'), isNull);
    });

    test('timeout with healthy backend reports scan timeout', () async {
      final service = CameraDeviceService(
        httpGet: (uri) async {
          if (uri.path == '/health') {
            return '{"status":"ok"}';
          }
          throw TimeoutException('scan timed out');
        },
      );
      await service.refresh();
      expect(service.state, CameraDiscoveryState.error);
      expect(service.errorKind, CameraDiscoveryErrorKind.scanTimeout);
      expect(service.errorMessage, contains('camera scan took too long'));
    });

    test(
      'timeout with unhealthy backend reports backend unavailable',
      () async {
        final service = CameraDeviceService(
          httpGet: (uri) async {
            throw TimeoutException('scan timed out');
          },
        );
        await service.refresh();
        expect(service.errorKind, CameraDiscoveryErrorKind.backendUnreachable);
        expect(service.errorMessage, contains('Backend unavailable'));
      },
    );

    test('preserves previous cameras after transient refresh error', () async {
      var call = 0;
      final service = CameraDeviceService(
        httpGet: (uri) async {
          if (uri.path == '/health') {
            return '{"status":"ok"}';
          }
          call += 1;
          if (call == 1) {
            return successBody;
          }
          throw TimeoutException('scan timed out');
        },
      );

      await service.refresh();
      expect(service.cameras, hasLength(1));

      await service.refresh();
      expect(service.cameras, hasLength(1));
      expect(service.errorKind, CameraDiscoveryErrorKind.scanTimeout);
    });

    test('socket exception is backend unreachable', () async {
      final service = CameraDeviceService(
        httpGet: (_) async => throw const SocketException('refused'),
      );
      await service.refresh();
      expect(service.errorKind, CameraDiscoveryErrorKind.backendUnreachable);
    });

    test('http exception is distinguishable', () async {
      final service = CameraDeviceService(
        httpGet: (_) async => throw const HttpException('HTTP 500'),
      );
      await service.refresh();
      expect(service.errorKind, CameraDiscoveryErrorKind.httpError);
      expect(service.errorMessage, contains('HTTP 500'));
    });

    test('forceRefresh bypasses backend cache via query parameter', () async {
      Uri? requestedUri;
      final service = CameraDeviceService(
        httpGet: (uri) async {
          requestedUri = uri;
          return successBody;
        },
      );

      await service.refresh();
      expect(requestedUri!.queryParameters['force_refresh'], isNull);

      await service.refresh(forceRefresh: true);
      expect(requestedUri!.queryParameters['force_refresh'], 'true');
    });

    test('saved camera missing only after successful discovery', () {
      final cameras = [
        const CameraDevice(
          deviceId: 'dev-a',
          displayName: 'Integrated Camera',
          runtimeIndex: 0,
          identityStable: true,
        ),
      ];

      bool selectedMissing({
        required CameraDiscoveryState state,
        required String? selectedId,
        required List<CameraDevice> discovered,
      }) {
        final discoveryComplete =
            state == CameraDiscoveryState.success ||
            state == CameraDiscoveryState.empty;
        if (selectedId == null) return false;
        final inList = discovered.any((c) => c.deviceId == selectedId);
        return discoveryComplete && !inList;
      }

      expect(
        selectedMissing(
          state: CameraDiscoveryState.loading,
          selectedId: 'missing',
          discovered: cameras,
        ),
        isFalse,
      );
      expect(
        selectedMissing(
          state: CameraDiscoveryState.error,
          selectedId: 'missing',
          discovered: cameras,
        ),
        isFalse,
      );
      expect(
        selectedMissing(
          state: CameraDiscoveryState.success,
          selectedId: 'missing',
          discovered: cameras,
        ),
        isTrue,
      );
    });
  });
}
