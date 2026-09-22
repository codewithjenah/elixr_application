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
  static const movementsLibraryQuery = 'library';
  static const myMovementsLibraryValue = 'mine';
  static const myMovements = '/my-movements';
  static const assignedMovements = '/assigned-movements';
  static const assignedPracticePrefix = '/assigned-practice';
  static const classChallengePlayPrefix = '/class-challenge-play';
  static const learn = '/learn';
  static const training = '/training';
  static const history = '/history';
  static const calendar = '/calendar';
  static const coaching = '/coaching';
  static const messages = '/messages';
  static const activityCenter = '/activity-center';
  static const progress = '/progress';
  static const achievements = '/achievements';

  // Teacher shell
  static const teacherDashboard = '/teacher/dashboard';
  static const teacherCalendar = '/teacher/calendar';
  static const teacherGroups = '/teacher/groups';
  static const teacherFaculties = '/teacher/faculties';
  static const teacherStudents = '/teacher/students';
  static const teacherStudentDetailSegment = 'students';
  static const teacherLeaderboard = '/teacher/leaderboard';
  static const teacherAnalytics = '/teacher/analytics';

  /// Legacy deep link retained only to redirect existing URLs to Analytics.
  static const teacherProgress = '/teacher/progress';
  static const teacherMovements = '/teacher/movements';
  static const teacherMovementPreview = '/teacher/movements/preview';
  static const teacherToReview = '/teacher/to-review';
  static const teacherGrades = '/teacher/grades';
  static const teacherGradesGroupQuery = 'groupId';
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
    teacherCalendar,
    teacherGroups,
    teacherFaculties,
    teacherStudents,
    teacherLeaderboard,
    teacherAnalytics,
    teacherProgress,
    teacherMovements,
    teacherToReview,
    teacherGrades,
    teacherActivityCenter,
    teacherMessages,
    teacherSettings,
  };

  static const traineeShellRoutes = {
    dashboard,
    teacherAccess,
    leaderboard,
    movements,
    myMovements,
    assignedMovements,
    learn,
    training,
    history,
    calendar,
    coaching,
    messages,
    activityCenter,
    progress,
    achievements,
  };

  static const traineePracticeRoutes = {practice, livePractice};

  /// Canonical Movements destination with the personal library selected.
  static String get movementsMyMovements =>
      '$movements?$movementsLibraryQuery=$myMovementsLibraryValue';

  static bool opensMyMovementsLibrary(Uri uri) =>
      uri.queryParameters[movementsLibraryQuery] == myMovementsLibraryValue;

  /// Personal practice opened from the canonical Movements > My Movements
  /// library. The legacy [myMovementPractice] route remains available for
  /// existing deep links.
  static String movementsMyMovementPractice(String movementId) =>
      '$movements/practice/${Uri.encodeComponent(movementId)}';

  /// Legacy personal-practice deep link.
  static String myMovementPractice(String movementId) =>
      '$myMovements/practice/${Uri.encodeComponent(movementId)}';

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

  static String teacherClassChallengeLeaderboard(
    String groupId,
    String challengeId,
  ) =>
      '${teacherGroup(groupId)}/challenges/${Uri.encodeComponent(challengeId)}';

  static String classChallengeLeaderboard(String groupId, String challengeId) =>
      '${teacherAccessClass(groupId)}/challenges/${Uri.encodeComponent(challengeId)}';

  static String classChallengePlay(String groupId, String challengeId) =>
      '$classChallengePlayPrefix/${Uri.encodeComponent(groupId)}/'
      '${Uri.encodeComponent(challengeId)}';

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

  /// Personal practice entry with the exact query contract consumed by the
  /// strict practice redirect.
  static String personalPractice({
    required String movement,
    required String difficulty,
    required String prop,
  }) =>
      '$practice?movement=${Uri.encodeComponent(movement)}'
      '&difficulty=${Uri.encodeComponent(difficulty)}'
      '&prop=${Uri.encodeComponent(prop)}';

  /// Teacher-only, non-persistent preview of an official catalog variant.
  static String teacherPreviewMovement({
    required String movement,
    required String prop,
  }) =>
      '$teacherMovementPreview?movement=${Uri.encodeComponent(movement)}'
      '&prop=${Uri.encodeComponent(prop)}';

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

  static String teacherGradesForGroup(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) return teacherGrades;
    return '$teacherGrades?$teacherGradesGroupQuery='
        '${Uri.encodeQueryComponent(id)}';
  }

  static String teacherStudentDetail(String traineeId, {String? groupId}) {
    final base = '/teacher/students/${Uri.encodeComponent(traineeId)}';
    if (groupId == null || groupId.isEmpty) return base;
    return '$base?groupId=${Uri.encodeQueryComponent(groupId)}';
  }

  static String teacherStudentClasswork(
    String traineeId, {
    required String groupId,
  }) =>
      '/teacher/students/${Uri.encodeComponent(traineeId)}/classwork'
      '?groupId=${Uri.encodeQueryComponent(groupId)}';

  static String teacherStudentAssignmentReview(
    String traineeId, {
    required String groupId,
    required String assignmentId,
  }) =>
      '/teacher/students/${Uri.encodeComponent(traineeId)}/classwork/'
      '${Uri.encodeComponent(assignmentId)}?groupId=${Uri.encodeQueryComponent(groupId)}';

  static String teacherStudentPracticeHistory(
    String traineeId, {
    String? groupId,
  }) {
    final base = '/teacher/students/${Uri.encodeComponent(traineeId)}/practice';
    return groupId == null || groupId.isEmpty
        ? base
        : '$base?groupId=${Uri.encodeQueryComponent(groupId)}';
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
        location.startsWith('$classChallengePlayPrefix/') ||
        location.startsWith('$livePractice?') ||
        location == assignedPracticePrefix ||
        location.startsWith('$assignedPracticePrefix/');
  }
}
