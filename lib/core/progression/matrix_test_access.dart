import 'package:flutter/foundation.dart';

/// Local debug-only access for exercising the complete trainee matrix.
///
/// This deliberately depends on [kDebugMode], so a supplied Dart define cannot
/// enable the override in profile or release builds.
class MatrixTestAccessPolicy {
  const MatrixTestAccessPolicy({String? configuredUid})
    : _configuredUidOverride = configuredUid;

  static const configuredUid = String.fromEnvironment('ELIXR_MATRIX_TEST_UID');

  final String? _configuredUidOverride;

  bool isEnabledFor(String? signedInUid) => isEnabled(
    isDebugBuild: kDebugMode,
    configuredUid: _configuredUidOverride ?? configuredUid,
    signedInUid: signedInUid,
  );

  /// Pure UID comparison used by tests and the runtime wrapper above.
  static bool isEnabled({
    required bool isDebugBuild,
    required String? configuredUid,
    required String? signedInUid,
  }) {
    final configured = configuredUid?.trim() ?? '';
    final signedIn = signedInUid?.trim() ?? '';
    return isDebugBuild && configured.isNotEmpty && configured == signedIn;
  }
}
