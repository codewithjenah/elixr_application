import 'package:elixr_application/services/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(BackendRuntime.reset);

  test('uses the development backend endpoint by default', () {
    expect(BackendRuntime.httpBaseUri.toString(), 'http://127.0.0.1:8000');
    expect(BackendRuntime.wsUri.toString(), 'ws://127.0.0.1:8000/ws');
  });

  test('updates HTTP and WebSocket endpoints together for a packaged port', () {
    BackendRuntime.usePort(43210);

    expect(BackendRuntime.httpBaseUri.toString(), 'http://127.0.0.1:43210');
    expect(BackendRuntime.wsUri.toString(), 'ws://127.0.0.1:43210/ws');
  });

  test('startup errors are available to connection services', () {
    BackendRuntime.setStartupError('backend failed');

    expect(BackendRuntime.startupError, 'backend failed');
  });
}
