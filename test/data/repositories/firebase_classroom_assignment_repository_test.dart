import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/repositories/firebase_classroom_assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Function failures retain safe HTTP status and server code', () {
    final conflict = classroomFunctionFailure(
      statusCode: 409,
      responseBody: {'error': 'conflict'},
    );
    expect(conflict.code, ClassroomError.conflict);
    expect(conflict.httpStatus, 409);
    expect(conflict.serverCode, 'conflict');

    expect(
      classroomFunctionFailure(
        statusCode: 409,
        responseBody: {'error': 'attempt_limit_conflict'},
      ).code,
      ClassroomError.attemptLimitConflict,
    );
    expect(
      classroomFunctionFailure(
        statusCode: 409,
        responseBody: {'error': 'invalid_recipient'},
      ).code,
      ClassroomError.invalidRecipient,
    );
    expect(
      classroomFunctionFailure(
        statusCode: 409,
        responseBody: {'error': 'not_found'},
      ).code,
      ClassroomError.notFound,
    );
  });

  test('unknown non-success Function responses fail closed', () {
    final failure = classroomFunctionFailure(
      statusCode: 503,
      responseBody: {'error': 'unavailable'},
    );
    expect(failure.code, ClassroomError.invalidState);
    expect(failure.httpStatus, 503);
    expect(failure.serverCode, 'unavailable');
  });
}
