import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/error_log_service.dart';

Future<void> main() async {
  // Keep binding init, Firebase init, and runApp in the same zone so hot
  // restart / async callbacks (including Firestore) do not wedge after a
  // zone-mismatch assertion.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

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
        unawaited(
          errorLog.logError(error, stack, context: 'PlatformDispatcher'),
        );
        return true;
      };

      runApp(const ElixrApp());
    },
    (error, stack) {
      // Best-effort: ErrorLogService may not be ready if init failed early.
      unawaited(
        ErrorLogService().logError(error, stack, context: 'ZonedGuarded'),
      );
    },
  );
}
