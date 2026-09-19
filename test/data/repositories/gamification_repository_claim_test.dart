import 'dart:io';

import 'package:elixr_application/data/models/quest_claim.dart';
import 'package:elixr_application/data/repositories/gamification_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GamificationRepository.claimQuest', () {
    test('maps a successful claimed JSON response', () async {
      final server = await _QuestClaimServer.start((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/claimDailyQuest');
        expect(
          request.headers.value('X-Firebase-Authorization'),
          'Bearer test-token',
        );
        await request.drain<void>();
        _json(request, HttpStatus.ok, '{"status":"claimed","xp_awarded":10}');
      });
      addTearDown(server.close);

      final result = await _claim(_repository(server));

      expect(result.status, QuestClaimStatus.claimed);
      expect(result.xpAwarded, 10);
    });

    test('maps an already_claimed JSON response', () async {
      final server = await _QuestClaimServer.start((request) async {
        _json(request, HttpStatus.ok, '{"status":"already_claimed"}');
      });
      addTearDown(server.close);

      final result = await _claim(_repository(server));

      expect(result.status, QuestClaimStatus.alreadyClaimed);
    });

    test('maps an expected incomplete JSON response', () async {
      final server = await _QuestClaimServer.start((request) async {
        _json(request, HttpStatus.ok, '{"status":"quest_not_completed"}');
      });
      addTearDown(server.close);

      final result = await _claim(_repository(server));

      expect(result.status, QuestClaimStatus.questNotCompleted);
    });

    test(
      'turns an HTML 404 response into a controlled service error',
      () async {
        final server = await _QuestClaimServer.start((request) async {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><head><title>Not found</title></head></html>',
          );
        });
        addTearDown(server.close);

        await expectLater(
          _claim(_repository(server)),
          throwsA(
            isA<QuestClaimServiceException>()
                .having(
                  (error) => error.error,
                  'error',
                  QuestClaimServiceError.unavailable,
                )
                .having(
                  (error) => error.statusCode,
                  'status code',
                  HttpStatus.notFound,
                ),
          ),
        );
      },
    );

    test(
      'turns 401 and 403 responses into controlled authorization errors',
      () async {
        for (final statusCode in [
          HttpStatus.unauthorized,
          HttpStatus.forbidden,
        ]) {
          final server = await _QuestClaimServer.start((request) async {
            _json(request, statusCode, '{"error":"unauthenticated"}');
          });
          try {
            await expectLater(
              _claim(_repository(server)),
              throwsA(
                isA<QuestClaimServiceException>()
                    .having(
                      (error) => error.error,
                      'error',
                      QuestClaimServiceError.unauthorized,
                    )
                    .having(
                      (error) => error.statusCode,
                      'status code',
                      statusCode,
                    ),
              ),
            );
          } finally {
            await server.close();
          }
        }
      },
    );

    test('turns malformed JSON into a controlled service error', () async {
      final server = await _QuestClaimServer.start((request) async {
        _json(request, HttpStatus.ok, '{"status":');
      });
      addTearDown(server.close);

      await expectLater(
        _claim(_repository(server)),
        throwsA(
          isA<QuestClaimServiceException>().having(
            (error) => error.error,
            'error',
            QuestClaimServiceError.malformedResponse,
          ),
        ),
      );
    });

    test('turns an empty response into a controlled service error', () async {
      final server = await _QuestClaimServer.start((request) async {
        _json(request, HttpStatus.ok, '');
      });
      addTearDown(server.close);

      await expectLater(
        _claim(_repository(server)),
        throwsA(
          isA<QuestClaimServiceException>().having(
            (error) => error.error,
            'error',
            QuestClaimServiceError.malformedResponse,
          ),
        ),
      );
    });

    test('turns a 5xx response into a controlled service error', () async {
      final server = await _QuestClaimServer.start((request) async {
        _json(
          request,
          HttpStatus.serviceUnavailable,
          '{"error":"unavailable"}',
        );
      });
      addTearDown(server.close);

      await expectLater(
        _claim(_repository(server)),
        throwsA(
          isA<QuestClaimServiceException>()
              .having(
                (error) => error.error,
                'error',
                QuestClaimServiceError.unavailable,
              )
              .having(
                (error) => error.statusCode,
                'status code',
                HttpStatus.serviceUnavailable,
              ),
        ),
      );
    });

    test('turns a delayed response into a controlled timeout error', () async {
      final server = await _QuestClaimServer.start((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        _json(request, HttpStatus.ok, '{"status":"claimed","xp_awarded":10}');
      });
      addTearDown(server.close);

      await expectLater(
        _claim(
          _repository(server, requestTimeout: const Duration(milliseconds: 25)),
        ),
        throwsA(
          isA<QuestClaimServiceException>().having(
            (error) => error.error,
            'error',
            QuestClaimServiceError.timedOut,
          ),
        ),
      );
    });
  });
}

GamificationRepository _repository(
  _QuestClaimServer server, {
  Duration requestTimeout = const Duration(seconds: 1),
}) => GamificationRepository(
  apiBaseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  tokenProvider: (_) async => 'test-token',
  requestTimeout: requestTimeout,
);

Future<QuestClaimResult> _claim(GamificationRepository repository) =>
    repository.claimQuest(
      userId: 'trainee-1',
      questId: 'session_count_1',
      sessionsToday: const [],
    );

void _json(HttpRequest request, int statusCode, String body) {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(body);
}

class _QuestClaimServer {
  _QuestClaimServer._(this._server);

  final HttpServer _server;

  InternetAddress get address => _server.address;
  int get port => _server.port;

  static Future<_QuestClaimServer> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handler(request);
      } finally {
        try {
          await request.response.close();
        } on HttpException {
          // The timeout test intentionally closes the client first.
        }
      }
    });
    return _QuestClaimServer._(server);
  }

  Future<void> close() => _server.close(force: true);
}
