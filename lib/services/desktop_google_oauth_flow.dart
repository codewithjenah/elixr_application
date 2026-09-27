import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef GoogleBrowserLauncher = Future<void> Function(Uri uri);

/// Runs Google authentication in the system browser and returns the PKCE
/// authorization code to the app over a private loopback redirect.
///
/// The Supabase Auth server performs the Google OAuth exchange; the browser
/// is redirected to `http://localhost:{port}/elixr-google/{nonce}/callback`
/// with a one-time `code`. The code is useless without the PKCE verifier held
/// by this app's auth client, and the random path segment keeps other local
/// processes from guessing the callback.
class DesktopGoogleOAuthFlow implements GoogleOAuthFlow {
  DesktopGoogleOAuthFlow({
    GoogleBrowserLauncher? browserLauncher,
    this.timeout = const Duration(minutes: 5),
  }) : _browserLauncher = browserLauncher ?? _launchCompatibleBrowser;

  final GoogleBrowserLauncher _browserLauncher;
  final Duration timeout;

  @override
  Future<GoogleOAuthCredential> authenticate(
    OAuthAuthorizationUrlBuilder authorizationUrlFor,
  ) async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      throw const GoogleOAuthFlowException(
        'This Google sign-in flow is available only on Windows and macOS.',
      );
    }

    HttpServer? ipv4;
    HttpServer? ipv6;
    final subscriptions = <StreamSubscription<HttpRequest>>[];
    final completion = Completer<GoogleOAuthCredential>();
    final nonce = _randomToken();

    try {
      ipv4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        ipv6 = await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          ipv4.port,
          v6Only: true,
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Google OAuth IPv6 loopback not bound: $error');
        }
      }

      final callbackPath = '/elixr-google/$nonce/callback';
      final callbackUri = Uri(
        scheme: 'http',
        host: 'localhost',
        port: ipv4.port,
        path: callbackPath,
      );

      Future<void> handle(HttpRequest request) async {
        final response = request.response;
        try {
          if (request.method != 'GET' || request.uri.path != callbackPath) {
            response.statusCode = HttpStatus.notFound;
            return;
          }
          final params = request.uri.queryParameters;
          final code = _nonEmptyString(params['code']);
          final error = _nonEmptyString(params['error']);
          response.headers.contentType = ContentType.html;
          if (code != null) {
            response.statusCode = HttpStatus.ok;
            response.write(
              _resultPage(
                'Sign-in complete. You can close this tab and return to ELIXR.',
              ),
            );
            if (!completion.isCompleted) {
              completion.complete(
                GoogleOAuthCredential(authorizationCode: code),
              );
            }
          } else if (error == 'access_denied') {
            response.statusCode = HttpStatus.ok;
            response.write(
              _resultPage('Sign-in cancelled. You can return to ELIXR.'),
            );
            if (!completion.isCompleted) {
              completion.completeError(const GoogleSignInCancelledException());
            }
          } else {
            response.statusCode = HttpStatus.ok;
            response.write(
              _resultPage(
                'Google sign-in failed. Return to ELIXR for details.',
              ),
            );
            if (!completion.isCompleted) {
              completion.completeError(
                GoogleOAuthFlowException(
                  _messageForProviderError(
                    error,
                    _nonEmptyString(params['error_description']),
                  ),
                ),
              );
            }
          }
        } catch (error, stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(
              const GoogleOAuthFlowException(
                'ELIXR could not read the Google sign-in response. Please try again.',
              ),
              stackTrace,
            );
          }
          response.statusCode = HttpStatus.badRequest;
        } finally {
          await response.close();
        }
      }

      void listen(HttpServer server) {
        subscriptions.add(
          server.listen(
            (request) => unawaited(handle(request)),
            onError: (Object error, StackTrace stackTrace) {
              if (!completion.isCompleted) {
                completion.completeError(
                  const GoogleOAuthFlowException(
                    'The local Google sign-in callback stopped unexpectedly. Please try again.',
                  ),
                  stackTrace,
                );
              }
            },
          ),
        );
      }

      listen(ipv4);
      if (ipv6 != null) listen(ipv6);
      final authorizationUri = await authorizationUrlFor(callbackUri);
      unawaited(
        _browserLauncher(authorizationUri).catchError((
          Object error,
          StackTrace stack,
        ) {
          if (!completion.isCompleted) {
            completion.completeError(error, stack);
          }
        }),
      );
      return await completion.future.timeout(timeout);
    } on GoogleSignInCancelledException {
      rethrow;
    } on GoogleOAuthFlowException {
      rethrow;
    } on TimeoutException {
      throw const GoogleOAuthFlowException(
        'Google sign-in timed out. Close the browser tab and try again.',
      );
    } on SocketException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Google OAuth loopback failed: $error');
        debugPrint('$stackTrace');
      }
      throw const GoogleOAuthFlowException(
        'ELIXR could not start the local Google sign-in callback. Check firewall settings and try again.',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Google OAuth flow failed: $error');
        debugPrint('$stackTrace');
      }
      throw const GoogleOAuthFlowException(
        'ELIXR could not open Google sign-in. Please try again.',
      );
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await ipv4?.close(force: true);
      await ipv6?.close(force: true);
    }
  }

  static Future<void> _launchCompatibleBrowser(Uri uri) async {
    if (Platform.isMacOS) return _launchMacOSBrowser(uri);

    final environment = Platform.environment;
    final programFilesX86 =
        environment['ProgramFiles(x86)'] ?? environment['PROGRAMFILES(X86)'];
    final programFiles =
        environment['ProgramFiles'] ?? environment['PROGRAMFILES'];
    final localAppData =
        environment['LOCALAPPDATA'] ?? environment['LocalAppData'];
    final edgeCandidates = <String>[
      if (programFilesX86 != null)
        '$programFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',
      if (programFiles != null)
        '$programFiles\\Microsoft\\Edge\\Application\\msedge.exe',
      if (localAppData != null)
        '$localAppData\\Microsoft\\Edge\\Application\\msedge.exe',
    ];

    try {
      for (final edgePath in edgeCandidates) {
        if (await File(edgePath).exists()) {
          await Process.start(edgePath, [
            '--new-window',
            uri.toString(),
          ], mode: ProcessStartMode.detached);
          return;
        }
      }
      await Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      throw const GoogleOAuthFlowException(
        'ELIXR could not open your default browser. Open a default browser and try again.',
      );
    }
  }

  /// Opens the default browser through LaunchServices (url_launcher), which
  /// works inside the App Sandbox without spawning a shell command.
  static Future<void> _launchMacOSBrowser(Uri uri) async {
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!launched) {
      throw const GoogleOAuthFlowException(
        'ELIXR could not open your default browser. Open a default browser and try again.',
      );
    }
  }

  static String _resultPage(String message) {
    final safe = const HtmlEscape().convert(message);
    return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Sign in to ELIXR</title>
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:#101318; color:#f3f5f7; font-family:Segoe UI,-apple-system,sans-serif; }
    main { width:min(420px,calc(100% - 48px)); padding:36px; border:1px solid #343b45; border-radius:16px; background:#181d24; text-align:center; box-shadow:0 18px 60px #0008; }
    h1 { letter-spacing:.12em; margin:0 0 12px; }
    p { color:#b9c0ca; line-height:1.5; }
  </style>
</head>
<body>
<main>
  <h1>ELIXR</h1>
  <p>$safe</p>
</main>
</body>
</html>''';
  }

  static String _messageForProviderError(String? error, String? description) {
    final detail = description?.toLowerCase() ?? '';
    if (detail.contains('provider is not enabled') ||
        detail.contains('unsupported provider')) {
      return 'Google sign-in is not enabled for this ELIXR server.';
    }
    if (detail.contains('redirect')) {
      return 'The ELIXR server does not allow the local sign-in callback. Add http://localhost:*/** to the Auth redirect URLs.';
    }
    if (detail.contains('multiple accounts') || detail.contains('identity')) {
      return 'This email already uses another sign-in method. Sign in with your existing method first.';
    }
    return 'Google sign-in could not be completed in the browser (${error ?? 'unknown'}). Please try again.';
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
