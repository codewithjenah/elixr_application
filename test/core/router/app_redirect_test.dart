import 'package:elixr_application/core/router/app_redirect.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

User _trainee({String id = 'trainee-1'}) => User(
  id: id,
  firstName: 'Train',
  lastName: 'Ee',
  email: 'trainee@example.com',
  role: User.roleTrainee,
);

User _teacher({String id = 'teacher-1'}) => User(
  id: id,
  firstName: 'Tea',
  lastName: 'Cher',
  email: 'teacher@example.com',
  role: User.roleTeacher,
);

AppRedirectState _state({
  bool isLoading = false,
  bool isAuthenticated = true,
  User? user,
  bool needsTeacherEmailVerification = false,
  String location = AppRoutePaths.dashboard,
  bool hasPendingJoinCode = false,
  bool tutorialInitialized = true,
  bool hasCompletedLesson = true,
}) {
  return AppRedirectState(
    isLoading: isLoading,
    isAuthenticated: isAuthenticated,
    user: user,
    needsTeacherEmailVerification: needsTeacherEmailVerification,
    location: location,
    hasPendingJoinCode: hasPendingJoinCode,
    tutorialInitialized: tutorialInitialized,
    practiceMovement: 'Hand Stall',
    practiceDifficulty: 'Easy',
    practiceProp: 'bottle',
    hasCompletedLesson: (_) => hasCompletedLesson,
  );
}

void main() {
  test('loading never redirects', () {
    expect(
      resolveAppRedirect(
        _state(isLoading: true, isAuthenticated: false, user: null),
      ),
      isNull,
    );
  });

  test('unauthenticated protected route redirects to login', () {
    expect(
      resolveAppRedirect(
        _state(
          isAuthenticated: false,
          user: null,
          location: AppRoutePaths.dashboard,
        ),
      ),
      AppRoutePaths.login,
    );
  });

  test('unauthenticated legal routes stay reachable', () {
    expect(
      resolveAppRedirect(
        _state(
          isAuthenticated: false,
          user: null,
          location: AppRoutePaths.privacyPolicy,
        ),
      ),
      isNull,
    );
  });

  test('authenticated trainee on auth route redirects to dashboard', () {
    expect(
      resolveAppRedirect(
        _state(user: _trainee(), location: AppRoutePaths.login),
      ),
      AppRoutePaths.dashboard,
    );
  });

  test(
    'authenticated verified teacher on auth route redirects to teacher dashboard',
    () {
      expect(
        resolveAppRedirect(
          _state(user: _teacher(), location: AppRoutePaths.login),
        ),
        AppRoutePaths.teacherDashboard,
      );
    },
  );

  test('unverified teacher is kept on verify-email', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _teacher(),
          needsTeacherEmailVerification: true,
          location: AppRoutePaths.teacherDashboard,
        ),
      ),
      AppRoutePaths.verifyEmail,
    );
    expect(
      resolveAppRedirect(
        _state(
          user: _teacher(),
          needsTeacherEmailVerification: true,
          location: AppRoutePaths.verifyEmail,
        ),
      ),
      isNull,
    );
  });

  test(
    'verified teacher on practice routes redirects to teacher dashboard',
    () {
      expect(
        resolveAppRedirect(
          _state(user: _teacher(), location: AppRoutePaths.practice),
        ),
        AppRoutePaths.teacherDashboard,
      );
      expect(
        resolveAppRedirect(
          _state(user: _teacher(), location: AppRoutePaths.dashboard),
        ),
        AppRoutePaths.teacherDashboard,
      );
    },
  );

  test('trainee on teacher routes redirects to trainee dashboard', () {
    expect(
      resolveAppRedirect(
        _state(user: _trainee(), location: AppRoutePaths.teacherDashboard),
      ),
      AppRoutePaths.dashboard,
    );
  });

  test('trainee with pending join code redirects to join-coach', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          hasPendingJoinCode: true,
          location: AppRoutePaths.dashboard,
        ),
      ),
      AppRoutePaths.joinCoach,
    );
  });

  test('teacher with pending join code does not enter join-coach', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _teacher(),
          hasPendingJoinCode: true,
          location: AppRoutePaths.dashboard,
        ),
      ),
      AppRoutePaths.teacherDashboard,
    );
    expect(
      resolveAppRedirect(
        _state(
          user: _teacher(),
          hasPendingJoinCode: true,
          location: AppRoutePaths.joinCoach,
        ),
      ),
      AppRoutePaths.teacherDashboard,
    );
  });

  test('trainee practice redirects to lesson when incomplete', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          location: AppRoutePaths.practice,
          hasCompletedLesson: false,
        ),
      ),
      '/learn/movement/Hand%20Stall?difficulty=Easy&prop=bottle',
    );
  });

  test('never redirects to the current location', () {
    final locations = [
      AppRoutePaths.login,
      AppRoutePaths.register,
      AppRoutePaths.registerTeacher,
      AppRoutePaths.verifyEmail,
      AppRoutePaths.dashboard,
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.joinCoach,
    ];

    for (final location in locations) {
      final result = resolveAppRedirect(
        _state(user: _trainee(), location: location),
      );
      expect(result, isNot(location), reason: 'trainee at $location');
    }
  });
}
