import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:elixr_core/models/coach_code.dart';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

class JoinLinkService extends ChangeNotifier {
  JoinLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  String? _pendingCode;
  bool _disposed = false;

  String? get pendingCode => _pendingCode;
  bool get hasPendingCode => _pendingCode != null;

  Future<void> initialize() async {
    if (Platform.isWindows) {
      try {
        _registerWindowsScheme();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Could not register elixr URI scheme: $error');
        }
      }
    }
    final previousSubscription = _subscription;
    if (previousSubscription != null) {
      await previousSubscription.cancel();
    }
    _subscription = _appLinks.uriLinkStream.listen(
      acceptUri,
      onError: (Object error) {
        if (kDebugMode) debugPrint('Join-link stream error: $error');
      },
    );
  }

  @visibleForTesting
  bool acceptUri(Uri uri) {
    final values = uri.queryParametersAll;
    final codes = values['code'];
    if (uri.scheme.toLowerCase() != 'elixr' ||
        uri.host.toLowerCase() != 'join' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        values.length != 1 ||
        codes == null ||
        codes.length != 1) {
      return false;
    }
    final normalized = CoachCode.tryNormalize(codes.single);
    if (normalized == null) return false;
    _pendingCode = normalized;
    if (!_disposed) notifyListeners();
    return true;
  }

  void clearPendingCode() {
    if (_pendingCode == null) return;
    _pendingCode = null;
    if (!_disposed) notifyListeners();
  }

  void _registerWindowsScheme() {
    final appPath = Platform.resolvedExecutable;
    const protocolKey = r'Software\Classes\elixr';
    final root = CURRENT_USER.create(protocolKey);
    try {
      root.setValue('', const RegistryValue.string('URL:ELIXR Join Protocol'));
      root.setValue('URL Protocol', const RegistryValue.string(''));
      final command = root.create(r'shell\open\command');
      try {
        command.setValue('', RegistryValue.string('"$appPath" "%1"'));
      } finally {
        command.close();
      }
    } finally {
      root.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
