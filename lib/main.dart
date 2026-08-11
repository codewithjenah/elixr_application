import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/error_log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final errorLog = ErrorLogService();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      errorLog.logError(
        details.exception,
        details.stack ?? StackTrace.empty,
        context: 'FlutterError',
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(errorLog.logError(error, stack, context: 'PlatformDispatcher'));
    return true;
  };

  runZonedGuarded(
    () {
      runApp(const ElixrApp());
    },
    (error, stack) {
      unawaited(errorLog.logError(error, stack, context: 'ZonedGuarded'));
    },
  );
}
