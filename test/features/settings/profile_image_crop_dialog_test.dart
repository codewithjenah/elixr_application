import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/settings/models/pending_profile_crop.dart';
import 'package:elixr_application/features/settings/widgets/profile_image_crop_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal valid 1×1 PNG (red pixel).
Uint8List testPngBytes() {
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
    0x90,
    0x77,
    0x53,
    0xDE,
    0x00,
    0x00,
    0x00,
    0x0C,
    0x49,
    0x44,
    0x41,
    0x54,
    0x08,
    0xD7,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x01,
    0x00,
    0x05,
    0xFE,
    0xD4,
    0xEF,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setSurface(
    WidgetTester tester, {
    Size size = const Size(800, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('ProfileImageCropDialog', () {
    testWidgets('Cancel closes dialog with no result', (tester) async {
      await setSurface(tester);
      PendingProfileCrop? result;

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                content: Button(
                  onPressed: () async {
                    result = await ProfileImageCropDialog.show(
                      context,
                      sourceBytes: testPngBytes(),
                    );
                  },
                  child: const Text('Open crop'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust profile photo'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Adjust profile photo'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('Apply is disabled while crop generation is active', (
      tester,
    ) async {
      await setSurface(tester);
      final completer = Completer<PendingProfileCrop?>();
      final cropped = PendingProfileCrop(bytes: testPngBytes());

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                content: Button(
                  onPressed: () {
                    ProfileImageCropDialog.show(
                      context,
                      sourceBytes: testPngBytes(),
                      applyHook: (_) => completer.future,
                    );
                  },
                  child: const Text('Open crop'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply crop'));
      await tester.pump();

      expect(find.byType(ProgressRing), findsWidgets);

      final cancel = tester.widget<Button>(
        find.ancestor(of: find.text('Cancel'), matching: find.byType(Button)),
      );
      expect(cancel.onPressed, isNull);

      completer.complete(cropped);
      await tester.pumpAndSettle();
      expect(find.text('Adjust profile photo'), findsNothing);
    });

    testWidgets('fits within a compact surface without overflow', (
      tester,
    ) async {
      await setSurface(tester, size: const Size(400, 700));
      FlutterErrorDetails? overflow;

      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) {
          overflow = details;
        }
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                content: Button(
                  onPressed: () {
                    ProfileImageCropDialog.show(
                      context,
                      sourceBytes: testPngBytes(),
                    );
                  },
                  child: const Text('Open crop'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();

      expect(find.text('Adjust profile photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(overflow, isNull);

      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Apply with hook returns cropped result', (tester) async {
      await setSurface(tester);
      final staged = PendingProfileCrop(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      PendingProfileCrop? result;

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                content: Button(
                  onPressed: () async {
                    result = await ProfileImageCropDialog.show(
                      context,
                      sourceBytes: testPngBytes(),
                      applyHook: (_) async => staged,
                    );
                  },
                  child: const Text('Open crop'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();

      expect(result, same(staged));
      expect(result!.contentType, 'image/png');
    });

    testWidgets('Apply failure shows error and stays without result', (
      tester,
    ) async {
      await setSurface(tester);
      PendingProfileCrop? result;

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                content: Button(
                  onPressed: () async {
                    result = await ProfileImageCropDialog.show(
                      context,
                      sourceBytes: testPngBytes(),
                      applyHook: (_) async {
                        throw Exception('Crop exploded');
                      },
                    );
                  },
                  child: const Text('Open crop'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.textContaining('Crop exploded'), findsOneWidget);
      expect(result, isNull);

      // Dismiss error, then cancel crop.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
