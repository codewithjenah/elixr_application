import 'package:elixr_core/models/user.dart';

import '../../data/models/training_prop.dart';
import '../progression/practice_variant.dart';
import '../progression/progression_access.dart';
import '../progression/progression_catalog.dart';
import 'app_route_paths.dart';

/// Inputs required to resolve role-aware redirects for [AppRouter].
class AppRedirectState {
  const AppRedirectState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.user,
    required this.needsEmailVerification,
    required this.location,
    required this.hasPendingJoinCode,
    required this.tutorialInitialized,
    required this.practiceMovement,
    required this.practiceProp,
    required this.hasCompletedLesson,
    this.currentLevel,
    this.hasPendingGoogleProfile = false,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final User? user;
  final bool needsEmailVerification;
  final String location;
  final bool hasPendingJoinCode;
  final bool tutorialInitialized;
  final String? practiceMovement;
  final String? practiceProp;
  final bool Function(String movement, TrainingProp prop) hasCompletedLesson;

  /// Already-resolved trainee level. Null means personal XP is still loading.
  final int? currentLevel;
  final bool hasPendingGoogleProfile;
}

/// Returns a redirect location, or null when [state.location] is already valid.
String? resolveAppRedirect(AppRedirectState state) {
  if (state.isLoading) return null;

  final location = state.location;
  final isAuthRoute = AppRoutePaths.authRoutes.contains(location);
  final isLegalRoute = AppRoutePaths.legalRoutes.contains(location);
  final isVerifyRoute = location == AppRoutePaths.verifyEmail;
  final isPublicRoute = isAuthRoute || isLegalRoute;

  if (state.hasPendingGoogleProfile) {
    if (location == AppRoutePaths.completeGoogleProfile || isLegalRoute) {
      return null;
    }
    return AppRoutePaths.completeGoogleProfile;
  }

  if (!state.isAuthenticated) {
    if (isPublicRoute) return null;
    return AppRoutePaths.login;
  }

  final user = state.user;
  final isTeacher = user?.isTeacher ?? false;
  final isTrainee = user?.isTrainee ?? false;

  if (isTeacher) {
    return _redirectAuthenticatedTeacher(
      location: location,
      isAuthRoute: isAuthRoute,
      isLegalRoute: isLegalRoute,
      isVerifyRoute: isVerifyRoute,
      needsVerification: state.needsEmailVerification,
    );
  }

  if (isTrainee) {
    return _redirectAuthenticatedTrainee(
      state: state,
      location: location,
      isAuthRoute: isAuthRoute,
      isLegalRoute: isLegalRoute,
      isVerifyRoute: isVerifyRoute,
      needsVerification: state.needsEmailVerification,
    );
  }

  // Unsupported persisted role (Admin, malformed, unknown) must not inherit
  // Trainee or Teacher product routing. Keep auth/legal surfaces to avoid
  // redirect loops; send every other location back to login.
  if (isAuthRoute || isLegalRoute) return null;
  return AppRoutePaths.login;
}

String? _redirectAuthenticatedTeacher({
  required String location,
  required bool isAuthRoute,
  required bool isLegalRoute,
  required bool isVerifyRoute,
  required bool needsVerification,
}) {
  if (needsVerification) {
    if (isVerifyRoute || isLegalRoute) return null;
    return AppRoutePaths.verifyEmail;
  }

  if (isAuthRoute || isVerifyRoute) {
    return AppRoutePaths.teacherDashboard;
  }

  if (location == AppRoutePaths.joinCoach) {
    return AppRoutePaths.teacherDashboard;
  }

  if (AppRoutePaths.isTraineeShellRoute(location) ||
      AppRoutePaths.isTraineePracticeRoute(location) ||
      location == AppRoutePaths.joinCoach) {
    return AppRoutePaths.teacherDashboard;
  }

  return null;
}

String? _redirectAuthenticatedTrainee({
  required AppRedirectState state,
  required String location,
  required bool isAuthRoute,
  required bool isLegalRoute,
  required bool isVerifyRoute,
  required bool needsVerification,
}) {
  if (needsVerification) {
    if (isVerifyRoute || isLegalRoute) return null;
    return AppRoutePaths.verifyEmail;
  }

  if (isVerifyRoute || AppRoutePaths.isTeacherShellRoute(location)) {
    return AppRoutePaths.dashboard;
  }

  if (state.hasPendingJoinCode && location != AppRoutePaths.teacherAccess) {
    return AppRoutePaths.teacherAccess;
  }

  if (isAuthRoute) return AppRoutePaths.dashboard;

  // Classroom is the single entry point for trainee assignments. Keep the
  // legacy path only as a redirect for old links and navigation history.
  if (location == AppRoutePaths.assignedMovements) {
    return AppRoutePaths.teacherAccess;
  }

  if (location == AppRoutePaths.practice) {
    final step = resolveStrictPracticeRouteVariant(
      movementName: state.practiceMovement,
      propProtocolValue: state.practiceProp,
    );
    if (step == null) return AppRoutePaths.movements;
    final movement = step.movement.name;
    final prop = step.prop;
    final variant = PracticeVariant(movementName: movement, trainingProp: prop);
    final access = evaluatePersonal(
      variant: variant,
      currentLevel: state.currentLevel,
      tutorialCompleted: state.tutorialInitialized
          ? state.hasCompletedLesson(movement, prop)
          : null,
    );
    switch (access) {
      case ProgressionAccessResult.personalReady:
        return null;
      case ProgressionAccessResult.personalLearn:
        return '/learn/movement/${Uri.encodeComponent(movement)}'
            '?difficulty=${step.movement.difficulty}&prop=${prop.protocolValue}';
      case ProgressionAccessResult.personalLoading:
      case ProgressionAccessResult.personalLocked:
      case ProgressionAccessResult.invalid:
        return AppRoutePaths.movements;
      case ProgressionAccessResult.assignmentLoading:
      case ProgressionAccessResult.assignmentLearn:
      case ProgressionAccessResult.assignmentReady:
        // Personal practice redirect never evaluates assignment grants.
        return AppRoutePaths.movements;
    }
  }

  return null;
}
