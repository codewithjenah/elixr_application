import 'package:elixr_teacher/core/router/teacher_routes.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const locations = [
    TeacherRoutes.login,
    TeacherRoutes.register,
    TeacherRoutes.forgotPassword,
    TeacherRoutes.verifyEmail,
    TeacherRoutes.privacyPolicy,
    TeacherRoutes.termsOfService,
    TeacherRoutes.roster,
  ];

  test('never redirects to the current location', () {
    for (final status in TeacherAuthStatus.values) {
      for (final location in locations) {
        final result = resolveTeacherRedirect(
          status: status,
          location: location,
        );
        expect(
          result,
          isNot(location),
          reason: '$status at $location redirected to itself',
        );
      }
    }
  });

  test('initializing never redirects', () {
    for (final location in locations) {
      expect(
        resolveTeacherRedirect(
          status: TeacherAuthStatus.initializing,
          location: location,
        ),
        isNull,
      );
    }
  });

  test('legal routes stay reachable while signed out or unverified', () {
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.signedOut,
        location: TeacherRoutes.privacyPolicy,
      ),
      isNull,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.unverifiedTeacher,
        location: TeacherRoutes.termsOfService,
      ),
      isNull,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.authenticatedTeacher,
        location: TeacherRoutes.privacyPolicy,
      ),
      isNull,
    );
  });

  test('signed-out users are sent to login from protected routes', () {
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.signedOut,
        location: TeacherRoutes.roster,
      ),
      TeacherRoutes.login,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.signedOut,
        location: TeacherRoutes.verifyEmail,
      ),
      TeacherRoutes.login,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.signedOut,
        location: TeacherRoutes.login,
      ),
      isNull,
    );
  });

  test('unverified Teachers are kept on verify-email', () {
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.unverifiedTeacher,
        location: TeacherRoutes.roster,
      ),
      TeacherRoutes.verifyEmail,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.unverifiedTeacher,
        location: TeacherRoutes.login,
      ),
      TeacherRoutes.verifyEmail,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.unverifiedTeacher,
        location: TeacherRoutes.verifyEmail,
      ),
      isNull,
    );
  });

  test('verified Teachers are kept out of auth routes', () {
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.authenticatedTeacher,
        location: TeacherRoutes.login,
      ),
      TeacherRoutes.roster,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.authenticatedTeacher,
        location: TeacherRoutes.register,
      ),
      TeacherRoutes.roster,
    );
    expect(
      resolveTeacherRedirect(
        status: TeacherAuthStatus.authenticatedTeacher,
        location: TeacherRoutes.roster,
      ),
      isNull,
    );
  });
}
