import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Registers the per-user `elixr://` protocol handler for this executable.
///
/// Windows-only: macOS declares the scheme in `macos/Runner/Info.plist`
/// (`CFBundleURLTypes`) and needs no runtime registration. Callers must gate
/// this behind `Platform.isWindows` so no registry API is evaluated elsewhere.
void registerWindowsElixrUriScheme() {
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
