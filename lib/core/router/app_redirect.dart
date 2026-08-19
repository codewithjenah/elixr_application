import 'package:elixr_core/models/user.dart';

import 'app_route_paths.dart';

/// Inputs required to resolve role-aware redirects for [AppRouter].
class AppRedirectState {
  const AppRedirectState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.user,
    required this.needsTeacherEmailVerification,
    required this.location,
    required this.hasPendingJoinCode,
    required this.tutorialInitialized,
    required this.practiceMovement,
    required this.practiceDifficulty,
    required this.practiceProp,
    required this.hasCompletedLesson,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final User? user;
  final bool needsTeacherEmailVerification;
  final String location;
  final bool hasPendingJoinCode;
  final bool tutorialInitialized;
  final String practiceMovement;
  final String practiceDifficulty;
  final String practiceProp;
  final bool Function(String movement) hasCompletedLesson;
}

/// Returns a redirect location, or null when [state.location] is already valid.
String? resolveAppRedirect(AppRedirectState state) {
  if (state.isLoading) return null;

  final location = state.location;
  final isAuthRoute = AppRoutePaths.authRoutes.contains(location);
  final isLegalRoute = AppRoutePaths.legalRoutes.contains(location);
  final isVerifyRoute = location == AppRoutePaths.verifyEmail;
  final isPublicRoute = isAuthRoute || isLegalRoute;

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
      needsVerification: state.needsTeacherEmailVerification,
    );
  }

  if (isTrainee || user != null) {
    return _redirectAuthenticatedTrainee(
      state: state,
      location: location,
      isAuthRoute: isAuthRoute,
      isLegalRoute: isLegalRoute,
    );
  }

  // Unknown role (e.g. Admin): keep trainee-safe routing.
  if (AppRoutePaths.isTeacherShellRoute(location)) {
    return AppRoutePaths.dashboard;
  }
  if (isAuthRoute) return AppRoutePaths.dashboard;
  return null;
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
}) {
  if (AppRoutePaths.isTeacherShellRoute(location)) {
    return AppRoutePaths.dashboard;
  }

  if (state.hasPendingJoinCode && location != AppRoutePaths.joinCoach) {
    return AppRoutePaths.joinCoach;
  }

  if (isAuthRoute) return AppRoutePaths.dashboard;

  if (location == AppRoutePaths.practice && state.tutorialInitialized) {
    final movement = state.practiceMovement;
    if (!state.hasCompletedLesson(movement)) {
      return '/learn/movement/${Uri.encodeComponent(movement)}'
          '?difficulty=${state.practiceDifficulty}&prop=${state.practiceProp}';
    }
  }

  return null;
}
