import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

typedef GoogleBrowserLauncher = Future<void> Function(Uri uri);

/// Runs Google authentication in the system browser and returns the Google
/// credential to the Windows Firebase Auth client over a private loopback URL.
///
/// FlutterFire delegates Windows auth to the Firebase C++ SDK, whose
/// `SignInWithProvider` implementation is unavailable on desktop. The hosted
/// Firebase JavaScript SDK performs the supported web popup flow on localhost;
/// the native client then exchanges the resulting Google credential through
/// `signInWithCredential`.
class WindowsGoogleOAuthFlow implements GoogleOAuthFlow {
  WindowsGoogleOAuthFlow({
    GoogleBrowserLauncher? browserLauncher,
    FirebaseOptions? firebaseOptions,
    this.timeout = const Duration(minutes: 5),
  }) : _browserLauncher = browserLauncher ?? _launchCompatibleBrowser,
       _firebaseOptions = firebaseOptions;

  final GoogleBrowserLauncher _browserLauncher;
  final FirebaseOptions? _firebaseOptions;
  final Duration timeout;

  @override
  Future<GoogleOAuthCredential> authenticate() async {
    if (!Platform.isWindows) {
      throw const GoogleOAuthFlowException(
        'This Google sign-in flow is available only on Windows.',
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

      final pagePath = '/elixr-google/$nonce';
      final callbackPath = '$pagePath/complete';
      final pageUri = Uri(
        scheme: 'http',
        host: 'localhost',
        port: ipv4.port,
        path: pagePath,
      );
      final callbackUri = pageUri.replace(path: callbackPath);
      final options = _firebaseOptions ?? Firebase.app().options;
      if (options.authDomain?.trim().isEmpty ?? true) {
        throw const GoogleOAuthFlowException(
          'Google sign-in is missing the Firebase auth domain configuration.',
        );
      }
      final page = _oauthPage(options, callbackUri);

      Future<void> handle(HttpRequest request) async {
        final response = request.response;
        try {
          if (request.method == 'GET' && request.uri.path == pagePath) {
            response.statusCode = HttpStatus.ok;
            response.headers.contentType = ContentType.html;
            response.write(page);
            return;
          }
          if (request.method == 'POST' && request.uri.path == callbackPath) {
            final body = await utf8.decoder.bind(request).join();
            final payload = jsonDecode(body);
            if (payload is! Map<String, dynamic>) {
              throw const FormatException('Invalid OAuth callback payload.');
            }
            final status = payload['status'];
            if (status == 'cancelled') {
              if (!completion.isCompleted) {
                completion.completeError(
                  const GoogleSignInCancelledException(),
                );
              }
            } else if (status == 'success') {
              final idToken = _nonEmptyString(payload['idToken']);
              final accessToken = _nonEmptyString(payload['accessToken']);
              if (idToken == null && accessToken == null) {
                throw const FormatException('Google token was missing.');
              }
              if (!completion.isCompleted) {
                completion.complete(
                  GoogleOAuthCredential(
                    idToken: idToken,
                    accessToken: accessToken,
                    isNewUser: payload['isNewUser'] == true,
                  ),
                );
              }
            } else {
              final code = _nonEmptyString(payload['code']) ?? 'unknown';
              if (!completion.isCompleted) {
                completion.completeError(
                  GoogleOAuthFlowException(_messageForWebError(code)),
                );
              }
            }
            response.statusCode = HttpStatus.ok;
            response.headers.contentType = ContentType.json;
            response.write('{"ok":true}');
            return;
          }
          response.statusCode = HttpStatus.notFound;
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
      unawaited(
        _browserLauncher(pageUri).catchError((Object error, StackTrace stack) {
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

  static String _oauthPage(FirebaseOptions options, Uri callbackUri) {
    final config = jsonEncode({
      'apiKey': options.apiKey,
      'appId': options.appId,
      'authDomain': options.authDomain,
      'messagingSenderId': options.messagingSenderId,
      'projectId': options.projectId,
      'storageBucket': options.storageBucket,
    });
    final callback = jsonEncode(callbackUri.toString());
    return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Sign in to ELIXR</title>
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:#101318; color:#f3f5f7; font-family:Segoe UI,sans-serif; }
    main { width:min(420px,calc(100% - 48px)); padding:36px; border:1px solid #343b45; border-radius:16px; background:#181d24; text-align:center; box-shadow:0 18px 60px #0008; }
    h1 { letter-spacing:.12em; margin:0 0 12px; }
    p { color:#b9c0ca; line-height:1.5; }
    button { width:100%; margin-top:18px; padding:13px 18px; border:0; border-radius:8px; background:#fff; color:#202124; font-size:15px; font-weight:600; cursor:pointer; }
    button:disabled { opacity:.65; cursor:wait; }
    #status { min-height:24px; margin-top:18px; font-size:14px; }
  </style>
</head>
<body>
<main>
  <h1>ELIXR</h1>
  <p>Continue securely with your Google account. This tab returns the result only to the ELIXR app running on this computer.</p>
  <button id="google" type="button">Continue with Google</button>
  <div id="status" role="status"></div>
</main>
<script type="module">
  import { initializeApp } from 'https://www.gstatic.com/firebasejs/11.6.1/firebase-app.js';
  import { getAuth, GoogleAuthProvider, signInWithPopup, getAdditionalUserInfo } from 'https://www.gstatic.com/firebasejs/11.6.1/firebase-auth.js';

  const app = initializeApp($config);
  const auth = getAuth(app);
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({prompt: 'select_account'});
  const callbackUrl = $callback;
  const button = document.getElementById('google');
  const status = document.getElementById('status');
  let finished = false;

  async function post(payload) {
    const response = await fetch(callbackUrl, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(payload)
    });
    if (!response.ok) throw new Error('callback-failed');
    finished = true;
  }

  button.addEventListener('click', async () => {
    button.disabled = true;
    status.textContent = 'Waiting for Google…';
    try {
      const result = await signInWithPopup(auth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);
      const details = getAdditionalUserInfo(result);
      if (!credential || (!credential.idToken && !credential.accessToken)) {
        throw {code: 'auth/missing-google-credential'};
      }
      await post({
        status: 'success',
        idToken: credential.idToken || null,
        accessToken: credential.accessToken || null,
        isNewUser: details ? details.isNewUser === true : false
      });
      status.textContent = 'Sign-in complete. You can close this tab and return to ELIXR.';
      button.hidden = true;
    } catch (error) {
      const code = error && error.code ? String(error.code) : 'unknown';
      const cancelled = code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request';
      try {
        await post(cancelled ? {status: 'cancelled'} : {status: 'error', code});
      } catch (_) {}
      status.textContent = cancelled ? 'Sign-in cancelled. You can return to ELIXR.' : 'Google sign-in failed. Return to ELIXR for details.';
      button.disabled = false;
    }
  });

  window.addEventListener('beforeunload', () => {
    if (!finished) {
      const body = new Blob([JSON.stringify({status:'cancelled'})], {type:'application/json'});
      navigator.sendBeacon(callbackUrl, body);
    }
  });
</script>
</body>
</html>''';
  }

  static String _messageForWebError(String code) {
    switch (code) {
      case 'auth/operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project.';
      case 'auth/unauthorized-domain':
        return 'Firebase does not authorize the local ELIXR sign-in callback. Add localhost to Authentication authorized domains.';
      case 'auth/network-request-failed':
        return 'Could not reach Google. Check your internet connection and try again.';
      case 'auth/popup-blocked':
        return 'The browser blocked the Google window. Allow pop-ups on the ELIXR sign-in tab and retry.';
      case 'auth/web-storage-unsupported':
      case 'auth/operation-not-supported-in-this-environment':
        return 'This browser blocks the storage required by Google sign-in. Retry in Microsoft Edge.';
      case 'auth/configuration-not-found':
        return 'The Firebase Google sign-in configuration was not found. Check the Authentication provider setup.';
      case 'auth/internal-error':
        return 'The browser could not initialize Google sign-in. Close the sign-in window and retry.';
      case 'auth/account-exists-with-different-credential':
        return 'This email already uses another sign-in method. Sign in with your existing method first.';
      default:
        return 'Google sign-in could not be completed in the browser ($code). Please try again.';
    }
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
