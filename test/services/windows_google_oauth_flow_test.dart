import 'dart:io';

import 'package:elixr_application/services/windows_google_oauth_flow.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uri> _authorizationUrl(Uri redirect) async => Uri.parse(
  'https://auth.example.test/authorize',
).replace(queryParameters: {'redirect_to': redirect.toString()});

/// Simulates the browser returning from the auth server to the loopback.
GoogleBrowserLauncher _returnWith(Map<String, String> params) {
  return (authorizationUri) async {
    final redirect = Uri.parse(
      authorizationUri.queryParameters['redirect_to']!,
    );
    expect(redirect.host, 'localhost');
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        redirect.replace(queryParameters: params),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.ok);
    } finally {
      client.close(force: true);
    }
  };
}

void main() {
  test('returns the PKCE code delivered to the private loopback', () async {
    final flow = WindowsGoogleOAuthFlow(
      browserLauncher: _returnWith({'code': 'one-time-code'}),
    );

    final credential = await flow.authenticate(_authorizationUrl);

    expect(credential.authorizationCode, 'one-time-code');
  });

  test('maps provider access denial to the dedicated exception', () async {
    final flow = WindowsGoogleOAuthFlow(
      browserLauncher: _returnWith({'error': 'access_denied'}),
    );

    await expectLater(
      flow.authenticate(_authorizationUrl),
      throwsA(isA<GoogleSignInCancelledException>()),
    );
  });

  test('returns an actionable redirect configuration error', () async {
    final flow = WindowsGoogleOAuthFlow(
      browserLauncher: _returnWith({
        'error': 'invalid_request',
        'error_description': 'redirect url not allowed',
      }),
    );

    await expectLater(
      flow.authenticate(_authorizationUrl),
      throwsA(
        isA<GoogleOAuthFlowException>().having(
          (error) => error.message,
          'message',
          contains('localhost'),
        ),
      ),
    );
  });

  test('ignores requests to paths other than the random callback', () async {
    late Uri callback;
    final flow = WindowsGoogleOAuthFlow(
      timeout: const Duration(seconds: 2),
      browserLauncher: (authorizationUri) async {
        callback = Uri.parse(authorizationUri.queryParameters['redirect_to']!);
        final client = HttpClient();
        try {
          final wrong = await client.getUrl(
            callback.replace(
              path: '/elixr-google/guess/callback',
              query: 'code=x',
            ),
          );
          final response = await wrong.close();
          await response.drain<void>();
          expect(response.statusCode, HttpStatus.notFound);
          final right = await client.getUrl(
            callback.replace(query: 'code=real'),
          );
          await (await right.close()).drain<void>();
        } finally {
          client.close(force: true);
        }
      },
    );

    final credential = await flow.authenticate(_authorizationUrl);
    expect(credential.authorizationCode, 'real');
  });
}
