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

User _admin({String id = 'admin-1'}) => User(
  id: id,
  firstName: 'Ad',
  lastName: 'Min',
  email: 'admin@example.com',
  role: User.roleAdmin,
);

User _unknownRole({String id = 'unknown-1'}) => User(
  id: id,
  firstName: 'Un',
  lastName: 'Known',
  email: 'unknown@example.com',
  role: 'Moderator',
);

AppRedirectState _state({
  bool isLoading = false,
  bool isAuthenticated = true,
  User? user,
  bool needsEmailVerification = false,
  String location = AppRoutePaths.dashboard,
  bool hasPendingJoinCode = false,
  bool tutorialInitialized = true,
  bool hasCompletedLesson = true,
  bool hasPendingGoogleProfile = false,
}) {
  return AppRedirectState(
    isLoading: isLoading,
    isAuthenticated: isAuthenticated,
    user: user,
    needsEmailVerification: needsEmailVerification,
    location: location,
    hasPendingJoinCode: hasPendingJoinCode,
    tutorialInitialized: tutorialInitialized,
    practiceMovement: 'Hand Stall',
    practiceDifficulty: 'Easy',
    practiceProp: 'bottle',
    hasCompletedLesson: (_) => hasCompletedLesson,
    hasPendingGoogleProfile: hasPendingGoogleProfile,
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

  test(
    'pending Google profile is restricted to completion and legal routes',
    () {
      expect(
        resolveAppRedirect(
          _state(
            isAuthenticated: false,
            user: null,
            hasPendingGoogleProfile: true,
            location: AppRoutePaths.dashboard,
          ),
        ),
        AppRoutePaths.completeGoogleProfile,
      );
      expect(
        resolveAppRedirect(
          _state(
            isAuthenticated: false,
            user: null,
            hasPendingGoogleProfile: true,
            location: AppRoutePaths.completeGoogleProfile,
          ),
        ),
        isNull,
      );
      expect(
        resolveAppRedirect(
          _state(
            isAuthenticated: false,
            user: null,
            hasPendingGoogleProfile: true,
            location: AppRoutePaths.privacyPolicy,
          ),
        ),
        isNull,
      );
    },
  );

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
          needsEmailVerification: true,
          location: AppRoutePaths.teacherDashboard,
        ),
      ),
      AppRoutePaths.verifyEmail,
    );
    expect(
      resolveAppRedirect(
        _state(
          user: _teacher(),
          needsEmailVerification: true,
          location: AppRoutePaths.verifyEmail,
        ),
      ),
      isNull,
    );
  });

  test('verified trainee on verify-email redirects to dashboard', () {
    expect(
      resolveAppRedirect(
        _state(user: _trainee(), location: AppRoutePaths.verifyEmail),
      ),
      AppRoutePaths.dashboard,
    );
  });

  test('unverified trainee is kept on verify-email', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          needsEmailVerification: true,
          location: AppRoutePaths.dashboard,
        ),
      ),
      AppRoutePaths.verifyEmail,
    );
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          needsEmailVerification: true,
          location: AppRoutePaths.verifyEmail,
        ),
      ),
      isNull,
    );
  });

  test('unverified trainee legal routes stay reachable', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          needsEmailVerification: true,
          location: AppRoutePaths.privacyPolicy,
        ),
      ),
      isNull,
    );
  });

  test('unverified trainee join-code waits for email verification', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          needsEmailVerification: true,
          hasPendingJoinCode: true,
          location: AppRoutePaths.dashboard,
        ),
      ),
      AppRoutePaths.verifyEmail,
    );
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          needsEmailVerification: true,
          hasPendingJoinCode: true,
          location: AppRoutePaths.joinCoach,
        ),
      ),
      AppRoutePaths.verifyEmail,
    );
  });

  test('verified teacher on verify-email redirects to teacher dashboard', () {
    expect(
      resolveAppRedirect(
        _state(user: _teacher(), location: AppRoutePaths.verifyEmail),
      ),
      AppRoutePaths.teacherDashboard,
    );
  });

  test('unauthenticated verify-email redirects to login', () {
    expect(
      resolveAppRedirect(
        _state(
          isAuthenticated: false,
          user: null,
          location: AppRoutePaths.verifyEmail,
        ),
      ),
      AppRoutePaths.login,
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
      expect(
        resolveAppRedirect(
          _state(
            user: _teacher(),
            location: AppRoutePaths.assignedPractice('asg1'),
          ),
        ),
        AppRoutePaths.teacherDashboard,
      );
      expect(
        resolveAppRedirect(
          _state(user: _teacher(), location: AppRoutePaths.assignedMovements),
        ),
        AppRoutePaths.teacherDashboard,
      );
    },
  );

  test('trainee assigned practice stays reachable', () {
    expect(
      resolveAppRedirect(
        _state(
          user: _trainee(),
          location: AppRoutePaths.assignedPractice('asg1'),
        ),
      ),
      isNull,
    );
    expect(
      resolveAppRedirect(
        _state(user: _trainee(), location: AppRoutePaths.assignedMovements),
      ),
      isNull,
    );
  });

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

  test('admin role cannot enter trainee or teacher product routes', () {
    for (final location in [
      AppRoutePaths.dashboard,
      AppRoutePaths.practice,
      AppRoutePaths.livePractice,
      AppRoutePaths.joinCoach,
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.teacherSettings,
      AppRoutePaths.verifyEmail,
    ]) {
      final result = resolveAppRedirect(
        _state(user: _admin(), location: location),
      );
      expect(result, isNot(AppRoutePaths.dashboard), reason: location);
      expect(result, isNot(AppRoutePaths.teacherDashboard), reason: location);
      expect(result, isNotNull, reason: location);
      expect(result, isNot(location), reason: location);
    }

    expect(
      resolveAppRedirect(_state(user: _admin(), location: AppRoutePaths.login)),
      isNull,
    );
  });

  test('unknown role cannot enter trainee or teacher product routes', () {
    for (final location in [
      AppRoutePaths.dashboard,
      AppRoutePaths.practice,
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.verifyEmail,
    ]) {
      final result = resolveAppRedirect(
        _state(user: _unknownRole(), location: location),
      );
      expect(result, isNot(AppRoutePaths.dashboard), reason: location);
      expect(result, isNot(AppRoutePaths.teacherDashboard), reason: location);
      expect(result, isNotNull, reason: location);
      expect(result, isNot(location), reason: location);
    }

    expect(
      resolveAppRedirect(
        _state(user: _unknownRole(), location: AppRoutePaths.login),
      ),
      isNull,
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
