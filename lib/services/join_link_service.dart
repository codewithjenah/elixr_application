import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:elixr_core/models/coach_code.dart';
import 'package:flutter/foundation.dart';

import 'windows_uri_scheme_registration.dart';

class JoinLinkService extends ChangeNotifier {
  JoinLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  String? _pendingCode;
  Uri? _pendingAuthCallback;
  bool _disposed = false;

  /// Set by [AuthService] so `elixr://auth` continue-URL redirects are handled
  /// even when the loopback HTTP page is blocked.
  void Function(Uri uri)? authCallbackHandler;

  String? get pendingCode => _pendingCode;
  bool get hasPendingCode => _pendingCode != null;
  Uri? get pendingAuthCallback => _pendingAuthCallback;

  Future<void> initialize() async {
    // macOS declares `elixr://` in the bundle's Info.plist; app_links then
    // delivers the URL through the same stream below.
    if (Platform.isWindows) {
      try {
        registerWindowsElixrUriScheme();
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
    if (_acceptAuthCallback(uri)) return true;
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

  bool _acceptAuthCallback(Uri uri) {
    if (uri.scheme.toLowerCase() != 'elixr') return false;
    if (uri.host.toLowerCase() != 'auth') return false;
    if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
    if (uri.path.isNotEmpty && uri.path != '/') return false;
    _pendingAuthCallback = uri;
    authCallbackHandler?.call(uri);
    if (!_disposed) notifyListeners();
    return true;
  }

  void clearPendingCode() {
    if (_pendingCode == null) return;
    _pendingCode = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
