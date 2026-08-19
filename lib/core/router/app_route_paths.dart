/// Canonical route paths for the unified ELIXR Windows application.
abstract final class AppRoutePaths {
  // Public auth
  static const login = '/login';
  static const register = '/register';
  static const registerTeacher = '/register/teacher';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';

  // Legal
  static const privacyPolicy = '/privacy-policy';
  static const termsOfService = '/terms-of-service';

  // Trainee join
  static const joinCoach = '/join-coach';

  // Trainee practice (outside shell)
  static const practice = '/practice';
  static const livePractice = '/live-practice';

  // Trainee shell
  static const dashboard = '/dashboard';
  static const leaderboard = '/leaderboard';
  static const movements = '/movements';
  static const learn = '/learn';
  static const training = '/training';
  static const history = '/history';
  static const calendar = '/calendar';
  static const coaching = '/coaching';
  static const progress = '/progress';
  static const achievements = '/achievements';

  // Teacher shell
  static const teacherDashboard = '/teacher/dashboard';
  static const teacherGroups = '/teacher/groups';
  static const teacherStudents = '/teacher/students';
  static const teacherStudentDetailSegment = 'students';
  static const teacherLeaderboard = '/teacher/leaderboard';
  static const teacherMovements = '/teacher/movements';
  static const teacherSettings = '/teacher/settings';

  static const authRoutes = {login, register, registerTeacher, forgotPassword};

  static const legalRoutes = {privacyPolicy, termsOfService};

  static const teacherShellRoutes = {
    teacherDashboard,
    teacherGroups,
    teacherStudents,
    teacherLeaderboard,
    teacherMovements,
    teacherSettings,
  };

  static const traineeShellRoutes = {
    dashboard,
    leaderboard,
    movements,
    learn,
    training,
    history,
    calendar,
    coaching,
    progress,
    achievements,
  };

  static const traineePracticeRoutes = {practice, livePractice};

  static bool isTeacherShellRoute(String location) {
    return location.startsWith('/teacher/');
  }

  static String teacherStudentDetail(String traineeId, {String? groupId}) {
    final base = '/teacher/students/$traineeId';
    if (groupId == null || groupId.isEmpty) return base;
    return '$base?groupId=$groupId';
  }

  static bool isTraineeShellRoute(String location) {
    for (final route in traineeShellRoutes) {
      if (location == route || location.startsWith('$route/')) {
        return true;
      }
    }
    if (location.startsWith('/profile/')) return true;
    if (location.startsWith('/learn/')) return true;
    return false;
  }

  static bool isTraineePracticeRoute(String location) {
    return location == practice ||
        location.startsWith('$practice?') ||
        location == livePractice ||
        location.startsWith('$livePractice?');
  }
}
