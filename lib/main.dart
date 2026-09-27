import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'services/backend_service.dart';
import 'services/error_log_service.dart';

/// Public client configuration. Defaults to ELIXR's production project; a
/// build may override either value with `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`. Only the project URL and the
/// publishable (RLS-bound) key belong in the client; never a secret key.
const _defaultSupabaseUrl = 'https://uobufdulmmkpyavjghwg.supabase.co';
const _defaultSupabasePublishableKey =
    'sb_publishable_v6gfUhU_3pducoT-4H4hHw_7TDePfGo';
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: _defaultSupabaseUrl,
);
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: _defaultSupabasePublishableKey,
);

Future<void> main() async {
  // Keep binding init, backend init, and runApp in the same zone so hot
  // restart / async callbacks do not wedge after a zone-mismatch assertion.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final configurationError = _supabaseConfigurationError();
      if (configurationError != null) {
        runApp(_StartupFailureApp(message: configurationError));
        return;
      }
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabasePublishableKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          // Email and OAuth codes arrive on ELIXR's own loopback callbacks
          // and are exchanged explicitly by the auth repository.
          detectSessionInUri: false,
        ),
      );
      ElixrSupabase.configure(Supabase.instance.client);

      final backendService = BackendService();
      await backendService.start();

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

      runApp(ElixrApp(backendService: backendService));
    },
    (error, stack) {
      // Best-effort: ErrorLogService may not be ready if init failed early.
      unawaited(
        ErrorLogService().logError(error, stack, context: 'ZonedGuarded'),
      );
    },
  );
}

/// Returns a presentation-safe message when the build is missing or has an
/// unusable Supabase client configuration.
String? _supabaseConfigurationError() {
  final uri = Uri.tryParse(_supabaseUrl);
  if (_supabaseUrl.isEmpty ||
      uri == null ||
      !(uri.isScheme('https') ||
          (uri.isScheme('http') &&
              (uri.host == 'localhost' || uri.host == '127.0.0.1')))) {
    return 'This ELIXR build is missing its server address (SUPABASE_URL).';
  }
  if (_supabasePublishableKey.isEmpty) {
    return 'This ELIXR build is missing its client key '
        '(SUPABASE_PUBLISHABLE_KEY).';
  }
  if (_supabasePublishableKey.startsWith('sb_secret_') ||
      _isLegacyServiceRoleJwt(_supabasePublishableKey)) {
    // A secret key bypasses row-level security and must never ship.
    return 'This ELIXR build is misconfigured with a server-only key. '
        'Rebuild it with the publishable key.';
  }
  return null;
}

bool _isLegacyServiceRoleJwt(String key) {
  final parts = key.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map && payload['role'] == 'service_role';
  } on FormatException {
    return false;
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: 'ELIXR',
      home: ScaffoldPage(
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: InfoBar(
              title: const Text('ELIXR cannot start'),
              content: Text(message),
              severity: InfoBarSeverity.error,
            ),
          ),
        ),
      ),
    );
  }
}
