/// Canonical route paths for the unified ELIXR Windows application.
abstract final class AppRoutePaths {
  // Public auth
  static const login = '/login';
  static const register = '/register';
  static const registerTeacher = '/register/teacher';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';
  static const completeGoogleProfile = '/complete-google-profile';

  // Legal
  static const privacyPolicy = '/privacy-policy';
  static const termsOfService = '/terms-of-service';

  // Trainee join
  static const joinCoach = '/join-coach';
  static const teacherAccess = '/teacher-access';

  // Trainee practice (outside shell)
  static const practice = '/practice';
  static const livePractice = '/live-practice';

  // Trainee shell
  static const dashboard = '/dashboard';
  static const leaderboard = '/leaderboard';
  static const movements = '/movements';
  static const assignedMovements = '/assigned-movements';
  static const assignedPracticePrefix = '/assigned-practice';
  static const learn = '/learn';
  static const training = '/training';
  static const history = '/history';
  static const calendar = '/calendar';
  static const coaching = '/coaching';
  static const messages = '/messages';
  static const progress = '/progress';
  static const achievements = '/achievements';

  // Teacher shell
  static const teacherDashboard = '/teacher/dashboard';
  static const teacherGroups = '/teacher/groups';
  static const teacherFaculties = '/teacher/faculties';
  static const teacherStudents = '/teacher/students';
  static const teacherStudentDetailSegment = 'students';
  static const teacherLeaderboard = '/teacher/leaderboard';
  static const teacherAnalytics = '/teacher/analytics';
  static const teacherMovements = '/teacher/movements';
  static const teacherActivityCenter = '/teacher/activity-center';
  static const teacherMessages = '/teacher/messages';
  static const teacherSettings = '/teacher/settings';
  static const teacherSettingsSectionQuery = 'section';
  static const teacherProfilePrefix = '/teacher/profile';

  static const authRoutes = {
    login,
    register,
    registerTeacher,
    forgotPassword,
    completeGoogleProfile,
  };

  static const legalRoutes = {privacyPolicy, termsOfService};

  static const teacherShellRoutes = {
    teacherDashboard,
    teacherGroups,
    teacherFaculties,
    teacherStudents,
    teacherLeaderboard,
    teacherAnalytics,
    teacherMovements,
    teacherActivityCenter,
    teacherMessages,
    teacherSettings,
  };

  static const traineeShellRoutes = {
    dashboard,
    teacherAccess,
    leaderboard,
    movements,
    assignedMovements,
    learn,
    training,
    history,
    calendar,
    coaching,
    messages,
    progress,
    achievements,
  };

  static const traineePracticeRoutes = {practice, livePractice};

  static String teacherAccessClass(String groupId) {
    return '$teacherAccess/${Uri.encodeComponent(groupId)}';
  }

  static String teacherAccessClassWork(String groupId) {
    return '${teacherAccessClass(groupId)}/work';
  }

  static String groupIdFromTeacherAccessClass(String location) {
    final prefix = '$teacherAccess/';
    if (!location.startsWith(prefix)) return '';
    return Uri.decodeComponent(
      location.substring(prefix.length).split('?').first,
    );
  }

  static String teacherGroup(String groupId) {
    return '$teacherGroups/${Uri.encodeComponent(groupId)}';
  }

  static String teacherGroupClasswork(
    String groupId,
    String assignmentId, {
    String? traineeId,
  }) {
    final path =
        '${teacherGroup(groupId)}/classwork/'
        '${Uri.encodeComponent(assignmentId)}';
    final student = traineeId?.trim();
    if (student == null || student.isEmpty) return path;
    return '$path?traineeId=${Uri.encodeQueryComponent(student)}';
  }

  static String groupIdFromTeacherGroup(String location) {
    final prefix = '$teacherGroups/';
    if (!location.startsWith(prefix)) return '';
    return Uri.decodeComponent(
      location.substring(prefix.length).split('?').first,
    );
  }

  static String assignmentDetail(String assignmentId) {
    return '$assignedMovements/${Uri.encodeComponent(assignmentId)}';
  }

  static String assignmentIdFromAssignmentDetail(String location) {
    final prefix = '$assignedMovements/';
    if (!location.startsWith(prefix)) return '';
    return Uri.decodeComponent(
      location.substring(prefix.length).split('?').first,
    );
  }

  static String assignedPractice(String assignmentId) {
    return '$assignedPracticePrefix/${Uri.encodeComponent(assignmentId)}';
  }

  static String assignmentIdFromAssignedPractice(String location) {
    final prefix = '$assignedPracticePrefix/';
    if (!location.startsWith(prefix)) return '';
    return Uri.decodeComponent(
      location.substring(prefix.length).split('?').first,
    );
  }

  static String movementLesson({
    required String movement,
    required String difficulty,
    required String prop,
    String? assignmentId,
  }) {
    final base =
        '/learn/movement/${Uri.encodeComponent(movement)}'
        '?difficulty=$difficulty&prop=$prop';
    final id = assignmentId?.trim();
    if (id == null || id.isEmpty) return base;
    return '$base&assignmentId=${Uri.encodeComponent(id)}';
  }

  static bool isTeacherShellRoute(String location) {
    return location.startsWith('/teacher/');
  }

  static String teacherStudentDetail(String traineeId, {String? groupId}) {
    final base = '/teacher/students/${Uri.encodeComponent(traineeId)}';
    if (groupId == null || groupId.isEmpty) return base;
    return '$base?groupId=${Uri.encodeQueryComponent(groupId)}';
  }

  static String teacherProfile(String userId) {
    return '$teacherProfilePrefix/${Uri.encodeComponent(userId)}';
  }

  /// Teacher Settings with a `?section=` pane (`accountProfile`, `privacy`, ...).
  static String teacherSettingsWithSection(String sectionName) {
    return '$teacherSettings?$teacherSettingsSectionQuery='
        '${Uri.encodeComponent(sectionName)}';
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
        location.startsWith('$livePractice?') ||
        location == assignedPracticePrefix ||
        location.startsWith('$assignedPracticePrefix/');
  }
}
