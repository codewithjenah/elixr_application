import 'dart:io';

import 'package:elixr_application/services/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(BackendRuntime.reset);

  group('packagedBackendCandidates', () {
    test('Windows keeps the installed backend folder layout', () {
      final candidates = BackendService.packagedBackendCandidates(
        hostPlatform: BackendHostPlatform.windows,
        resolvedExecutable: r'C:\Program Files\ELIXR\elixr_application.exe',
      );

      expect(candidates, <String>[
        r'C:\Program Files\ELIXR\backend\elixr_backend.exe',
        r'C:\Program Files\ELIXR\elixr_backend.exe',
      ]);
    });

    test('macOS resolves the sidecar inside the app bundle Resources', () {
      final candidates = BackendService.packagedBackendCandidates(
        hostPlatform: BackendHostPlatform.macos,
        resolvedExecutable: '/Applications/ELIXR.app/Contents/MacOS/ELIXR',
      );

      expect(candidates, <String>[
        '/Applications/ELIXR.app/Contents/Resources/backend/elixr_backend',
      ]);
      expect(candidates.single, isNot(endsWith('.exe')));
    });

    test('macOS lookup follows a relocated bundle, not a fixed path', () {
      final candidates = BackendService.packagedBackendCandidates(
        hostPlatform: BackendHostPlatform.macos,
        resolvedExecutable:
            '/Volumes/ELIXR/Some Folder/ELIXR.app/Contents/MacOS/ELIXR',
      );

      expect(
        candidates.single,
        '/Volumes/ELIXR/Some Folder/ELIXR.app/Contents/Resources/backend/'
        'elixr_backend',
      );
    });

    test('unsupported hosts never look for a sidecar', () {
      expect(
        BackendService.packagedBackendCandidates(
          hostPlatform: BackendHostPlatform.unsupported,
          resolvedExecutable: '/usr/bin/elixr',
        ),
        isEmpty,
      );
    });
  });

  group('start without a packaged sidecar', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('elixr_backend_service_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    String missingExecutable() =>
        '${root.path}${Platform.pathSeparator}ELIXR.app'
        '${Platform.pathSeparator}Contents${Platform.pathSeparator}MacOS'
        '${Platform.pathSeparator}ELIXR';

    test('a packaged macOS app reports the missing backend', () async {
      final service = BackendService(
        hostPlatform: BackendHostPlatform.macos,
        resolvedExecutable: missingExecutable(),
        requirePackagedBackend: true,
      );

      await service.start();

      expect(service.managesPackagedBackend, isFalse);
      expect(BackendRuntime.startupError, contains('missing'));
      expect(BackendRuntime.httpBaseUri, BackendRuntime.defaultHttpBaseUri);
    });

    test('development runs keep the manually started backend', () async {
      final service = BackendService(
        hostPlatform: BackendHostPlatform.macos,
        resolvedExecutable: missingExecutable(),
        requirePackagedBackend: false,
      );

      await service.start();

      expect(service.managesPackagedBackend, isFalse);
      expect(BackendRuntime.startupError, isNull);
    });

    test('Windows behavior stays a silent development no-op', () async {
      final service = BackendService(
        hostPlatform: BackendHostPlatform.windows,
        resolvedExecutable: r'C:\missing\elixr_application.exe',
      );

      await service.start();

      expect(BackendRuntime.startupError, isNull);
    });

    test('macOS allows a longer first-launch startup budget', () {
      expect(
        BackendService(hostPlatform: BackendHostPlatform.macos).startupTimeout,
        const Duration(seconds: 45),
      );
      expect(
        BackendService(
          hostPlatform: BackendHostPlatform.windows,
        ).startupTimeout,
        const Duration(seconds: 15),
      );
    });
  });
}
