import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/teacher_auth_controller.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/legal/legal_screens.dart';
import '../../features/roster/roster_screen.dart';
import '../../features/student_progress/student_progress_screen.dart';
import 'teacher_routes.dart';

GoRouter createTeacherRouter(TeacherAuthController auth) {
  return GoRouter(
    initialLocation: TeacherRoutes.login,
    refreshListenable: auth,
    redirect: (context, state) {
      return resolveTeacherRedirect(
        status: auth.status,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: TeacherRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.privacyPolicy,
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.termsOfService,
        builder: (context, state) => const TermsOfServiceScreen(),
      ),
      GoRoute(
        path: TeacherRoutes.roster,
        builder: (context, state) => const RosterScreen(),
      ),
      GoRoute(
        path: '/students/:traineeId',
        builder: (context, state) => StudentProgressScreen(
          traineeId: state.pathParameters['traineeId']!,
        ),
      ),
    ],
  );
}
