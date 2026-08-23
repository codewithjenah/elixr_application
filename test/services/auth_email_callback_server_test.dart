import 'dart:io';

import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loopback server reports the clicked continue URL', () async {
    final server = LoopbackAuthEmailCallbackServer();
    final received = server.callbacks.first;
    final base = await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      base.replace(queryParameters: {'mode': 'verify'}),
    );
    final response = await request.close();
    expect(response.statusCode, 200);

    final uri = await received.timeout(const Duration(seconds: 2));
    await response.drain<void>();
    expect(uri.queryParameters['mode'], 'verify');
    expect(uri.host, 'localhost');
    expect(uri.path, '/elixr-auth');
  });

  test(
    'loopback server accepts the root path Firebase may redirect to',
    () async {
      final server = LoopbackAuthEmailCallbackServer();
      final received = server.callbacks.first;
      final base = await server.start();
      addTearDown(server.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri(scheme: 'http', host: 'localhost', port: base.port, path: '/'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      await received.timeout(const Duration(seconds: 2));
      await response.drain<void>();
    },
  );

  test('loopback server accepts IPv6 localhost when it is available', () async {
    final server = LoopbackAuthEmailCallbackServer();
    final received = server.callbacks.first;
    final base = await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);
    try {
      final request = await client.getUrl(
        Uri.parse('http://[::1]:${base.port}/elixr-auth?elixr_action=verify'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      final uri = await received.timeout(const Duration(seconds: 2));
      await response.drain<void>();
      expect(uri.queryParameters['elixr_action'], 'verify');
    } on SocketException {
      // Dual-stack loopback is not available on this runner.
    }
  });
}
