import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/auth/teacher_auth_controller.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final authController = TeacherAuthController(
    repository: AuthRepository(),
    awaitInitialAuthState: () => FirebaseAuth.instance.authStateChanges().first,
  );

  runApp(ElixrTeacherApp(authController: authController));
}
