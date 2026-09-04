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

  test(
    'assignment creation Function failures retain safe actionable detail',
    () {
      final recipient = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'invalid_recipient'},
      );
      expect(recipient.code, ClassroomError.invalidRecipient);
      expect(recipient.message, contains('approved members'));

      final movement = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'invalid_movement'},
      );
      expect(movement.code, ClassroomError.identityMismatch);
      expect(movement.message, contains('no longer available'));

      final staleRevision = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'stale_revision'},
      );
      expect(staleRevision.code, ClassroomError.identityMismatch);
      expect(staleRevision.message, contains('updated'));

      final archived = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'movement_archived'},
      );
      expect(archived.code, ClassroomError.archived);

      final assessment = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'invalid_activity_assessment'},
      );
      expect(assessment.code, ClassroomError.invalidGrade);
      expect(assessment.message, contains('rubric'));

      final instructions = classroomFunctionFailure(
        statusCode: 400,
        responseBody: {'error': 'invalid_instructions'},
      );
      expect(instructions.code, ClassroomError.malformed);
      expect(instructions.message, contains('2,000'));
    },
  );
}
