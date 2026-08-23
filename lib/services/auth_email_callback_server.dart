import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Receives the Firebase Auth continue URL after the user clicks an email link.
abstract class AuthEmailCallbackServer {
  Stream<Uri> get callbacks;

  Future<Uri> start();

  Future<void> stop();
}

/// In-memory callback server for tests. Does not bind a socket.
class MemoryAuthEmailCallbackServer implements AuthEmailCallbackServer {
  MemoryAuthEmailCallbackServer({
    this.continueUri = 'http://localhost:1/elixr-auth',
  });

  final String continueUri;
  final _controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get callbacks => _controller.stream;

  @override
  Future<Uri> start() async => Uri.parse(continueUri);

  @override
  Future<void> stop() async {}

  void emit(Uri uri) {
    if (!_controller.isClosed) {
      _controller.add(uri);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Listens on IPv4 and IPv6 loopback so `localhost` continue URLs reach the
/// running Windows app after the user clicks the Firebase email link.
class LoopbackAuthEmailCallbackServer implements AuthEmailCallbackServer {
  HttpServer? _ipv4;
  HttpServer? _ipv6;
  final _subscriptions = <StreamSubscription<HttpRequest>>[];
  final _controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get callbacks => _controller.stream;

  @override
  Future<Uri> start() async {
    await stop();
    final ipv4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _ipv4 = ipv4;
    _subscriptions.add(ipv4.listen(_handleRequest, onError: _onError));
    try {
      final ipv6 = await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        ipv4.port,
        v6Only: true,
      );
      _ipv6 = ipv6;
      _subscriptions.add(ipv6.listen(_handleRequest, onError: _onError));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('IPv6 loopback auth callback not bound: $error');
      }
    }
    if (kDebugMode) {
      debugPrint('Auth email callback listening on localhost:${ipv4.port}');
    }
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: ipv4.port,
      path: '/elixr-auth',
    );
  }

  @override
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final ipv4 = _ipv4;
    final ipv6 = _ipv6;
    _ipv4 = null;
    _ipv6 = null;
    await ipv4?.close(force: true);
    await ipv6?.close(force: true);
  }

  void _onError(Object error) {
    if (kDebugMode) {
      debugPrint('Auth email callback server error: $error');
    }
  }

  void _handleRequest(HttpRequest request) {
    final response = request.response;
    try {
      final path = request.uri.path;
      final isCallbackPath =
          path == '/elixr-auth' || path == '/' || path.isEmpty;
      if (request.method == 'GET' && isCallbackPath) {
        final uri = Uri(
          scheme: 'http',
          host: 'localhost',
          port: _ipv4?.port ?? request.requestedUri.port,
          path: path.isEmpty ? '/elixr-auth' : path,
          query: request.uri.query,
        );
        if (kDebugMode) {
          debugPrint('Auth email callback received $uri');
        }
        if (!_controller.isClosed) {
          _controller.add(uri);
        }
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.html;
        response.write(_successHtml(request.uri.query));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } finally {
      unawaited(response.close());
    }
  }

  static String _successHtml(String query) {
    final queryPart = query.isEmpty ? '' : '?$query';
    final protocolUrl = jsonEncode('elixr://auth$queryPart');
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<title>ELIXR</title>'
        '</head>'
        '<body style="font-family:Segoe UI,sans-serif;background:#111;color:#eee;'
        'text-align:center;padding:64px">'
        '<h1>ELIXR</h1>'
        '<p>You can close this tab and return to the app.</p>'
        '<script>window.location.replace($protocolUrl);</script>'
        '</body></html>';
  }
}
