import '../../features/auth/teacher_auth_controller.dart';

abstract final class TeacherRoutes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';
  static const privacyPolicy = '/privacy-policy';
  static const termsOfService = '/terms-of-service';
  static const roster = '/roster';
}

/// Redirects for the Teacher app. Returns null when the current location is
/// already valid for [status], which is what prevents redirect loops.
String? resolveTeacherRedirect({
  required TeacherAuthStatus status,
  required String location,
}) {
  final isAuthRoute =
      location == TeacherRoutes.login ||
      location == TeacherRoutes.register ||
      location == TeacherRoutes.forgotPassword;
  final isLegalRoute =
      location == TeacherRoutes.privacyPolicy ||
      location == TeacherRoutes.termsOfService;
  final isVerifyRoute = location == TeacherRoutes.verifyEmail;

  switch (status) {
    case TeacherAuthStatus.initializing:
    case TeacherAuthStatus.initializationFailed:
      return null;
    case TeacherAuthStatus.signedOut:
      if (isAuthRoute || isLegalRoute) return null;
      return TeacherRoutes.login;
    case TeacherAuthStatus.unverifiedTeacher:
      if (isVerifyRoute || isLegalRoute) return null;
      return TeacherRoutes.verifyEmail;
    case TeacherAuthStatus.authenticatedTeacher:
      if (isAuthRoute || isVerifyRoute) return TeacherRoutes.roster;
      return null;
  }
}
