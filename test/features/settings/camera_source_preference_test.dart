import 'dart:io';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/settings/widgets/camera_source_preference.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _cameraResponse =
    '{"cameras":[{"device_id":"dev-external","display_name":"External Camera","runtime_index":2,"is_active":false,"identity_stable":true}],"preferred_index":1,"fallback_index":0,"active_index":null,"active_device_id":null}';
const _unstableCameraResponse =
    '{"cameras":[{"device_id":"opencv:2","display_name":"Camera 2","runtime_index":2,"is_active":false,"identity_stable":false}],"preferred_index":1,"fallback_index":0,"active_index":null,"active_device_id":null}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SettingsService settings;
  late CameraDeviceService cameras;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'elixr-camera-source-widget-',
    );
    settings = SettingsService(
      settingsFile: File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      ),
    );
    await settings.initialize();
    cameras = CameraDeviceService(httpGet: (_) async => _cameraResponse);
  });

  tearDown(() async {
    cameras.dispose();
    settings.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> pumpPreference(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    await cameras.refresh(forceRefresh: true);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SizedBox(
            width: 480,
            child: CameraSourcePreference(
              settings: settings,
              cameras: cameras,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('persists a discovered physical camera selection', (
    tester,
  ) async {
    await pumpPreference(tester);

    final selector = tester.widget<ComboBox<String>>(
      find.byKey(const ValueKey('camera-source-selector')),
    );
    expect(selector.items, hasLength(2));
    await tester.runAsync(
      () => settings.setSelectedCameraDevice(
        'dev-external',
        displayName: 'External Camera',
      ),
    );
    await pumpPreference(tester);

    expect(settings.selectedCameraDeviceId, 'dev-external');
    expect(settings.selectedCameraDisplayName, 'External Camera');
    expect(
      tester
          .widget<ComboBox<String>>(
            find.byKey(const ValueKey('camera-source-selector')),
          )
          .value,
      'dev-external',
    );

    final reloaded = SettingsService(
      settingsFile: File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      ),
    );
    await tester.runAsync(reloaded.initialize);
    expect(reloaded.selectedCameraDeviceId, 'dev-external');
    reloaded.dispose();
  });

  testWidgets('disabled selector cannot change during a live session', (
    tester,
  ) async {
    await pumpPreference(tester, enabled: false);

    final selector = tester.widget<ComboBox<String>>(
      find.byKey(const ValueKey('camera-source-selector')),
    );
    expect(selector.onChanged, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('camera-source-refresh')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('saved missing camera remains visible with warning', (
    tester,
  ) async {
    await tester.runAsync(
      () => settings.setSelectedCameraDevice(
        'dev-missing',
        displayName: 'Studio Camera',
      ),
    );
    await pumpPreference(tester);

    expect(find.text('Studio Camera — unavailable'), findsOneWidget);
    expect(find.text('Studio Camera is no longer available'), findsOneWidget);
    expect(settings.selectedCameraDeviceId, 'dev-missing');
  });

  testWidgets('mount force-refreshes an already populated discovery service', (
    tester,
  ) async {
    var requests = 0;
    final populated = CameraDeviceService(
      httpGet: (_) async {
        requests++;
        return _cameraResponse;
      },
    );
    addTearDown(populated.dispose);
    await populated.refresh(forceRefresh: true);
    expect(requests, 1);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: CameraSourcePreference(
            settings: settings,
            cameras: populated,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(requests, 2);
  });

  testWidgets('unstable runtime identity cannot be persisted explicitly', (
    tester,
  ) async {
    final unstable = CameraDeviceService(
      httpGet: (_) async => _unstableCameraResponse,
    );
    addTearDown(unstable.dispose);
    await unstable.refresh(forceRefresh: true);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: CameraSourcePreference(
            settings: settings,
            cameras: unstable,
          ),
        ),
      ),
    );
    await tester.pump();

    final selector = tester.widget<ComboBox<String>>(
      find.byKey(const ValueKey('camera-source-selector')),
    );
    selector.onChanged!('opencv:2');
    await tester.pump();

    expect(settings.selectedCameraDeviceId, isNull);
    expect(find.textContaining('stable physical identity'), findsOneWidget);
    final labels = selector.items!
        .map((item) => (item.child as Text).data)
        .toList();
    expect(labels, contains('Camera 2 — Auto-select only'));
  });
}
