import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/services/windows_google_oauth_flow.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: 'test-app-id',
  messagingSenderId: 'test-sender-id',
  projectId: 'test-project',
  authDomain: 'test-project.firebaseapp.com',
);

void main() {
  test('returns Google tokens posted by the private loopback page', () async {
    final flow = WindowsGoogleOAuthFlow(
      firebaseOptions: _options,
      browserLauncher: (pageUri) => _openPageAndPost(pageUri, {
        'status': 'success',
        'idToken': 'google-id-token',
        'accessToken': 'google-access-token',
        'isNewUser': true,
      }),
    );

    final credential = await flow.authenticate();

    expect(credential.idToken, 'google-id-token');
    expect(credential.accessToken, 'google-access-token');
    expect(credential.isNewUser, isTrue);
  });

  test('maps browser cancellation to the dedicated exception', () async {
    final flow = WindowsGoogleOAuthFlow(
      firebaseOptions: _options,
      browserLauncher: (pageUri) =>
          _openPageAndPost(pageUri, {'status': 'cancelled'}),
    );

    await expectLater(
      flow.authenticate(),
      throwsA(isA<GoogleSignInCancelledException>()),
    );
  });

  test('returns an actionable unauthorized-domain error', () async {
    final flow = WindowsGoogleOAuthFlow(
      firebaseOptions: _options,
      browserLauncher: (pageUri) => _openPageAndPost(pageUri, {
        'status': 'error',
        'code': 'auth/unauthorized-domain',
      }),
    );

    await expectLater(
      flow.authenticate(),
      throwsA(
        isA<GoogleOAuthFlowException>().having(
          (error) => error.message,
          'message',
          contains('localhost'),
        ),
      ),
    );
  });

  test(
    'rejects Firebase options without an auth domain before launch',
    () async {
      var browserLaunched = false;
      final flow = WindowsGoogleOAuthFlow(
        firebaseOptions: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: 'test-app-id',
          messagingSenderId: 'test-sender-id',
          projectId: 'test-project',
        ),
        browserLauncher: (_) async {
          browserLaunched = true;
        },
      );

      await expectLater(
        flow.authenticate(),
        throwsA(
          isA<GoogleOAuthFlowException>().having(
            (error) => error.message,
            'message',
            contains('auth domain'),
          ),
        ),
      );
      expect(browserLaunched, isFalse);
    },
  );
}

Future<void> _openPageAndPost(Uri pageUri, Map<String, Object?> payload) async {
  final client = HttpClient();
  try {
    final pageRequest = await client.getUrl(pageUri);
    final pageResponse = await pageRequest.close();
    final page = await utf8.decoder.bind(pageResponse).join();
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(page, contains('Continue with Google'));
    expect(page, contains('test-project.firebaseapp.com'));

    final callbackUri = pageUri.replace(path: '${pageUri.path}/complete');
    final callbackRequest = await client.postUrl(callbackUri);
    callbackRequest.headers.contentType = ContentType.json;
    callbackRequest.write(jsonEncode(payload));
    final callbackResponse = await callbackRequest.close();
    await callbackResponse.drain<void>();
    expect(callbackResponse.statusCode, HttpStatus.ok);
  } finally {
    client.close(force: true);
  }
}
