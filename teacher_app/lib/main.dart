import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/auth/teacher_auth_controller.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  final authController = TeacherAuthController(
    repository: AuthRepository(createMissingProfile: false),
    awaitInitialAuthState: () => FirebaseAuth.instance.authStateChanges().first,
  );

  runApp(ElixrTeacherApp(authController: authController));
}
