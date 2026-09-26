import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Completes a password recovery link with the new password. Returns a
/// presentation-safe error message, or null on success.
typedef PasswordResetHandler =
    Future<String?> Function(String code, String newPassword);

/// Receives the auth redirect after the user clicks an email link.
///
/// Links carry a one-time PKCE `code` that only this app's auth client can
/// exchange. Recovery links are answered with a local new-password form so
/// the password never leaves this computer except to the auth server.
abstract class AuthEmailCallbackServer {
  Stream<Uri> get callbacks;

  /// Set by the auth service before the server is started.
  PasswordResetHandler? passwordResetHandler;

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
  PasswordResetHandler? passwordResetHandler;

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

/// Listens on IPv4 and IPv6 loopback so `localhost` redirect URLs reach the
/// running Windows app after the user clicks an email link.
class LoopbackAuthEmailCallbackServer implements AuthEmailCallbackServer {
  HttpServer? _ipv4;
  HttpServer? _ipv6;
  final _subscriptions = <StreamSubscription<HttpRequest>>[];
  final _controller = StreamController<Uri>.broadcast();

  static const _callbackPath = '/elixr-auth';
  static const _resetSubmitPath = '/elixr-auth/reset';

  @override
  PasswordResetHandler? passwordResetHandler;

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
      path: _callbackPath,
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

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      final params = request.uri.queryParameters;
      if (request.method == 'POST' && path == _resetSubmitPath) {
        await _handleResetSubmit(request);
        return;
      }
      final isCallbackPath =
          path == _callbackPath || path == '/' || path.isEmpty;
      if (request.method != 'GET' || !isCallbackPath) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final action = (params['elixr_action'] ?? '').toLowerCase();
      final code = params['code']?.trim() ?? '';
      response.headers.contentType = ContentType.html;
      response.statusCode = HttpStatus.ok;
      if (action == 'reset') {
        response.write(
          code.isEmpty
              ? _page(_resetLinkErrorMessage(params))
              : _resetFormPage(code: code),
        );
        return;
      }
      final uri = Uri(
        scheme: 'http',
        host: 'localhost',
        port: _ipv4?.port ?? request.requestedUri.port,
        path: path.isEmpty ? _callbackPath : path,
        query: request.uri.query,
      );
      if (kDebugMode) {
        debugPrint('Auth email callback received action=$action');
      }
      if (!_controller.isClosed) {
        _controller.add(uri);
      }
      response.write(
        _page(
          'You can close this tab and return to the app.',
          returnAction: action.isEmpty ? 'verify' : action,
        ),
      );
    } catch (error) {
      _onError(error);
      response.statusCode = HttpStatus.badRequest;
    } finally {
      unawaited(response.close());
    }
  }

  Future<void> _handleResetSubmit(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.html;
    response.statusCode = HttpStatus.ok;
    final body = await utf8.decoder
        .bind(request)
        .join()
        .timeout(const Duration(seconds: 10));
    if (body.length > 8192) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      return;
    }
    final form = Uri.splitQueryString(body);
    final code = form['code']?.trim() ?? '';
    final password = form['password'] ?? '';
    final confirmation = form['confirmation'] ?? '';
    final handler = passwordResetHandler;
    if (code.isEmpty || handler == null) {
      response.write(
        _page('This reset link is invalid or has expired. Request a new one.'),
      );
      return;
    }
    if (password != confirmation) {
      response.write(
        _resetFormPage(code: code, error: 'Passwords do not match.'),
      );
      return;
    }
    final error = await handler(code, password);
    if (error != null) {
      response.write(_resetFormPage(code: code, error: error));
      return;
    }
    response.write(
      _page(
        'Your password was updated. Return to ELIXR and sign in with your new password.',
        returnAction: 'reset',
      ),
    );
  }

  static String _resetLinkErrorMessage(Map<String, String> params) {
    final description = params['error_description']?.toLowerCase() ?? '';
    if (description.contains('expired')) {
      return 'This reset link has expired. Request a new one from ELIXR.';
    }
    return 'This reset link is invalid or has already been used. Request a new one from ELIXR.';
  }

  static String _resetFormPage({required String code, String? error}) {
    const escape = HtmlEscape();
    final errorHtml = error == null
        ? ''
        : '<p class="error" role="alert">${escape.convert(error)}</p>';
    return _shell(
      '''
<h1>ELIXR</h1>
<p>Choose a new password for your ELIXR account.</p>
$errorHtml
<form method="post" action="$_resetSubmitPath">
  <input type="hidden" name="code" value="${escape.convert(code)}">
  <label>New password<input name="password" type="password" autocomplete="new-password" minlength="8" required></label>
  <label>Confirm password<input name="confirmation" type="password" autocomplete="new-password" minlength="8" required></label>
  <button type="submit">Update password</button>
</form>
<p class="hint">Use 8+ characters with at least one letter and one number.</p>''',
    );
  }

  static String _page(String message, {String? returnAction}) {
    final safe = const HtmlEscape().convert(message);
    // Brings the app to the foreground without forwarding any link secret.
    final script = returnAction == null
        ? ''
        : '<script>window.location.replace(${jsonEncode('elixr://auth?elixr_action=$returnAction')});</script>';
    return _shell('<h1>ELIXR</h1><p>$safe</p>$script');
  }

  static String _shell(String body) {
    return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>ELIXR</title><style>'
        'body{font-family:Segoe UI,sans-serif;background:#111;color:#eee;'
        'display:grid;place-items:center;min-height:100vh;margin:0}'
        'main{width:min(420px,calc(100% - 48px));text-align:center}'
        'label{display:block;text-align:left;margin:12px 0;color:#ccc}'
        'input{display:block;width:100%;box-sizing:border-box;margin-top:6px;'
        'padding:10px;border-radius:8px;border:1px solid #444;background:#1b1b1b;color:#eee}'
        'button{width:100%;margin-top:12px;padding:12px;border:0;border-radius:8px;'
        'background:#fff;color:#111;font-weight:600;cursor:pointer}'
        '.error{color:#ff8a80}.hint{color:#999;font-size:13px}'
        '</style></head><body><main>$body</main></body></html>';
  }
}
